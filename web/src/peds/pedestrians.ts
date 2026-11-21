import type { Car } from '../drive/car';
import type { Tuning, TuningPedestrians } from '../gen/tuning';
import { Prng } from '../rules/prng';
import type { City, RoadEdge } from '../world/model';

/**
 * Pedestrians (specs/pedestrians.md, version 1). Pure logic, no DOM or Babylon. They walk the
 * sidewalks of kept ground edges and always dodge cars (R7): not physics bodies, the dodge is a
 * pure function of the car pose and velocity. Port: packages/drive_core/lib/src/pedestrians.dart.
 */

/** A car pedestrians dodge (player now, traffic later). Half sizes already include car_scale. */
export interface CarPose {
  x: number;
  y: number;
  heading: number;
  halfLength: number;
  halfWidth: number;
  vx: number;
  vy: number;
}

export function carPose(car: Car): CarPose {
  const v = car.body.getLinearVelocity();
  return { x: car.x, y: car.y, heading: car.heading, halfLength: car.halfLength, halfWidth: car.halfWidth, vx: v.x, vy: v.y };
}

/** A predicted contact: leap by (dx, dy) within dur seconds; contact in tc seconds. */
export interface Dodge {
  tc: number;
  dx: number;
  dy: number;
  dur: number;
}

/**
 * Threat test of specs/pedestrians.md "Uskočení": is the point (px, py) with body radius r in the
 * band the car's box sweeps over dodge_horizon_s? Returns the sideways leap that leaves the band.
 */
export function dodge(px: number, py: number, r: number, car: CarPose, t: TuningPedestrians): Dodge | null {
  const v = Math.hypot(car.vx, car.vy);
  if (v < t.dodgeMinMps) return null;
  const ux = car.vx / v, uy = car.vy / v;
  const nx = -uy, ny = ux;
  const th = car.heading - Math.atan2(car.vy, car.vx);
  const c = Math.abs(Math.cos(th)), s = Math.abs(Math.sin(th));
  const a = car.halfLength * c + car.halfWidth * s;
  const e = car.halfWidth * c + car.halfLength * s;
  const dx = px - car.x, dy = py - car.y;
  const along = dx * ux + dy * uy;
  const perp = dx * nx + dy * ny;
  const R = r + t.dodgeMarginM;
  if (Math.abs(perp) >= e + R) return null;
  if (along <= -a - R || along >= a + v * t.dodgeHorizonS + R) return null;
  const tc = Math.max(0, (along - a - R) / v);
  const side = perp < 0 ? -1 : 1;
  const k = side * (e + R + t.dodgeExtraM) - perp;
  return { tc, dx: nx * k, dy: ny * k, dur: Math.min(t.leapS, tc * t.leapFraction) };
}

/** The soonest dodge over all cars, or null. */
export function dodgeAll(px: number, py: number, r: number, cars: readonly CarPose[], t: TuningPedestrians): Dodge | null {
  let best: Dodge | null = null;
  for (const c of cars) {
    const d = dodge(px, py, r, c, t);
    if (d && (best === null || d.tc < best.tc)) best = d;
  }
  return best;
}

/** True when a circle (px, py, r) overlaps the car's oriented box. */
export function overlapsBox(px: number, py: number, r: number, car: CarPose): boolean {
  const cs = Math.cos(car.heading), sn = Math.sin(car.heading);
  const dx = px - car.x, dy = py - car.y;
  const lx = dx * cs + dy * sn, ly = -dx * sn + dy * cs;
  const qx = Math.max(-car.halfLength, Math.min(car.halfLength, lx));
  const qy = Math.max(-car.halfWidth, Math.min(car.halfWidth, ly));
  const ex = lx - qx, ey = ly - qy;
  return ex * ex + ey * ey < r * r;
}

/** Moves a point straight out across the nearest side of the car's box to distance R. */
export function pushOut(px: number, py: number, R: number, car: CarPose): { x: number; y: number } {
  const cs = Math.cos(car.heading), sn = Math.sin(car.heading);
  const dx = px - car.x, dy = py - car.y;
  let lx = dx * cs + dy * sn, ly = -dx * sn + dy * cs;
  const fx = car.halfLength + R - Math.abs(lx), fy = car.halfWidth + R - Math.abs(ly);
  if (fx < fy) lx = (lx < 0 ? -1 : 1) * (car.halfLength + R);
  else ly = (ly < 0 ? -1 : 1) * (car.halfWidth + R);
  return { x: car.x + lx * cs - ly * sn, y: car.y + lx * sn + ly * cs };
}

export type PedMode = 'walk' | 'cross' | 'leap' | 'stun' | 'recover';

export class Pedestrian {
  /** Path: edge index, side (+1 = left of from → to), metres from `from`, walking direction. */
  edge = 0;
  side = 1;
  s = 0;
  dir = 1;
  speed = 1.4;
  mode: PedMode = 'walk';
  /** Mode to return to after a dodge. */
  resume: 'walk' | 'cross' = 'walk';
  /** Base point (on the path or the crossing line) and the offset from it. */
  bx = 0;
  by = 0;
  ox = 0;
  oy = 0;
  x = 0;
  y = 0;
  heading = 0;
  /** Seconds left of the "!!" bubble. */
  bubble = 0;
  /** Leap from (lx0, ly0) to (lx1, ly1) offset over ldur; lt elapsed. */
  lx0 = 0;
  ly0 = 0;
  lx1 = 0;
  ly1 = 0;
  lt = 0;
  ldur = 0;
  /** Stun countdown. */
  timer = 0;
  /** Crossing line target. */
  cx1 = 0;
  cy1 = 0;

  constructor(readonly id: number) {}
}

export interface PedStats {
  clamps: number;
  dodges: number;
}

/**
 * One step of dodging for a pedestrian (steps 1–3 and 6 of "Průběh v kroku"). Returns true
 * when the base point may advance this step (walk, cross, or a blocked recover walking around).
 */
export function stepAvoid(p: Pedestrian, cars: readonly CarPose[], r: number, dt: number, t: TuningPedestrians, stats: PedStats): boolean {
  p.bubble = Math.max(0, p.bubble - dt);
  const tx = p.bx + (p.mode === 'leap' ? p.lx1 : p.ox), ty = p.by + (p.mode === 'leap' ? p.ly1 : p.oy);
  if (dodgeAll(tx, ty, r, cars, t) !== null) {
    const d = dodgeAll(p.bx + p.ox, p.by + p.oy, r, cars, t);
    if (d !== null) {
      if (p.mode === 'walk' || p.mode === 'cross') p.resume = p.mode;
      stats.dodges++;
      p.bubble = t.bubbleS;
      p.lx0 = p.ox;
      p.ly0 = p.oy;
      p.lx1 = p.ox + d.dx;
      p.ly1 = p.oy + d.dy;
      p.lt = 0;
      p.ldur = d.dur;
      p.mode = 'leap';
    }
  }
  switch (p.mode) {
    case 'walk':
    case 'cross':
      return true;
    case 'leap': {
      p.lt += dt;
      const k = p.ldur <= dt ? 1 : Math.min(1, p.lt / p.ldur);
      p.ox = p.lx0 + (p.lx1 - p.lx0) * k;
      p.oy = p.ly0 + (p.ly1 - p.ly0) * k;
      if (k >= 1) {
        p.mode = 'stun';
        p.timer = t.stunS;
      }
      return false;
    }
    case 'stun':
      p.timer -= dt;
      if (p.timer <= 0) p.mode = 'recover';
      return false;
    case 'recover': {
      const len = Math.hypot(p.ox, p.oy);
      if (len === 0) {
        p.mode = p.resume;
        return true;
      }
      const step = Math.min(p.speed * dt, len);
      const k = 1 - step / len;
      const nx = p.bx + p.ox * k, ny = p.by + p.oy * k;
      const R = r + t.dodgeMarginM;
      if (dodgeAll(nx, ny, r, cars, t) !== null || cars.some((c) => overlapsBox(nx, ny, R, c))) return true;
      p.ox *= k;
      p.oy *= k;
      if (step >= len) {
        p.ox = p.oy = 0;
        p.mode = p.resume;
      }
      return false;
    }
  }
}

/** Sets x, y from base + offset and applies the safety push-out (step 5). */
export function settle(p: Pedestrian, cars: readonly CarPose[], r: number, t: TuningPedestrians, stats: PedStats): void {
  p.x = p.bx + p.ox;
  p.y = p.by + p.oy;
  for (const c of cars) {
    if (!overlapsBox(p.x, p.y, r, c)) continue;
    stats.clamps++;
    const q = pushOut(p.x, p.y, r + t.dodgeMarginM, c);
    p.x = q.x;
    p.y = q.y;
    p.ox = p.x - p.bx;
    p.oy = p.y - p.by;
    if (p.mode === 'walk' || p.mode === 'cross') {
      p.resume = p.mode;
      p.mode = 'recover';
    } else if (p.mode === 'leap') {
      p.mode = 'stun';
      p.timer = t.stunS;
    }
  }
}

/** All pedestrians of a city around the player (specs/pedestrians.md). */
export class PedestrianWorld {
  readonly peds: Pedestrian[] = [];
  readonly stats: PedStats = { clamps: 0, dodges: 0 };
  /** Body radius in metres (radius_m · car_scale). */
  readonly radius: number;
  private readonly t: TuningPedestrians;
  private readonly rnd: Prng;
  private readonly busy: Set<string>;
  private readonly cum = new Map<number, Float64Array>();
  private nextId = 1;
  private spawnAcc = 0;
  private focus: { x: number; y: number } | null = null;

  constructor(
    readonly city: City,
    readonly tuning: Tuning,
  ) {
    this.t = tuning.pedestrians;
    this.radius = this.t.radiusM * tuning.carScale;
    this.rnd = new Prng(this.t.seed);
    this.busy = new Set(this.t.busyDistricts);
  }

  get enabled(): boolean {
    return this.t.enabled;
  }

  /** Sidewalk offset from the edge axis (same as street furniture). */
  offset(e: RoadEdge): number {
    return e.width / 2 - this.tuning.sidewalkWidthM / 2;
  }

  walkable(e: RoadEdge): boolean {
    return e.kept && e.isGround && !e.bridge && e.length > 0 && this.offset(e) > 0;
  }

  /** Cap on the count (night lowers it). */
  cap(night: boolean): number {
    if (!this.t.enabled) return 0;
    return night ? Math.round(this.t.maxCount * this.t.nightFactor) : this.t.maxCount;
  }

  /** Nearest pedestrian to (x, y) within maxDist, or null (for dialogue and police). */
  nearest(x: number, y: number, maxDist = Infinity): Pedestrian | null {
    let best: Pedestrian | null = null;
    let bd = maxDist;
    for (const p of this.peds) {
      const d = Math.hypot(p.x - x, p.y - y);
      if (d <= bd) {
        bd = d;
        best = p;
      }
    }
    return best;
  }

  byId(id: number): Pedestrian | null {
    return this.peds.find((p) => p.id === id) ?? null;
  }

  clear(): void {
    this.peds.length = 0;
    this.focus = null;
  }

  /** One frame. cars[0] is the player's car (the spawn and despawn centre). */
  update(dt: number, cars: readonly CarPose[], viewRadius: number, night: boolean): void {
    const t = this.t;
    if (!t.enabled || cars.length === 0) {
      this.peds.length = 0;
      return;
    }
    dt = Math.min(dt, 0.1);
    const fx = cars[0]!.x, fy = cars[0]!.y;
    const rIn = viewRadius + t.spawnMarginM, rOut = rIn + t.spawnBandM;
    const cap = this.cap(night);
    if (this.focus === null || Math.hypot(fx - this.focus.x, fy - this.focus.y) > t.spawnBandM) {
      this.peds.length = 0;
      for (let i = 0; i < t.fillAttempts && this.peds.length < cap; i++) this.trySpawn(fx, fy, t.fillClearM, rOut, night);
    }
    this.focus = { x: fx, y: fy };

    const far = viewRadius + t.despawnMarginM;
    for (let i = this.peds.length - 1; i >= 0; i--) {
      const p = this.peds[i]!;
      const d = Math.hypot(p.x - fx, p.y - fy);
      if (d > far || (this.peds.length > cap && d > viewRadius)) this.peds.splice(i, 1);
    }
    this.spawnAcc += t.spawnPerS * dt;
    while (this.spawnAcc >= 1) {
      this.spawnAcc -= 1;
      if (this.peds.length < cap) this.trySpawn(fx, fy, rIn, rOut, night);
    }

    const r = this.radius;
    for (const p of this.peds) {
      if (stepAvoid(p, cars, r, dt, t, this.stats)) this.advance(p, dt);
      settle(p, cars, r, t, this.stats);
    }
  }

  private unit(): number {
    return this.rnd.nextU32() / 4294967296;
  }

  private trySpawn(fx: number, fy: number, rIn: number, rOut: number, night: boolean): void {
    const t = this.t;
    const ang = this.unit() * 2 * Math.PI;
    const rad = Math.sqrt(rIn * rIn + this.unit() * (rOut * rOut - rIn * rIn));
    const px = fx + Math.cos(ang) * rad, py = fy + Math.sin(ang) * rad;
    const hit = this.city.graph.nearest(px, py, t.snapM, (e) => this.walkable(e));
    if (hit === null) return;
    const district = this.city.districtAt(hit.x, hit.y);
    const dens = (t.classDensity[hit.edge.roadClass] ?? 0) *
      (district !== null && this.busy.has(district) ? t.busyFactor : t.quietFactor) * (night ? t.nightFactor : 1);
    if (this.unit() >= Math.min(1, dens)) return;
    const side = hit.dirX * (py - hit.y) - hit.dirY * (px - hit.x) >= 0 ? 1 : -1;
    const dir = this.unit() < 0.5 ? 1 : -1;
    const speed = t.walkMps + (this.unit() * 2 - 1) * t.walkJitterMps;
    const e = hit.edge;
    const s = hit.t * e.length;
    const q = this.pathPoint(e, s, side);
    if (Math.hypot(q.x - fx, q.y - fy) < rIn) return;
    const p = new Pedestrian(this.nextId++);
    p.edge = e.index;
    p.side = side;
    p.s = s;
    p.dir = dir;
    p.speed = speed;
    p.bx = p.x = q.x;
    p.by = p.y = q.y;
    p.heading = Math.atan2(q.dy * dir, q.dx * dir);
    this.peds.push(p);
  }

  /** Point on the sidewalk at s metres along edge e, on `side`; (dx, dy) is the segment direction. */
  pathPoint(e: RoadEdge, s: number, side: number): { x: number; y: number; dx: number; dy: number } {
    let cum = this.cum.get(e.index);
    if (!cum) {
      cum = new Float64Array(e.pointCount);
      for (let i = 1; i < e.pointCount; i++) {
        cum[i] = cum[i - 1]! + Math.hypot(e.pts[2 * i]! - e.pts[2 * i - 2]!, e.pts[2 * i + 1]! - e.pts[2 * i - 1]!);
      }
      this.cum.set(e.index, cum);
    }
    s = Math.max(0, Math.min(e.length, s));
    let i = 0;
    while (i < e.pointCount - 2 && (cum[i + 1]! < s || cum[i + 1] === cum[i])) i++;
    const ax = e.pts[2 * i]!, ay = e.pts[2 * i + 1]!, bx = e.pts[2 * i + 2]!, by = e.pts[2 * i + 3]!;
    const l = Math.hypot(bx - ax, by - ay);
    const dx = l === 0 ? 1 : (bx - ax) / l, dy = l === 0 ? 0 : (by - ay) / l;
    const k = Math.min(l, Math.max(0, s - cum[i]!));
    const o = this.offset(e) * side;
    return { x: ax + dx * k - dy * o, y: ay + dy * k + dx * o, dx, dy };
  }

  /** Walk, turn at nodes, cross (specs/pedestrians.md "Chůze"). */
  private advance(p: Pedestrian, dt: number): void {
    const step = p.speed * dt;
    if (p.mode === 'cross' || (p.mode === 'recover' && p.resume === 'cross')) {
      const dx = p.cx1 - p.bx, dy = p.cy1 - p.by;
      const l = Math.hypot(dx, dy);
      if (l <= step) {
        p.bx = p.cx1;
        p.by = p.cy1;
        if (p.mode === 'cross') p.mode = 'walk';
        else p.resume = 'walk';
      } else {
        p.bx += (dx / l) * step;
        p.by += (dy / l) * step;
        p.heading = Math.atan2(dy, dx);
      }
      return;
    }
    const g = this.city.graph;
    const e = g.edges[p.edge]!;
    p.s += p.dir * step;
    if (p.dir > 0 ? p.s >= e.length : p.s <= 0) {
      const node = p.dir > 0 ? e.to : e.from;
      const opts = g.nodeEdges[node]!.filter((i) => i !== p.edge && this.walkable(g.edges[i]!));
      const next = opts.length > 0 ? opts[this.rnd.nextInt(opts.length)]! : p.edge;
      let ws = p.side * p.dir;
      if (this.unit() < this.t.crossChance) ws = -ws;
      const ne = g.edges[next]!;
      const nd = ne.from === node ? 1 : -1;
      p.edge = next;
      p.dir = nd;
      p.side = ws * nd;
      p.s = nd > 0 ? 0 : ne.length;
      const q = this.pathPoint(ne, p.s, p.side);
      p.cx1 = q.x;
      p.cy1 = q.y;
      if (p.mode === 'recover') p.resume = 'cross';
      else p.mode = 'cross';
      return;
    }
    const q = this.pathPoint(e, p.s, p.side);
    p.bx = q.x;
    p.by = q.y;
    p.heading = Math.atan2(q.dy * p.dir, q.dx * p.dir);
  }
}
