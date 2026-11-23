import type { TuningFlowRescue, TuningFlowWall } from '../gen/tuning';
import type { RoadGraph } from '../world/model';

/**
 * Smooth driving (specs/flow.md v1, F-069): wall slide and bounce, the trail, automatic and manual
 * rescue, stuck metering. Pure rules (no planck, no Babylon); DriveWorld applies them.
 * The literal numbers below are fixed by the spec text (not tuning values).
 */

/** Trail sample period, minimum speed, age and length (5 s / 0.25 s), specs/flow.md "Stopa". */
export const TRAIL_DT_S = 0.25;
export const TRAIL_MIN_MPS = 3;
export const TRAIL_KEEP_S = 5;
export const TRAIL_MAX = 20;
/** Rescues counted for the next attempt: the last 5 s, within 25 m of the first. */
export const RESCUE_WINDOW_S = 5;
export const RESCUE_NEAR_M = 25;
/** The move: 0.4 s animation (speed 0), then 1 s more of grace. */
export const RESCUE_ANIM_S = 0.4;
export const RESCUE_GRACE_S = 1.4;
/** Slide: heading eases to the wall at 6 rad/s (exponential), spin × 0.5. */
export const SLIDE_EASE_PER_S = 6;
export const SLIDE_SPIN_KEEP = 0.5;
/** Head-on bounce: the car is moved 1 m away from the wall along n. */
export const UNSTICK_M = 1;
/** Debug overlay window: stuck events in the last 10 minutes of driving. */
export const STUCK_WINDOW_S = 600;

export type StuckKind = 'auto1' | 'auto2' | 'road' | 'button';

export interface TrailPoint {
  x: number;
  y: number;
  heading: number;
  /** Driving time of the sample (s): points older than 5 s are dropped. */
  t: number;
}

export interface WallResponse {
  vx: number;
  vy: number;
  /** true = oblique (slide along t), false = head-on bounce. */
  slide: boolean;
  /** Unit wall direction along the velocity (slide only). */
  tx: number;
  ty: number;
}

/**
 * The response to a static contact (specs/flow.md "Náraz do pevné překážky"): v = velocity before the
 * contact, n = unit normal from the wall to the car. null when the car does not move into the wall.
 */
export function wallResponse(vx: number, vy: number, nx: number, ny: number, t: TuningFlowWall): WallResponse | null {
  const sp = Math.hypot(vx, vy);
  const vn = vx * nx + vy * ny;
  if (sp < 1e-6 || vn >= 0) return null;
  const alpha = Math.asin(Math.min(1, -vn / sp));
  const vtx = vx - vn * nx, vty = vy - vn * ny;
  const vt = Math.hypot(vtx, vty);
  if (alpha < (t.slideAngleDeg * Math.PI) / 180 && vt > 1e-9) {
    const tx = vtx / vt, ty = vty / vt;
    const mag = Math.max(vt, sp * t.slideSpeedKeep * Math.cos(alpha));
    return { vx: tx * mag, vy: ty * mag, slide: true, tx, ty };
  }
  return { vx: -vn * nx * t.restitution + vtx, vy: -vn * ny * t.restitution + vty, slide: false, tx: 0, ty: 0 };
}

const wrap = (a: number): number => {
  while (a > Math.PI) a -= 2 * Math.PI;
  while (a < -Math.PI) a += 2 * Math.PI;
  return a;
};

/**
 * Slide heading: eases towards the wall direction (t or −t, whichever the nose is closer to) at
 * SLIDE_EASE_PER_S, exponentially.
 */
export function easeHeading(heading: number, tx: number, ty: number, dt: number): number {
  let target = Math.atan2(ty, tx);
  if (Math.cos(heading - target) < 0) target += Math.PI;
  return heading + wrap(target - heading) * (1 - Math.exp(-SLIDE_EASE_PER_S * dt));
}

/**
 * The rewind point (specs/flow.md "Vyproštění" 3): the trail point whose length along the trail,
 * counted from (x, y) through the newest point backwards, is closest to `dist`; when the trail is
 * shorter, the oldest point. Returns its index, or −1 for an empty trail.
 */
export function rewindIndex(trail: readonly TrailPoint[], x: number, y: number, dist: number): number {
  if (trail.length === 0) return -1;
  let best = trail.length - 1, bestErr = Infinity;
  let s = 0, px = x, py = y;
  for (let i = trail.length - 1; i >= 0; i--) {
    const p = trail[i]!;
    s += Math.hypot(p.x - px, p.y - py);
    px = p.x;
    py = p.y;
    const err = Math.abs(s - dist);
    if (err < bestErr) {
      bestErr = err;
      best = i;
    }
  }
  return s < dist ? 0 : best;
}

export interface RoadSpot {
  x: number;
  y: number;
  heading: number;
  node: number;
}

/**
 * "Přesun na silnici": the nearest node of a kept ground (layer 0) road; ties by the smaller node
 * index. Heading along the GPS route when its polyline passes within `routeM` of the node (the
 * route's direction there), else along the node's first kept ground edge, away from the node.
 */
export function roadSpot(g: RoadGraph, x: number, y: number, route: ArrayLike<number> | null, routeM: number): RoadSpot | null {
  let node = -1, bd = Infinity;
  for (const e of g.edges) {
    if (!e.kept || !e.isGround) continue;
    for (const n of [e.from, e.to]) {
      const d = Math.hypot(g.nodeXY[2 * n]! - x, g.nodeXY[2 * n + 1]! - y);
      if (d < bd || (d === bd && n < node)) {
        bd = d;
        node = n;
      }
    }
  }
  if (node < 0) return null;
  const nx = g.nodeXY[2 * node]!, ny = g.nodeXY[2 * node + 1]!;
  if (route !== null && route.length >= 4) {
    let rd = Infinity, rh = 0;
    for (let i = 0; i + 3 < route.length; i += 2) {
      const ax = route[i]!, ay = route[i + 1]!, bx = route[i + 2]!, by = route[i + 3]!;
      const dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy;
      if (l2 < 1e-9) continue;
      const t = Math.min(1, Math.max(0, ((nx - ax) * dx + (ny - ay) * dy) / l2));
      const d = Math.hypot(ax + dx * t - nx, ay + dy * t - ny);
      if (d < rd) {
        rd = d;
        rh = Math.atan2(dy, dx);
      }
    }
    if (rd <= routeM) return { x: nx, y: ny, heading: rh, node };
  }
  const list = g.nodeEdges[node] ?? [];
  const ei = list.find((i) => g.edges[i]!.kept && g.edges[i]!.isGround) ?? list[0];
  let heading = 0;
  if (ei !== undefined) {
    const e = g.edges[ei]!, p = e.pts, k = p.length;
    heading = e.from === node ? Math.atan2(p[3]! - p[1]!, p[2]! - p[0]!) : Math.atan2(p[k - 3]! - p[k - 1]!, p[k - 4]! - p[k - 2]!);
  }
  return { x: nx, y: ny, heading, node };
}

export interface FlowCar {
  x: number;
  y: number;
  heading: number;
  speed: number;
  /** The player brakes (brake pedal or reverse, handbrake). */
  braking: boolean;
  airborne: boolean;
}

export interface StuckEvent {
  /** Driving time (s, the DriveWorld clock: pause and minigames excluded). */
  t: number;
  kind: StuckKind;
  x: number;
  y: number;
}

/** What the automatic rescue decided this step. */
export type RescuePlan = { kind: 'auto1' | 'auto2'; point: TrailPoint } | { kind: 'road' };

/** Trail, stuck timers and the stuck log of one session (specs/flow.md "Stav"). */
export class FlowState {
  trail: TrailPoint[] = [];
  stuckT = 0;
  slowT = 0;
  /** The current series of automatic rescues at one place (see decide). */
  rescues: { t: number; x: number; y: number }[] = [];
  graceT = 0;
  /** Rescue animation left (s); the car stands while > 0. */
  animT = 0;
  readonly events: StuckEvent[] = [];
  private trailAcc = 0;

  constructor(readonly t: TuningFlowRescue) {}

  /** The "Na silnici" button is shown. */
  get buttonShown(): boolean {
    return this.slowT >= this.t.buttonAfterS;
  }

  /**
   * One fixed step after physics at driving time `now`. `blocked` = a context button is shown
   * (pause and minigames do not step at all). Returns the automatic rescue to perform, or null.
   */
  step(dt: number, now: number, car: FlowCar, blocked: boolean): RescuePlan | null {
    this.graceT = Math.max(0, this.graceT - dt);
    this.animT = Math.max(0, this.animT - dt);
    // Trail: every 0.25 s while faster than 3 m/s and on the ground.
    this.trailAcc += dt;
    if (this.trailAcc >= TRAIL_DT_S - 1e-9) {
      this.trailAcc -= TRAIL_DT_S;
      if (car.speed > TRAIL_MIN_MPS && !car.airborne && this.animT === 0) {
        this.trail.push({ x: car.x, y: car.y, heading: car.heading, t: now });
        if (this.trail.length > TRAIL_MAX) this.trail.shift();
      }
    }
    // Only the last 5 s: a car crawling along a wall for long has no stale point far behind.
    while (this.trail.length > 0 && this.trail[0]!.t < now - TRAIL_KEEP_S - 1e-9) this.trail.shift();
    const slow = car.speed < this.t.stuckSpeedMps;
    this.slowT = slow && this.animT === 0 ? this.slowT + dt : 0;
    if (this.graceT > 0 || blocked) {
      this.stuckT = 0;
      return null;
    }
    this.stuckT = slow && !car.braking ? this.stuckT + dt : 0;
    if (this.stuckT < this.t.stuckTimeS) return null;
    return this.decide(now, car.x, car.y);
  }

  private decide(now: number, x: number, y: number): RescuePlan {
    // The series of attempts at one place: each within 5 s of the previous one (the shortest gap is
    // grace + stuck_time_s = 2.9 s, so "the last 5 s" counted from now could never reach a third),
    // all within 25 m of the first. Otherwise this is a first attempt again.
    const last = this.rescues[this.rescues.length - 1], first = this.rescues[0];
    if (last === undefined || now - last.t > RESCUE_WINDOW_S || Math.hypot(first!.x - x, first!.y - y) > RESCUE_NEAR_M) this.rescues = [];
    const n = this.rescues.length;
    this.rescues.push({ t: now, x, y });
    this.stuckT = 0;
    this.slowT = 0;
    this.graceT = RESCUE_GRACE_S;
    this.animT = RESCUE_ANIM_S;
    if (n < 2) {
      const i = rewindIndex(this.trail, x, y, this.t.rewindM[n]!);
      if (i >= 0) {
        const point = this.trail[i]!;
        // The car stands on that point now; the newer part of the trail is behind it.
        this.trail.length = i + 1;
        const kind = n === 0 ? 'auto1' : 'auto2';
        this.log(now, kind, x, y);
        return { kind, point };
      }
    }
    this.trail = [];
    this.log(now, 'road', x, y);
    return { kind: 'road' };
  }

  /** The manual "Na silnici" (button or pause menu): counted as stuck, starts the animation. */
  manual(now: number, x: number, y: number): void {
    this.trail = [];
    this.stuckT = 0;
    this.slowT = 0;
    this.graceT = RESCUE_GRACE_S;
    this.animT = RESCUE_ANIM_S;
    this.log(now, 'button', x, y);
  }

  /** A respawn or teleport outside the flow rules: the trail and timers start over. */
  reset(): void {
    this.trail = [];
    this.stuckT = 0;
    this.slowT = 0;
    this.trailAcc = 0;
  }

  /** Stuck events in the last 10 minutes of driving (debug overlay `flowStuck10`). */
  count10(now: number): number {
    let n = 0;
    for (const e of this.events) if (e.t > now - STUCK_WINDOW_S) n++;
    return n;
  }

  onStuck: ((e: StuckEvent) => void) | null = null;

  private log(t: number, kind: StuckKind, x: number, y: number): void {
    const e = { t, kind, x, y };
    this.events.push(e);
    while (this.events.length > 0 && this.events[0]!.t <= t - STUCK_WINDOW_S) this.events.shift();
    this.onStuck?.(e);
  }
}

/** The stuck.log line (specs/flow.md "Měření zaseknutí"), unix seconds. */
export function stuckLine(unixS: number, city: string, e: StuckEvent): string {
  const r = (v: number): number => Math.round(v * 10) / 10;
  return JSON.stringify({ t: Math.floor(unixS), city, x: r(e.x), y: r(e.y), kind: e.kind });
}
