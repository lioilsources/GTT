import type { CarSpec } from '../gen/schema';
import { tokens } from '../gen/tokens';
import { Tris } from '../render/geometry';
import { rgba, type Rgba } from '../render/palette';
import { decalArt, decalRaster, wheelArt, wheelRaster } from '../garage/cosmetics';
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
 * A decal with a sprite (specs/art.md v3, `decalArt`) replaces the procedural one: its raster
 * over the car rectangle 2 hl × 2 hw, clipped to the body and drawn right over it (only the
 * painted body, under the glass, details and lights).
 */
export function carPrims(spec: CarSpec, hl: number, hw: number, night: boolean, look: Look | null = null,
  shadowCol: Rgba = rgba(tokens.colorCarShadow), axle = 0): CarPrim[] {
  const paint = rgba(look ? lookPaint(spec, look) : paintHex(spec.paint));
  const shape = carShape(spec.class, hl, hw, spec.length_m, axle);
  const out: CarPrim[] = [];
  const body = shape.find((r) => r.part === 'body');
  const decal = body ? (look?.decal ?? 0) : 0;
  const art = decal !== 0 ? decalArt(decal) : null;
  let pending = decal !== 0;
  const addDecal = (): void => {
    pending = false;
    if (art) {
      const clip = body!.poly ?? rectPoly(body!);
      for (const p of decalRaster(art, hl, hw)) {
        const poly = clipConvex(p, clip);
        if (poly.length >= 6) out.push({ part: 'decal', poly, color: rgba(tokens.colorGarageDecal) });
      }
      return;
    }
    for (const p of decalPolys(decal, body!)) {
      const poly = body!.poly ? clipConvex(p, body!.poly) : p;
      if (poly.length >= 6) out.push({ part: 'decal', poly, color: rgba(tokens.colorGarageDecal) });
    }
  };
  for (const r of shape) {
    if (pending && (r.part === 'head' || r.part === 'tail')) addDecal();
    out.push({ part: r.part, poly: rectPoly(r), color: partColor(r, paint, night, shadowCol) });
    if (pending && art && r === body) addDecal();
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

/**
 * One procedural wheel of a car with [look] (null = catalog: the tyre only), in car space shifted
 * by (−dx, −dy): the tyre and the rim in `color.garage.wheels[value]`; with a garage wheel sprite
 * (specs/art.md v3 "Kola", `wheelArt`) its raster over the tyre rectangle instead, tinted by the
 * rim colour, mirrored on the left side.
 */
export function wheelPrims(w: WheelRect, look: Look | null, dx = 0, dy = 0): Array<{ poly: Poly; color: Rgba }> {
  const r = (x0: number, y0: number, x1: number, y1: number): Poly => [x0 - dx, y0 - dy, x1 - dx, y0 - dy, x1 - dx, y1 - dy, x0 - dx, y1 - dy];
  const v = look?.wheels ?? 0, art = v > 0 ? wheelArt(v) : null;
  if (art) {
    return wheelRaster(art, w.x0 - dx, w.y0 - dy, w.x1 - dx, w.y1 - dy, rgba(lookRim(look)), (w.y0 + w.y1) / 2 > 0);
  }
  const out = [{ poly: r(w.x0, w.y0, w.x1, w.y1), color: rgba(tokens.colorCarTyre) }];
  if (look) out.push({ poly: r(w.rim[0], w.rim[1], w.rim[2], w.rim[3]), color: rgba(lookRim(look)) });
  return out;
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
  const wheel = (w: WheelRect, at: number): void => {
    wheelPrims(w, look).forEach((p, i) => polyTris(t, ox, oy, ang, p.poly, at + (i > 0 ? CAR_PART_DZ * 0.5 : 0), p.color));
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
export function carShadowTris(t: Tris, spec: CarSpec, hl: number, hw: number, h: number, col: Rgba = rgba(tokens.colorCarShadow),
  ox = 0, oy = 0, ang = 0): void {
  for (const r of carShape(spec.class, hl, hw, spec.length_m)) {
    if (r.part === 'shadow') t.rect(ox, oy, ang, r.x0, r.y0, r.x1, r.y1, h, col);
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
  /** Cars drawn as sprites (specs/art.md v2): only their shadow (and underglow) go into the mesh. */
  sprite: ((p: ParkedCar, look: Look | null) => boolean) | null = null,
): Tris {
  const t = new Tris();
  for (const p of cars) {
    const s = specs.get(p.carId);
    if (!s) continue;
    const hl = (s.length_m * scale) / 2, hw = (s.width_m * scale) / 2;
    const look = lookOf?.(p) ?? null;
    if (look) carGlowTris(t, look, hl, hw, glow.margin, p.x, p.y, p.heading, h - CAR_PART_DZ, glow.strength);
    if (sprite?.(p, look)) {
      carShadowTris(t, s, hl, hw, h, shadow, p.x, p.y, p.heading);
      continue;
    }
    carTris(t, s, hl, hw, hl * axleOffset, p.x, p.y, p.heading, h, false, true, true, shadow, look);
  }
  return t;
}
