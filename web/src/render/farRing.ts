import { Constants } from '@babylonjs/core/Engines/constants';
import { Effect } from '@babylonjs/core/Materials/effect';
import { ShaderMaterial } from '@babylonjs/core/Materials/shaderMaterial';
import { RawTexture } from '@babylonjs/core/Materials/Textures/rawTexture';
import { Color3 } from '@babylonjs/core/Maths/math.color';
import { Vector2, Vector3, Vector4 } from '@babylonjs/core/Maths/math.vector';
import { Mesh } from '@babylonjs/core/Meshes/mesh';
import { VertexData } from '@babylonjs/core/Meshes/mesh.vertexData';
import type { Scene } from '@babylonjs/core/scene';

import type { Lod } from '../gen/pb/citypack_pb';
import { tokens } from '../gen/tokens';
import type { Tuning } from '../gen/tuning';
import { decodeLod, type PackSource } from '../world/citypack';
import type { City } from '../world/model';
import { FOG_END_M, FOG_START_M, RING_M } from './chase';
import type { Tris } from './geometry';
import { lodTris, tilesWithin } from './lodGeometry';
import { rgba, type Palette } from './palette';

/**
 * Far ring and sky of the chase camera (specs/terrain.md "Upřesnění T2", specs/nature.md 5.4; P2):
 * lod tiles within RING_M of the car, one mesh and draw call each, drawn only outside the loaded
 * chunks (a chunk mask texture), with the linear fog of the chase view; the sky is one dome around
 * the eye. Tiles load in the background and build one per frame, so a camera switch never stalls.
 */

/** Sky dome radius: beyond the fog end, inside the camera's far plane. */
export const SKY_R = 1900;
/** Tiles further than the ring plus this are dropped (hysteresis). */
const DROP_EXTRA_M = 600;
const MAX_IN_FLIGHT = 2;

Effect.ShadersStore['farRingVertexShader'] = `
precision highp float;
attribute vec3 position;
attribute vec4 color;
uniform mat4 worldViewProjection;
varying vec4 vColor;
varying vec3 vPos;
void main(void) {
  vColor = color;
  vPos = position;
  gl_Position = worldViewProjection * vec4(position, 1.0);
}`;

// maskRect = (min chunk x, min chunk y, width, height); a set texel = loaded chunk, drawn near by.
Effect.ShadersStore['farRingFragmentShader'] = `
precision highp float;
varying vec4 vColor;
varying vec3 vPos;
uniform sampler2D mask;
uniform vec4 maskRect;
uniform float chunkM;
uniform vec3 eye;
uniform vec2 fogRange;
uniform vec3 fogColor;
void main(void) {
  vec2 c = floor(vPos.xz / chunkM) - maskRect.xy;
  if (c.x >= 0.0 && c.y >= 0.0 && c.x < maskRect.z && c.y < maskRect.w) {
    if (texture2D(mask, (c + 0.5) / maskRect.zw).r > 0.5) discard;
  }
  float f = clamp((distance(vPos, eye) - fogRange.x) / (fogRange.y - fogRange.x), 0.0, 1.0);
  gl_FragColor = vec4(mix(vColor.rgb, fogColor, f * f), 1.0);
}`;

Effect.ShadersStore['chaseSkyVertexShader'] = `
precision highp float;
attribute vec3 position;
uniform mat4 worldViewProjection;
varying vec3 vDir;
void main(void) {
  vDir = position;
  gl_Position = worldViewProjection * vec4(position, 1.0);
}`;

Effect.ShadersStore['chaseSkyFragmentShader'] = `
precision highp float;
varying vec3 vDir;
uniform vec3 horizon;
uniform vec3 zenith;
void main(void) {
  float k = clamp(normalize(vDir).y, 0.0, 1.0);
  gl_FragColor = vec4(mix(horizon, zenith, pow(k, 0.55)), 1.0);
}`;

interface Tile {
  key: string;
  x: number;
  y: number;
  lod: Lod | null;
  mesh: Mesh | null;
  loading: boolean;
  failed: boolean;
}

export interface FarRingEnv {
  scene: Scene;
  city: City;
  tuning: Tuning;
  H: number;
  /** Puts a mesh on the world layer (risograph, specs/style.md). */
  world(m: Mesh): Mesh;
}

export class FarRing {
  private readonly mat: ShaderMaterial;
  private readonly skyMat: ShaderMaterial;
  readonly sky: Mesh;
  private readonly tiles = new Map<string, Tile>();
  private readonly tileM: number;
  private readonly gridM: number;
  private source: PackSource | null = null;
  private pal: Palette;
  private active = false;
  private inFlight = 0;
  private readonly mask: RawTexture | null;
  private readonly maskData: Uint8Array;
  private readonly maskRect: Vector4;
  private maskDirty = true;
  private readonly eye = new Vector3();
  /** Triangles and meshes of the built tiles in the ring (debug overlay). */
  tris = 0;

  constructor(readonly env: FarRingEnv, pal: Palette) {
    this.pal = pal;
    const m = env.city.manifest;
    this.tileM = Math.max(1, m.lodChunks) * env.city.chunkM;
    this.gridM = m.lodGridM || 32;
    this.mat = new ShaderMaterial('far-ring', env.scene, { vertex: 'farRing', fragment: 'farRing' }, {
      attributes: ['position', 'color'],
      uniforms: ['worldViewProjection', 'maskRect', 'chunkM', 'eye', 'fogRange', 'fogColor'],
      samplers: ['mask'],
    });
    // geometry.ts winds front faces clockwise; the ring is seen from above and the side, cull nothing.
    this.mat.backFaceCulling = false;
    let x0 = 0, y0 = 0, x1 = 0, y1 = 0;
    m.chunks.forEach((c, i) => {
      if (i === 0 || c.x < x0) x0 = c.x;
      if (i === 0 || c.y < y0) y0 = c.y;
      if (i === 0 || c.x > x1) x1 = c.x;
      if (i === 0 || c.y > y1) y1 = c.y;
    });
    const w = Math.max(1, x1 - x0 + 1), h = Math.max(1, y1 - y0 + 1);
    this.maskRect = new Vector4(x0, y0, w, h);
    // RGBA (4-byte texels): row alignment stays valid for any width.
    this.maskData = new Uint8Array(w * h * 4);
    this.mask = m.chunks.length > 0
      ? new RawTexture(this.maskData, w, h, Constants.TEXTUREFORMAT_RGBA, env.scene, false, false, Constants.TEXTURE_NEAREST_SAMPLINGMODE, Constants.TEXTURETYPE_UNSIGNED_BYTE)
      : null;
    if (this.mask) this.mat.setTexture('mask', this.mask);
    this.mat.setVector4('maskRect', this.maskRect);
    this.mat.setFloat('chunkM', env.city.chunkM);
    this.mat.setVector2('fogRange', new Vector2(FOG_START_M, FOG_END_M));
    this.skyMat = new ShaderMaterial('chase-sky', env.scene, { vertex: 'chaseSky', fragment: 'chaseSky' }, {
      attributes: ['position'],
      uniforms: ['worldViewProjection', 'horizon', 'zenith'],
    });
    this.skyMat.backFaceCulling = false;
    this.sky = skyDome(env.scene, SKY_R);
    this.sky.material = this.skyMat;
    this.sky.isPickable = false;
    this.sky.alwaysSelectAsActiveMesh = true;
    env.world(this.sky);
    this.sky.setEnabled(false);
    this.applyColors();
  }

  setSource(s: PackSource): void {
    this.source = s;
  }

  /** The chase view's fog colour (horizon), shared with the water plane's fog. */
  get fogColor(): Color3 {
    const c = rgba(this.pal.night ? tokens.colorWorldSkyNightHorizon : tokens.colorWorldSkyHorizon);
    return new Color3(c[0], c[1], c[2]);
  }

  private applyColors(): void {
    const z = rgba(this.pal.night ? tokens.colorWorldSkyNightZenith : tokens.colorWorldSkyZenith);
    const f = this.fogColor;
    this.skyMat.setColor3('horizon', f);
    this.skyMat.setColor3('zenith', new Color3(z[0], z[1], z[2]));
    this.mat.setColor3('fogColor', f);
  }

  setPalette(pal: Palette): void {
    this.pal = pal;
    this.applyColors();
    for (const t of this.tiles.values()) {
      t.mesh?.dispose();
      t.mesh = null;
    }
  }

  /** Marks a chunk loaded (true) or dropped (false) in the near world. */
  setChunk(cx: number, cy: number, loaded: boolean): void {
    const r = this.maskRect;
    const i = cx - r.x, j = cy - r.y;
    if (i < 0 || j < 0 || i >= r.z || j >= r.w) return;
    this.maskData[4 * (j * r.z + i)] = loaded ? 255 : 0;
    this.maskDirty = true;
  }

  /**
   * Per frame. [on] = chase view; off hides the ring and the sky and keeps what is built.
   * [ex, ey, ez] = the eye in world coordinates (x east, y north, z up).
   */
  update(on: boolean, x: number, y: number, ex: number, ey: number, ez: number, build: (t: Tris) => Mesh): void {
    if (on !== this.active) {
      this.active = on;
      this.sky.setEnabled(on);
      for (const t of this.tiles.values()) t.mesh?.setEnabled(on);
    }
    if (!on) return;
    this.eye.set(ex, ez, ey);
    this.sky.position.copyFrom(this.eye);
    this.mat.setVector3('eye', this.eye);
    if (this.maskDirty && this.mask) {
      this.mask.update(this.maskData);
      this.maskDirty = false;
    }
    const want = tilesWithin(this.env.city.manifest.lods, this.tileM, x, y, RING_M);
    for (const r of want) {
      const key = `${r.x}_${r.y}`;
      if (!this.tiles.has(key)) this.tiles.set(key, { key, x: r.x, y: r.y, lod: null, mesh: null, loading: false, failed: false });
    }
    let built = false;
    let tris = 0;
    // Nearest first: loads and the one build of this frame go to the tile the player sees soonest.
    const order = [...this.tiles.values()].sort((a, b) => this.dist(a, x, y) - this.dist(b, x, y));
    for (const t of order) {
      const d = this.dist(t, x, y);
      if (d > RING_M + DROP_EXTRA_M) {
        t.mesh?.dispose();
        this.tiles.delete(t.key);
        continue;
      }
      if (d > RING_M) {
        t.mesh?.setEnabled(false);
        continue;
      }
      if (!t.lod && !t.loading && !t.failed) this.load(t);
      if (t.lod && !t.mesh && !built) {
        built = true;
        const tr = lodTris(t.lod, this.pal, this.env.tuning, this.env.H, { gridM: this.gridM, tileM: this.tileM, relief: this.env.city.terrain.enabled });
        t.mesh = this.env.world(build(tr));
        t.mesh.material = this.mat;
        t.mesh.applyFog = false;
      }
      if (t.mesh) {
        t.mesh.setEnabled(true);
        tris += t.mesh.getTotalIndices() / 3;
      }
    }
    this.tris = tris;
  }

  private dist(t: Tile, x: number, y: number): number {
    const m = this.tileM;
    const cx = Math.min(Math.max(x, t.x * m), (t.x + 1) * m), cy = Math.min(Math.max(y, t.y * m), (t.y + 1) * m);
    return Math.hypot(cx - x, cy - y);
  }

  private load(t: Tile): void {
    const src = this.source;
    if (!src || this.inFlight >= MAX_IN_FLIGHT) return;
    t.loading = true;
    this.inFlight++;
    void src.read(`lod/${t.key}.pb`).then(decodeLod).then(
      (l) => {
        t.lod = l;
      },
      () => {
        // A missing tile only leaves the horizon to the fog.
        t.failed = true;
      },
    ).finally(() => {
      t.loading = false;
      this.inFlight--;
    });
  }

  dispose(): void {
    for (const t of this.tiles.values()) t.mesh?.dispose();
    this.tiles.clear();
    this.sky.dispose();
    this.mask?.dispose();
  }
}

/** Low-poly sphere around the origin (the eye), seen from inside. */
function skyDome(scene: Scene, r: number): Mesh {
  const seg = 16, rings = 10;
  const pos: number[] = [], idx: number[] = [];
  for (let j = 0; j <= rings; j++) {
    const phi = -Math.PI / 2 + (Math.PI * j) / rings;
    for (let i = 0; i <= seg; i++) {
      const th = (2 * Math.PI * i) / seg;
      pos.push(r * Math.cos(phi) * Math.cos(th), r * Math.sin(phi), r * Math.cos(phi) * Math.sin(th));
    }
  }
  for (let j = 0; j < rings; j++) {
    for (let i = 0; i < seg; i++) {
      const a = j * (seg + 1) + i, b = a + 1, c = a + seg + 1, d = c + 1;
      idx.push(a, c, b, b, c, d);
    }
  }
  const m = new Mesh('chase-sky', scene);
  const vd = new VertexData();
  vd.positions = pos;
  vd.indices = idx;
  vd.applyToMesh(m, false);
  return m;
}
