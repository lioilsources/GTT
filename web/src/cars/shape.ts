import { tokens } from '../gen/tokens';

/**
 * Top-down vector shape of a car by class (specs/cars.md "Kreslení", P2). Rectangles in car
 * space: x forward, y left, in metres after car_scale. Port: app/lib/game/paint/car_shape.dart.
 * ComfyUI sprites (METROPOLE_PLAN 10) will replace this drawing later; sizes stay from the JSON.
 */
export type CarPart = 'shadow' | 'body' | 'cabin' | 'glass' | 'stripe' | 'detail' | 'head' | 'tail';

export interface CarRect {
  part: CarPart;
  x0: number;
  y0: number;
  x1: number;
  y1: number;
  /** Colour for `stripe`/`detail` parts (token hex); other parts are coloured by the client. */
  color?: string;
}

interface Cabin {
  c0: number;
  c1: number;
}

const cabins: Record<string, Cabin> = {
  coupe: { c0: -0.42, c1: 0.3 },
  hatchback: { c0: -0.7, c1: 0.25 },
  muscle: { c0: -0.5, c1: 0.1 },
  taxi: { c0: -0.45, c1: 0.3 },
  pickup: { c0: 0.05, c1: 0.45 },
};

/** Body colour of a car spec (token key in color.carPaint). */
export function paintHex(paint: string): string {
  return tokens.colorCarPaint[paint] ?? tokens.colorCarPaint['comet_red']!;
}

export function carShape(cls: string, hl: number, hw: number): CarRect[] {
  const r = (part: CarPart, x0: number, y0: number, x1: number, y1: number, color?: string): CarRect =>
    color === undefined ? { part, x0, y0, x1, y1 } : { part, x0, y0, x1, y1, color };
  const cab = cabins[cls] ?? cabins['coupe']!;
  const out: CarRect[] = [r('shadow', -hl + 0.6, -hw - 0.6, hl + 0.6, hw - 0.6), r('body', -hl, -hw, hl, hw)];
  if (cls === 'pickup') {
    out.push(r('detail', -hl * 0.95, -hw * 0.85, -hl * 0.05, hw * 0.85, tokens.colorCarDetailBedRim));
    out.push(r('detail', -hl * 0.9, -hw * 0.72, -hl * 0.1, hw * 0.72, tokens.colorCarDetailBed));
  }
  if (cls === 'muscle') {
    for (const s of [-1, 1]) {
      out.push(r('detail', -hl * 0.98, s * hw * 0.12, hl * 0.98, s * hw * 0.32, tokens.colorCarDetailMuscleStripe));
    }
  }
  out.push(r('cabin', hl * cab.c0, -hw * 0.78, hl * cab.c1, hw * 0.78));
  const g0 = hl * cab.c0 + hl * 0.12, g1 = hl * cab.c1 - hl * 0.18;
  out.push(r('glass', g0, -hw * 0.66, Math.max(g1, g0 + hl * 0.08), hw * 0.66));
  if (cls === 'coupe') {
    out.push(r('stripe', hl * 0.3, -hw * 0.12, hl * 0.98, hw * 0.12, tokens.colorCarStripe));
    out.push(r('stripe', -hl * 0.98, -hw * 0.12, -hl * 0.42, hw * 0.12, tokens.colorCarStripe));
  }
  if (cls === 'taxi') {
    out.push(r('detail', -hl * 0.15, -hw * 0.35, hl * 0.05, hw * 0.35, tokens.colorCarDetailTaxiSign));
    for (let i = 0; i < 6; i++) {
      const x0 = -hl * 0.6 + i * hl * 0.2;
      if (i % 2 === 0) {
        out.push(r('detail', x0, hw * 0.86, x0 + hl * 0.1, hw * 0.98, tokens.colorCarDetailTaxiChecker));
        out.push(r('detail', x0, -hw * 0.98, x0 + hl * 0.1, -hw * 0.86, tokens.colorCarDetailTaxiChecker));
      }
    }
  }
  out.push(r('head', hl * 0.9, hw * 0.5, hl, hw * 0.85), r('head', hl * 0.9, -hw * 0.85, hl, -hw * 0.5));
  out.push(r('tail', -hl, hw * 0.5, -hl * 0.92, hw * 0.85), r('tail', -hl, -hw * 0.85, -hl * 0.92, -hw * 0.5));
  return out;
}
