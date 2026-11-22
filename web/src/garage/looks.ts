import type { CarSpec } from '../gen/schema';
import { tokens } from '../gen/tokens';
import type { CarRect } from '../cars/shape';
import { paintHex } from '../cars/shape';
import type { Look } from './rules';

/**
 * Drawing of looks (specs/garage.md "Kreslení", P1), pure: colours and polygons in car space
 * (x forward, y left, metres after car_scale). The world mesh (carTris) and the garage preview
 * (canvas) both draw these, so the preview looks the same as the car in the world.
 */

/** Body colour hex: the catalog paint for 0, `color.garage.paints[i − 1]` otherwise. */
export function lookPaint(spec: CarSpec, look: Look | null): string {
  const i = look?.paint ?? 0;
  return (i >= 1 ? tokens.colorGaragePaints[i - 1] : undefined) ?? paintHex(spec.paint);
}

/** Rim colour hex of an own car (`color.garage.wheels[value]`). */
export function lookRim(look: Look | null): string {
  const i = look?.wheels ?? 0;
  return tokens.colorGarageWheels[i] ?? tokens.colorGarageWheels[0]!;
}

/** Underglow colour hex (with alpha) or null for none. */
export function lookGlow(look: Look | null): string | null {
  const i = look?.glow ?? 0;
  return i >= 1 ? (tokens.colorGarageGlow[i - 1] ?? null) : null;
}

/** Smoke colour hex (stored and shown in the garage only in v1). */
export function lookSmoke(look: Look | null): string {
  const i = look?.smoke ?? 0;
  return (i >= 1 ? tokens.colorGarageSmoke[i - 1] : undefined) ?? tokens.colorGarageSmoke[0]!;
}

/** Underglow strength: full at night or in a tunnel, garage.glow_day by day. */
export function glowStrength(night: boolean, tunnel: boolean, glowDay: number): number {
  return night || tunnel ? 1 : glowDay;
}

/** A convex polygon in car space as flat x, y pairs, counter-clockwise. */
export type Poly = number[];

const rect = (x0: number, y0: number, x1: number, y1: number): Poly => [x0, y0, x1, y0, x1, y1, x0, y1];

/**
 * Decal polygons (`color.garage.decal`) over the body rectangle [b] of the shape: stripes = two
 * long stripes at ±0.22 hw over the whole car; flames = three triangles from the nose back to
 * 0.35 hl; checker = a band of squares along both sides.
 */
export function decalPolys(decal: number, b: Pick<CarRect, 'x0' | 'y0' | 'x1' | 'y1'>): Poly[] {
  const hl = (b.x1 - b.x0) / 2, hw = (b.y1 - b.y0) / 2;
  const cx = (b.x0 + b.x1) / 2, cy = (b.y0 + b.y1) / 2;
  const out: Poly[] = [];
  if (decal === 1) {
    const w = hw * 0.07;
    for (const s of [1, -1]) out.push(rect(cx - hl, cy + s * hw * 0.22 - w, cx + hl, cy + s * hw * 0.22 + w));
  } else if (decal === 2) {
    // Bases across the nose, tips pointing back to x = 0.35 hl.
    const nose = cx + hl * 0.98, tip = cx + hl * 0.35;
    for (const [y0, y1, back] of [[-0.85, -0.3, 0.12], [-0.28, 0.28, 0], [0.3, 0.85, 0.12]] as const) {
      out.push([nose, cy + hw * y0, nose, cy + hw * y1, tip + hl * back, cy + (hw * (y0 + y1)) / 2]);
    }
  } else if (decal === 3) {
    const sq = hw * 0.16, n = Math.max(2, Math.floor((hl * 1.6) / sq));
    const x0 = cx - (n * sq) / 2;
    for (const side of [1, -1]) {
      for (let row = 0; row < 2; row++) {
        const ya = cy + side * hw * (0.96 - row * 0.16), yb = ya - side * sq;
        for (let i = 0; i < n; i++) {
          if ((i + row) % 2 !== 0) continue;
          const xa = x0 + i * sq;
          out.push(rect(xa, Math.min(ya, yb), xa + sq, Math.max(ya, yb)));
        }
      }
    }
  }
  return out.map(ccw);
}

/** Rounded rectangle [margin] past the body outline (underglow), as one convex polygon. */
export function glowPoly(hl: number, hw: number, margin: number, segs = 4): Poly {
  const r = Math.max(margin, 0.05), ax = hl + margin - r, ay = hw + margin - r;
  const out: Poly = [];
  const corners: Array<[number, number, number]> = [[ax, ay, 0], [-ax, ay, Math.PI / 2], [-ax, -ay, Math.PI], [ax, -ay, (3 * Math.PI) / 2]];
  for (const [x, y, a0] of corners) {
    for (let i = 0; i <= segs; i++) {
      const a = a0 + (i * Math.PI) / 2 / segs;
      out.push(x + r * Math.cos(a), y + r * Math.sin(a));
    }
  }
  return out;
}

/** The polygon counter-clockwise (positive signed area). */
function ccw(p: Poly): Poly {
  let a = 0;
  for (let i = 0; i < p.length; i += 2) {
    const j = (i + 2) % p.length;
    a += p[i]! * p[j + 1]! - p[j]! * p[i + 1]!;
  }
  if (a >= 0) return p;
  const out: Poly = [];
  for (let i = p.length - 2; i >= 0; i -= 2) out.push(p[i]!, p[i + 1]!);
  return out;
}
