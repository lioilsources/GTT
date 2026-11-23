import { Constants } from '@babylonjs/core/Engines/constants';
import { ShaderStore } from '@babylonjs/core/Engines/shaderStore';
import { RawTexture } from '@babylonjs/core/Materials/Textures/rawTexture';
import { Texture } from '@babylonjs/core/Materials/Textures/texture';
import { ShaderMaterial } from '@babylonjs/core/Materials/shaderMaterial';
import { Matrix } from '@babylonjs/core/Maths/math.vector';
import { Mesh } from '@babylonjs/core/Meshes/mesh';
import { VertexData } from '@babylonjs/core/Meshes/mesh.vertexData';
import type { Scene } from '@babylonjs/core/scene';
import '@babylonjs/core/Meshes/thinInstanceMesh';
import '@babylonjs/core/Shaders/ShadersInclude/instancesDeclaration';
import '@babylonjs/core/Shaders/ShadersInclude/instancesVertex';

import { composeBody, loadCarSprite, type CarSprite } from '../cars/spriteArt';
import { atlasCarIds, packAtlas, POLICE_SPRITE, spriteWheels, uvRect, type AtlasItem, type AtlasLayout } from '../cars/sprites';
import type { CarSpec } from '../gen/schema';
import type { Tuning } from '../gen/tuning';
import type { Rgba } from './palette';
import { setCount } from './shadow';

// One shader for the three meshes: texture × instance colour, or with the mask atlas
// body × mix(1, paint, mask) (specs/art.md v2 "Lak").
const VERTEX = /* glsl */ `
precision highp float;
attribute vec3 position;
attribute vec2 uv;
attribute vec4 uvRect;
#include<instancesDeclaration>
uniform mat4 viewProjection;
varying vec2 vUV;
varying vec4 vColor;
void main(void) {
#include<instancesVertex>
  gl_Position = viewProjection * finalWorld * vec4(position, 1.0);
  vUV = uvRect.xy + uv * uvRect.zw;
#ifdef INSTANCESCOLOR
  vColor = instanceColor;
#else
  vColor = vec4(1.0);
#endif
}
`;

const FRAGMENT = /* glsl */ `
precision highp float;
varying vec2 vUV;
varying vec4 vColor;
uniform sampler2D tex;
#ifdef MASK
uniform sampler2D maskTex;
#endif
void main(void) {
  vec4 c = texture2D(tex, vUV);
#ifdef ADDITIVE
  gl_FragColor = vec4(c.rgb * vColor.rgb, c.a * vColor.a);
#else
  // Alpha-tested; a fade (instance alpha < 1) dissolves by screen-door dithering.
  float h = fract(sin(dot(floor(gl_FragCoord.xy), vec2(12.9898, 78.233))) * 43758.5453);
  if (c.a < 0.5 || vColor.a <= h) discard;
#ifdef MASK
  float m = dot(texture2D(maskTex, vUV).rgb, vec3(0.299, 0.587, 0.114));
  gl_FragColor = vec4(c.rgb * mix(vec3(1.0), vColor.rgb, m), 1.0);
#else
  gl_FragColor = vec4(c.rgb * vColor.rgb, 1.0);
#endif
#endif
}
`;

ShaderStore.ShadersStore['carSpriteVertexShader'] = VERTEX;
ShaderStore.ShadersStore['carSpriteFragmentShader'] = FRAGMENT;

/** Heights over the car's base (Z.car): wheels under the body, lights over it. */
const DZ_WHEEL = 0.01, DZ_BODY = 0.02, DZ_LIGHTS = 0.03;
const WHITE: Rgba = [1, 1, 1, 1];
type UvRect = [number, number, number, number];

/** Which part of lights.png to show: none, the rear half (brake by day) or all (night). */
export const LIGHTS_OFF = 0, LIGHTS_BRAKE = 1, LIGHTS_FULL = 2;

/** One sprite car to draw this frame. */
export interface SpriteCar {
  id: string;
  /** `looks.decal` of an own car (0 = none); a variant cell must be required first. */
  decal: number;
  /** Car frame: rotation and translation (base height Z.car, lift); may carry the hop flip scale. */
  world: Matrix;
  /** Sprite size in world metres (along x, across y). */
  len: number;
  wid: number;
  /** Half extents and axle (world metres) for the wheel layout. */
  hl: number;
  hw: number;
  axle: number;
  /** Paint colour (0..1); ignored for the patrol. */
  paint: Rgba;
  /** Front wheel angle (radians, + = left); 0 for parked cars and traffic. */
  steer: number;
  /** Garage rim colour multiplying the wheel (null = untinted). */
  wheelTint: Rgba | null;
  lights: number;
  /** Fade (0..1, rescue animation of the player's car); 1 when absent. */
  alpha?: number;
}

interface Layer {
  mesh: Mesh;
  mat: ShaderMaterial;
  m: Float32Array;
  uv: Float32Array;
  col: Float32Array;
  n: number;
  /** Instances per car of this layer at most (wheels 4). */
  per: number;
}

/** Per-section staging (player, parked, traffic, patrols): written by their owners, merged on flush. */
class Section {
  m: number[] = [];
  uv: number[] = [];
  col: number[] = [];
  n = 0;
  clear(): void {
    this.m.length = 0;
    this.uv.length = 0;
    this.col.length = 0;
    this.n = 0;
  }
}

export type SectionId = 'player' | 'parked' | 'traffic' | 'police';
const SECTIONS: SectionId[] = ['parked', 'traffic', 'police', 'player'];

interface Entry {
  sprite: CarSprite;
  cls: string;
  lengthM: number;
}

/**
 * Car sprites of client W (specs/art.md v2 "Auta" → W): three atlases (body + same-layout mask,
 * wheels, lights) built when the city loads from its cars + traffic_sedan + police_patrol, and
 * three thin-instance meshes shared by the player, parked cars, traffic and patrols, so sprites
 * cost at most three draw calls in total. Body and wheels are alpha-tested and write depth (the
 * procedural shadows and the headlight cone drawn later stay under them); the lights add up.
 */
export class CarSpriteView {
  private readonly entries = new Map<string, Entry>();
  private bodyCells = new Map<string, UvRect>();
  private wheelCells = new Map<string, UvRect>();
  private lightCells = new Map<string, UvRect>();
  private readonly wheelPx = new Map<string, [number, number]>();
  private layout: AtlasLayout | null = null;
  private body: Layer | null = null;
  private wheels: Layer | null = null;
  private lights: Layer | null = null;
  private textures: Texture[] = [];
  private readonly sections = new Map<SectionId, Section>(SECTIONS.map((s) => [s, new Section()]));
  private readonly listeners: Array<() => void> = [];
  private decals = new Set<string>();
  private disposed = false;
  /** True once the atlases are up (until then every car is procedural). */
  ready = false;
  /** Ids dropped because the atlas would pass 2048² (specs/art.md "Hraniční případy"). */
  dropped: string[] = [];
  private readonly a = Matrix.Identity();
  private readonly b = Matrix.Identity();
  private readonly tmp = new Float32Array(16);

  constructor(
    private readonly scene: Scene,
    private readonly tuning: Tuning,
    cityId: string,
    specs: ReadonlyMap<string, CarSpec>,
  ) {
    const ids = atlasCarIds(specs.values(), cityId);
    // The traffic shape and the patrol are sedans of the traffic size.
    const clsOf = (id: string): [string, number] => {
      const s = specs.get(id);
      return s ? [s.class, s.length_m] : ['sedan', tuning.traffic.carLengthM];
    };
    void Promise.all(ids.map(async (id) => [id, await loadCarSprite(id, clsOf(id)[0])] as const)).then((all) => {
      if (this.disposed) return;
      for (const [id, s] of all) if (s) this.entries.set(id, { sprite: s, cls: clsOf(id)[0], lengthM: clsOf(id)[1] });
      this.build();
      this.ready = this.entries.size > 0;
      for (const l of this.listeners) l();
    });
  }

  /** Called once the atlases are ready (or right away if they already are). */
  onReady(cb: () => void): void {
    if (this.ready) cb();
    else this.listeners.push(cb);
  }

  /** Car [id] draws a sprite (in the atlas); with [decal] the variant cell must exist too. */
  has(id: string, decal = 0): boolean {
    return this.ready && this.bodyCells.has(`${id}#${decal}`);
  }

  /** lights.png of [id] is in the atlas (else the code draws the lights as before). */
  hasLights(id: string): boolean {
    return this.ready && this.lightCells.has(id);
  }

  /** Sprite canvas size in px (width across, height along). */
  size(id: string): { w: number; h: number } | null {
    const e = this.entries.get(id);
    return e ? { w: e.sprite.body.width, h: e.sprite.body.height } : null;
  }

  /** Instances drawn last frame (bodies, wheels, lights), for ?debug. */
  counts(): [number, number, number] {
    return [this.body?.n ?? 0, this.wheels?.n ?? 0, this.lights?.n ?? 0];
  }

  /**
   * Decal variants (own cars' `looks.decal`, specs/art.md "Polep") the atlas must hold; rebuilds
   * the atlas when a new pair appears. Returns true when it rebuilt.
   */
  requireDecals(pairs: Iterable<[string, number]>): boolean {
    let changed = false;
    for (const [id, d] of pairs) {
      const k = `${id}#${d}`;
      if (d === 0 || !this.entries.has(id) || this.decals.has(k)) continue;
      this.decals.add(k);
      changed = true;
    }
    if (changed && this.ready) this.build();
    return changed && this.ready;
  }

  private build(): void {
    for (const t of this.textures) t.dispose();
    this.textures = [];
    const cs = this.tuning.carScale;
    // Body + mask: base cells in content order, then the decal variants.
    const items: AtlasItem[] = [];
    const cellsOf = new Map<string, { body: ImageData; mask: ImageData }>();
    for (const [id, e] of this.entries) {
      items.push({ key: `${id}#0`, w: e.sprite.body.width, h: e.sprite.body.height });
    }
    for (const k of this.decals) {
      const [id] = k.split('#');
      const e = this.entries.get(id!)!;
      items.push({ key: k, w: e.sprite.body.width, h: e.sprite.body.height });
    }
    const lay = (this.layout = packAtlas(items));
    this.dropped = lay.dropped.filter((k) => k.endsWith('#0')).map((k) => k.slice(0, -2));
    for (const k of lay.cells.keys()) {
      const [id, d] = k.split('#');
      cellsOf.set(k, composeBody(this.entries.get(id!)!.sprite, Number(d), cs));
    }
    const bodyTex = this.atlasTexture('car-body-atlas', lay, (k) => cellsOf.get(k)!.body);
    const maskTex = this.atlasTexture('car-mask-atlas', lay, (k) => cellsOf.get(k)!.mask);
    this.bodyCells = new Map([...lay.cells].map(([k, c]) => [k, uvRect(c, lay.w, lay.h)]));
    // A body dropped from the atlas drops its wheels and lights too (whole car procedural).
    const inAtlas = [...this.entries].filter(([id]) => this.bodyCells.has(`${id}#0`));

    const wItems = inAtlas.filter(([, e]) => e.sprite.wheel).map(([id, e]) => ({ key: id, w: e.sprite.wheel!.width, h: e.sprite.wheel!.height }));
    const wLay = packAtlas(wItems);
    const wheelTex = this.atlasTexture('car-wheel-atlas', wLay, (k) => this.entries.get(k)!.sprite.wheel!);
    this.wheelCells = new Map([...wLay.cells].map(([k, c]) => [k, uvRect(c, wLay.w, wLay.h)]));
    for (const [id, e] of inAtlas) if (e.sprite.wheel) this.wheelPx.set(id, [e.sprite.wheel.width, e.sprite.wheel.height]);

    const lItems = inAtlas.filter(([, e]) => e.sprite.lights).map(([id, e]) => ({ key: id, w: e.sprite.lights!.width, h: e.sprite.lights!.height }));
    const lLay = packAtlas(lItems);
    const lightTex = this.atlasTexture('car-light-atlas', lLay, (k) => this.entries.get(k)!.sprite.lights!);
    this.lightCells = new Map([...lLay.cells].map(([k, c]) => [k, uvRect(c, lLay.w, lLay.h)]));

    if (!this.body) {
      this.body = this.layer('car-sprite-body', ['MASK'], false, 1);
      this.wheels = this.layer('car-sprite-wheels', [], false, 4);
      this.lights = this.layer('car-sprite-lights', ['ADDITIVE'], true, 1);
    }
    this.body.mat.setTexture('tex', bodyTex);
    this.body.mat.setTexture('maskTex', maskTex);
    this.wheels!.mat.setTexture('tex', wheelTex);
    this.lights!.mat.setTexture('tex', lightTex);
  }

  private atlasTexture(name: string, lay: AtlasLayout, data: (key: string) => ImageData): Texture {
    const buf = new Uint8Array(lay.w * lay.h * 4);
    for (const [k, c] of lay.cells) {
      const d = data(k).data;
      for (let row = 0; row < c.h; row++) {
        buf.set(d.subarray(row * c.w * 4, (row + 1) * c.w * 4), ((c.y + row) * lay.w + c.x) * 4);
      }
    }
    const t = RawTexture.CreateRGBATexture(buf, lay.w, lay.h, this.scene, false, false, Texture.BILINEAR_SAMPLINGMODE);
    t.name = name;
    t.wrapU = Texture.CLAMP_ADDRESSMODE;
    t.wrapV = Texture.CLAMP_ADDRESSMODE;
    this.textures.push(t);
    return t;
  }

  private layer(name: string, defines: string[], additive: boolean, per: number): Layer {
    const mat = new ShaderMaterial(name, this.scene, 'carSprite', {
      attributes: ['position', 'uv', 'uvRect'],
      uniforms: ['world', 'viewProjection'],
      samplers: defines.includes('MASK') ? ['tex', 'maskTex'] : ['tex'],
      defines,
      needAlphaBlending: additive,
      needAlphaTesting: !additive,
    });
    mat.backFaceCulling = false;
    if (additive) {
      mat.alphaMode = Constants.ALPHA_ADD;
      mat.disableDepthWrite = true;
    }
    const mesh = new Mesh(name, this.scene);
    const vd = new VertexData();
    // Unit quad in car space (x forward, y left) → Babylon (x, 0, y); image nose up, left = +y.
    vd.positions = new Float32Array([0.5, 0, 0.5, 0.5, 0, -0.5, -0.5, 0, -0.5, -0.5, 0, 0.5]);
    vd.uvs = new Float32Array([0, 0, 1, 0, 1, 1, 0, 1]);
    vd.indices = new Uint16Array([0, 1, 2, 0, 2, 3]);
    vd.applyToMesh(mesh, false);
    mesh.material = mat;
    mesh.isPickable = false;
    mesh.alwaysSelectAsActiveMesh = true;
    mesh.doNotSyncBoundingInfo = true;
    const cap = 64 * per;
    const l: Layer = { mesh, mat, m: new Float32Array(cap * 16), uv: new Float32Array(cap * 4), col: new Float32Array(cap * 4), n: 0, per };
    this.bind(l);
    setCount(mesh, 0);
    return l;
  }

  private bind(l: Layer): void {
    l.mesh.thinInstanceSetBuffer('matrix', l.m, 16, false);
    l.mesh.thinInstanceSetBuffer('uvRect', l.uv, 4, false);
    l.mesh.thinInstanceSetBuffer('color', l.col, 4, false);
  }

  /** Clears one section before its owner writes this frame's cars. */
  begin(s: SectionId): void {
    this.sections.get(s)!.clear();
  }

  /** Adds a car to section [s] (the car must pass `has(id, decal)`). */
  add(s: SectionId, c: SpriteCar): void {
    const sec = this.sections.get(s)!;
    const body = this.bodyCells.get(`${c.id}#${c.decal}`) ?? this.bodyCells.get(`${c.id}#0`);
    if (!body) return;
    const a = c.alpha ?? 1;
    if (a <= 0) return;
    sec.n++;
    const paint = c.id === POLICE_SPRITE ? WHITE : c.paint;
    // Wheels (under the body), front ones steered, left ones mirrored.
    const wc = this.wheelCells.get(c.id), wpx = this.wheelPx.get(c.id), e = this.entries.get(c.id)!;
    if (wc && wpx) {
      const k = this.tuning.carScale / 32;
      const ww = wpx[0] * k, wl = wpx[1] * k;
      for (const w of spriteWheels(e.cls, e.lengthM, c.hl, c.hw, c.axle)) {
        this.local(wl, ww * (w.mirror ? -1 : 1), w.front ? c.steer : 0, w.x, DZ_WHEEL, w.y);
        this.push(sec, 'w', c.world, wc, c.wheelTint ?? WHITE, a);
      }
    }
    this.local(c.len, c.wid, 0, 0, DZ_BODY, 0);
    this.push(sec, 'b', c.world, body, paint, a);
    const lc = this.lightCells.get(c.id);
    if (lc && c.lights !== LIGHTS_OFF) {
      if (c.lights === LIGHTS_FULL) {
        this.local(c.len, c.wid, 0, 0, DZ_LIGHTS, 0);
        this.push(sec, 'l', c.world, lc, WHITE, a);
      } else {
        // Rear half of the canvas (below its centre): brake lights by day.
        this.local(c.len / 2, c.wid, 0, -c.len / 4, DZ_LIGHTS, 0);
        this.push(sec, 'l', c.world, [lc[0], lc[1] + lc[3] / 2, lc[2], lc[3] / 2], WHITE, a);
      }
    }
  }

  /** this.a = scale(sx along, sz across) · rotY(−steer) · translate(x, dz, y) in car space. */
  private local(sx: number, sz: number, steer: number, x: number, dz: number, y: number): void {
    // Babylon RotationY(a) rows: (cos, 0, −sin), (0, 1, 0), (sin, 0, cos); a = −steer.
    const c = Math.cos(-steer), s = Math.sin(-steer), o = this.tmp;
    o[0] = c * sx; o[1] = 0; o[2] = -s * sx; o[3] = 0;
    o[4] = 0; o[5] = 1; o[6] = 0; o[7] = 0;
    o[8] = s * sz; o[9] = 0; o[10] = c * sz; o[11] = 0;
    o[12] = x; o[13] = dz; o[14] = y; o[15] = 1;
    Matrix.FromArrayToRef(o, 0, this.a);
  }

  private push(sec: Section, kind: 'b' | 'w' | 'l', world: Matrix, uv: readonly number[], col: Rgba, alpha: number): void {
    this.a.multiplyToRef(world, this.b);
    const arr = this.b.asArray();
    sec.m.push(kind === 'b' ? 0 : kind === 'w' ? 1 : 2);
    for (let i = 0; i < 16; i++) sec.m.push(arr[i]!);
    sec.uv.push(uv[0]!, uv[1]!, uv[2]!, uv[3]!);
    sec.col.push(col[0], col[1], col[2], alpha);
  }

  /** Merges the sections into the three meshes; call once per frame before scene.render. */
  flush(): void {
    if (!this.body) return;
    const layers = [this.body, this.wheels!, this.lights!];
    for (const l of layers) l.n = 0;
    for (const s of SECTIONS) {
      const sec = this.sections.get(s)!;
      const count = sec.uv.length / 4;
      for (let i = 0; i < count; i++) {
        const l = layers[sec.m[i * 17]!]!;
        if ((l.n + 1) * 16 > l.m.length) this.grow(l);
        for (let j = 0; j < 16; j++) l.m[l.n * 16 + j] = sec.m[i * 17 + 1 + j]!;
        for (let j = 0; j < 4; j++) {
          l.uv[l.n * 4 + j] = sec.uv[i * 4 + j]!;
          l.col[l.n * 4 + j] = sec.col[i * 4 + j]!;
        }
        l.n++;
      }
    }
    for (const l of layers) {
      setCount(l.mesh, l.n);
      if (l.n === 0) continue;
      l.mesh.thinInstanceBufferUpdated('matrix');
      l.mesh.thinInstanceBufferUpdated('uvRect');
      l.mesh.thinInstanceBufferUpdated('color');
    }
  }

  private grow(l: Layer): void {
    const cap = (l.m.length / 16) * 2;
    const m = new Float32Array(cap * 16), uv = new Float32Array(cap * 4), col = new Float32Array(cap * 4);
    m.set(l.m);
    uv.set(l.uv);
    col.set(l.col);
    l.m = m;
    l.uv = uv;
    l.col = col;
    this.bind(l);
  }

  dispose(): void {
    this.disposed = true;
    for (const t of this.textures) t.dispose();
    for (const l of [this.body, this.wheels, this.lights]) {
      l?.mesh.dispose();
      l?.mat.dispose();
    }
  }
}

