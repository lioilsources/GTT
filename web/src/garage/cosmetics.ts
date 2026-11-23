// Garage cosmetics sprites (specs/art.md v3 "Kosmetika z garáže"), pure part: which decal and
// wheel sprites exist (assets/index.json), the decoded pixels once loaded, and their raster as
// car-space polygons for procedural cars (the world mesh and the preview draw the same polygons).
// No DOM: the loader lives in cosmeticsLoad.ts.
import type { Rgba } from '../render/palette';
import type { Poly } from './looks';
import { decalIds, wheelIds } from './rules';

/** RGBA pixels, straight alpha (ImageData-compatible). */
export interface Pixels {
  width: number;
  height: number;
  data: Uint8ClampedArray;
}

/** Decal cell in the W atlas: 512 × 1024 sprites shrunk to a quarter (specs/art.md v3 "W"). */
export const DECAL_CELL_W = 128;
export const DECAL_CELL_H = 256;
/** Raster of a decal sprite on a procedural car (columns across, rows along). */
export const DECAL_GRID_COLS = 24;
export const DECAL_GRID_ROWS = 48;
/** Raster of a garage wheel sprite on a procedural wheel. */
export const WHEEL_GRID = 10;

/** `garage/decals/<id>.png` of decal choice [i] (1..8), else null. */
export function decalPath(i: number): string | null {
  const id = i >= 1 ? decalIds[i] : undefined;
  return id ? `garage/decals/${id}.png` : null;
}

/** `garage/wheels/<id>.png` of wheel choice [i] (1..6), else null. */
export function wheelPath(i: number): string | null {
  const id = i >= 1 ? wheelIds[i] : undefined;
  return id ? `garage/wheels/${id}.png` : null;
}

/** Indexed cosmetics sprites: choice → path (a file not in the index does not exist). */
export function cosmeticFiles(index: { has(path: string): boolean }): { decals: Map<number, string>; wheels: Map<number, string> } {
  const pick = (n: number, path: (i: number) => string | null): Map<number, string> => {
    const out = new Map<number, string>();
    for (let i = 1; i < n; i++) {
      const p = path(i);
      if (p && index.has(p)) out.set(i, p);
    }
    return out;
  };
  return { decals: pick(decalIds.length, decalPath), wheels: pick(wheelIds.length, wheelPath) };
}

const decals = new Map<number, Pixels>();
const wheels = new Map<number, Pixels>();

/** Decoded decal sprite of choice [i] (DECAL_CELL size), or null = procedural decal. */
export function decalArt(i: number): Pixels | null {
  return decals.get(i) ?? null;
}

/** Decoded garage wheel sprite of choice [i], or null = the car's wheel in the rim colour. */
export function wheelArt(i: number): Pixels | null {
  return wheels.get(i) ?? null;
}

/** Registers (or with null forgets) a decoded sprite; the loader and tests call it. */
export function setCosmeticArt(kind: 'decal' | 'wheel', i: number, px: Pixels | null): void {
  const m = kind === 'decal' ? decals : wheels;
  if (px) m.set(i, px);
  else m.delete(i);
}

/** Drops every decoded sprite (tests). */
export function clearCosmeticArt(): void {
  decals.clear();
  wheels.clear();
}

/** Mean of channel [ch] over the pixel block [x0, x1) × [y0, y1) (0..1). */
function blockMean(px: Pixels, x0: number, x1: number, y0: number, y1: number, ch: number): number {
  let s = 0, n = 0;
  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      s += px.data[(y * px.width + x) * 4 + ch]!;
      n++;
    }
  }
  return n ? s / n / 255 : 0;
}

/** Pixel range of block [i] of [n] over [size] px (at least one px). */
function span(i: number, n: number, size: number): [number, number] {
  const a = Math.floor((i * size) / n);
  return [a, Math.max(a + 1, Math.floor(((i + 1) * size) / n))];
}

/**
 * A decal sprite stretched over the car rectangle 2 hl × 2 hw (no margin, specs/art.md v3
 * "Polep"), nose up = +x, image left = +y: blocks with alpha ≥ 0.5 merged into runs across,
 * as counter-clockwise rectangles. The caller clips them to the painted body.
 */
export function decalRaster(px: Pixels, hl: number, hw: number, cols = DECAL_GRID_COLS, rows = DECAL_GRID_ROWS): Poly[] {
  const out: Poly[] = [];
  const dx = (2 * hl) / rows, dy = (2 * hw) / cols;
  for (let r = 0; r < rows; r++) {
    const [py0, py1] = span(r, rows, px.height);
    const xa = hl - (r + 1) * dx, xb = hl - r * dx;
    let run = -1;
    for (let c = 0; c <= cols; c++) {
      let on = false;
      if (c < cols) {
        const [px0, px1] = span(c, cols, px.width);
        on = blockMean(px, px0, px1, py0, py1, 3) >= 0.5;
      }
      if (on && run < 0) run = c;
      if (!on && run >= 0) {
        // Columns run..c-1: y from hw − c·dy up to hw − run·dy.
        const ya = hw - c * dy, yb = hw - run * dy;
        out.push([xa, ya, xb, ya, xb, yb, xa, yb]);
        run = -1;
      }
    }
  }
  return out;
}

/**
 * A garage wheel sprite over the procedural wheel rectangle [x0, y0]–[x1, y1] (car space, nose
 * up): one rectangle per opaque block, colour = mean rgb × [tint] (`color.garage.wheels[i]`).
 * [mirror] flips it across (wheels on the left side, +y).
 */
export function wheelRaster(px: Pixels, x0: number, y0: number, x1: number, y1: number, tint: Rgba, mirror = false,
  n = WHEEL_GRID): Array<{ poly: Poly; color: Rgba }> {
  const out: Array<{ poly: Poly; color: Rgba }> = [];
  const dx = (x1 - x0) / n, dy = (y1 - y0) / n;
  for (let r = 0; r < n; r++) {
    const [py0, py1] = span(r, n, px.height);
    for (let c = 0; c < n; c++) {
      const [px0, px1] = span(mirror ? n - 1 - c : c, n, px.width);
      if (blockMean(px, px0, px1, py0, py1, 3) < 0.5) continue;
      const color: Rgba = [
        blockMean(px, px0, px1, py0, py1, 0) * tint[0],
        blockMean(px, px0, px1, py0, py1, 1) * tint[1],
        blockMean(px, px0, px1, py0, py1, 2) * tint[2],
        1,
      ];
      const xa = x1 - (r + 1) * dx, xb = x1 - r * dx, ya = y1 - (c + 1) * dy, yb = y1 - c * dy;
      out.push({ poly: [xa, ya, xb, ya, xb, yb, xa, yb], color });
    }
  }
  return out;
}
