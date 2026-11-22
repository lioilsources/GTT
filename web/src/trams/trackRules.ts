import { Prng } from '../rules/prng';
import type { TrackGraph } from '../world/model';

/**
 * Deterministic parts of trams (specs/trams.md "Deterministické funkce"): the next track edge,
 * articulated cars along the trail, the stop ahead. Pure (no DOM, no physics); the unit tests of
 * both clients check the same values.
 */

/**
 * Next track edge at `node` after arriving along `from` (as traffic's chooseNext, without one-way
 * streets and alleys): candidates are the edges at the node in ascending index order without
 * `from`, duplicates and loops; pick `prng.nextInt(count)`. No candidate = terminus: turn back
 * along `from`. A border node (or a loop as the only way) = −1, the tram disappears.
 */
export function chooseNextTrack(g: TrackGraph, node: number, from: number, rng: Prng, scratch: number[] = []): number {
  if (g.border[node]) return -1;
  scratch.length = 0;
  const list = g.nodeEdges[node]!;
  // nodeEdges is in ascending index order (built edge by edge); skip duplicates of loops.
  for (let k = 0; k < list.length; k++) {
    const ei = list[k]!;
    if (ei === from || (k > 0 && list[k - 1] === ei)) continue;
    const e = g.edges[ei]!;
    if (e.from !== e.to) scratch.push(ei);
  }
  if (scratch.length === 0) {
    const back = g.edges[from];
    return back && back.from !== back.to ? from : -1;
  }
  return scratch[rng.nextInt(scratch.length)]!;
}

/**
 * The path a tram has driven, newest first: the live head point plus up to `capacity − 1` fixed
 * vertices (track polyline points and nodes passed). Preallocated ring, no allocation per step.
 */
export class Trail {
  headX = 0;
  headY = 0;
  /** Unit travel direction at the oldest point; used to extend the trail straight behind it. */
  tailDirX = 1;
  tailDirY = 0;
  private readonly xs: Float64Array;
  private readonly ys: Float64Array;
  private start = 0;
  private n = 0;

  constructor(readonly capacity: number) {
    const c = Math.max(1, capacity - 1);
    this.xs = new Float64Array(c);
    this.ys = new Float64Array(c);
  }

  /** Points including the head. */
  get count(): number {
    return this.n + 1;
  }

  reset(x: number, y: number, dirX: number, dirY: number): void {
    this.n = 0;
    this.start = 0;
    this.headX = x;
    this.headY = y;
    this.tailDirX = dirX;
    this.tailDirY = dirY;
  }

  /** Adds a fixed vertex just behind the head (a point the head has passed). */
  push(x: number, y: number): void {
    const c = this.xs.length;
    this.start = (this.start + c - 1) % c;
    this.xs[this.start] = x;
    this.ys[this.start] = y;
    if (this.n < c) this.n++;
  }

  /** Adds a vertex at the far end (seeding the path behind a freshly placed tram). */
  pushOldest(x: number, y: number): void {
    const c = this.xs.length;
    if (this.n >= c) return;
    this.xs[(this.start + this.n) % c] = x;
    this.ys[(this.start + this.n) % c] = y;
    this.n++;
  }

  /** Point i, 0 = head, then newest to oldest fixed vertex. */
  x(i: number): number {
    return i === 0 ? this.headX : this.xs[(this.start + i - 1) % this.xs.length]!;
  }
  y(i: number): number {
    return i === 0 ? this.headY : this.ys[(this.start + i - 1) % this.ys.length]!;
  }
}

/**
 * The point `d` metres behind the head along the trail, into out[0..1]. Past the oldest point the
 * trail continues straight back (along the last segment, else `tailDir`).
 */
export function trailPoint(trail: Trail, d: number, out: Float64Array | number[]): void {
  let left = Math.max(0, d);
  let px = trail.x(0), py = trail.y(0);
  let dx = -trail.tailDirX, dy = -trail.tailDirY;
  for (let i = 1; i < trail.count; i++) {
    const qx = trail.x(i), qy = trail.y(i);
    const sx = qx - px, sy = qy - py;
    const l = Math.sqrt(sx * sx + sy * sy);
    if (l <= 1e-9) continue;
    if (left <= l) {
      out[0] = px + (sx * left) / l;
      out[1] = py + (sy * left) / l;
      return;
    }
    left -= l;
    px = qx;
    py = qy;
    dx = sx / l;
    dy = sy / l;
  }
  out[0] = px + dx * left;
  out[1] = py + dy * left;
}

/** Pose of one articulated car. */
export interface CarPose {
  x: number;
  y: number;
  heading: number;
}

const scratchA = [0, 0];
const scratchB = [0, 0];

/**
 * Car k of a tram (0 = the leading car): its front joint stands `k · (carLength + jointGap)`
 * behind the head along the trail, its rear joint `carLength` further back. The car's centre is
 * the middle between the two joints, its heading the direction from the rear to the front joint.
 */
export function articulate(trail: Trail, k: number, carLengthM: number, jointGapM: number, out: CarPose = { x: 0, y: 0, heading: 0 }): CarPose {
  const front = k * (carLengthM + jointGapM);
  trailPoint(trail, front, scratchA);
  trailPoint(trail, front + carLengthM, scratchB);
  const fx = scratchA[0]!, fy = scratchA[1]!, rx = scratchB[0]!, ry = scratchB[1]!;
  out.x = (fx + rx) / 2;
  out.y = (fy + ry) / 2;
  const hx = fx - rx, hy = fy - ry;
  out.heading = hx * hx + hy * hy > 1e-18 ? Math.atan2(hy, hx) : Math.atan2(trail.tailDirY, trail.tailDirX);
  return out;
}

/** A stop's distance along the travel direction of its edge (dir +1 from → to, −1 back). */
export function stopTravelS(g: TrackGraph, stop: number, dir: number): number {
  const st = g.stops[stop]!;
  return dir > 0 ? st.s : g.edges[st.edge]!.length - st.s;
}

/**
 * The nearest stop on `edge` ahead of a tram at `s` (metres along its travel direction `dir`)
 * that is further than `commitM`; `skip` (a stop just served) never counts. −1 = none.
 */
export function nextStopAhead(g: TrackGraph, edge: number, dir: number, s: number, commitM: number, skip = -1): number {
  const list = g.stopsByEdge[edge];
  if (!list) return -1;
  let best = -1, bestAhead = Infinity;
  for (const i of list) {
    if (i === skip) continue;
    const ahead = stopTravelS(g, i, dir) - s;
    if (ahead > commitM && ahead < bestAhead) {
      best = i;
      bestAhead = ahead;
    }
  }
  return best;
}
