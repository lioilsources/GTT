import type { Graph } from '../gen/pb/citypack_pb';
import type { TuningNav, TuningRoute } from '../gen/tuning';
import type { MessageKey } from '../gen/i18n';
import { findRoute, polylineDm, type Route, type RouteGraph } from '../drive/gps';
import type { EdgeHit, RoadGraph } from '../world/model';

/** GPS navigation glue (specs/phone.md "Navigace"): pure, no DOM. Coordinates in metres. */

export interface NavTarget {
  id: string;
  name: string;
  /** Spot's kept edge and parking point (dm, as in spots.pb). */
  edge: number;
  parkX: number;
  parkY: number;
}

export interface NavEnd {
  node: number;
  hit: EdgeHit;
}

/** Start: the car's edge (or the nearest kept one) and its end in the driving direction. */
export function navStart(g: RoadGraph, hit: EdgeHit | null, x: number, y: number, heading: number, searchM: number): NavEnd | null {
  const h = hit && hit.edge.kept ? hit : g.nearest(x, y, searchM, (e) => e.kept);
  if (!h) return null;
  const e = h.edge;
  let node: number;
  if (e.oneway === 1) node = e.to;
  else if (e.oneway === -1) node = e.from;
  else node = Math.cos(heading) * h.dirX + Math.sin(heading) * h.dirY >= 0 ? e.to : e.from;
  return { node, hit: h };
}

/** Projection of a point onto the closest segment of one edge. */
export function projectOnEdge(g: RoadGraph, edge: number, x: number, y: number): EdgeHit {
  const e = g.edges[edge]!;
  let best = g.project(e, 0, x, y);
  for (let s = 1; s < e.pointCount - 1; s++) {
    const h = g.project(e, s, x, y);
    if (h.dist < best.dist) best = h;
  }
  return best;
}

/** Goal: the entry end of the spot's edge (one-way) or the end nearer the parking point. */
export function navGoal(g: RoadGraph, t: NavTarget): NavEnd {
  const hit = projectOnEdge(g, t.edge, t.parkX / 10, t.parkY / 10);
  const e = hit.edge;
  const node = e.oneway === 1 ? e.from : e.oneway === -1 ? e.to : hit.t < 0.5 ? e.from : e.to;
  return { node, hit };
}

function pushPt(out: number[], x: number, y: number): void {
  const n = out.length;
  if (n >= 2 && out[n - 2] === x && out[n - 1] === y) return;
  out.push(x, y);
}

/** Points of an edge from index a up to b (fwd) or down to b, inclusive; nothing when past b. */
function pushRange(out: number[], pts: Float32Array, a: number, b: number, fwd: boolean): void {
  if (fwd) for (let i = a; i <= b; i++) pushPt(out, pts[2 * i]!, pts[2 * i + 1]!);
  else for (let i = a; i >= b; i--) pushPt(out, pts[2 * i]!, pts[2 * i + 1]!);
}

/** The route polyline: car → start node → route edges → goal node → parking point. */
export function navPath(g: RoadGraph, start: NavEnd, route: Route, goal: NavEnd, parkX: number, parkY: number): number[] {
  const out: number[] = [];
  const sh = start.hit, gh = goal.hit;
  pushPt(out, sh.x, sh.y);
  const se = sh.edge;
  const sameEdge = se.index === gh.edge.index;
  const forward = start.node === se.to;
  if (sameEdge && (forward ? gh.t >= sh.t : gh.t <= sh.t)) {
    if (forward) pushRange(out, se.pts, sh.segment + 1, gh.segment, true);
    else pushRange(out, se.pts, sh.segment, gh.segment + 1, false);
  } else {
    if (forward) pushRange(out, se.pts, sh.segment + 1, se.pointCount - 1, true);
    else pushRange(out, se.pts, sh.segment, 0, false);
    route.edges.forEach((ei, i) => {
      const e = g.edges[ei]!;
      if (e.from === route.nodes[i]) pushRange(out, e.pts, 0, e.pointCount - 1, true);
      else pushRange(out, e.pts, e.pointCount - 1, 0, false);
    });
    const ge = gh.edge;
    if (goal.node === ge.from) pushRange(out, ge.pts, 0, gh.segment, true);
    else pushRange(out, ge.pts, ge.pointCount - 1, gh.segment + 1, false);
  }
  pushPt(out, gh.x, gh.y);
  pushPt(out, parkX, parkY);
  return out;
}

/** Edge lengths in dm (sum of floor segment lengths, specs/route.md), cached per graph. */
export function edgeLengthsDm(pb: Graph): Int32Array {
  return Int32Array.from(pb.edges, (e) => polylineDm(e.points));
}

/** Integer distance for the feed (specs/feed.md "Kandidáti"). */
export function feedDistDm(
  rg: RouteGraph,
  lensDm: Int32Array,
  start: NavEnd | null,
  goal: NavEnd,
  carX: number,
  carY: number,
  t: NavTarget,
  straightPct: number,
): number {
  const r = start ? findRoute(rg, start.node, goal.node) : null;
  if (r && r.cost >= 0) return r.edges.reduce((s, e) => s + lensDm[e]!, 0);
  const dx = t.parkX - Math.floor(carX * 10 + 0.5), dy = t.parkY - Math.floor(carY * 10 + 0.5);
  return Math.floor((Math.floor(Math.sqrt(dx * dx + dy * dy)) * straightPct) / 100);
}

export type NavEvent = 'arrived' | 'rerouted' | null;

/** Follows the car along the active route: progress, reroute, arrival. */
export class Navigator {
  target: NavTarget | null = null;
  /** Interleaved x, y (m); empty when no road route was found. */
  path: number[] = [];
  private cum: number[] = [];
  private seg = 0;
  private offS = 0;
  /** Car projection on the path. */
  px = 0;
  py = 0;
  remaining = 0;
  off = 0;

  constructor(
    private readonly g: RoadGraph,
    private readonly rg: RouteGraph,
    private readonly route: TuningRoute,
    private readonly nav: TuningNav,
  ) {}

  get active(): boolean {
    return this.target !== null;
  }
  get hasRoute(): boolean {
    return this.path.length >= 4;
  }
  get parkX(): number {
    return (this.target?.parkX ?? 0) / 10;
  }
  get parkY(): number {
    return (this.target?.parkY ?? 0) / 10;
  }

  /** Starts navigation; returns false when no road route exists (the arrow still guides). */
  start(t: NavTarget, x: number, y: number, heading: number, hit: EdgeHit | null): boolean {
    this.target = t;
    this.plan(x, y, heading, hit);
    return this.hasRoute;
  }

  cancel(): void {
    this.target = null;
    this.path = [];
    this.cum = [];
  }

  private plan(x: number, y: number, heading: number, hit: EdgeHit | null): void {
    const t = this.target!;
    const s = navStart(this.g, hit, x, y, heading, this.nav.searchM);
    const goal = navGoal(this.g, t);
    const r = s ? findRoute(this.rg, s.node, goal.node) : null;
    this.path = s && r && r.cost >= 0 ? navPath(this.g, s, r, goal, t.parkX / 10, t.parkY / 10) : [];
    this.cum = [0];
    for (let i = 2; i < this.path.length; i += 2) {
      this.cum.push(this.cum[this.cum.length - 1]! + Math.hypot(this.path[i]! - this.path[i - 2]!, this.path[i + 1]! - this.path[i - 1]!));
    }
    this.seg = 0;
    this.offS = 0;
    this.track(x, y);
  }

  private track(x: number, y: number): void {
    const p = this.path;
    if (p.length < 4) {
      this.px = x;
      this.py = y;
      this.off = 0;
      this.remaining = Math.hypot(this.parkX - x, this.parkY - y);
      return;
    }
    let best = Infinity, bi = this.seg, bt = 0;
    for (let i = Math.max(0, this.seg - 2); 2 * i + 3 < p.length; i++) {
      const ax = p[2 * i]!, ay = p[2 * i + 1]!, dx = p[2 * i + 2]! - ax, dy = p[2 * i + 3]! - ay;
      const l2 = dx * dx + dy * dy;
      const t = l2 === 0 ? 0 : Math.min(1, Math.max(0, ((x - ax) * dx + (y - ay) * dy) / l2));
      const d = Math.hypot(ax + dx * t - x, ay + dy * t - y);
      if (d < best) {
        best = d;
        bi = i;
        bt = t;
      }
    }
    this.seg = bi;
    const ax = p[2 * bi]!, ay = p[2 * bi + 1]!, dx = p[2 * bi + 2]! - ax, dy = p[2 * bi + 3]! - ay;
    this.px = ax + dx * bt;
    this.py = ay + dy * bt;
    this.off = best;
    const total = this.cum[this.cum.length - 1]!;
    this.remaining = total - (this.cum[bi]! + (this.cum[bi + 1]! - this.cum[bi]!) * bt);
  }

  /** Call every frame with real (unscaled) dt. */
  update(x: number, y: number, heading: number, hit: EdgeHit | null, dt: number): NavEvent {
    if (!this.target) return null;
    if (Math.hypot(this.parkX - x, this.parkY - y) <= this.route.arriveM) return 'arrived';
    this.track(x, y);
    if (this.hasRoute && this.off > this.route.rerouteM) this.offS += dt;
    else this.offS = 0;
    if (this.offS > this.route.rerouteS) {
      this.plan(x, y, heading, hit);
      return 'rerouted';
    }
    return null;
  }

  /** The polyline still ahead of the car (for drawing). */
  ahead(): number[] {
    if (!this.hasRoute) return [];
    return [this.px, this.py, ...this.path.slice(2 * this.seg + 2)];
  }
}

/** HUD distance text (specs/phone.md "Formát vzdálenosti"). */
export function formatDistance(m: number, imperial: boolean, nav: TuningNav): { key: MessageKey; args: Record<string, string | number> } {
  if (!imperial) {
    if (m < nav.kmFromM) return { key: 'distanceM', args: { m: Math.round(m / nav.roundM) * nav.roundM } };
    return { key: 'distanceKm', args: { km: (m / 1000).toFixed(1) } };
  }
  const mi = m / 1609.344;
  if (mi < nav.miFrom) return { key: 'distanceFt', args: { ft: Math.round((m * 3.28084) / nav.roundFt) * nav.roundFt } };
  return { key: 'distanceMi', args: { mi: mi.toFixed(1) } };
}

/** Drive minutes on a feed card. */
export const driveMinutes = (driveS: number): number => Math.max(1, Math.floor((driveS + 30) / 60));

/**
 * Edge-of-screen arrow towards an off-screen target: the point where the ray from the anchor
 * (ax, ay) to the target leaves the screen rectangle inset by margin; null when the target is visible.
 */
export function edgeArrow(
  tx: number, ty: number, w: number, h: number, margin: number, ax: number, ay: number,
): { x: number; y: number; angle: number } | null {
  const x0 = margin, x1 = w - margin, y0 = margin, y1 = h - margin;
  if (tx >= x0 && tx <= x1 && ty >= y0 && ty <= y1) return null;
  const dx = tx - ax, dy = ty - ay;
  let s = Infinity;
  if (dx > 0) s = Math.min(s, (x1 - ax) / dx);
  if (dx < 0) s = Math.min(s, (x0 - ax) / dx);
  if (dy > 0) s = Math.min(s, (y1 - ay) / dy);
  if (dy < 0) s = Math.min(s, (y0 - ay) / dy);
  if (!Number.isFinite(s)) return null;
  return { x: ax + dx * s, y: ay + dy * s, angle: Math.atan2(dy, dx) };
}
