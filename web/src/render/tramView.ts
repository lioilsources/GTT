import { Material } from '@babylonjs/core/Materials/material';
import { StandardMaterial } from '@babylonjs/core/Materials/standardMaterial';
import { Color3 } from '@babylonjs/core/Maths/math.color';
import { Matrix } from '@babylonjs/core/Maths/math.vector';
import { Mesh } from '@babylonjs/core/Meshes/mesh';
import { VertexData } from '@babylonjs/core/Meshes/mesh.vertexData';
import type { Scene } from '@babylonjs/core/scene';
import '@babylonjs/core/Meshes/thinInstanceMesh';

import { tokens } from '../gen/tokens';
import type { Tuning } from '../gen/tuning';
import type { Terrain } from '../world/terrain';
import type { Trams } from '../trams/trams';
import { baseHeight, Tris, Z } from './geometry';
import { rgba, type Rgba } from './palette';
import { setCount, setShadowColour } from './shadow';

/**
 * Tram cars (specs/trams.md "Kreslení"): rounded rectangles in color.trams.body with a stripe and
 * window bands (windowLit at night). Thin instances over preallocated buffers, so a frame
 * allocates nothing; three draw calls. Rails and stops are part of the road meshes (geometry.ts).
 */
export class TramView {
  private readonly mat: StandardMaterial;
  private readonly body: Mesh;
  private readonly details: Mesh;
  private readonly windows: Mesh;
  private readonly carM: Float32Array;
  private readonly winC: Float32Array;
  private readonly winDay: Rgba;
  private readonly winNight: Rgba;
  private readonly m = Matrix.Identity();
  private night = false;
  private nightDirty = true;

  constructor(
    scene: Scene,
    readonly trams: Trams,
    readonly tuning: Tuning,
  ) {
    const m = (this.mat = new StandardMaterial('trams', scene));
    m.disableLighting = true;
    m.emissiveColor = Color3.White();
    m.diffuseColor = Color3.Black();
    m.specularColor = Color3.Black();
    m.sideOrientation = Material.ClockWiseSideOrientation;

    const t = tuning.trams;
    const hl = t.carLengthM / 2, hw = t.carWidthM / 2;
    const r = hw * 0.4;
    const white: Rgba = [1, 1, 1, 1];
    const body = new Tris();
    roundedRect(body, hl, hw, r, 0.02, rgba(tokens.colorTramsBody));
    const det = new Tris();
    det.rect(0, 0, 0, -hl + 0.6, -hw - 0.6, hl + 0.6, hw - 0.6, -0.02, rgba(tokens.colorCarShadow));
    const stripe = rgba(tokens.colorTramsStripe);
    det.rect(0, 0, 0, -hl + r, -hw * 0.12, hl - r, hw * 0.12, 0.04, stripe);
    const win = new Tris();
    win.rect(0, 0, 0, -hl + r, hw * 0.55, hl - r, hw * 0.85, 0.03, white);
    win.rect(0, 0, 0, -hl + r, -hw * 0.85, hl - r, -hw * 0.55, 0.03, white);

    const n = t.maxTrams * t.carsPerTram;
    this.body = this.mesh(scene, 'tram-body', body, false);
    this.details = this.mesh(scene, 'tram-details', det, true);
    this.windows = this.mesh(scene, 'tram-windows', win, false);
    this.carM = new Float32Array(n * 16);
    this.winC = new Float32Array(n * 4).fill(1);
    this.body.thinInstanceSetBuffer('matrix', this.carM, 16, false);
    this.details.thinInstanceSetBuffer('matrix', this.carM, 16, false);
    this.windows.thinInstanceSetBuffer('matrix', this.carM, 16, false);
    this.windows.thinInstanceSetBuffer('color', this.winC, 4, false);
    for (const mesh of [this.body, this.details, this.windows]) setCount(mesh, 0);
    this.winDay = rgba(tokens.colorTramsWindow);
    this.winNight = rgba(tokens.colorTramsWindowLit);
  }

  private mesh(scene: Scene, name: string, t: Tris, alpha: boolean): Mesh {
    const mesh = new Mesh(name, scene);
    const vd = new VertexData();
    vd.positions = new Float32Array(t.pos);
    vd.colors = new Float32Array(t.col);
    vd.indices = new Uint16Array(t.idx);
    vd.applyToMesh(mesh, false);
    mesh.material = this.mat;
    mesh.hasVertexAlpha = alpha;
    mesh.isPickable = false;
    mesh.alwaysSelectAsActiveMesh = true;
    return mesh;
  }

  /** Ground shadow colour (the city skin's `shadow` by day, specs/style.md); the first rect of the details. */
  setShadow(c: Rgba): void {
    setShadowColour(this.details, 4, c);
  }

  /** Lit windows at night (color.trams.windowLit). */
  setNight(night: boolean): void {
    if (night === this.night) return;
    this.night = night;
    this.nightDirty = true;
  }

  /** Heights of the city (specs/terrain.md); null = flat. */
  terrain: Terrain | null = null;

  /** Writes the instance buffers; call once per frame before scene.render. */
  update(playerLayer: number): void {
    const lift = this.tuning.layers.deckLiftM;
    const inTunnel = playerLayer < 0;
    const max = this.carM.length / 16;
    let n = 0;
    for (const c of this.trams.items) {
      if (c.layer < 0 !== inTunnel || n >= max) continue;
      const h = baseHeight(this.terrain, c.x, c.y, c.layer, lift) + Z.car;
      // Babylon rotates about +Y clockwise seen from above; world headings are CCW.
      Matrix.RotationYToRef(-c.heading, this.m);
      this.m.setTranslationFromFloats(c.x, h, c.y);
      this.m.copyToArray(this.carM, 16 * n);
      n++;
    }
    if (this.nightDirty) {
      this.nightDirty = false;
      const col = this.night ? this.winNight : this.winDay;
      for (let i = 0; i < max; i++) this.winC.set(col, 4 * i);
      this.windows.thinInstanceBufferUpdated('color');
    }
    setCount(this.body, n);
    setCount(this.details, n);
    setCount(this.windows, n);
    this.body.thinInstanceBufferUpdated('matrix');
    this.details.thinInstanceBufferUpdated('matrix');
    this.windows.thinInstanceBufferUpdated('matrix');
  }

  dispose(): void {
    for (const mesh of [this.body, this.details, this.windows]) mesh.dispose();
    this.mat.dispose();
  }
}

/** Rectangle ±hl × ±hw with corners rounded by r, centred at the origin. */
function roundedRect(t: Tris, hl: number, hw: number, r: number, h: number, c: Rgba): void {
  t.rect(0, 0, 0, -hl + r, -hw, hl - r, hw, h, c);
  t.rect(0, 0, 0, -hl, -hw + r, -hl + r, hw - r, h, c);
  t.rect(0, 0, 0, hl - r, -hw + r, hl, hw - r, h, c);
  for (const [x, y] of [[hl - r, hw - r], [-hl + r, hw - r], [-hl + r, -hw + r], [hl - r, -hw + r]] as const) {
    t.disc(x, y, r, h, c, 8);
  }
}
