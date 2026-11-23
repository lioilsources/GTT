// Car sprites (specs/art.md v2 "Auta"), pure part: which cars draw a sprite, the atlas packing,
// world sizes and wheel placement. No DOM, no Babylon (tests run it directly).
import { wheelLayout } from './shape';

/** Sprite scale: 32 px per metre of the real car (before car_scale), docs/art-requests.md §3. */
export const SPRITE_PX_PER_M = 32;
/** Canvas = car dimensions × 1.1 (5 % margin); traffic and patrols are stretched to this. */
export const SPRITE_CANVAS = 1.1;
/** Atlas edge limit (W): cars past it stay procedural. */
export const ATLAS_MAX = 2048;
/** Transparent gap between atlas cells (no bleeding with bilinear sampling). */
export const ATLAS_PAD = 2;
/** The generic traffic shape and the patrol (specs/art.md "Kdy"). */
export const TRAFFIC_SPRITE = 'traffic_sedan';
export const POLICE_SPRITE = 'police_patrol';

/** Asset paths (relative to `assets/`) of one car's layers. */
export interface SpriteFiles {
  body: string;
  /** Null for the patrol (never tinted). */
  mask: string | null;
  /** Null for class `micro` (wheels in body.png). */
  wheel: string | null;
  /** Optional: without it the code draws the lights as before. */
  lights: string | null;
}

/**
 * The layers of car [id] when it draws a sprite, else null (specs/art.md "Kdy"): body.png,
 * paint_mask.png (not the patrol) and wheel.png (not class micro) must all be in the index;
 * otherwise the whole car is procedural – never half.
 */
export function spriteFiles(index: { has(path: string): boolean }, id: string, cls: string): SpriteFiles | null {
  const p = (f: string): string => `cars/${id}/${f}.png`;
  const needMask = id !== POLICE_SPRITE, needWheel = cls !== 'micro';
  if (!index.has(p('body'))) return null;
  if (needMask && !index.has(p('paint_mask'))) return null;
  if (needWheel && !index.has(p('wheel'))) return null;
  return {
    body: p('body'),
    mask: needMask ? p('paint_mask') : null,
    wheel: needWheel ? p('wheel') : null,
    lights: index.has(p('lights')) ? p('lights') : null,
  };
}

/**
 * Cars of the city atlas (specs/art.md "W"): catalog cars whose `tags` hold the city, in content
 * id order, then the traffic shape and the patrol.
 */
export function atlasCarIds(cars: Iterable<{ id: string; tags: readonly string[] }>, cityId: string): string[] {
  const ids = [...cars].filter((c) => c.tags.includes(cityId)).map((c) => c.id).sort();
  return [...ids, TRAFFIC_SPRITE, POLICE_SPRITE];
}

export interface AtlasItem {
  key: string;
  w: number;
  h: number;
}

export interface Cell {
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface AtlasLayout {
  w: number;
  h: number;
  cells: Map<string, Cell>;
  /** Items that did not fit (the last ones in input order). */
  dropped: string[];
}

/**
 * Row packing by height (specs/art.md "W"): tallest first, left to right in rows at most [max]
 * wide. When the rows exceed [max] in height the last item in input order is dropped and the rest
 * packed again (cars past the limit stay procedural, in content id order).
 */
export function packAtlas(items: readonly AtlasItem[], max = ATLAS_MAX, pad = ATLAS_PAD): AtlasLayout {
  const keep = items.filter((i) => i.w + pad <= max && i.h + pad <= max);
  const dropped = items.filter((i) => !keep.includes(i)).map((i) => i.key);
  for (;;) {
    const order = keep.map((it, i) => ({ it, i })).sort((a, b) => b.it.h - a.it.h || a.i - b.i);
    const cells = new Map<string, Cell>();
    let x = 0, y = 0, rowH = 0, w = 0;
    for (const { it } of order) {
      if (x + it.w + pad > max) {
        y += rowH;
        x = 0;
        rowH = 0;
      }
      cells.set(it.key, { x: x + pad / 2, y: y + pad / 2, w: it.w, h: it.h });
      x += it.w + pad;
      w = Math.max(w, x);
      rowH = Math.max(rowH, it.h + pad);
    }
    const h = y + rowH;
    if (h <= max || keep.length === 0) return { w: Math.max(w, 1), h: Math.max(h, 1), cells, dropped };
    dropped.unshift(keep.pop()!.key);
  }
}

/** Atlas cell → texture rect (u, v, du, dv), v down from the top row. */
export function uvRect(c: Cell, atlasW: number, atlasH: number): [number, number, number, number] {
  return [c.x / atlasW, c.y / atlasH, c.w / atlasW, c.h / atlasH];
}

/** World size (along, across) of a catalog car's sprite of w × h px: px ÷ 32 × car_scale. */
export function spriteWorldSize(wPx: number, hPx: number, carScale: number): { len: number; wid: number } {
  return { len: (hPx / SPRITE_PX_PER_M) * carScale, wid: (wPx / SPRITE_PX_PER_M) * carScale };
}

/** Traffic and patrols: their tuning size × car_scale, stretched to the canvas (× 1.1). */
export function stretchedSize(lengthM: number, widthM: number, carScale: number): { len: number; wid: number } {
  return { len: lengthM * carScale * SPRITE_CANVAS, wid: widthM * carScale * SPRITE_CANVAS };
}

/** One wheel sprite in car space: centre, steering, mirrored (left side, +y). */
export interface SpriteWheel {
  x: number;
  y: number;
  front: boolean;
  mirror: boolean;
}

/**
 * Wheel positions of a sprite car (specs/art.md "Kola"): wheelLayout of specs/cars.md (axle at
 * drive.axle_offset × hl, ±0.92 hw; bus, trike and rickshaw by class); left wheels mirrored.
 */
export function spriteWheels(cls: string, lengthM: number, hl: number, hw: number, axle: number): SpriteWheel[] {
  return wheelLayout(cls, hl, hw, axle, lengthM).map((w) => ({ x: w.x, y: w.y, front: w.front, mirror: w.y > 0 }));
}

/** Linear-ish luminance of a mask pixel (0..1), the `m` of body × mix(1, paint, m). */
export function maskLuma(r: number, g: number, b: number): number {
  return (0.299 * r + 0.587 * g + 0.114 * b) / 255;
}

/**
 * The paint formula on one pixel (specs/art.md "Lak"): body.rgb × mix(1, paint.rgb, m), all 0..255
 * for body and 0..1 for paint and m. [out] gets r, g, b.
 */
export function tintPixel(body: readonly number[], paint: readonly number[], m: number, out: number[]): void {
  for (let i = 0; i < 3; i++) out[i] = body[i]! * (1 + (paint[i]! - 1) * m);
}

/**
 * Decal over the paint only (specs/art.md "Polep"): coverage [d] (0..1) of the decal colour
 * [decal] (0..255) is clipped by the mask [m]: the body takes the decal colour by d·m and the mask
 * loses that part (so the paint tint leaves the decal alone). Returns the new mask; [body] is
 * changed in place.
 */
export function applyDecal(body: number[], decal: readonly number[], d: number, m: number): number {
  const k = d * m;
  for (let i = 0; i < 3; i++) body[i] = body[i]! + (decal[i]! - body[i]!) * k;
  return m * (1 - d);
}
