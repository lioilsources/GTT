import type { Tuning } from '../gen/tuning';
import { carriageHalf } from '../traffic/roadRules';
import type { BuildingData } from '../world/chunk';
import type { EdgeHit } from '../world/model';

/**
 * Pure geometry of the police (specs/police.md "Chodník", "Dohled"): no DOM, no physics.
 * Port in packages/drive_core/lib/src/police/sense.dart; both clients test the same cases.
 */

/**
 * True when the point of the hits is on the sidewalk band of some kept ground edge and on the
 * carriageway of none (hits = graph.near(x, y, r) for the player's centre).
 */
export function onSidewalk(hits: readonly EdgeHit[], tuning: Tuning): boolean {
  const margin = tuning.police.sidewalkMarginM;
  let band = false;
  for (const h of hits) {
    const e = h.edge;
    if (!e.kept || e.layerAt(h.t) !== 0 || e.tunnel) continue;
    const c = carriageHalf(e, tuning) + margin;
    if (h.dist <= c) return false;
    if (h.dist <= e.width / 2) band = true;
  }
  return band;
}

/** True when segment a–b properly crosses segment c–d (touching ends do not count). */
export function segmentsCross(
  ax: number, ay: number, bx: number, by: number, cx: number, cy: number, dx: number, dy: number,
): boolean {
  const d1 = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
  const d2 = (bx - ax) * (dy - ay) - (by - ay) * (dx - ax);
  const d3 = (dx - cx) * (ay - cy) - (dy - cy) * (ax - cx);
  const d4 = (dx - cx) * (by - cy) - (dy - cy) * (bx - cx);
  return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
}

/** Distance from point p to segment a–b. */
function pointSegDist(px: number, py: number, ax: number, ay: number, bx: number, by: number): number {
  const dx = bx - ax, dy = by - ay;
  const l2 = dx * dx + dy * dy;
  const t = l2 === 0 ? 0 : Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / l2));
  return Math.hypot(ax + dx * t - px, ay + dy * t - py);
}

/** True when segment a–b crosses an outline edge of a colliding building (bounding circle first). */
export function sightBlocked(ax: number, ay: number, bx: number, by: number, buildings: Iterable<BuildingData>): boolean {
  for (const b of buildings) {
    if (!b.collide || pointSegDist(b.cx, b.cy, ax, ay, bx, by) > b.radius) continue;
    let start = 0;
    for (const end of b.ringEnds) {
      for (let i = start; i < end; i++) {
        const j = i + 1 < end ? i + 1 : start;
        if (segmentsCross(ax, ay, bx, by, b.xy[2 * i]!, b.xy[2 * i + 1]!, b.xy[2 * j]!, b.xy[2 * j + 1]!)) return true;
      }
      start = end;
    }
  }
  return false;
}

/** Patrol sees the player (without the building test): tunnel ↔ tunnel and within view_m. */
export function inView(px: number, py: number, pLayer: number, qx: number, qy: number, qLayer: number, viewM: number): boolean {
  if (pLayer < 0 !== qLayer < 0) return false;
  const dx = qx - px, dy = qy - py;
  return dx * dx + dy * dy <= viewM * viewM;
}
