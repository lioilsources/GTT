import { GreenClass, WaterClass } from '../gen/pb/citypack_pb';
import { tokens } from '../gen/tokens';
import type { City } from '../world/model';
import type { NatureChunk, NatureMap, NaturePiece, Tree } from '../world/nature';
import { rgba, type Palette, type Rgba } from './palette';
import { Tris } from './geometry';

/**
 * Water and green geometry for client W (specs/nature.md "Vykreslení shora", P2). Pure (no
 * Babylon): green fills and the bank line go into the chunk's flat ground mesh, the water of all
 * loaded chunks into one plane whose colour alpha carries the wave strength for the water shader.
 * Widths and heights below are presentation, like the road markings.
 */

/** Flat layer heights: green fills with the park ground, water over plazas, bank line and bridge shadow below the pedestrian paving. */
export const NZ = { wood: 0.0, park: 0.002, meadow: 0.004, water: 0.03, shore: 0.034, bridgeShadow: 0.038, bank: 0.042 } as const;
/** Bank line width (m) and the bridge shadow: band width added to the deck, offset away from the sun, sample step over water. */
const BANK_HW = 0.45;
const BRIDGE_SHADOW_EXTRA = 2.0;
const BRIDGE_SHADOW_OFFSET = 3.0;
const BRIDGE_SHADOW_STEP = 4.0;
/** Wave strength per class (colour alpha in the water plane): small water is still. */
const WAVE: Record<number, number> = {
  [WaterClass.WATER_SEA]: 1.5, [WaterClass.WATER_RIVER]: 1, [WaterClass.WATER_CANAL]: 0.8, [WaterClass.WATER_LAKE]: 0.7, [WaterClass.WATER_SMALL]: 0,
};
const SHORE_WAVE = 0.4;

export function waterColor(cls: WaterClass, pal: Palette): Rgba {
  if (pal.night) return pal.water;
  switch (cls) {
    case WaterClass.WATER_SEA: return rgba(tokens.colorWaterSea);
    case WaterClass.WATER_LAKE: return rgba(tokens.colorWaterLake);
    case WaterClass.WATER_SMALL: return rgba(tokens.colorWaterSmall);
    default: return rgba(tokens.colorWaterRiver);
  }
}

export function greenColor(cls: GreenClass, pal: Palette): Rgba {
  if (pal.night) return pal.park;
  switch (cls) {
    case GreenClass.GREEN_WOOD: return rgba(tokens.colorGreenWood);
    case GreenClass.GREEN_GRASS: return rgba(tokens.colorGreenGrass);
    case GreenClass.GREEN_SAND: return rgba(tokens.colorGreenSand);
    default: return rgba(tokens.colorGreenParkland);
  }
}

export function greenZ(cls: GreenClass): number {
  return cls === GreenClass.GREEN_WOOD ? NZ.wood : cls === GreenClass.GREEN_GRASS || cls === GreenClass.GREEN_SAND ? NZ.meadow : NZ.park;
}

function pieceTris(p: NaturePiece, h: number, col: Rgba, out: Tris): void {
  const base = out.vertexCount;
  for (let i = 0; i < p.xy.length; i += 2) out.vertex(p.xy[i]!, p.xy[i + 1]!, h, col);
  for (let i = 0; i + 2 < p.idx.length; i += 3) out.tri(base + p.idx[i]!, base + p.idx[i + 1]!, base + p.idx[i + 2]!);
}

/** Green fills of one chunk by class (specs/nature.md: wood, parkland, meadow, sand). */
export function greenTris(n: NatureChunk, pal: Palette, out: Tris): void {
  for (const g of n.green) pieceTris(g, greenZ(g.cls), greenColor(g.cls, pal), out);
}

/**
 * The bank: edges of the chunk's water triangles that belong to one triangle only (shared edges
 * cancel, also across pieces), without the edges on the chunk grid; drawn as a dark line.
 */
export function bankTris(n: NatureChunk, chunkM: number, pal: Palette, out: Tris, relief = false): void {
  const col = pal.night ? pal.water : rgba(tokens.colorWaterLine);
  const key = (x: number, y: number): string => `${Math.round(x * 10)},${Math.round(y * 10)}`;
  const edges = new Map<string, [number, number, number, number, number, number]>();
  for (const w of n.water) {
    // Relief (specs/terrain.md): the bank lies at the water's level.
    const z = relief ? w.z : 0;
    const xy = w.xy, idx = w.idx;
    for (let i = 0; i + 2 < idx.length; i += 3) {
      for (let e = 0; e < 3; e++) {
        const a = idx[i + e]!, b = idx[i + ((e + 1) % 3)]!;
        const ax = xy[2 * a]!, ay = xy[2 * a + 1]!, bx = xy[2 * b]!, by = xy[2 * b + 1]!;
        const ka = key(ax, ay), kb = key(bx, by);
        const k = ka < kb ? `${ka}|${kb}` : `${kb}|${ka}`;
        const prev = edges.get(k);
        if (prev) prev[4]++;
        else edges.set(k, [ax, ay, bx, by, 1, z]);
      }
    }
  }
  const x0 = n.x * chunkM, x1 = x0 + chunkM, y0 = n.y * chunkM, y1 = y0 + chunkM;
  const onGrid = (a: number, b: number, g: number): boolean => Math.abs(a - g) < 0.15 && Math.abs(b - g) < 0.15;
  for (const [ax, ay, bx, by, count, z] of edges.values()) {
    if (count !== 1) continue;
    if (onGrid(ax, bx, x0) || onGrid(ax, bx, x1) || onGrid(ay, by, y0) || onGrid(ay, by, y1)) continue;
    out.quad(ax, ay, bx, by, BANK_HW, NZ.bank + z, col);
    out.disc(ax, ay, BANK_HW, NZ.bank + z, col, 6);
  }
}

/** The water plane of all loaded chunks with the shore band; colour alpha = wave strength (water shader). */
export function waterTris(nature: NatureMap, pal: Palette, out: Tris, relief = false): void {
  for (const n of nature.chunks.values()) {
    for (const w of n.water) {
      const c = waterColor(w.cls, pal);
      pieceTris(w, NZ.water + (relief ? w.z : 0), [c[0], c[1], c[2], WAVE[w.cls] ?? 1], out);
    }
    const s = pal.night ? pal.water : rgba(tokens.colorWaterShore);
    // Relief: the shore band at the level of the water it lies in (the chunk's first one as fallback).
    const level = (p: NaturePiece): number => {
      if (!relief) return 0;
      const mx = (p.x0 + p.x1) / 2, my = (p.y0 + p.y1) / 2;
      return (nature.waterAt(mx, my) ?? n.water[0])?.z ?? 0;
    };
    for (const p of n.shore) pieceTris(p, NZ.shore + level(p), [s[0], s[1], s[2], SHORE_WAVE], out);
  }
}

/**
 * Bridge shadows on the water (specs/nature.md: a dark band on the surface): bridge edges sampled
 * every 4 m, a piece kept when its midpoint is over water; the band is offset away from the sun.
 * Bucketed by chunk key like the roads; the water plane draws them (alpha 0 = still).
 */
export function bridgeShadowTris(city: City, nature: NatureMap, pal: Palette, out: Tris, relief = false): void {
  const sl = Math.hypot(pal.sunX, pal.sunY);
  const ox = sl > 1e-6 ? (-pal.sunX / sl) * BRIDGE_SHADOW_OFFSET : 0, oy = sl > 1e-6 ? (-pal.sunY / sl) * BRIDGE_SHADOW_OFFSET : 0;
  const c = pal.night ? pal.water : rgba(tokens.colorWaterLine);
  const col: Rgba = [c[0], c[1], c[2], 0];
  for (const e of city.graph.edges) {
    if (e.drawLayer <= 0) continue;
    const hw = e.width / 2 + BRIDGE_SHADOW_EXTRA;
    for (let s = 0; s + 1 < e.pointCount; s++) {
      const ax = e.pts[2 * s]!, ay = e.pts[2 * s + 1]!, bx = e.pts[2 * s + 2]!, by = e.pts[2 * s + 3]!;
      const l = Math.hypot(bx - ax, by - ay);
      const n = Math.max(1, Math.ceil(l / BRIDGE_SHADOW_STEP));
      for (let i = 0; i < n; i++) {
        const t0 = i / n, t1 = (i + 1) / n;
        const px = ax + (bx - ax) * t0, py = ay + (by - ay) * t0, qx = ax + (bx - ax) * t1, qy = ay + (by - ay) * t1;
        const mx = (px + qx) / 2 + ox, my = (py + qy) / 2 + oy;
        const w = nature.waterAt(mx, my);
        if (w === null) continue;
        out.quad(px + ox, py + oy, qx + ox, qy + oy, hw, NZ.bridgeShadow + (relief ? w.z : 0), col);
      }
    }
  }
}

/** Crown segments per size (low-poly S/M/L models, specs/nature.md 5.4). */
const CROWN_SEGS = [7, 9, 11] as const;

/**
 * One crown model at the origin, radius r: a lit centre towards the sun, darker rim (the
 * instances multiply it with their colour jitter); L gets an inner ring for a fuller look.
 */
export function crownTris(size: number, r: number, pal: Palette, out: Tris): void {
  const base = pal.night ? pal.park : rgba(tokens.colorGreenCrown);
  const shade = (k: number): Rgba => [Math.min(1, base[0] * k), Math.min(1, base[1] * k), Math.min(1, base[2] * k), 1];
  const segs = CROWN_SEGS[size] ?? 9;
  const sl = Math.hypot(pal.sunX, pal.sunY) || 1;
  const sx = (pal.sunX / sl) * r * 0.25, sy = (pal.sunY / sl) * r * 0.25;
  const c = out.vertex(sx, sy, 0.3 * r, shade(1.18));
  const ring = (rr: number, h: number, k: number, phase: number): number => {
    const first = out.vertexCount;
    for (let i = 0; i < segs; i++) {
      const a = ((i + phase) * 2 * Math.PI) / segs;
      // Light from the sun side: the rim is lit where it faces the sun.
      const lit = Math.cos(a) * (pal.sunX / sl) + Math.sin(a) * (pal.sunY / sl);
      out.vertex(rr * Math.cos(a) + sx * (1 - rr / r), rr * Math.sin(a) + sy * (1 - rr / r), h, shade(k + 0.12 * lit));
    }
    return first;
  };
  if (size === 2) {
    const inner = ring(r * 0.55, 0.2 * r, 1.05, 0.5);
    const outer = ring(r, 0, 0.82, 0);
    for (let i = 0; i < segs; i++) {
      const j = (i + 1) % segs;
      out.tri(c, inner + i, inner + j);
      out.tri(outer + i, outer + j, inner + i);
      out.tri(outer + j, inner + j, inner + i);
    }
  } else {
    const outer = ring(r, 0, 0.85, 0);
    for (let i = 0; i < segs; i++) out.tri(c, outer + i, outer + ((i + 1) % segs));
  }
}

/** Trunk dot: a dark disc of radius r on the ground. */
export function trunkTris(r: number, pal: Palette, out: Tris): void {
  out.disc(0, 0, r, 0, pal.night ? pal.land : rgba(tokens.colorGreenTrunk), 8);
}

/** Colour jitter of a crown (6 bits): brightness 0.88..1.12 and a slight yellow/blue shift. */
export function crownJitter(j: number): [number, number, number] {
  const b = 0.88 + ((j & 7) / 7) * 0.24;
  const hue = ((j >> 3) / 7 - 0.5) * 0.12;
  return [b * (1 + hue), b, b * (1 - hue)];
}

/**
 * The trees to draw around (x, y): within maxM, the nearest `cap` when there are more (the draw
 * distance shrinks first, specs/nature.md budget), fallen saplings left out.
 */
export function visibleTrees(nature: NatureMap, x: number, y: number, maxM: number, cap: number, hidden: (t: Tree) => boolean): Tree[] {
  const list = nature.treesNear(x, y, maxM, []).filter((t) => !hidden(t));
  if (list.length <= cap) return list;
  const d = (t: Tree): number => (t.x - x) ** 2 + (t.y - y) ** 2;
  list.sort((a, b) => d(a) - d(b));
  list.length = cap;
  return list;
}
