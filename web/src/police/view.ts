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
import { Tris, Z } from '../render/geometry';
import { rgba, type Rgba } from '../render/palette';
import { setShadowColour } from '../render/shadow';
import type { Traffic } from '../traffic/traffic';

/**
 * Light-bar phase (specs/police.md "Kreslení"): −1 = off (not chasing), else 0 / 1 alternating
 * every light_blink_s. Pure, the Flutter painter uses the same rule; a roadblock patrol passes
 * pursuing = true (its lights always blink).
 */
export function lightPhase(pursuing: boolean, timeS: number, blinkS: number): number {
  if (!pursuing) return -1;
  return Math.floor(timeS / blinkS) % 2;
}

/**
 * Patrol cars (specs/police.md "Kreslení"): police livery and a light bar whose two lamps blink
 * while chasing. Thin instances with preallocated buffers; TrafficView skips police cars.
 */
export class PoliceView {
  private readonly mat: StandardMaterial;
  private readonly body: Mesh;
  private readonly lampL: Mesh;
  private readonly lampR: Mesh;
  private readonly carM: Float32Array;
  private readonly colL: Float32Array;
  private readonly colR: Float32Array;
  private readonly red: Rgba;
  private readonly blue: Rgba;
  private readonly off: Rgba;
  private readonly m = Matrix.Identity();
  private time = 0;

  constructor(
    scene: Scene,
    readonly traffic: Traffic,
    readonly tuning: Tuning,
  ) {
    const m = (this.mat = new StandardMaterial('police', scene));
    m.disableLighting = true;
    m.emissiveColor = Color3.White();
    m.diffuseColor = Color3.Black();
    m.specularColor = Color3.Black();
    m.sideOrientation = Material.ClockWiseSideOrientation;

    const t = tuning.traffic;
    const hl = (t.carLengthM * tuning.carScale) / 2, hw = (t.carWidthM * tuning.carScale) / 2;
    const b = new Tris();
    b.rect(0, 0, 0, -hl + 0.6, -hw - 0.6, hl + 0.6, hw - 0.6, -0.02, rgba(tokens.colorCarShadow));
    b.rect(0, 0, 0, -hl, -hw, hl, hw, 0.02, rgba(tokens.colorPoliceBody));
    b.rect(0, 0, 0, -hl * 0.45, -hw, hl * 0.2, hw, 0.025, rgba(tokens.colorPoliceDoor));
    b.rect(0, 0, 0, -hl * 0.42, -hw * 0.78, hl * 0.3, hw * 0.78, 0.03, rgba(tokens.colorCarCabin));
    b.rect(0, 0, 0, -hl * 0.12, -hw * 0.85, hl * 0.04, hw * 0.85, 0.04, rgba(tokens.colorPoliceBar));
    const head = rgba(tokens.colorCarHeadlightDay), tail = rgba(tokens.colorCarTail);
    b.rect(0, 0, 0, hl * 0.9, hw * 0.5, hl, hw * 0.85, 0.05, head);
    b.rect(0, 0, 0, hl * 0.9, -hw * 0.85, hl, -hw * 0.5, 0.05, head);
    b.rect(0, 0, 0, -hl, hw * 0.5, -hl * 0.92, hw * 0.85, 0.05, tail);
    b.rect(0, 0, 0, -hl, -hw * 0.85, -hl * 0.92, -hw * 0.5, 0.05, tail);
    const white: Rgba = [1, 1, 1, 1];
    const l = new Tris();
    l.rect(0, 0, 0, -hl * 0.1, hw * 0.1, hl * 0.02, hw * 0.8, 0.05, white);
    const r = new Tris();
    r.rect(0, 0, 0, -hl * 0.1, -hw * 0.8, hl * 0.02, -hw * 0.1, 0.05, white);

    const n = t.maxCars;
    this.body = this.mesh(scene, 'police-body', b, true);
    this.lampL = this.mesh(scene, 'police-lamp-l', l, false);
    this.lampR = this.mesh(scene, 'police-lamp-r', r, false);
    this.carM = new Float32Array(n * 16);
    this.colL = new Float32Array(n * 4).fill(1);
    this.colR = new Float32Array(n * 4).fill(1);
    for (const mesh of [this.body, this.lampL, this.lampR]) {
      mesh.thinInstanceSetBuffer('matrix', this.carM, 16, false);
      mesh.thinInstanceCount = 0;
    }
    this.lampL.thinInstanceSetBuffer('color', this.colL, 4, false);
    this.lampR.thinInstanceSetBuffer('color', this.colR, 4, false);
    this.red = rgba(tokens.colorPoliceLightRed);
    this.blue = rgba(tokens.colorPoliceLightBlue);
    this.off = rgba(tokens.colorPoliceLightOff);
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

  /** Ground shadow colour (the city skin's `shadow` by day, specs/style.md); the first rect of the body. */
  setShadow(c: Rgba): void {
    setShadowColour(this.body, 4, c);
  }

  /** Writes the instance buffers; call once per frame before scene.render. */
  update(dt: number, playerLayer: number): void {
    this.time += dt;
    const lift = this.tuning.layers.deckLiftM, blink = this.tuning.police.lightBlinkS;
    const inTunnel = playerLayer < 0;
    let n = 0;
    for (const c of this.traffic.cars) {
      if (!c.police || c.layer < 0 !== inTunnel) continue;
      const h = (c.layer > 0 ? lift * c.layer : 0) + Z.car;
      Matrix.RotationYToRef(-c.heading, this.m);
      this.m.setTranslationFromFloats(c.x, h, c.y);
      this.m.copyToArray(this.carM, 16 * n);
      // A roadblock patrol's lights blink always (specs/roadblock.md).
      const ph = lightPhase(c.pursuing || c.blocking, this.time, blink);
      this.colL.set(ph < 0 ? this.off : ph === 0 ? this.red : this.off, 4 * n);
      this.colR.set(ph < 0 ? this.off : ph === 1 ? this.blue : this.off, 4 * n);
      n++;
    }
    for (const mesh of [this.body, this.lampL, this.lampR]) {
      mesh.thinInstanceCount = n;
      mesh.thinInstanceBufferUpdated('matrix');
    }
    this.lampL.thinInstanceBufferUpdated('color');
    this.lampR.thinInstanceBufferUpdated('color');
  }

  dispose(): void {
    for (const mesh of [this.body, this.lampL, this.lampR]) mesh.dispose();
    this.mat.dispose();
  }
}
