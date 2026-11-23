import { Material } from '@babylonjs/core/Materials/material';
import { StandardMaterial } from '@babylonjs/core/Materials/standardMaterial';
import { Color3 } from '@babylonjs/core/Maths/math.color';
import { Matrix, Quaternion, Vector3 } from '@babylonjs/core/Maths/math.vector';
import { Mesh } from '@babylonjs/core/Meshes/mesh';
import { VertexData } from '@babylonjs/core/Meshes/mesh.vertexData';
import type { Scene } from '@babylonjs/core/scene';
import '@babylonjs/core/Meshes/thinInstanceMesh';

import { tokens } from '../gen/tokens';
import type { Tuning } from '../gen/tuning';
import type { Terrain } from '../world/terrain';
import type { PedestrianWorld } from '../peds/pedestrians';
import type { CameraRig } from './worldView';
import { baseHeight, Tris, Z } from './geometry';
import { rgba } from './palette';

/** Just above the props, below the car (draw order METROPOLE_PLAN 6.3 step 4). */
const PED_Z = Z.props + 0.02;

/**
 * Pedestrians of client W: a top-down figure (shadow, shoulders, head) per shirt colour as thin
 * instances, and the "!!" bubble on the overlay canvas (specs/pedestrians.md "Kreslení").
 */
export class PedView {
  private readonly meshes: Mesh[];

  constructor(scene: Scene) {
    const mat = new StandardMaterial('peds', scene);
    mat.disableLighting = true;
    mat.emissiveColor = Color3.White();
    mat.diffuseColor = Color3.Black();
    mat.specularColor = Color3.Black();
    mat.backFaceCulling = true;
    mat.sideOrientation = Material.ClockWiseSideOrientation;
    this.meshes = tokens.colorPedestriansShirts.map((shirt, i) => {
      const t = figure(shirt);
      const m = new Mesh(`ped-${i}`, scene);
      const vd = new VertexData();
      vd.positions = new Float32Array(t.pos);
      vd.colors = new Float32Array(t.col);
      vd.indices = new Uint16Array(t.idx);
      vd.applyToMesh(m, false);
      m.material = mat;
      m.hasVertexAlpha = true;
      m.isPickable = false;
      m.alwaysSelectAsActiveMesh = true;
      return m;
    });
  }

  /** Heights of the city (specs/terrain.md); null = flat. */
  terrain: Terrain | null = null;

  update(w: PedestrianWorld): void {
    const lists: number[][] = this.meshes.map(() => []);
    const m = Matrix.Identity();
    const s = new Vector3(w.radius, 1, w.radius);
    const pos = new Vector3();
    for (const p of w.peds) {
      pos.set(p.x, PED_Z + baseHeight(this.terrain, p.x, p.y, 0, 0), p.y);
      Matrix.ComposeToRef(s, Quaternion.RotationAxis(Vector3.Up(), -p.heading), pos, m);
      lists[p.id % lists.length]!.push(...m.m);
    }
    this.meshes.forEach((mesh, i) => {
      const l = lists[i]!;
      mesh.setEnabled(l.length > 0);
      mesh.thinInstanceSetBuffer('matrix', l.length ? new Float32Array(l) : null, 16, false);
    });
  }
}

/** Unit figure facing +x: shadow, shoulders (capsule across the walking direction), head. */
function figure(shirt: string): Tris {
  const t = new Tris();
  t.disc(0.18, -0.18, 1.05, 0, rgba(tokens.colorPedestriansShadow), 12);
  const c = rgba(shirt);
  t.rect(0, 0, 0, -0.38, -0.7, 0.38, 0.7, 0.005, c);
  t.disc(0, -0.7, 0.38, 0.005, c, 8);
  t.disc(0, 0.7, 0.38, 0.005, c, 8);
  t.disc(0.06, 0, 0.42, 0.01, rgba(tokens.colorPedestriansHead), 10);
  return t;
}

/** "!!" bubbles above pedestrians that just dodged (screen space, overlay canvas). */
export function drawPedBubbles(
  ctx: CanvasRenderingContext2D, w: PedestrianWorld, rig: CameraRig, size: { w: number; h: number }, tuning: Tuning, text: string,
): void {
  const t = tuning.pedestrians;
  const px = t.bubblePx;
  ctx.font = `900 ${px}px system-ui, sans-serif`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  for (const p of w.peds) {
    if (p.bubble <= 0) continue;
    const q = rig.toScreen(p.x, p.y, size.w, size.h, tuning);
    if (q.x < -px || q.y < -px || q.x > size.w + px || q.y > size.h + px) continue;
    const a = Math.min(1, p.bubble / (t.bubbleS * 0.25));
    const y = q.y - t.bubbleLiftPx;
    const bw = ctx.measureText(text).width + px * 0.9, bh = px * 1.5;
    ctx.globalAlpha = a;
    ctx.fillStyle = tokens.colorPedestriansBubble;
    ctx.strokeStyle = tokens.colorPedestriansBubbleOutline;
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.roundRect(q.x - bw / 2, y - bh / 2, bw, bh, bh / 2);
    ctx.moveTo(q.x - px * 0.25, y + bh / 2);
    ctx.lineTo(q.x, y + bh / 2 + px * 0.45);
    ctx.lineTo(q.x + px * 0.25, y + bh / 2);
    ctx.fill();
    ctx.stroke();
    ctx.fillStyle = tokens.colorPedestriansBubbleText;
    ctx.fillText(text, q.x, y + 0.5);
  }
  ctx.globalAlpha = 1;
}
