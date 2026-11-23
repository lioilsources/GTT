import { LodKind, type Lod } from '../gen/pb/citypack_pb';
import { tokens } from '../gen/tokens';
import type { Tuning } from '../gen/tuning';
import { displayHeight, extrusionScale } from '../world/camera';
import { Tris } from './geometry';
import { waterColor } from './natureGeometry';
import { rgba, type Palette, type Rgba } from './palette';
import { shadeFactor } from './terrainMesh';

/**
 * Far ring of the chase camera from `lod/{x}_{y}.pb` (specs/terrain.md "Upřesnění T2",
 * specs/nature.md 5.4; P2): coarse terrain shaded like the pack's `shade`, block masses, wood and
 * parkland masses and the water surface of one tile as one triangle set (one draw call).
 */

/** Hillshade sun of the pack (specs/terrain.md `shade`): azimuth 315°, altitude 45°. */
const SUN_AZ_DEG = 315;
const SUN_ALT_DEG = 45;
/** Water a little above the capped terrain under it, wood and parkland a little apart from blocks. */
const WATER_LIFT_M = 0.3;

export interface LodGrid {
  /** Samples per side (33). */
  n: number;
  /** Sample step (m). */
  step: number;
  /** South-west corner (m). */
  x0: number;
  y0: number;
  /** Heights (m), rows from the south. */
  h: Float32Array;
}

/** The tile's 33 × 33 int16 LE dm grid in metres; a tile without terrain is flat. */
export function lodGrid(l: Lod, gridM: number, tileM: number): LodGrid {
  const n = Math.round(tileM / gridM) + 1;
  const h = new Float32Array(n * n);
  const b = l.terrain;
  if (b.length >= n * n * 2) {
    const dv = new DataView(b.buffer, b.byteOffset, b.byteLength);
    for (let i = 0; i < n * n; i++) h[i] = dv.getInt16(2 * i, true) / 10;
  }
  return { n, step: gridM, x0: l.x * tileM, y0: l.y * tileM, h };
}

/**
 * Horn hillshade of a grid as 0–255 with 128 = flat, as `citypack` computes `Chunk.shade`
 * (tools/citypack terrain.Raster.Shade): the ring is lit by the same sun as the near terrain.
 */
export function gridShade(g: LodGrid): Uint8Array {
  const { n, step, h } = g;
  const zen = ((90 - SUN_ALT_DEG) * Math.PI) / 180;
  const az = ((((360 - SUN_AZ_DEG + 90) % 360) + 360) % 360) * (Math.PI / 180);
  const at = (i: number, j: number): number => h[Math.min(n - 1, Math.max(0, j)) * n + Math.min(n - 1, Math.max(0, i))]!;
  const out = new Uint8Array(n * n);
  for (let j = 0; j < n; j++) {
    for (let i = 0; i < n; i++) {
      const dzdx = (at(i + 1, j) - at(i - 1, j)) / (2 * step);
      const dzdy = -(at(i, j + 1) - at(i, j - 1)) / (2 * step);
      const slope = Math.atan(Math.hypot(dzdx, dzdy));
      const aspect = Math.atan2(dzdy, -dzdx);
      const v = Math.max(0, Math.cos(zen) * Math.cos(slope) + Math.sin(zen) * Math.sin(slope) * Math.cos(az - aspect));
      out[j * n + i] = Math.max(0, Math.min(255, Math.round((128 * v) / Math.cos(zen))));
    }
  }
  return out;
}

/** Bilinear height in the grid (clamped to the tile). */
export function gridAt(g: LodGrid, x: number, y: number): number {
  const u = Math.min(Math.max((x - g.x0) / g.step, 0), g.n - 1), v = Math.min(Math.max((y - g.y0) / g.step, 0), g.n - 1);
  const i = Math.min(Math.floor(u), g.n - 2), j = Math.min(Math.floor(v), g.n - 2);
  const fu = u - i, fv = v - j, n = g.n, h = g.h;
  const a = h[j * n + i]! + (h[j * n + i + 1]! - h[j * n + i]!) * fu;
  const b = h[(j + 1) * n + i]! + (h[(j + 1) * n + i + 1]! - h[(j + 1) * n + i]!) * fu;
  return a + (b - a) * fv;
}

/** Caps grid samples inside a water triangle at level − underwater (as renderHeights near by). */
function capUnderWater(g: LodGrid, xy: ArrayLike<number>, idx: ArrayLike<number>, cap: number): void {
  const { n, step, x0, y0, h } = g;
  for (let t = 0; t + 2 < idx.length; t += 3) {
    const a = idx[t]!, b = idx[t + 1]!, d = idx[t + 2]!;
    const ax = xy[2 * a]!, ay = xy[2 * a + 1]!, bx = xy[2 * b]!, by = xy[2 * b + 1]!, dx = xy[2 * d]!, dy = xy[2 * d + 1]!;
    const i0 = Math.max(0, Math.ceil((Math.min(ax, bx, dx) - x0) / step)), i1 = Math.min(n - 1, Math.floor((Math.max(ax, bx, dx) - x0) / step));
    const j0 = Math.max(0, Math.ceil((Math.min(ay, by, dy) - y0) / step)), j1 = Math.min(n - 1, Math.floor((Math.max(ay, by, dy) - y0) / step));
    for (let j = j0; j <= j1; j++) {
      for (let i = i0; i <= i1; i++) {
        const k = j * n + i;
        if (h[k]! <= cap) continue;
        const px = x0 + i * step, py = y0 + j * step;
        const d1 = (px - bx) * (ay - by) - (ax - bx) * (py - by);
        const d2 = (px - dx) * (by - dy) - (bx - dx) * (py - dy);
        const d3 = (px - ax) * (dy - ay) - (dx - ax) * (py - ay);
        if ((d1 < 0 || d2 < 0 || d3 < 0) && (d1 > 0 || d2 > 0 || d3 > 0)) continue;
        h[k] = cap;
      }
    }
  }
}

function scaled(c: Rgba, k: number): Rgba {
  return [Math.min(1, c[0] * k), Math.min(1, c[1] * k), Math.min(1, c[2] * k), 1];
}

/** Mass colour: blocks in the facade colours, wood and parkland in the green tokens (night: the night park). */
function massColor(kind: LodKind, i: number, pal: Palette): Rgba {
  if (kind === LodKind.LOD_BLOCK) return pal.facades[i % pal.facades.length]!;
  if (pal.night) return scaled(pal.park, kind === LodKind.LOD_WOOD ? 0.8 : 1);
  return rgba(kind === LodKind.LOD_WOOD ? tokens.colorGreenWood : tokens.colorGreenParkland);
}

export interface LodTrisOptions {
  /** Manifest.lod_grid_m and the tile edge (lod_chunks × chunk_m). */
  gridM: number;
  tileM: number;
  /** The pack has heights (a flat pack draws everything at 0). */
  relief: boolean;
}

/** All triangles of one lod tile. */
export function lodTris(l: Lod, pal: Palette, tuning: Tuning, H: number, o: LodTrisOptions, out = new Tris()): Tris {
  const g = lodGrid(l, o.gridM, o.tileM);
  if (!o.relief) g.h.fill(0);
  const under = tuning.terrain.pipeline.underwaterM;
  const water = l.water.map((w) => ({ xy: Float32Array.from(w.vertices, (v) => v / 10), idx: w.indices, z: o.relief ? w.zDm / 10 : 0, cls: w.waterClass }));
  if (o.relief) for (const w of water) capUnderWater(g, w.xy, w.idx, w.z - under);
  // Terrain.
  const shade = gridShade(g);
  const base = out.vertexCount, n = g.n;
  for (let j = 0; j < n; j++) {
    for (let i = 0; i < n; i++) out.vertex(g.x0 + i * g.step, g.y0 + j * g.step, g.h[j * n + i]!, scaled(pal.land, shadeFactor(shade[j * n + i]!)));
  }
  for (let j = 0; j + 1 < n; j++) {
    for (let i = 0; i + 1 < n; i++) {
      const a = base + j * n + i, b = a + 1, d = a + n, e = d + 1;
      out.tri(a, b, e);
      out.tri(a, e, d);
    }
  }
  // Water: one surface per class at its level.
  for (const w of water) {
    const c = waterColor(w.cls, pal);
    const wb = out.vertexCount;
    for (let i = 0; i < w.xy.length / 2; i++) out.vertex(w.xy[2 * i]!, w.xy[2 * i + 1]!, w.z + WATER_LIFT_M, [c[0], c[1], c[2], 1]);
    for (let t = 0; t + 2 < w.idx.length; t += 3) out.tri(wb + w.idx[t]!, wb + w.idx[t + 1]!, wb + w.idx[t + 2]!);
  }
  // Masses: walls from base_z down into the slope to the display height, then the flat top.
  l.masses.forEach((m, mi) => {
    const xy = Float32Array.from(m.rings, (v) => v / 10);
    const count = xy.length >> 1;
    if (count < 3) return;
    const z0 = o.relief ? m.baseZDm / 10 : 0;
    const z1 = z0 + displayHeight(extrusionScale(m.heightM, tuning), H);
    const col = massColor(m.kind, mi, pal);
    const ends = m.ringEnds.length > 0 ? m.ringEnds : [count];
    let start = 0;
    for (const end of ends) {
      for (let i = start; i < end; i++) {
        const k = i + 1 < end ? i + 1 : start;
        const ax = xy[2 * i]!, ay = xy[2 * i + 1]!, bx = xy[2 * k]!, by = xy[2 * k + 1]!;
        const ex = bx - ax, ey = by - ay, len = Math.hypot(ex, ey);
        if (len < 0.05) continue;
        const nx = ey / len, ny = -ex / len;
        const light = pal.ambient + (1 - pal.ambient) * Math.max(0, nx * pal.sunX + ny * pal.sunY);
        const c = scaled(col, light);
        const v0 = out.vertex(ax, ay, z0, c), v1 = out.vertex(bx, by, z0, c), v2 = out.vertex(bx, by, z1, c), v3 = out.vertex(ax, ay, z1, c);
        out.idx.push(v0, v2, v1, v0, v3, v2);
      }
      start = end;
    }
    const top = m.kind === LodKind.LOD_BLOCK ? (pal.roof ? scaled(pal.roof, 1) : scaled(col, pal.roofLight)) : scaled(col, 1.08);
    const rb = out.vertexCount;
    for (let i = 0; i < count; i++) out.vertex(xy[2 * i]!, xy[2 * i + 1]!, z1, top);
    for (let k = 0; k + 2 < m.roof.length; k += 3) out.tri(rb + m.roof[k]!, rb + m.roof[k + 1]!, rb + m.roof[k + 2]!);
  });
  return out;
}

/** Tiles whose square reaches within [r] metres of (x, y). */
export function tilesWithin(refs: ReadonlyArray<{ x: number; y: number }>, tileM: number, x: number, y: number, r: number): Array<{ x: number; y: number }> {
  return refs.filter((t) => {
    const cx = Math.min(Math.max(x, t.x * tileM), (t.x + 1) * tileM), cy = Math.min(Math.max(y, t.y * tileM), (t.y + 1) * tileM);
    return Math.hypot(cx - x, cy - y) <= r;
  });
}
