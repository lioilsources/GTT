import type { BenchRoute, Crossing } from '../gen/schema';
import type { RoadGraph } from '../world/model';

/** A route polyline in world metres with cumulative distances (specs/bench.md). */
export class RoutePath {
  readonly cum: Float64Array;

  constructor(
    /** Interleaved x, y. */
    readonly pts: Float64Array,
    readonly legs: number,
    /** Graph edges in driving order (empty when built from bare points). */
    readonly edges: readonly number[] = [],
  ) {
    const n = pts.length >> 1;
    this.cum = new Float64Array(n);
    for (let i = 1; i < n; i++) {
      this.cum[i] = this.cum[i - 1]! + Math.hypot(pts[2 * i]! - pts[2 * i - 2]!, pts[2 * i + 1]! - pts[2 * i - 1]!);
    }
  }

  get length(): number {
    return this.cum[this.cum.length - 1] ?? 0;
  }
  get count(): number {
    return this.pts.length >> 1;
  }

  /** Segment index containing distance s. */
  segmentAt(s: number): number {
    let lo = 0, hi = this.count - 1;
    while (hi - lo > 1) {
      const mid = (lo + hi) >> 1;
      if (this.cum[mid]! <= s) lo = mid;
      else hi = mid;
    }
    return lo;
  }

  /** Point and direction at distance s (clamped to the route). */
  at(s: number): { x: number; y: number; dir: number } {
    const c = Math.min(Math.max(s, 0), this.length);
    const i = Math.min(this.segmentAt(c), this.count - 2);
    const ax = this.pts[2 * i]!, ay = this.pts[2 * i + 1]!, bx = this.pts[2 * i + 2]!, by = this.pts[2 * i + 3]!;
    const l = this.cum[i + 1]! - this.cum[i]!;
    const t = l > 0 ? (c - this.cum[i]!) / l : 0;
    return { x: ax + (bx - ax) * t, y: ay + (by - ay) * t, dir: Math.atan2(by - ay, bx - ax) };
  }

  /** Distance along the route of the closest point to (x, y), searched within [s0, s1]. */
  project(x: number, y: number, s0: number, s1: number): number {
    const i0 = this.segmentAt(Math.max(0, s0)), i1 = Math.min(this.segmentAt(Math.min(s1, this.length)), this.count - 2);
    let best = Infinity, bestS = s0;
    for (let i = i0; i <= i1; i++) {
      const ax = this.pts[2 * i]!, ay = this.pts[2 * i + 1]!, bx = this.pts[2 * i + 2]!, by = this.pts[2 * i + 3]!;
      const dx = bx - ax, dy = by - ay;
      const l2 = dx * dx + dy * dy;
      const t = l2 === 0 ? 0 : Math.min(1, Math.max(0, ((x - ax) * dx + (y - ay) * dy) / l2));
      const d = Math.hypot(ax + dx * t - x, ay + dy * t - y);
      if (d < best) {
        best = d;
        bestS = this.cum[i]! + Math.sqrt(l2) * t;
      }
    }
    return bestS;
  }

  /** Largest absolute change of direction between s0 and s1. */
  maxTurn(s0: number, s1: number): number {
    const i0 = this.segmentAt(Math.max(0, s0)), i1 = Math.min(this.segmentAt(Math.min(s1, this.length)), this.count - 2);
    const dir = (i: number): number => Math.atan2(this.pts[2 * i + 3]! - this.pts[2 * i + 1]!, this.pts[2 * i + 2]! - this.pts[2 * i]!);
    const d0 = dir(i0);
    let max = 0;
    for (let i = i0 + 1; i <= i1; i++) {
      let d = dir(i) - d0;
      while (d > Math.PI) d -= 2 * Math.PI;
      while (d < -Math.PI) d += 2 * Math.PI;
      max = Math.max(max, Math.abs(d));
    }
    return max;
  }
}

/** Node where an edge named a and an edge named b meet; the smallest index wins. */
export function crossingNode(g: RoadGraph, c: Crossing): number {
  for (let n = 0; n < g.nodeEdges.length; n++) {
    let hasA = false, hasB = false;
    for (const ei of g.nodeEdges[n]!) {
      const name = g.edges[ei]!.name;
      if (name === c.a) hasA = true;
      if (name === c.b) hasB = true;
    }
    if (hasA && hasB) return n;
  }
  throw new Error(`bench route: no crossing of ${c.a} and ${c.b}`);
}

/**
 * Shortest path (edge length) from node a to b over edges named in via; ties go to smaller node index.
 * With `oneway` (bench v2) an edge is taken only in its allowed direction.
 */
function leg(g: RoadGraph, from: number, to: number, via: ReadonlySet<string>, oneway: boolean): number[] {
  const n = g.nodeEdges.length;
  const dist = new Float64Array(n).fill(Infinity);
  const prevEdge = new Int32Array(n).fill(-1);
  const done = new Uint8Array(n);
  dist[from] = 0;
  for (;;) {
    let u = -1;
    for (let i = 0; i < n; i++) if (!done[i] && dist[i]! < Infinity && (u < 0 || dist[i]! < dist[u]!)) u = i;
    if (u < 0) throw new Error(`bench route: no path over ${[...via].join(', ')}`);
    if (u === to) break;
    done[u] = 1;
    for (const ei of g.nodeEdges[u]!) {
      const e = g.edges[ei]!;
      if (!via.has(e.name)) continue;
      if (oneway && ((e.oneway === 1 && e.from !== u) || (e.oneway === -1 && e.to !== u))) continue;
      const v = e.from === u ? e.to : e.from;
      const d = dist[u]! + e.length;
      if (d < dist[v]!) {
        dist[v] = d;
        prevEdge[v] = ei;
      }
    }
  }
  const edges: number[] = [];
  for (let v = to; v !== from; ) {
    const ei = prevEdge[v]!;
    edges.push(ei);
    const e = g.edges[ei]!;
    v = e.from === v ? e.to : e.from;
  }
  return edges.reverse();
}

/** Builds the route polyline of specs/bench.md. */
export function resolveRoute(g: RoadGraph, r: BenchRoute): RoutePath {
  let node = crossingNode(g, r.start);
  const pts: number[] = [g.nodeXY[2 * node]!, g.nodeXY[2 * node + 1]!];
  const edges: number[] = [];
  for (const l of r.legs) {
    const to = crossingNode(g, l.to);
    for (const ei of leg(g, node, to, new Set(l.via), r.oneway === true)) {
      edges.push(ei);
      const e = g.edges[ei]!;
      const forward = e.from === node;
      const k = e.pointCount;
      for (let j = 1; j < k; j++) {
        const i = forward ? j : k - 1 - j;
        pts.push(e.pts[2 * i]!, e.pts[2 * i + 1]!);
      }
      node = forward ? e.to : e.from;
    }
  }
  return new RoutePath(Float64Array.from(pts), r.legs.length, edges);
}

/**
 * File of a route in content/bench/ (specs/bench.md v2): the city's benchmark is `<city>.json`,
 * a further route `<city>-<id>.json` (`?city=<city>&route=<id>`).
 */
export function routeFile(city: string, id: string | null): string {
  return id === null ? `${city}.json` : `${city}-${id}.json`;
}
