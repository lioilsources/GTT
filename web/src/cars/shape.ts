import { tokens } from '../gen/tokens';

/**
 * Top-down vector shape of a car by class (specs/cars.md "Kreslení", P2, v2). Rectangles (and a
 * few convex polygons) in car space: x forward, y left, in metres after car_scale.
 * Port: app/lib/game/paint/car_shape.dart. ComfyUI sprites (METROPOLE_PLAN 10) will replace this
 * drawing later; sizes stay from the JSON.
 */
export type CarPart = 'shadow' | 'body' | 'cabin' | 'glass' | 'stripe' | 'detail' | 'head' | 'tail' | 'tyre';

export interface CarRect {
  part: CarPart;
  /** Bounding box (the rectangle itself unless [poly] is set). */
  x0: number;
  y0: number;
  x1: number;
  y1: number;
  /** Colour for `stripe`/`detail` parts (token hex); other parts are coloured by the client. */
  color?: string;
  /** A convex counter-clockwise polygon (flat x, y pairs) drawn instead of the box. */
  poly?: number[];
}

/** Cabin span along x as fractions of hl (specs/cars.md "Kreslení"). */
const cabins: Record<string, [number, number]> = {
  coupe: [-0.42, 0.3],
  hatchback: [-0.7, 0.25],
  muscle: [-0.5, 0.1],
  taxi: [-0.45, 0.3],
  pickup: [0.05, 0.45],
  mini: [-0.55, 0.35],
  sedan: [-0.45, 0.25],
  kombi: [-0.75, 0.25],
  supersport: [-0.3, 0.15],
  veteran: [-0.4, 0.15],
  offroad: [-0.6, 0.3],
  limo: [-0.55, 0.35],
  trike: [-0.35, 0.1],
};

/** Body colour of a car spec (token key in color.carPaint). */
export function paintHex(paint: string): string {
  return tokens.colorCarPaint[paint] ?? tokens.colorCarPaint['comet_red']!;
}

/** Below this JSON length a `micro` car is drawn as a scooter, otherwise as a bicycle. */
const SCOOTER_MAX_LENGTH_M = 1.5;
/** JSON lengths splitting `special` (specs/cars.md): food truck ≥ 5 m, trike 2.8–5 m, rickshaw below. */
const FOOD_TRUCK_MIN_LENGTH_M = 5;
const TRIKE_MIN_LENGTH_M = 2.8;

/** The drawing variant of a class: `special` splits by JSON length into three shapes. */
export type ShapeKind = string;

export function shapeKind(cls: string, lengthM: number): ShapeKind {
  if (cls !== 'special') return cls;
  if (lengthM >= FOOD_TRUCK_MIN_LENGTH_M) return 'foodtruck';
  return lengthM >= TRIKE_MIN_LENGTH_M ? 'trike' : 'rickshaw';
}

/** Centre of one wheel in car space. [front] steers; [top] is drawn over the body (single front wheel). */
export interface WheelPos {
  x: number;
  y: number;
  front: boolean;
  top: boolean;
}

/**
 * Wheel centres of a class (specs/cars.md): four at ±[axle] on ±0.92 hw; `bus` on −0.70 and 0.60 hl;
 * trike and rickshaw one front wheel in the middle on 0.75 hl. `micro` carries its wheels in the shape.
 */
export function wheelLayout(cls: string, hl: number, hw: number, axle: number, lengthM = 0): WheelPos[] {
  const kind = shapeKind(cls, lengthM);
  if (kind === 'micro') return [];
  const side = (x: number, front: boolean): WheelPos[] => [
    { x, y: hw * 0.92, front, top: false }, { x, y: -hw * 0.92, front, top: false }];
  if (kind === 'trike' || kind === 'rickshaw') return [{ x: hl * 0.75, y: 0, front: true, top: true }, ...side(-axle, false)];
  if (kind === 'bus') return [...side(hl * 0.6, true), ...side(-hl * 0.7, false)];
  return [...side(axle, true), ...side(-axle, false)];
}

/** Tyre size (length along x, width along y): 0.36 hl × 0.32 hw, no longer than hw on long cars. */
export function wheelSize(hl: number, hw: number): [number, number] {
  return [Math.min(hl * 0.36, hw), hw * 0.32];
}

type RectFn = (part: CarPart, x0: number, y0: number, x1: number, y1: number, color?: string) => CarRect;

const rectFn: RectFn = (part, x0, y0, x1, y1, color) =>
  color === undefined ? { part, x0, y0, x1, y1 } : { part, x0, y0, x1, y1, color };

/** A convex polygon part with its bounding box. */
function polyPart(part: CarPart, poly: number[], color?: string): CarRect {
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (let i = 0; i < poly.length; i += 2) {
    x0 = Math.min(x0, poly[i]!);
    x1 = Math.max(x1, poly[i]!);
    y0 = Math.min(y0, poly[i + 1]!);
    y1 = Math.max(y1, poly[i + 1]!);
  }
  const r: CarRect = { part, x0, y0, x1, y1, poly };
  if (color !== undefined) r.color = color;
  return r;
}

/** Circle as a convex counter-clockwise polygon. */
function circle(cx: number, cy: number, rad: number, segs = 14): number[] {
  const out: number[] = [];
  for (let i = 0; i < segs; i++) {
    const a = (i * 2 * Math.PI) / segs;
    out.push(cx + rad * Math.cos(a), cy + rad * Math.sin(a));
  }
  return out;
}

/**
 * Shape of class [cls] with half extents [hl] x [hw]; [lengthM] is the car's JSON `length_m`
 * (`micro` and `special` use it to pick their variant), [axle] the wheel distance from the centre
 * (veteran fenders sit over the wheels).
 */
export function carShape(cls: string, hl: number, hw: number, lengthM = 0, axle = 0): CarRect[] {
  const r = rectFn;
  const kind = shapeKind(cls, lengthM);
  if (kind === 'micro') return microShape(r, hl, hw, lengthM < SCOOTER_MAX_LENGTH_M);
  // Body half width: veterans have a narrow body between the fenders.
  const bw = kind === 'veteran' ? hw * 0.8 : hw;
  const out: CarRect[] = [r('shadow', -hl + 0.6, -hw - 0.6, hl + 0.6, hw - 0.6)];
  if (kind === 'trike') {
    // Body narrowed to ±0.45 hw in front of 0.30 hl.
    out.push(polyPart('body', [-hl, -hw, hl * 0.3, -hw, hl, -hw * 0.45, hl, hw * 0.45, hl * 0.3, hw, -hl, hw]));
  } else if (kind === 'rickshaw') {
    // The passenger cart behind, the bicycle frame in front (like a `micro` bicycle).
    out.push(r('body', -hl, -hw, hl * 0.3, hw), r('body', hl * 0.3, -hw * 0.12, hl * 0.92, hw * 0.12));
  } else {
    out.push(r('body', -hl, -bw, hl, bw));
  }
  if (kind === 'pickup') {
    out.push(r('detail', -hl * 0.95, -hw * 0.85, -hl * 0.05, hw * 0.85, tokens.colorCarDetailBedRim));
    out.push(r('detail', -hl * 0.9, -hw * 0.72, -hl * 0.1, hw * 0.72, tokens.colorCarDetailBed));
  }
  if (kind === 'muscle') {
    for (const [a, b] of [[-0.32, -0.12], [0.12, 0.32]] as const) {
      out.push(r('detail', -hl * 0.98, hw * a, hl * 0.98, hw * b, tokens.colorCarDetailMuscleStripe));
    }
  }
  if (kind === 'veteran') {
    // A fender over each wheel on its outer side.
    for (const w of wheelLayout(cls, hl, hw, axle, lengthM)) {
      const y0 = w.y > 0 ? hw * 0.7 : -hw, y1 = w.y > 0 ? hw : -hw * 0.7;
      out.push(r('detail', w.x - hl * 0.16, y0, w.x + hl * 0.16, y1, tokens.colorCarDetailFender));
    }
  }
  if (kind === 'van' || kind === 'foodtruck') {
    // Only the windscreen; the rest of the roof is the cargo box (paint + cargoRoof).
    out.push(r('detail', -hl * 0.98, -hw * 0.9, hl * 0.55, hw * 0.9, tokens.colorCarDetailCargoRoof));
    out.push(r('cabin', hl * 0.58, -hw * 0.82, hl * 0.88, hw * 0.82));
    out.push(r('glass', hl * 0.62, -hw * 0.72, hl * 0.85, hw * 0.72));
  } else if (kind === 'bus') {
    // No cabin: the roof is the paint; the windscreen across the nose, two roof AC units.
    out.push(r('cabin', hl * 0.9, -hw * 0.9, hl, hw * 0.9));
    out.push(r('glass', hl * 0.92, -hw * 0.82, hl, hw * 0.82));
    for (const [a, b] of [[-0.3, -0.1], [0.2, 0.4]] as const) {
      out.push(r('detail', hl * a, -hw * 0.4, hl * b, hw * 0.4, tokens.colorCarDetailBusRoofUnit));
    }
  } else if (kind === 'rickshaw') {
    // Rider and handlebar on the frame, canopy over the passenger seat.
    out.push(r('tyre', hl * 0.6, -hw * 0.45, hl * 0.66, hw * 0.45));
    out.push(r('cabin', hl * 0.28, -hw * 0.3, hl * 0.56, hw * 0.3));
    out.push(r('detail', -hl * 0.9, -hw, hl * 0.1, hw, tokens.colorCarDetailCanopy));
  } else {
    const [c0, c1] = cabins[kind] ?? cabins['coupe']!;
    const cw = kind === 'supersport' ? 0.7 : 0.78;
    out.push(r('cabin', hl * c0, -bw * cw, hl * c1, bw * cw));
    const g0 = hl * c0 + hl * 0.12, g1 = hl * c1 - hl * 0.18;
    const gw = bw * (cw - 0.12);
    const gx1 = Math.max(g1, g0 + hl * 0.08);
    out.push(r('glass', g0, -gw, gx1, gw));
    if (kind === 'limo') {
      for (const x of [-0.25, 0.05]) out.push(r('detail', hl * (x - 0.02), -gw, hl * (x + 0.02), gw, tokens.colorCarDetailLimoPillar));
    }
  }
  if (kind === 'coupe') {
    out.push(r('stripe', hl * 0.3, -hw * 0.12, hl * 0.98, hw * 0.12, tokens.colorCarStripe));
    out.push(r('stripe', -hl * 0.98, -hw * 0.12, -hl * 0.42, hw * 0.12, tokens.colorCarStripe));
  }
  if (kind === 'taxi') {
    out.push(r('detail', -hl * 0.15, -hw * 0.35, hl * 0.05, hw * 0.35, tokens.colorCarDetailTaxiSign));
    for (let i = 0; i < 6; i++) {
      const x0 = -hl * 0.6 + i * hl * 0.2;
      if (i % 2 === 0) {
        out.push(r('detail', x0, hw * 0.86, x0 + hl * 0.1, hw * 0.98, tokens.colorCarDetailTaxiChecker));
        out.push(r('detail', x0, -hw * 0.98, x0 + hl * 0.1, -hw * 0.86, tokens.colorCarDetailTaxiChecker));
      }
    }
  }
  if (kind === 'kombi') {
    for (const s of [1, -1]) {
      const y = s * hw * 0.7;
      out.push(r('detail', -hl * 0.7, y - hw * 0.03, hl * 0.2, y + hw * 0.03, tokens.colorCarDetailRoofRail));
    }
  }
  if (kind === 'supersport') out.push(r('detail', -hl, -hw * 0.95, -hl * 0.9, hw * 0.95, tokens.colorCarDetailSpoiler));
  if (kind === 'offroad') out.push(polyPart('detail', circle(-hl * 0.98, 0, hw * 0.45), tokens.colorCarDetailSpare));
  if (kind === 'foodtruck') {
    // Awning on the right side (y < 0), stripes of 0.15 hl alternating.
    for (let i = 0; i < 6; i++) {
      const x0 = -hl * 0.6 + i * hl * 0.15;
      out.push(r('detail', x0, -hw, x0 + hl * 0.15, -hw * 0.8, i % 2 === 0 ? tokens.colorCarDetailAwningA : tokens.colorCarDetailAwningB));
    }
  }
  out.push(...lights(kind, hl, bw));
  return out;
}

/** Head and tail lights inside the body outline (trike: in the narrow nose, rickshaw: one lamp on the bar). */
function lights(kind: ShapeKind, hl: number, bw: number): CarRect[] {
  const r = rectFn;
  const tails = [r('tail', -hl, bw * 0.5, -hl * 0.92, bw * 0.85), r('tail', -hl, -bw * 0.85, -hl * 0.92, -bw * 0.5)];
  if (kind === 'rickshaw') return [r('head', hl * 0.66, -bw * 0.1, hl * 0.72, bw * 0.1), ...tails];
  if (kind === 'trike') return [r('head', hl * 0.9, bw * 0.2, hl, bw * 0.4), r('head', hl * 0.9, -bw * 0.4, hl, -bw * 0.2), ...tails];
  return [r('head', hl * 0.9, bw * 0.5, hl, bw * 0.85), r('head', hl * 0.9, -bw * 0.85, hl, -bw * 0.5), ...tails];
}

/**
 * Scooter or bicycle seen from above (specs/cars.md "Kreslení podle třídy"): deck or frame in the
 * paint, two in-line wheels, handlebar, rider blob; no lights. Wheels are part of the shape.
 */
function microShape(r: RectFn, hl: number, hw: number, scooter: boolean): CarRect[] {
  const out: CarRect[] = [r('shadow', -hl + 0.3, -hw * 0.5 - 0.3, hl + 0.3, hw * 0.5 - 0.3)];
  if (scooter) {
    out.push(r('tyre', hl * 0.62, -hw * 0.2, hl * 0.98, hw * 0.2), r('tyre', -hl * 0.98, -hw * 0.2, -hl * 0.62, hw * 0.2));
    out.push(r('body', -hl * 0.75, -hw * 0.38, hl * 0.5, hw * 0.38));
    // Stem and handlebar.
    out.push(r('body', hl * 0.5, -hw * 0.12, hl * 0.72, hw * 0.12));
    out.push(r('tyre', hl * 0.64, -hw * 0.95, hl * 0.74, hw * 0.95));
    out.push(r('cabin', -hl * 0.3, -hw * 0.62, hl * 0.3, hw * 0.62));
  } else {
    out.push(r('tyre', hl * 0.5, -hw * 0.14, hl * 0.98, hw * 0.14), r('tyre', -hl * 0.98, -hw * 0.14, -hl * 0.5, hw * 0.14));
    out.push(r('body', -hl * 0.6, -hw * 0.16, hl * 0.6, hw * 0.16));
    out.push(r('tyre', hl * 0.42, -hw * 0.95, hl * 0.5, hw * 0.95));
    out.push(r('cabin', -hl * 0.4, -hw * 0.66, hl * 0.25, hw * 0.66));
  }
  return out;
}
