import { Box, type Body, type Fixture, type Vec2Value, type World } from 'planck';

import type { Tuning } from '../gen/tuning';
import { CAT_CAR, CAT_PARKED, CAT_TRAFFIC, CAT_TRAM, type Car } from '../drive/car';
import { Prng } from '../rules/prng';
import { obbOverlap, type Traffic } from '../traffic/traffic';
import type { TrackEdge, TrackGraph, TrackStop } from '../world/model';
import { articulate, chooseNextTrack, nextStopAhead, stopTravelS, Trail, type CarPose } from './trackRules';

/** One articulated car of a tram: a kinematic box (specs/trams.md step 4). Read-only for others. */
export class TramCar {
  x = 0;
  y = 0;
  heading = 0;
  layer = 0;
  /** @internal current filter mask */
  mask = -1;

  constructor(
    readonly tram: Tram,
    /** 0 = the leading car. */
    readonly index: number,
    readonly halfLength: number,
    readonly halfWidth: number,
    readonly body: Body,
    readonly fixture: Fixture,
  ) {}
}

/** One tram (specs/trams.md "Stav"). Read-only for other features. */
export class Tram {
  /** Speed along the track, m/s (never negative). */
  speed = 0;
  layer = 0;
  braking = false;
  /** Seconds left standing at a stop. */
  dwellTimer = 0;
  /** Seconds left standing after the player hit it. */
  hitTimer = 0;
  readonly cars: TramCar[] = [];
  readonly trail: Trail;

  /** @internal path state */
  edge: TrackEdge;
  dir: number;
  s: number;
  /** Segment index in travel order on the current edge. */
  seg = 0;
  /** Stop the tram is heading for (−1 none) and the stop it last stood at on this edge. */
  stop = -1;
  served = -1;
  /** Fixed step at which the tram entered its current edge (single-track right of way). */
  enteredAt = 0;
  touching = false;

  constructor(
    readonly id: number,
    edge: TrackEdge,
    dir: number,
    s: number,
    readonly rng: Prng,
    trailPoints: number,
  ) {
    this.edge = edge;
    this.dir = dir;
    this.s = s;
    this.trail = new Trail(trailPoints);
  }
}

export type TramHitListener = (tram: Tram, impactMps: number) => void;

const TWO_PI = 2 * Math.PI;
const wrap = (a: number): number => {
  while (a > Math.PI) a -= TWO_PI;
  while (a < -Math.PI) a += TWO_PI;
  return a;
};

/** Index of travel-order point j of an edge driven in direction dir. */
const travelIdx = (e: TrackEdge, dir: number, j: number): number => (dir > 0 ? j : e.pointCount - 1 - j);
/** Distance of travel-order point j from the start of the travel direction. */
const travelCum = (e: TrackEdge, dir: number, j: number): number => (dir > 0 ? e.cum[j]! : e.length - e.cum[e.pointCount - 1 - j]!);

/**
 * Trams on the track graph (specs/trams.md). Every car is a kinematic planck body: the player
 * bounces off it, nothing pushes it. Motion is computed here like traffic (traffic/traffic.ts).
 */
export class Trams {
  readonly trams: Tram[] = [];
  /** All cars of all trams (specs/trams.md "API"). */
  readonly items: TramCar[] = [];
  readonly stops: ReadonlyArray<TrackStop>;
  /** Player hits so far. */
  hits = 0;
  /** False = the player is a ghost to trams (benchmark autopilot), as Traffic.solid. */
  solid = true;
  /** Fixed steps since start. */
  stepCount = 0;

  private readonly rng: Prng;
  private readonly listeners: TramHitListener[] = [];
  private readonly scratch: number[] = [];
  private readonly cands: number[] = [];
  /** Per edge: bounding box min x, min y, max x, max y. */
  private readonly boxes: Float32Array;
  private readonly v: Vec2Value = { x: 0, y: 0 };
  private readonly pos: Vec2Value = { x: 0, y: 0 };
  private readonly p = [0, 0, 0, 0];
  private readonly pose: CarPose = { x: 0, y: 0, heading: 0 };
  private readonly halfLength: number;
  private readonly halfWidth: number;
  private spawnTimer = 0;
  private fresh = true;
  private nextId = 1;
  private pvx = 0;
  private pvy = 0;

  constructor(
    readonly world: World,
    readonly graph: TrackGraph,
    readonly tuning: Tuning,
    /** Traffic cars are obstacles ahead (step 1 b); null without traffic. */
    readonly traffic: Traffic | null = null,
  ) {
    this.stops = graph.stops;
    this.rng = new Prng(tuning.trams.seed);
    this.halfLength = tuning.trams.carLengthM / 2;
    this.halfWidth = tuning.trams.carWidthM / 2;
    this.boxes = new Float32Array(graph.edges.length * 4);
    for (const e of graph.edges) {
      let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
      for (let i = 0; i < e.pts.length; i += 2) {
        x0 = Math.min(x0, e.pts[i]!);
        x1 = Math.max(x1, e.pts[i]!);
        y0 = Math.min(y0, e.pts[i + 1]!);
        y1 = Math.max(y1, e.pts[i + 1]!);
      }
      this.boxes.set([x0, y0, x1, y1], 4 * e.index);
    }
  }

  /** Registers a "tram hit by player" listener; returns the unsubscribe function. */
  onHit(fn: TramHitListener): () => void {
    this.listeners.push(fn);
    return () => {
      const i = this.listeners.indexOf(fn);
      if (i >= 0) this.listeners.splice(i, 1);
    };
  }

  /** Removes all trams and refills around the player on the next step. */
  reset(): void {
    for (const tr of this.trams) for (const c of tr.cars) this.world.destroyBody(c.body);
    this.trams.length = 0;
    this.items.length = 0;
    this.fresh = true;
  }

  destroy(): void {
    this.reset();
    this.listeners.length = 0;
  }

  /** Before world.step: spawn/despawn, drive every tram, set the kinematic velocities. */
  preStep(dt: number, player: Car): void {
    const t = this.tuning.trams;
    this.stepCount++;
    const pv = player.body.getLinearVelocity();
    this.pvx = pv.x;
    this.pvy = pv.y;
    const px = player.x, py = player.y;
    const d2 = t.despawnM * t.despawnM;
    for (let i = this.trams.length - 1; i >= 0; i--) {
      const h = this.trams[i]!.cars[0]!;
      const dx = h.x - px, dy = h.y - py;
      if (dx * dx + dy * dy > d2) this.remove(i);
    }
    this.spawn(dt, px, py);
    for (let i = this.trams.length - 1; i >= 0; i--) {
      if (!this.drive(this.trams[i]!, dt, player)) this.remove(i);
    }
  }

  /**
   * After world.step: player hits and the layer masks. A hit is an overlap of the player's box
   * with any car (SAT with traffic.hit_margin_m, as traffic step 6).
   */
  postStep(player: Car): void {
    const t = this.tuning.trams;
    const ph = player.heading, pc = Math.cos(ph), ps = Math.sin(ph);
    const round = this.tuning.drive.bodyRoundM, margin = this.tuning.traffic.hitMarginM;
    const phl = player.halfLength + round, phw = player.halfWidth + round;
    const px = player.x, py = player.y;
    for (const tr of this.trams) {
      let touch = false;
      for (const c of tr.cars) {
        const same = this.solid && c.layer === player.layer;
        this.setMask(c, same);
        if (!same || touch) continue;
        touch = obbOverlap(px, py, pc, ps, phl, phw, c.x, c.y, Math.cos(c.heading), Math.sin(c.heading), c.halfLength, c.halfWidth, margin);
      }
      if (touch && !tr.touching) {
        const h = tr.cars[0]!.heading;
        const rvx = this.pvx - Math.cos(h) * tr.speed, rvy = this.pvy - Math.sin(h) * tr.speed;
        const impact = Math.sqrt(rvx * rvx + rvy * rvy);
        if (impact >= t.hitMinMps) {
          tr.hitTimer = t.hitStopS;
          tr.speed = 0;
          this.hits++;
          for (const fn of this.listeners) fn(tr, impact);
        }
      }
      tr.touching = touch;
    }
  }

  /** Same layer as the player: CAT_CAR; on the ground also traffic and parked cars (step 4). */
  private setMask(c: TramCar, same: boolean): void {
    const ground = c.layer === 0;
    const mask = (same ? CAT_CAR : 0) | (ground ? CAT_TRAFFIC | CAT_PARKED : 0);
    if (mask === c.mask) return;
    c.mask = mask;
    c.fixture.setFilterData({ groupIndex: 0, categoryBits: CAT_TRAM, maskBits: mask });
  }

  // ---------- spawning

  private unit(): number {
    return this.rng.nextU32() / 4294967296;
  }

  private spawn(dt: number, px: number, py: number): void {
    const t = this.tuning.trams;
    this.spawnTimer += dt;
    if (!this.fresh && this.spawnTimer < t.spawnIntervalS) return;
    this.fresh = false;
    this.spawnTimer = 0;
    if (this.trams.length >= t.maxTrams) return;
    // An empty city around the player (start, teleport) fills from initial_min_m.
    const rMin = this.trams.length === 0 ? t.initialMinM : t.spawnMinM;
    const rMax = t.spawnMaxM;
    const c = this.cands;
    c.length = 0;
    const b = this.boxes;
    for (const e of this.graph.edges) {
      if (!e.isGround || e.from === e.to || e.length <= 1) continue;
      const o = 4 * e.index;
      const nx = Math.max(b[o]! - px, 0, px - b[o + 2]!), ny = Math.max(b[o + 1]! - py, 0, py - b[o + 3]!);
      if (nx * nx + ny * ny > rMax * rMax) continue;
      const fx = Math.max(Math.abs(b[o]! - px), Math.abs(b[o + 2]! - px));
      const fy = Math.max(Math.abs(b[o + 1]! - py), Math.abs(b[o + 3]! - py));
      if (fx * fx + fy * fy < rMin * rMin) continue;
      c.push(e.index);
    }
    if (c.length === 0) return;
    for (let i = 0; i < t.spawnTries && this.trams.length < t.maxTrams; i++) this.trySpawn(px, py, rMin);
  }

  private trySpawn(px: number, py: number, rMin: number): boolean {
    const t = this.tuning.trams;
    const e = this.graph.edges[this.cands[this.rng.nextInt(this.cands.length)]!]!;
    const d = this.unit() * e.length;
    e.pointAt(d, this.p);
    const x = this.p[0]!, y = this.p[1]!;
    const r = Math.hypot(x - px, y - py);
    if (r < rMin || r > t.spawnMaxM) return false;
    for (const c of this.items) if (Math.hypot(c.x - x, c.y - y) < t.spawnClearM) return false;
    const dir = this.rng.nextInt(2) === 0 ? 1 : -1;
    return this.addTram(e.index, dir, dir > 0 ? d : e.length - d) !== null;
  }

  /**
   * Puts a tram with its head on edge `edge` going `dir` (+1 from → to, −1 to → from), `s`
   * metres along the travel direction. Null when the edge does not exist or max_trams is reached.
   */
  addTram(edge: number, dir: number, s: number): Tram | null {
    const t = this.tuning.trams;
    const e = this.graph.edges[edge];
    if (!e || e.pointCount < 2 || this.trams.length >= t.maxTrams) return null;
    const d = dir > 0 ? 1 : -1;
    const tr = new Tram(this.nextId++, e, d, Math.max(0, Math.min(s, e.length)), new Prng(this.rng.nextU32()), t.trailPoints);
    tr.enteredAt = this.stepCount;
    for (let k = 0; k < t.carsPerTram; k++) {
      const body = this.world.createBody({ type: 'kinematic', position: { x: 0, y: 0 }, angle: 0 });
      const fixture = body.createFixture({
        shape: new Box(this.halfLength, this.halfWidth),
        friction: this.tuning.drive.carFriction,
        restitution: this.tuning.drive.carRestitution,
        filterCategoryBits: CAT_TRAM,
        filterMaskBits: CAT_CAR | CAT_TRAFFIC | CAT_PARKED,
      });
      const car = new TramCar(tr, k, this.halfLength, this.halfWidth, body, fixture);
      tr.cars.push(car);
      this.items.push(car);
    }
    // Head pose, then the path behind it on this edge (further back the trail runs straight).
    tr.seg = 0;
    while (tr.seg < e.pointCount - 2 && tr.s > travelCum(e, tr.dir, tr.seg + 1)) tr.seg++;
    this.head(tr);
    for (let j = tr.seg; j >= 0; j--) {
      const i = travelIdx(e, tr.dir, j);
      tr.trail.pushOldest(e.pts[2 * i]!, e.pts[2 * i + 1]!);
    }
    this.poseCars(tr);
    for (const c of tr.cars) {
      this.pos.x = c.x;
      this.pos.y = c.y;
      c.body.setTransform(this.pos, c.heading);
    }
    this.trams.push(tr);
    return tr;
  }

  private remove(i: number): void {
    const tr = this.trams[i]!;
    for (const c of tr.cars) this.world.destroyBody(c.body);
    let w = 0;
    for (let r = 0; r < this.items.length; r++) {
      const c = this.items[r]!;
      if (c.tram !== tr) this.items[w++] = c;
    }
    this.items.length = w;
    const last = this.trams.pop()!;
    if (last !== tr) this.trams[i] = last;
  }

  // ---------- driving

  /** One step of one tram; false = it has to disappear (border node). */
  private drive(tr: Tram, dt: number, player: Car): boolean {
    const t = this.tuning.trams;
    const g = this.graph;
    if (tr.hitTimer > 0) {
      tr.hitTimer = Math.max(0, tr.hitTimer - dt);
      tr.speed = 0;
      tr.braking = true;
    } else if (tr.dwellTimer > 0) {
      // Standing at a stop (P2: the bell when it leaves).
      tr.dwellTimer = Math.max(0, tr.dwellTimer - dt);
      tr.speed = 0;
      tr.braking = false;
    } else {
      if (tr.stop < 0) tr.stop = nextStopAhead(g, tr.edge.index, tr.dir, tr.s, t.stopCommitM, tr.served);
      const gap = this.gapAhead(tr, player);
      const free = Math.max(0, gap - t.minGapM);
      const want = Math.min(t.speedMps, Math.sqrt(2 * t.brakeMps2 * free));
      const dv = want - tr.speed;
      tr.braking = dv < -t.accelMps2 * dt;
      tr.speed = Math.max(0, tr.speed + Math.min(t.accelMps2 * dt, Math.max(-t.brakeMps2 * dt, dv)));
      // The head reaches its stop within this step: stand there for dwell_s.
      if (tr.stop >= 0) {
        const at = stopTravelS(g, tr.stop, tr.dir);
        if (at - tr.s <= tr.speed * dt) {
          tr.s = Math.max(tr.s, at);
          tr.speed = 0;
          tr.dwellTimer = t.dwellS;
          tr.served = tr.stop;
          tr.stop = -1;
        }
      }
    }
    tr.s += tr.speed * dt;
    // Edge transitions (a short edge may be crossed within one step; degenerate edges give up).
    for (let hops = 0; tr.s >= tr.edge.length; hops++) {
      if (hops > g.edges.length) return false;
      const e = tr.edge;
      // The rest of this edge's points, the end node included, join the trail.
      for (let j = tr.seg + 1; j < e.pointCount; j++) {
        const i = travelIdx(e, tr.dir, j);
        tr.trail.push(e.pts[2 * i]!, e.pts[2 * i + 1]!);
      }
      const node = tr.dir > 0 ? e.to : e.from;
      const next = chooseNextTrack(g, node, e.index, tr.rng, this.scratch);
      if (next < 0) return false;
      tr.s -= e.length;
      const ne = g.edges[next]!;
      tr.edge = ne;
      tr.dir = ne.from === node ? 1 : -1;
      tr.seg = 0;
      tr.stop = -1;
      tr.served = -1;
      tr.enteredAt = this.stepCount;
    }
    // Passed polyline points join the trail.
    const e = tr.edge;
    while (tr.seg < e.pointCount - 2 && tr.s > travelCum(e, tr.dir, tr.seg + 1)) {
      tr.seg++;
      const i = travelIdx(e, tr.dir, tr.seg);
      tr.trail.push(e.pts[2 * i]!, e.pts[2 * i + 1]!);
    }
    this.head(tr);
    for (const c of tr.cars) {
      const ox = c.x, oy = c.y, oh = c.heading;
      articulate(tr.trail, c.index, t.carLengthM, t.jointGapM, this.pose);
      c.x = this.pose.x;
      c.y = this.pose.y;
      c.heading = this.pose.heading;
      c.layer = tr.layer;
      this.v.x = (c.x - ox) / dt;
      this.v.y = (c.y - oy) / dt;
      c.body.setLinearVelocity(this.v);
      c.body.setAngularVelocity(wrap(c.heading - oh) / dt);
    }
    return true;
  }

  /** Head point of the trail and the tram's layer from its edge, segment and s. */
  private head(tr: Tram): void {
    const e = tr.edge;
    const a = travelIdx(e, tr.dir, tr.seg), b = travelIdx(e, tr.dir, tr.seg + 1);
    const c0 = travelCum(e, tr.dir, tr.seg), l = travelCum(e, tr.dir, tr.seg + 1) - c0;
    const ax = e.pts[2 * a]!, ay = e.pts[2 * a + 1]!, bx = e.pts[2 * b]!, by = e.pts[2 * b + 1]!;
    const f = l > 0 ? Math.min(1, Math.max(0, (tr.s - c0) / l)) : 0;
    tr.trail.headX = ax + (bx - ax) * f;
    tr.trail.headY = ay + (by - ay) * f;
    if (tr.trail.count === 1 && l > 0) {
      tr.trail.tailDirX = (bx - ax) / l;
      tr.trail.tailDirY = (by - ay) / l;
    }
    const d = tr.dir > 0 ? tr.s : e.length - tr.s;
    tr.layer = e.layerAt(e.length > 0 ? d / e.length : 0);
  }

  private poseCars(tr: Tram): void {
    const t = this.tuning.trams;
    for (const c of tr.cars) {
      articulate(tr.trail, c.index, t.carLengthM, t.jointGapM, this.pose);
      c.x = this.pose.x;
      c.y = this.pose.y;
      c.heading = this.pose.heading;
      c.layer = tr.layer;
    }
  }

  /** Free distance to the nearest obstacle ahead (step 1): player, traffic, trams, the stop. */
  private gapAhead(tr: Tram, player: Car): number {
    const t = this.tuning.trams;
    const h = tr.cars[0]!;
    const hc = Math.cos(h.heading), hs = Math.sin(h.heading);
    const look = t.lookAheadM;
    let gap = look;
    if (this.solid && player.layer === tr.layer) {
      gap = Math.min(gap, this.gapTo(h, hc, hs, player.x, player.y, player.halfLength, look));
    }
    if (this.traffic) {
      for (const c of this.traffic.cars) {
        if (c.layer !== tr.layer) continue;
        gap = Math.min(gap, this.gapTo(h, hc, hs, c.x, c.y, c.halfLength, look));
      }
    }
    for (const o of this.trams) {
      if (o === tr) continue;
      if (o.edge === tr.edge) {
        // Single track, opposite way: only the tram that entered the edge later waits.
        const later = tr.enteredAt > o.enteredAt || (tr.enteredAt === o.enteredAt && tr.id > o.id);
        if (o.dir !== tr.dir && !later) continue;
      }
      for (const c of o.cars) {
        if (c.layer !== tr.layer) continue;
        // Elsewhere only trams going roughly our way (±60°): not the other track of a double line.
        if (o.edge !== tr.edge && Math.cos(c.heading) * hc + Math.sin(c.heading) * hs < 0.5) continue;
        gap = Math.min(gap, this.gapTo(h, hc, hs, c.x, c.y, c.halfLength, look));
      }
    }
    // The stop: the head halts on it (like traffic's stop line, min_gap_m is added back).
    if (tr.stop >= 0) {
      const toStop = stopTravelS(this.graph, tr.stop, tr.dir) - tr.s;
      gap = Math.min(gap, Math.max(0, toStop + t.minGapM));
    }
    return gap;
  }

  private gapTo(h: TramCar, hc: number, hs: number, ox: number, oy: number, ohl: number, look: number): number {
    const dx = ox - h.x, dy = oy - h.y;
    const lx = dx * hc + dy * hs;
    if (lx <= 0 || lx > look + h.halfLength + ohl) return Infinity;
    const ly = -dx * hs + dy * hc;
    if (Math.abs(ly) > this.tuning.trams.corridorM) return Infinity;
    return Math.max(0, lx - h.halfLength - ohl);
  }
}
