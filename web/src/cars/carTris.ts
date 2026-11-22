import type { CarSpec } from '../gen/schema';
import { tokens } from '../gen/tokens';
import { Tris } from '../render/geometry';
import { rgba, type Rgba } from '../render/palette';
import type { ParkedCar } from './parked';
import { carShape, paintHex, type CarRect } from './shape';

/** Height step between car parts (painter's order of carShape). */
export const CAR_PART_DZ = 0.01;

function partColor(r: CarRect, paint: Rgba, night: boolean): Rgba {
  switch (r.part) {
    case 'shadow': return rgba(tokens.colorCarShadow);
    case 'body': return paint;
    case 'cabin': return rgba(tokens.colorCarCabin);
    case 'glass': {
      const g = rgba(tokens.colorUiText);
      return [paint[0] * 0.88 + g[0] * 0.12, paint[1] * 0.88 + g[1] * 0.12, paint[2] * 0.88 + g[2] * 0.12, 1];
    }
    case 'head': return rgba(night ? tokens.colorCarHeadlightNight : tokens.colorCarHeadlightDay);
    case 'tail': return rgba(tokens.colorCarTail);
    case 'tyre': return rgba(tokens.colorCarTyre);
    default: return rgba(r.color ?? tokens.colorCarStripe);
  }
}

/**
 * Adds a car's top-down shape at (ox, oy, ang) to [t]; returns the height above [h] of the top part.
 * Tyres are added when [tyres] is set (parked cars; the player's car steers its own wheel nodes);
 * `micro` cars carry their in-line wheels in the shape itself. [shadow] false leaves the ground
 * shadow out (the player's car draws it apart, so it stays on the ground during a hop).
 */
export function carTris(
  t: Tris, spec: CarSpec, hl: number, hw: number, axle: number,
  ox: number, oy: number, ang: number, h: number, night: boolean, tyres: boolean, shadow = true,
): number {
  const paint = rgba(paintHex(spec.paint));
  let z = h;
  if (tyres && spec.class !== 'micro') {
    const ww = hl * 0.36, wt = hw * 0.32, c = rgba(tokens.colorCarTyre);
    for (const fx of [axle, -axle]) {
      for (const sy of [hw * 0.92, -hw * 0.92]) t.rect(ox, oy, ang, fx - ww / 2, sy - wt / 2, fx + ww / 2, sy + wt / 2, h + CAR_PART_DZ, c);
    }
  }
  carShape(spec.class, hl, hw, spec.length_m).forEach((r, i) => {
    z = h + (r.part === 'shadow' ? 0 : (i + 2) * CAR_PART_DZ);
    if (r.part === 'shadow' && !shadow) return;
    t.rect(ox, oy, ang, r.x0, r.y0, r.x1, r.y1, z, partColor(r, paint, night));
  });
  return z - h;
}

/** The ground shadow of a car shape alone (see carTris [shadow]). */
export function carShadowTris(t: Tris, spec: CarSpec, hl: number, hw: number, h: number): void {
  for (const r of carShape(spec.class, hl, hw, spec.length_m)) {
    if (r.part === 'shadow') t.rect(0, 0, 0, r.x0, r.y0, r.x1, r.y1, h, rgba(tokens.colorCarShadow));
  }
}

/** Underside seen during a flip (specs/hop.md "Kreslení"): the body outline in `color.car.tyre`, at [h]. */
export function carUndersideTris(t: Tris, hl: number, hw: number, h: number): void {
  t.rect(0, 0, 0, -hl, -hw, hl, hw, h, rgba(tokens.colorCarTyre));
}

/** One mesh's worth of parked cars. */
export function parkedTris(cars: Iterable<ParkedCar>, specs: ReadonlyMap<string, CarSpec>, scale: number, axleOffset: number, h: number): Tris {
  const t = new Tris();
  for (const p of cars) {
    const s = specs.get(p.carId);
    if (!s) continue;
    const hl = (s.length_m * scale) / 2, hw = (s.width_m * scale) / 2;
    carTris(t, s, hl, hw, hl * axleOffset, p.x, p.y, p.heading, h, false, true);
  }
  return t;
}
