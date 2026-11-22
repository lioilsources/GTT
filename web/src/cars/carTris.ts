import type { CarSpec } from '../gen/schema';
import { tokens } from '../gen/tokens';
import { Tris } from '../render/geometry';
import { rgba, type Rgba } from '../render/palette';
import { clipConvex, decalPolys, glowPoly, lookGlow, lookPaint, lookRim, type Poly } from '../garage/looks';
import type { Look } from '../garage/rules';
import type { ParkedCar } from './parked';
import { carShape, paintHex, wheelLayout, wheelSize, type CarPart, type CarRect } from './shape';

/** Height step between car parts (painter's order of carShape). */
export const CAR_PART_DZ = 0.01;

function partColor(r: CarRect, paint: Rgba, night: boolean, shadow: Rgba): Rgba {
  switch (r.part) {
    case 'shadow': return shadow;
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

/** One coloured polygon of a car in painter's order (car space, see garage/looks.ts). */
export interface CarPrim {
  part: CarPart | 'decal';
  poly: Poly;
  color: Rgba;
}

const rectPoly = (r: CarRect): Poly => r.poly ?? [r.x0, r.y0, r.x1, r.y0, r.x1, r.y1, r.x0, r.y1];

/**
 * The car's top-down shape with its look (specs/garage.md "Kreslení") in painter's order: the
 * class shape (shadow first) in the look's paint, the decal over the body and the class details
 * (muscle stripes, taxi sign stay under it), then the lights. [look] null = catalog drawing.
 * Decals are clipped to the body outline (the trike's narrow nose). [axle] places veteran fenders.
 */
export function carPrims(spec: CarSpec, hl: number, hw: number, night: boolean, look: Look | null = null,
  shadowCol: Rgba = rgba(tokens.colorCarShadow), axle = 0): CarPrim[] {
  const paint = rgba(look ? lookPaint(spec, look) : paintHex(spec.paint));
  const shape = carShape(spec.class, hl, hw, spec.length_m, axle);
  const out: CarPrim[] = [];
  const body = shape.find((r) => r.part === 'body');
  const decal = body ? (look?.decal ?? 0) : 0;
  let pending = decal !== 0;
  const addDecal = (): void => {
    pending = false;
    for (const p of decalPolys(decal, body!)) {
      const poly = body!.poly ? clipConvex(p, body!.poly) : p;
      if (poly.length >= 6) out.push({ part: 'decal', poly, color: rgba(tokens.colorGarageDecal) });
    }
  };
  for (const r of shape) {
    if (pending && (r.part === 'head' || r.part === 'tail')) addDecal();
    out.push({ part: r.part, poly: rectPoly(r), color: partColor(r, paint, night, shadowCol) });
  }
  if (pending) addDecal();
  return out;
}

export interface WheelRect {
  x0: number;
  y0: number;
  x1: number;
  y1: number;
  /** The rim inside the tyre (own cars, `color.garage.wheels`). */
  rim: [number, number, number, number];
  /** Steering wheel. */
  front: boolean;
  /** Drawn over the body (the single front wheel of a trike or rickshaw). */
  top: boolean;
}

/** Wheels of a non-micro car by class (local rectangles, specs/cars.md), each with its rim. */
export function wheelRects(hl: number, hw: number, axle: number, cls = 'coupe', lengthM = 0): WheelRect[] {
  const [ww, wt] = wheelSize(hl, hw), rw = ww * 0.5, rt = wt * 0.55;
  return wheelLayout(cls, hl, hw, axle, lengthM).map((w) => ({
    x0: w.x - ww / 2, y0: w.y - wt / 2, x1: w.x + ww / 2, y1: w.y + wt / 2,
    rim: [w.x - rw / 2, w.y - rt / 2, w.x + rw / 2, w.y + rt / 2],
    front: w.front, top: w.top,
  }));
}

/** Adds a convex counter-clockwise polygon in a local frame at (ox, oy) rotated by ang. */
export function polyTris(t: Tris, ox: number, oy: number, ang: number, p: Poly, h: number, c: Rgba): void {
  const cs = Math.cos(ang), sn = Math.sin(ang);
  const base = t.vertexCount;
  for (let i = 0; i < p.length; i += 2) t.vertex(ox + p[i]! * cs - p[i + 1]! * sn, oy + p[i]! * sn + p[i + 1]! * cs, h, c);
  for (let i = 1; i + 1 < p.length / 2; i++) t.tri(base, base + i, base + i + 1);
}

/**
 * Adds a car's top-down shape at (ox, oy, ang) to [t]; returns the height above [h] of the top part.
 * Tyres are added when [tyres] is set (parked cars; the player's car steers its own wheel nodes);
 * `micro` cars carry their in-line wheels in the shape itself. [shadow] false leaves the ground
 * shadow out (the player's car draws it apart, so it stays on the ground during a hop); [shadowCol]
 * is its colour (the city skin's `shadow` by day, specs/style.md). [look] = an own car's looks.
 */
export function carTris(
  t: Tris, spec: CarSpec, hl: number, hw: number, axle: number,
  ox: number, oy: number, ang: number, h: number, night: boolean, tyres: boolean, shadow = true,
  shadowCol: Rgba = rgba(tokens.colorCarShadow), look: Look | null = null,
): number {
  let z = h;
  const wheels = tyres ? wheelRects(hl, hw, axle, spec.class, spec.length_m) : [];
  const tyre = rgba(tokens.colorCarTyre), rim = look ? rgba(lookRim(look)) : null;
  const wheel = (w: WheelRect, at: number): void => {
    t.rect(ox, oy, ang, w.x0, w.y0, w.x1, w.y1, at, tyre);
    if (rim) t.rect(ox, oy, ang, w.rim[0], w.rim[1], w.rim[2], w.rim[3], at + CAR_PART_DZ * 0.5, rim);
  };
  for (const w of wheels) if (!w.top) wheel(w, h + CAR_PART_DZ);
  carPrims(spec, hl, hw, night, look, shadowCol, axle).forEach((p, i) => {
    z = h + (p.part === 'shadow' ? 0 : (i + 2) * CAR_PART_DZ);
    if (p.part === 'shadow' && !shadow) return;
    polyTris(t, ox, oy, ang, p.poly, z, p.color);
  });
  for (const w of wheels) {
    if (!w.top) continue;
    z += CAR_PART_DZ;
    wheel(w, z);
    z += CAR_PART_DZ * 0.5;
  }
  return z - h;
}

/**
 * Underglow of an own car (specs/garage.md "glow"): a rounded rectangle [margin] past the car,
 * under its shadow, in the look's colour with its alpha × [strength]. Nothing without a glow.
 */
export function carGlowTris(t: Tris, look: Look | null, hl: number, hw: number, margin: number,
  ox: number, oy: number, ang: number, h: number, strength: number): void {
  const hex = lookGlow(look);
  if (!hex) return;
  polyTris(t, ox, oy, ang, glowPoly(hl, hw, margin), h, rgba(hex, strength));
}

/** The ground shadow of a car shape alone (see carTris [shadow]). */
export function carShadowTris(t: Tris, spec: CarSpec, hl: number, hw: number, h: number, col: Rgba = rgba(tokens.colorCarShadow)): void {
  for (const r of carShape(spec.class, hl, hw, spec.length_m)) {
    if (r.part === 'shadow') t.rect(0, 0, 0, r.x0, r.y0, r.x1, r.y1, h, col);
  }
}

/** Underside seen during a flip (specs/hop.md "Kreslení"): the body outline in `color.car.tyre`, at [h]. */
export function carUndersideTris(t: Tris, hl: number, hw: number, h: number): void {
  t.rect(0, 0, 0, -hl, -hw, hl, hw, h, rgba(tokens.colorCarTyre));
}

/** One mesh's worth of parked cars. */
export function parkedTris(
  cars: Iterable<ParkedCar>, specs: ReadonlyMap<string, CarSpec>, scale: number, axleOffset: number, h: number,
  shadow: Rgba = rgba(tokens.colorCarShadow),
  /** Looks of the player's own parked cars (specs/garage.md); null = catalog drawing. */
  lookOf: ((p: ParkedCar) => Look | null) | null = null,
  glow: { margin: number; strength: number } = { margin: 0, strength: 0 },
): Tris {
  const t = new Tris();
  for (const p of cars) {
    const s = specs.get(p.carId);
    if (!s) continue;
    const hl = (s.length_m * scale) / 2, hw = (s.width_m * scale) / 2;
    const look = lookOf?.(p) ?? null;
    if (look) carGlowTris(t, look, hl, hw, glow.margin, p.x, p.y, p.heading, h - CAR_PART_DZ, glow.strength);
    carTris(t, s, hl, hw, hl * axleOffset, p.x, p.y, p.heading, h, false, true, true, shadow, look);
  }
  return t;
}
