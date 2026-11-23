import { Effect } from '@babylonjs/core/Materials/effect';
import { ShaderMaterial } from '@babylonjs/core/Materials/shaderMaterial';
import type { StandardMaterial } from '@babylonjs/core/Materials/standardMaterial';
import { Color3 } from '@babylonjs/core/Maths/math.color';
import { Vector2, Vector3 } from '@babylonjs/core/Maths/math.vector';
import { Mesh } from '@babylonjs/core/Meshes/mesh';
import { VertexData } from '@babylonjs/core/Meshes/mesh.vertexData';
import type { Scene } from '@babylonjs/core/scene';
import '@babylonjs/core/Meshes/thinInstanceMesh';

import { tokens } from '../gen/tokens';
import type { Tuning } from '../gen/tuning';
import type { DriveWorld } from '../drive/driveWorld';
import type { City } from '../world/model';
import { TREE_S, type Tree } from '../world/nature';
import { displayHeight, extrusionScale } from '../world/camera';
import { Tris } from './geometry';
import { bridgeShadowTris, crownJitter, crownTris, trunkTris, visibleTrees, waterTris } from './natureGeometry';
import { rgba, type Palette, type Rgba } from './palette';

/**
 * Water plane, trees and hit effects of client W (specs/nature.md "Vykreslení shora", 5.4; P2).
 * Budget (Prompts/03 7): water 1 draw call, crowns 3 (S/M/L thin instances), trunks 1, leaves 1
 * while a hit is shown; at most nature.max instances (6000) within 300 m, nearest first.
 */

/** Trees are not drawn beyond 300 m; at most 6000 instances (Prompts/03 5.4 and 7). */
export const TREE_DRAW_M = 300;
export const TREE_MAX = 6000;
/** Instances are rebuilt after the player moved 20 m (the 300 m ring has room for it). */
const REBUILD_M = 20;
/** Crown shake and leaves after a hit (P2). */
const SHAKE_S = 0.6;
const SHAKE_M = 0.5;
const LEAF_S = 0.9;
const LEAVES_PER_HIT = 10;
const LEAF_MAX = 120;
/** Trunk dots above the sidewalks and markings, below the props. */
const TRUNK_Z = 0.13;
/** Chase view (specs/terrain.md "Šikmý pohled"): trunks as posts up to the crown within this range. */
const POST_M = 150;

Effect.ShadersStore['natureWaterVertexShader'] = `
precision highp float;
attribute vec3 position;
attribute vec4 color;
uniform mat4 worldViewProjection;
varying vec4 vColor;
varying vec2 vPos;
varying vec3 vWorld;
void main(void) {
  vColor = color;
  vPos = position.xz;
  vWorld = position;
  gl_Position = worldViewProjection * vec4(position, 1.0);
}`;

// Two scrolling value-noise layers modulate the class colour (alpha = wave strength); opaque.
Effect.ShadersStore['natureWaterFragmentShader'] = `
precision highp float;
varying vec4 vColor;
varying vec2 vPos;
varying vec3 vWorld;
uniform float time;
uniform vec2 origin;
uniform vec3 eye;
uniform vec3 fogRange;
uniform vec3 fogColor;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void main(void) {
  vec2 p = vPos - origin;
  float n1 = noise(p * 0.07 + vec2(time * 0.06, time * 0.025));
  float n2 = noise(p * 0.19 + vec2(-time * 0.05, time * 0.07));
  float w = (n1 * 0.6 + n2 * 0.4 - 0.5) * 0.18 * vColor.a;
  // Linear fog of the chase view (specs/terrain.md); from above it starts out of reach.
  float f = clamp((distance(vWorld, eye) - fogRange.x) / (fogRange.y - fogRange.x), 0.0, 1.0);
  gl_FragColor = vec4(mix(clamp(vColor.rgb * (1.0 + w), 0.0, 1.0), fogColor, f * f), 1.0);
}`;

export interface NatureViewEnv {
  scene: Scene;
  city: City;
  tuning: Tuning;
  drive: DriveWorld;
  /** Camera height (DUALSTACK 6.2): crowns sit at the display height of their tree height. */
  H: number;
  unlit(name: string): StandardMaterial;
  /** Builds a mesh from triangles with a material (WorldView.mesh). */
  mesh(name: string, t: Tris, mat: StandardMaterial, alpha: boolean, frozen: boolean): Mesh;
  /** Puts a mesh on the world layer (risograph, specs/style.md). */
  world(m: Mesh): Mesh;
}

interface TreeSlot {
  size: number;
  index: number;
  tree: Tree;
}

export class NatureView {
  private readonly waterMat: ShaderMaterial;
  private water: Mesh | null = null;
  private waterVersion = -1;
  private readonly crownMat: StandardMaterial;
  private readonly trunkMat: StandardMaterial;
  private crowns: Mesh[] = [];
  private trunks!: Mesh;
  /** Trunk posts of the chase view (a four-sided prism, unit height); off from above. */
  private posts!: Mesh;
  private chase = false;
  private leaves!: Mesh;
  private pal: Palette;
  private treeVersion = -1;
  private fallenVersion = -1;
  private treeX = Infinity;
  private treeY = Infinity;
  /** Per size: matrices and colours of the drawn crowns. */
  private mats: Float32Array[] = [new Float32Array(0), new Float32Array(0), new Float32Array(0)];
  private cols: Float32Array[] = [new Float32Array(0), new Float32Array(0), new Float32Array(0)];
  private readonly slots = new Map<string, TreeSlot>();
  private faded = new Set<string>();
  private shaking = new Map<string, number>();
  private lastEvent = 0;
  private readonly leafState: Array<{ x: number; y: number; z: number; vx: number; vy: number; vz: number; t: number; rot: number }> = [];
  private time = 0;
  private readonly origin = new Vector2(0, 0);
  /** Instances drawn (crowns), for the debug overlay. */
  instances = 0;
  /** Called on a new tree hit (sound, specs/flow.md P2). */
  onHit: ((size: number) => void) | null = null;

  constructor(readonly env: NatureViewEnv, pal: Palette) {
    this.pal = pal;
    const scene = env.scene;
    this.waterMat = new ShaderMaterial('nature-water', scene, { vertex: 'natureWater', fragment: 'natureWater' }, {
      attributes: ['position', 'color'],
      uniforms: ['worldViewProjection', 'time', 'origin', 'eye', 'fogRange', 'fogColor'],
    });
    this.waterMat.backFaceCulling = false;
    this.waterMat.setVector3('eye', Vector3.Zero());
    this.waterMat.setVector3('fogRange', new Vector3(1e6, 2e6, 0));
    this.waterMat.setColor3('fogColor', Color3.White());
    this.crownMat = env.unlit('crowns');
    this.trunkMat = env.unlit('trunks');
    this.buildModels();
  }

  private buildModels(): void {
    const e = this.env, sizes = e.tuning.nature.treeSizes;
    for (const m of this.crowns) m.dispose();
    this.trunks?.dispose();
    this.leaves?.dispose();
    this.posts?.dispose();
    this.crowns = [sizes.s, sizes.m, sizes.l].map((s, i) => {
      const t = new Tris();
      crownTris(i, s.crownR, this.pal, t);
      const m = e.world(e.mesh(`crowns-${i}`, t, this.crownMat, true, false));
      // Crowns go over the ground and buildings by depth, after the opaque world; taller sizes last.
      m.alphaIndex = 10 + i;
      m.alwaysSelectAsActiveMesh = true;
      return m;
    });
    const tt = new Tris();
    trunkTris(e.tuning.nature.trunkRadiusM, this.pal, tt);
    // After the crowns, which do not write depth: the trunk dot stays visible under its crown.
    this.trunks = e.world(e.mesh('trunks', tt, this.trunkMat, true, false));
    this.trunks.alphaIndex = 13;
    this.trunks.alwaysSelectAsActiveMesh = true;
    const lt = new Tris();
    lt.rect(0, 0, 0, -0.5, -0.3, 0.5, 0.3, 0, rgba(tokens.colorGreenGrass));
    this.leaves = e.world(e.mesh('leaves', lt, this.crownMat, true, false));
    this.leaves.alphaIndex = 14;
    this.leaves.alwaysSelectAsActiveMesh = true;
    this.leaves.setEnabled(false);
    const pt = new Tris();
    postTris(e.tuning.nature.trunkRadiusM, this.pal, pt);
    this.posts = e.world(e.mesh('trunk-posts', pt, this.trunkMat, false, false));
    this.posts.alwaysSelectAsActiveMesh = true;
    this.posts.setEnabled(false);
    this.treeVersion = -1;
    this.waterVersion = -1;
  }

  /** Fog of the chase view (specs/terrain.md "Upřesnění T2"), squared ramp from start to end metres. */
  setFog(start: number, end: number, color: Color3): void {
    this.waterMat.setVector3('fogRange', new Vector3(start, end, 0));
    this.waterMat.setColor3('fogColor', color);
  }

  /** Crowns and trunks: the chase view fades them between the eye and the car like buildings. */
  get occluderMaterials(): StandardMaterial[] {
    return [this.crownMat, this.trunkMat];
  }

  /** Chase view on or off: trunk posts under the crowns. */
  setChase(on: boolean): void {
    if (on === this.chase) return;
    this.chase = on;
    this.treeVersion = -1;
  }

  /** The chase camera's eye (world x east, y north, z up) for the water fog. */
  setEye(x: number, y: number, z: number): void {
    this.waterMat.setVector3('eye', new Vector3(x, z, y));
  }

  setPalette(pal: Palette): void {
    this.pal = pal;
    this.buildModels();
  }

  // ---------- water

  private updateWater(): void {
    const nature = this.env.drive.nature;
    if (nature.version === this.waterVersion) return;
    this.waterVersion = nature.version;
    this.water?.dispose();
    this.water = null;
    const t = new Tris();
    const relief = this.env.city.terrain.enabled;
    waterTris(nature, this.pal, t, relief);
    bridgeShadowTris(this.env.city, nature, this.pal, t, relief);
    if (t.empty) return;
    const m = new Mesh('nature-water', this.env.scene);
    const vd = new VertexData();
    vd.positions = new Float32Array(t.pos);
    vd.colors = new Float32Array(t.col);
    vd.indices = t.vertexCount > 65535 ? new Uint32Array(t.idx) : new Uint16Array(t.idx);
    vd.applyToMesh(m, false);
    m.material = this.waterMat;
    m.isPickable = false;
    m.doNotSyncBoundingInfo = true;
    m.freezeWorldMatrix();
    this.water = this.env.world(m);
  }

  // ---------- trees

  /** Terrain height under a tree or leaf (specs/terrain.md); 0 in a flat pack. */
  private groundAt(x: number, y: number): number {
    const ter = this.env.city.terrain;
    return ter.enabled ? ter.terrainAt(x, y) ?? 0 : 0;
  }

  private crownY(size: number): number {
    const s = this.env.tuning.nature.treeSizes;
    const h = size === 0 ? s.s.height : size === 1 ? s.m.height : s.l.height;
    return displayHeight(extrusionScale(h, this.env.tuning), this.env.H);
  }

  private rebuildTrees(px: number, py: number): void {
    const d = this.env.drive;
    this.treeVersion = d.nature.version;
    this.fallenVersion = d.trees.fallenVersion;
    this.treeX = px;
    this.treeY = py;
    const list = visibleTrees(d.nature, px, py, TREE_DRAW_M, TREE_MAX, (t) => t.size === TREE_S && d.trees.fallen.has(t.key));
    this.instances = list.length;
    const bySize: Tree[][] = [[], [], []];
    for (const t of list) bySize[t.size]!.push(t);
    this.slots.clear();
    this.faded.clear();
    const trunk = new Float32Array(list.length * 16);
    const posts: number[] = [];
    let ti = 0;
    for (let s = 0; s < 3; s++) {
      const trees = bySize[s]!;
      const mats = new Float32Array(trees.length * 16), cols = new Float32Array(trees.length * 4);
      const y = this.crownY(s);
      trees.forEach((t, i) => {
        // Rotation from the jitter: the low-poly outline does not repeat.
        const a = (t.jitter * 2.399) % (2 * Math.PI);
        writeMatrix(mats, i, t.x, y + this.groundAt(t.x, t.y), t.y, a, 1);
        const j = crownJitter(t.jitter);
        cols.set([j[0], j[1], j[2], 1], 4 * i);
        this.slots.set(t.key, { size: s, index: i, tree: t });
        writeMatrix(trunk, ti++, t.x, TRUNK_Z + this.groundAt(t.x, t.y), t.y, 0, 1);
        if (this.chase && (t.x - px) ** 2 + (t.y - py) ** 2 < POST_M * POST_M) posts.push(t.x, this.groundAt(t.x, t.y), t.y, y);
      });
      this.mats[s] = mats;
      this.cols[s] = cols;
      const m = this.crowns[s]!;
      m.thinInstanceSetBuffer('matrix', trees.length ? mats : null, 16, false);
      m.thinInstanceSetBuffer('color', trees.length ? cols : null, 4, false);
      m.setEnabled(trees.length > 0);
    }
    this.trunks.thinInstanceSetBuffer('matrix', list.length ? trunk : null, 16, false);
    this.trunks.setEnabled(list.length > 0);
    const n = posts.length / 4, pm = new Float32Array(n * 16);
    for (let i = 0; i < n; i++) {
      writeMatrix(pm, i, posts[4 * i]!, posts[4 * i + 1]!, posts[4 * i + 2]!, 0, 1);
      pm[16 * i + 5] = posts[4 * i + 3]!;
    }
    this.posts.thinInstanceSetBuffer('matrix', n ? pm : null, 16, false);
    this.posts.setEnabled(n > 0);
  }

  /** Crowns within crown_fade.radius_m (in a forest flow.forest.crown_fade_radius_m) of the car get crown_fade.alpha. */
  private updateFade(px: number, py: number): void {
    const d = this.env.drive, t = this.env.tuning;
    const r = d.surface === 'forest' ? t.flow.forest.crownFadeRadiusM : t.nature.crownFade.radiusM;
    const near = new Set<string>();
    for (const tr of d.nature.treesNear(px, py, r, [])) if (this.slots.has(tr.key)) near.add(tr.key);
    const dirty = [false, false, false];
    const set = (key: string, a: number): void => {
      const s = this.slots.get(key);
      if (!s) return;
      this.cols[s.size]![4 * s.index + 3] = a;
      dirty[s.size] = true;
    };
    for (const k of this.faded) if (!near.has(k)) set(k, 1);
    for (const k of near) if (!this.faded.has(k)) set(k, t.nature.crownFade.alpha);
    this.faded = near;
    for (let s = 0; s < 3; s++) if (dirty[s] && this.cols[s]!.length) this.crowns[s]!.thinInstanceBufferUpdated('color');
  }

  /** Crown shake and leaves for new hits (specs/flow.md: zatřesení koruny, listí; P2). */
  private updateHits(dt: number): void {
    const d = this.env.drive;
    for (const e of d.trees.events) {
      if (e.t <= this.lastEvent) continue;
      this.lastEvent = e.t;
      if (e.size !== TREE_S) this.shaking.set(e.key, 0);
      this.onHit?.(e.size);
      const z = this.crownY(e.size) + this.groundAt(e.x, e.y);
      for (let i = 0; i < LEAVES_PER_HIT && this.leafState.length < LEAF_MAX; i++) {
        const a = (i / LEAVES_PER_HIT) * 2 * Math.PI + e.t;
        const sp = 2 + (i % 3);
        this.leafState.push({ x: e.x, y: e.y, z, vx: Math.cos(a) * sp + e.dirX * 3, vy: Math.sin(a) * sp + e.dirY * 3, vz: -z / LEAF_S, t: 0, rot: a });
      }
    }
    const dirty = [false, false, false];
    for (const [k, age] of this.shaking) {
      const s = this.slots.get(k);
      const na = age + dt;
      if (!s) {
        this.shaking.delete(k);
        continue;
      }
      const done = na >= SHAKE_S;
      const off = done ? 0 : Math.sin(na * 38) * SHAKE_M * (1 - na / SHAKE_S);
      const a = (s.tree.jitter * 2.399) % (2 * Math.PI);
      writeMatrix(this.mats[s.size]!, s.index, s.tree.x + off, this.crownY(s.size) + this.groundAt(s.tree.x, s.tree.y), s.tree.y + off * 0.6, a, 1);
      dirty[s.size] = true;
      if (done) this.shaking.delete(k);
      else this.shaking.set(k, na);
    }
    for (let s = 0; s < 3; s++) if (dirty[s]) this.crowns[s]!.thinInstanceBufferUpdated('matrix');
    if (this.leafState.length === 0) {
      if (this.leaves.isEnabled(false)) this.leaves.setEnabled(false);
      return;
    }
    const buf = new Float32Array(this.leafState.length * 16);
    let n = 0;
    for (const l of this.leafState) {
      l.t += dt;
      l.x += l.vx * dt;
      l.y += l.vy * dt;
      l.z = Math.max(0.06 + this.groundAt(l.x, l.y), l.z + l.vz * dt);
      l.rot += dt * 6;
      if (l.t < LEAF_S) writeMatrix(buf, n++, l.x, l.z, l.y, l.rot, 1);
    }
    for (let i = this.leafState.length - 1; i >= 0; i--) if (this.leafState[i]!.t >= LEAF_S) this.leafState.splice(i, 1);
    this.leaves.thinInstanceSetBuffer('matrix', n ? buf.subarray(0, n * 16) : null, 16, false);
    this.leaves.setEnabled(n > 0);
  }

  update(px: number, py: number, dt: number): void {
    this.time += dt;
    const d = this.env.drive;
    this.updateWater();
    if (this.water) {
      // Noise relative to the chunk origin keeps the float arguments small.
      const cm = this.env.city.chunkM * 4;
      this.waterMat.setFloat('time', this.time);
      this.origin.set(Math.floor(px / cm) * cm, Math.floor(py / cm) * cm);
      this.waterMat.setVector2('origin', this.origin);
    }
    if (d.nature.version !== this.treeVersion || d.trees.fallenVersion !== this.fallenVersion || Math.hypot(px - this.treeX, py - this.treeY) > REBUILD_M) {
      this.rebuildTrees(px, py);
    }
    this.updateFade(px, py);
    this.updateHits(dt);
  }

  dispose(): void {
    this.water?.dispose();
    for (const m of this.crowns) m.dispose();
    this.trunks.dispose();
    this.leaves.dispose();
    this.posts.dispose();
  }
}

/** A trunk post: four sides of radius r from 0 to 1 (scaled to the crown height), shaded by the sun. */
function postTris(r: number, pal: Palette, out: Tris): void {
  const c = pal.night ? pal.land : rgba(tokens.colorGreenTrunk);
  const sl = Math.hypot(pal.sunX, pal.sunY) || 1;
  for (let i = 0; i < 4; i++) {
    const a0 = (i * Math.PI) / 2 + Math.PI / 4, a1 = a0 + Math.PI / 2;
    const nx = Math.cos(a0 + Math.PI / 4), ny = Math.sin(a0 + Math.PI / 4);
    const k = pal.ambient + (1 - pal.ambient) * Math.max(0, (nx * pal.sunX + ny * pal.sunY) / sl);
    const col: Rgba = [c[0] * k, c[1] * k, c[2] * k, 1];
    const ax = r * Math.cos(a0), ay = r * Math.sin(a0), bx = r * Math.cos(a1), by = r * Math.sin(a1);
    const v0 = out.vertex(ax, ay, 0, col), v1 = out.vertex(bx, by, 0, col), v2 = out.vertex(bx, by, 1, col), v3 = out.vertex(ax, ay, 1, col);
    out.idx.push(v0, v2, v1, v0, v3, v2);
  }
}

/** Column-major Babylon matrix: rotation about +Y by −a (world CCW), uniform scale s, translation. */
function writeMatrix(out: Float32Array, i: number, x: number, y: number, z: number, a: number, s: number): void {
  const c = Math.cos(-a) * s, sn = Math.sin(-a) * s, o = 16 * i;
  out[o] = c; out[o + 1] = 0; out[o + 2] = -sn; out[o + 3] = 0;
  out[o + 4] = 0; out[o + 5] = s; out[o + 6] = 0; out[o + 7] = 0;
  out[o + 8] = sn; out[o + 9] = 0; out[o + 10] = c; out[o + 11] = 0;
  out[o + 12] = x; out[o + 13] = y; out[o + 14] = z; out[o + 15] = 1;
}
