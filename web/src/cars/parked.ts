import type { CarSpec } from '../gen/schema';
import type { Tuning } from '../gen/tuning';
import { Prng } from '../rules/prng';
import type { RoadGraph } from '../world/model';
import type { CarOwner } from './rules';

/**
 * A parked car at a curb (specs/cars.md "Zaparkovaná auta"). The fleet keeps the pose in sync with
 * its dynamic body (it can be pushed) and fills the half extents.
 */
export interface ParkedCar {
  carId: string;
  owner: CarOwner;
  x: number;
  y: number;
  heading: number;
  /** Half length and width in metres (after car_scale); set by the fleet. */
  hl?: number;
  hw?: number;
  /** Chunk key it was generated for; null for a car the player left behind (kept until forget_m). */
  chunk: number | null;
}

interface Seg {
  ax: number;
  ay: number;
  dx: number;
  dy: number;
  l: number;
  width: number;
}

/**
 * Models that park in [cityId]: cars.parked.models in list order, only cars tagged with the city
 * (specs/cars.md; in New York that is every original model, so its generation is unchanged).
 */
export function parkedPool(models: readonly string[], specs: ReadonlyMap<string, CarSpec>, cityId: string): string[] {
  return models.filter((id) => specs.get(id)?.tags.includes(cityId) ?? false);
}

/**
 * Places parked cars for chunk (cx, cy) with the shared PRNG; every attempt draws four numbers
 * (segment, position, side, model) so both clients consume the stream identically.
 */
export function generateParked(
  graph: RoadGraph,
  cx: number,
  cy: number,
  chunk: number,
  tuning: Tuning,
  specs: ReadonlyMap<string, CarSpec>,
  avoid: ReadonlyArray<{ x: number; y: number }>,
  player: { x: number; y: number },
  cityId: string,
): ParkedCar[] {
  const t = tuning.cars.parked;
  const chunkM = tuning.chunkM;
  const x0 = cx * chunkM, y0 = cy * chunkM;
  const segs: Seg[] = [];
  for (const e of graph.edges) {
    if (!e.kept || !e.isGround || e.bridge || !t.classes.includes(e.roadClass)) continue;
    for (let s = 0; s + 1 < e.pointCount; s++) {
      const ax = e.pts[2 * s]!, ay = e.pts[2 * s + 1]!, bx = e.pts[2 * s + 2]!, by = e.pts[2 * s + 3]!;
      const mx = (ax + bx) / 2, my = (ay + by) / 2;
      if (mx < x0 || mx >= x0 + chunkM || my < y0 || my >= y0 + chunkM) continue;
      const dx = bx - ax, dy = by - ay;
      const l = Math.sqrt(dx * dx + dy * dy);
      if (l <= 2 * t.segmentMarginM) continue;
      segs.push({ ax, ay, dx: dx / l, dy: dy / l, l, width: e.width });
    }
  }
  const out: ParkedCar[] = [];
  const pool = parkedPool(t.models, specs, cityId);
  if (segs.length === 0 || pool.length === 0) return out;
  const rnd = new Prng((Math.imul(cx, 73856093) ^ Math.imul(cy, 19349663) ^ t.salt) >>> 0);
  const far = (x: number, y: number, p: { x: number; y: number }, d: number): boolean => (x - p.x) ** 2 + (y - p.y) ** 2 >= d * d;
  for (let i = 0; i < t.attempts && out.length < t.perChunk; i++) {
    const seg = segs[rnd.nextInt(segs.length)]!;
    const along = rnd.nextInt(1000);
    const side = rnd.nextInt(2);
    const model = pool[rnd.nextInt(pool.length)]!;
    const spec = specs.get(model);
    if (!spec) continue;
    const hw = (spec.width_m * tuning.carScale) / 2;
    const offset = seg.width / 2 - tuning.sidewalkWidthM - hw - t.curbGapM;
    if (offset - hw < t.minInnerM) continue;
    const d = t.segmentMarginM + ((seg.l - 2 * t.segmentMarginM) * along) / 1000;
    // Right of the segment direction is the normal (dy, -dx).
    const sgn = side === 0 ? 1 : -1;
    const x = seg.ax + seg.dx * d + seg.dy * offset * sgn;
    const y = seg.ay + seg.dy * d - seg.dx * offset * sgn;
    if (!out.every((p) => far(x, y, p, t.minSpacingM)) || !avoid.every((p) => far(x, y, p, t.minSpacingM))) continue;
    if (!far(x, y, player, t.clearPlayerM)) continue;
    const heading = Math.atan2(seg.dy, seg.dx) + (side === 0 ? 0 : Math.PI);
    out.push({ carId: model, owner: 'npc', x, y, heading, chunk });
  }
  return out;
}

/** Nearest parked car whose centre is within board_distance_m of (x, y), or null. */
export function boardCandidate(cars: Iterable<ParkedCar>, x: number, y: number, maxDist: number): ParkedCar | null {
  let best: ParkedCar | null = null;
  let bd = maxDist * maxDist;
  for (const p of cars) {
    const d = (p.x - x) ** 2 + (p.y - y) ** 2;
    if (d <= bd) {
      bd = d;
      best = p;
    }
  }
  return best;
}
