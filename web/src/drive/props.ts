import type { Tuning } from '../gen/tuning';
import { TuningPropsMix } from '../gen/tuning';
import { Prng } from '../rules/prng';
import { chunkKey, type RoadGraph } from '../world/model';

/** Kinds of street furniture; the name is the key in props.mix and props.radius_m. */
export type PropKind = (typeof TuningPropsMix.keys)[number];
export const propKinds: readonly PropKind[] = TuningPropsMix.keys;

/**
 * Street furniture, generated per chunk and never stored (METROPOLE_PLAN 6.4). Not physics
 * bodies: the car knocks them over by an overlap test; they come back after props.respawn_s.
 */
export class Prop {
  knocked = false;
  knockedAt = 0;
  ox = 0;
  oy = 0;
  vx = 0;
  vy = 0;
  spin = 0;
  rot = 0;

  constructor(
    readonly kind: PropKind,
    readonly x: number,
    readonly y: number,
    readonly radius: number,
    readonly angle: number,
  ) {}
}

export interface PropSet {
  chunkKey: number;
  props: Prop[];
}

/**
 * Places props along the sidewalks of kept ground roads whose segments lie in the chunk.
 * Randomness comes from the shared PRNG (specs/prng.md). Prop positions are presentation (P2):
 * client F still uses Dart's Random, so the two clients place different props.
 */
export function generateProps(graph: RoadGraph, cx: number, cy: number, tuning: Tuning): PropSet {
  const t = tuning.props;
  const chunkM = tuning.chunkM;
  const rnd = new Prng((Math.imul(cx, 73856093) ^ Math.imul(cy, 19349663)) >>> 0);
  const unit = (): number => rnd.nextU32() / 4294967296;
  const mixTotal = propKinds.reduce((s, k) => s + t.mix[k], 0);
  const pick = (): PropKind => {
    let r = unit() * mixTotal;
    for (const k of propKinds) {
      r -= t.mix[k];
      if (r < 0) return k;
    }
    return propKinds[propKinds.length - 1]!;
  };

  const props: Prop[] = [];
  const x0 = cx * chunkM, y0 = cy * chunkM;
  for (const e of graph.edges) {
    if (!e.kept || !e.isGround || e.bridge) continue;
    const offset = e.width / 2 - tuning.sidewalkWidthM / 2;
    if (offset <= 0) continue;
    let along = 0;
    for (let s = 0; s + 1 < e.pointCount; s++) {
      const ax = e.pts[2 * s]!, ay = e.pts[2 * s + 1]!, bx = e.pts[2 * s + 2]!, by = e.pts[2 * s + 3]!;
      const mx = (ax + bx) / 2, my = (ay + by) / 2;
      const dx = bx - ax, dy = by - ay;
      const l = Math.sqrt(dx * dx + dy * dy);
      if (mx < x0 || mx >= x0 + chunkM || my < y0 || my >= y0 + chunkM || l === 0) {
        along += l;
        continue;
      }
      const nx = -dy / l, ny = dx / l;
      for (let d = t.firstM; d < l - t.firstM; d += t.spacingM + unit() * t.spacingJitterM) {
        if (along + d < t.clearIntersectionM || e.length - (along + d) < t.clearIntersectionM) continue;
        for (const side of [-1, 1]) {
          if (unit() < t.skipChance) continue;
          const kind = pick();
          props.push(
            new Prop(kind, ax + (dx * d) / l + nx * offset * side, ay + (dy * d) / l + ny * offset * side,
              t.radiusM[kind] * tuning.carScale, Math.atan2(dy, dx)),
          );
        }
      }
      along += l;
    }
  }
  return { chunkKey: chunkKey(cx, cy), props };
}
