import { GroundKind } from '../gen/pb/citypack_pb';
import { TERRAIN_N, type ChunkData } from '../world/chunk';
import { bilinear } from '../world/terrain';
import { DRAPE_LIFT, Tris, Z } from './geometry';
import { groundColor, type Palette, type Rgba } from './palette';
import { greenColor, greenZ } from './natureGeometry';
import type { NatureChunk } from '../world/nature';

/**
 * Terrain of client W (specs/terrain.md "Vykreslení terénu"): one mesh per chunk from its
 * 33 × 33 grid (2 048 triangles), vertex colour = material × shade, and the chunk's ground
 * polygons draped onto exactly that surface. Pure geometry (Babylon axes as geometry.ts).
 */

/** Slope shading factor (specs/terrain.md): c × (0.75 + 0.5 × shade / 255). */
export function shadeFactor(shade: number): number {
  return 0.75 + (0.5 * shade) / 255;
}

export function shaded(c: Rgba, shade: number): Rgba {
  const k = shadeFactor(shade);
  return [Math.min(1, c[0] * k), Math.min(1, c[1] * k), Math.min(1, c[2] * k), c[3]];
}

/**
 * Heights the terrain is drawn at: the pack's grid, but no sample inside water with a level stands
 * above level − underwater (the pack's conform step can raise the ground under a bridge deck over
 * the river; drawn, it would cover the water).
 */
export function renderHeights(c: ChunkData, chunkM: number, underwater: number): Float32Array | null {
  const src = c.terrain;
  if (!src) return null;
  const h = Float32Array.from(src);
  const N = TERRAIN_N, step = chunkM / (N - 1);
  const x0 = c.x * chunkM, y0 = c.y * chunkM;
  for (const g of c.ground) {
    if (g.kind !== GroundKind.WATER || g.z === undefined) continue;
    const cap = g.z - underwater;
    for (let t = 0; t + 2 < g.indices.length; t += 3) {
      const a = g.indices[t]!, b = g.indices[t + 1]!, d = g.indices[t + 2]!;
      const ax = g.xy[2 * a]!, ay = g.xy[2 * a + 1]!, bx = g.xy[2 * b]!, by = g.xy[2 * b + 1]!, dx = g.xy[2 * d]!, dy = g.xy[2 * d + 1]!;
      const i0 = Math.max(0, Math.ceil((Math.min(ax, bx, dx) - x0) / step)), i1 = Math.min(N - 1, Math.floor((Math.max(ax, bx, dx) - x0) / step));
      const j0 = Math.max(0, Math.ceil((Math.min(ay, by, dy) - y0) / step)), j1 = Math.min(N - 1, Math.floor((Math.max(ay, by, dy) - y0) / step));
      for (let j = j0; j <= j1; j++) {
        for (let i = i0; i <= i1; i++) {
          const k = j * N + i;
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
  return h;
}

/** The terrain mesh of one chunk: cells split along the (i, j)–(i + 1, j + 1) diagonal. */
export function terrainTris(c: ChunkData, chunkM: number, col: Rgba, out: Tris, heights: Float32Array | null = null): void {
  const h = heights ?? c.terrain;
  if (!h) return;
  const N = TERRAIN_N, step = chunkM / (N - 1);
  const x0 = c.x * chunkM, y0 = c.y * chunkM;
  const base = out.vertexCount;
  for (let j = 0; j < N; j++) {
    for (let i = 0; i < N; i++) {
      const s = c.shade ? c.shade[j * N + i]! : 128;
      out.vertex(x0 + i * step, y0 + j * step, h[j * N + i]!, shaded(col, s));
    }
  }
  for (let j = 0; j + 1 < N; j++) {
    for (let i = 0; i + 1 < N; i++) {
      const a = base + j * N + i, b = a + 1, d = a + N, e = d + 1;
      out.tri(a, b, e);
      out.tri(a, e, d);
    }
  }
}

/** Height of the drawn terrain surface (the mesh's triangles, not bilinear) at grid coords (u, v). */
export function meshHeight(h: Float32Array, u: number, v: number): number {
  const N = TERRAIN_N;
  const i = Math.min(Math.max(Math.floor(u), 0), N - 2), j = Math.min(Math.max(Math.floor(v), 0), N - 2);
  const fu = u - i, fv = v - j;
  const h00 = h[j * N + i]!, h10 = h[j * N + i + 1]!, h01 = h[(j + 1) * N + i]!, h11 = h[(j + 1) * N + i + 1]!;
  return fv <= fu ? h00 + (h10 - h00) * fu + (h11 - h10) * fv : h00 + (h11 - h01) * fu + (h01 - h00) * fv;
}

type Poly = number[]; // interleaved u, v

/** Keeps the part of `p` where a·u + b·v + c ≥ 0 (Sutherland–Hodgman, one plane). */
function clip(p: Poly, a: number, b: number, c: number): Poly {
  const out: Poly = [];
  const n = p.length >> 1;
  for (let k = 0; k < n; k++) {
    const u0 = p[2 * k]!, v0 = p[2 * k + 1]!;
    const k1 = (k + 1) % n;
    const u1 = p[2 * k1]!, v1 = p[2 * k1 + 1]!;
    const d0 = a * u0 + b * v0 + c, d1 = a * u1 + b * v1 + c;
    if (d0 >= 0) out.push(u0, v0);
    if (d0 >= 0 !== d1 >= 0) {
      const t = d0 / (d0 - d1);
      out.push(u0 + (u1 - u0) * t, v0 + (v1 - v0) * t);
    }
  }
  return out;
}

/**
 * One triangulated polygon on the terrain: every triangle is cut by the grid's cells and diagonals
 * so each piece lies in one plane of the terrain mesh (grid heights `h`), `lift` above it, colour ×
 * the hillshade.
 */
export function drapePolygon(
  h: Float32Array, shade: Uint8Array | null | undefined, x0: number, y0: number, step: number,
  xy: ArrayLike<number>, indices: ArrayLike<number>, col: Rgba, lift: number, out: Tris,
): void {
  const N = TERRAIN_N;
  const shadeAt = (u: number, v: number): number => (shade ? bilinear(shade, u, v) : 128);
  const emit = (p: Poly): void => {
    const n = p.length >> 1;
    if (n < 3) return;
    let a2 = 0;
    for (let q = 0; q < n; q++) {
      const r = (q + 1) % n;
      a2 += p[2 * q]! * p[2 * r + 1]! - p[2 * r]! * p[2 * q + 1]!;
    }
    if (a2 < 1e-7) return; // sliver on a cell edge
    const base = out.vertexCount;
    for (let q = 0; q < n; q++) {
      const u = p[2 * q]!, v = p[2 * q + 1]!;
      out.vertex(x0 + u * step, y0 + v * step, meshHeight(h, u, v) + lift, shaded(col, shadeAt(u, v)));
    }
    for (let q = 1; q + 1 < n; q++) out.tri(base, base + q, base + q + 1);
  };
  for (let t = 0; t + 2 < indices.length; t += 3) {
    const tri: Poly = [];
    for (let q = 0; q < 3; q++) {
      const vi = indices[t + q]!;
      tri.push((xy[2 * vi]! - x0) / step, (xy[2 * vi + 1]! - y0) / step);
    }
    // Keep the world winding: the source triangles are CCW.
    const area = (tri[2]! - tri[0]!) * (tri[5]! - tri[1]!) - (tri[4]! - tri[0]!) * (tri[3]! - tri[1]!);
    if (Math.abs(area) < 1e-9) continue;
    if (area < 0) tri.push(...tri.splice(2, 2));
    const umin = Math.min(tri[0]!, tri[2]!, tri[4]!), umax = Math.max(tri[0]!, tri[2]!, tri[4]!);
    const vmin = Math.min(tri[1]!, tri[3]!, tri[5]!), vmax = Math.max(tri[1]!, tri[3]!, tri[5]!);
    const i0 = Math.max(0, Math.floor(umin)), i1 = Math.min(N - 2, Math.floor(umax));
    const j0 = Math.max(0, Math.floor(vmin)), j1 = Math.min(N - 2, Math.floor(vmax));
    for (let j = j0; j <= j1; j++) {
      for (let i = i0; i <= i1; i++) {
        // Lower-right triangle of the cell: v ≥ j, u ≤ i + 1, (v − j) ≤ (u − i).
        let p = clip(tri, 0, 1, -j);
        p = clip(p, -1, 0, i + 1);
        emit(clip(p, 1, -1, j - i));
        // Upper-left: u ≥ i, v ≤ j + 1, (v − j) ≥ (u − i).
        let q = clip(tri, 1, 0, -i);
        q = clip(q, 0, -1, j + 1);
        emit(clip(q, -1, 1, i - j));
      }
    }
  }
}

/**
 * Ground polygons of a chunk on the terrain (Z.ground order kept), DRAPE_LIFT above the mesh.
 * Water with a level stays flat at that level. With nature (specs/nature.md) water and parks are
 * the nature layers instead, as in groundTris.
 */
export function drapedGroundTris(
  c: ChunkData, pal: Palette, chunkM: number, out: Tris, order: readonly GroundKind[], heights: Float32Array | null = null,
): void {
  const h = heights ?? c.terrain;
  if (!h) return;
  const step = chunkM / (TERRAIN_N - 1);
  const x0 = c.x * chunkM, y0 = c.y * chunkM;
  order.forEach((kind, k) => {
    if (c.nature && (kind === GroundKind.WATER || kind === GroundKind.PARK)) return;
    const col = groundColor(pal, kind);
    const lift = Z.ground[k]! + DRAPE_LIFT;
    for (const g of c.ground) {
      if (g.kind !== kind) continue;
      if (g.z !== undefined) {
        // Water at its level: flat, as in a flat pack.
        const base = out.vertexCount;
        for (let i = 0; i < g.xy.length; i += 2) out.vertex(g.xy[i]!, g.xy[i + 1]!, g.z + lift, col);
        for (let i = 0; i + 2 < g.indices.length; i += 3) out.tri(base + g.indices[i]!, base + g.indices[i + 1]!, base + g.indices[i + 2]!);
        continue;
      }
      drapePolygon(h, c.shade, x0, y0, step, g.xy, g.indices, col, lift, out);
    }
  });
}

/** Green fills of a chunk with nature (specs/nature.md) on the terrain, in greenTris order and colours. */
export function drapedGreenTris(c: ChunkData, n: NatureChunk, pal: Palette, chunkM: number, out: Tris, heights: Float32Array | null = null): void {
  const h = heights ?? c.terrain;
  if (!h) return;
  const step = chunkM / (TERRAIN_N - 1);
  for (const g of n.green) drapePolygon(h, c.shade, c.x * chunkM, c.y * chunkM, step, g.xy, g.idx, greenColor(g.cls, pal), DRAPE_LIFT + greenZ(g.cls), out);
}
