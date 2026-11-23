import { Box, type Body, type Fixture, type Vec2Value, type World } from 'planck';

import { tokens } from '../gen/tokens';
import type { Tuning } from '../gen/tuning';
import { CAT_BUILDINGS, CAT_CAR, CAT_PARKED, CAT_TRAFFIC, CAT_TRAM, type Car } from '../drive/car';
import { TERRAIN_SPEC } from '../drive/slope';
import { Prng } from '../rules/prng';
import type { City, RoadEdge, RoadGraph } from '../world/model';
import {
  buildSignals, canLeave, chooseNext, chooseToward, laneOffset, lanesPerDir, LIGHT_AMBER, LIGHT_GREEN, lightState,
  signalClockMs, swerveShift, type Signals,
} from './roadRules';

/** What traffic needs of a parked car (specs/traffic.md step 8); hl/hw default to a traffic car. */
export interface ParkedPose {
  x: number;
  y: number;
  heading: number;
  hl?: number;
  hw?: number;
}

/** What traffic needs of a tram car (specs/traffic.md v3 step 1 b, specs/trams.md). */
export interface TramObstacle {
  readonly x: number;
  readonly y: number;
  readonly heading: number;
  readonly layer: number;
  readonly halfLength: number;
  readonly halfWidth: number;
}

/** One AI car (specs/traffic.md "Stav"). Read-only for other features. */
export class TrafficCar {
  x = 0;
  y = 0;
  heading = 0;
  /** Speed along the lane, m/s (never negative). */
  speed = 0;
  layer = 0;
  /** Game height of the lane under the car (specs/terrain.md: AI follows the height, never jumps). */
  z = 0;
  braking = false;
  /** Seconds left standing still after the player hit it. */
  hitTimer = 0;
  /** Seconds left loose after the last touch (specs/traffic.md step 7). */
  pushTimer = 0;
  /** Dynamic body: pushed or hit; the pose comes from physics. */
  loose = false;
  /** Police hooks (specs/police.md), set by the police module: a patrol car, chasing a goal. */
  police = false;
  pursuing = false;
  goalX = 0;
  goalY = 0;
  pursuitMps = 0;
  /** A chasing patrol brakes to stop this far from its goal. */
  goalStopM = 0;
  /**
   * Roadblock patrol (specs/roadblock.md): stands still across the road, never drives,
   * never despawns with distance; the police module removes it.
   */
  blocking = false;

  /** @internal path state */
  edge: RoadEdge;
  dir: number;
  s: number;
  lane: number;
  seg = 0;
  segStart = 0;
  touching = false;
  /** Current filter mask (switched by layer, solidity and looseness). */
  mask = -1;

  constructor(
    readonly id: number,
    edge: RoadEdge,
    dir: number,
    s: number,
    lane: number,
    readonly rng: Prng,
    /** Index into tokens.colorTrafficBodies. */
    readonly colour: number,
    readonly halfLength: number,
    readonly halfWidth: number,
    readonly body: Body,
    readonly fixture: Fixture,
  ) {
    this.edge = edge;
    this.dir = dir;
    this.s = s;
    this.lane = lane;
  }
}

export type TrafficHitListener = (car: TrafficCar, impactMps: number) => void;

const TWO_PI = 2 * Math.PI;
const wrap = (a: number): number => {
  while (a > Math.PI) a -= TWO_PI;
  while (a < -Math.PI) a += TWO_PI;
  return a;
};

/**
 * AI traffic and traffic lights (specs/traffic.md). Cars are kinematic planck bodies that only
 * collide with the player's car; their motion is computed here, the solver only pushes the player.
 * Port of packages/drive_core/lib/src/traffic/traffic.dart.
 */
export class Traffic {
  readonly cars: TrafficCar[] = [];
  readonly signals: Signals;
  readonly leftHand: boolean;
  /** Night halves the density (traffic.night_factor); the client sets it with its day/night toggle. */
  night = false;
  /** Player hits so far. */
  hits = 0;
  /**
   * False = the player is a ghost to traffic: no collisions, no hits, cars do not wait for it.
   * The D1 benchmark autopilot sets this, it does not avoid cars (specs/traffic.md).
   */
  solid = true;
  /**
   * The player hops over traffic (specs/hop.md): no collisions and no hits while it flies; cars
   * it overlaps on landing count as already touching, so they are pushed, not hit.
   */
  playerAirborne = false;
  /** Fixed steps since start: the signal clock. */
  stepCount = 0;
  /** Parked cars to drive round (set by the car fleet, specs/traffic.md step 8). */
  parked: ReadonlyArray<ParkedPose> = [];
  /** Tram cars, obstacles ahead in any direction (set by the drive world, specs/traffic.md v3). */
  trams: ReadonlyArray<TramObstacle> = [];

  private readonly graph: RoadGraph;
  private readonly rng: Prng;
  private readonly listeners: TrafficHitListener[] = [];
  private readonly scratch: number[] = [];
  private readonly v: Vec2Value = { x: 0, y: 0 };
  private readonly obs: number[] = [];
  private readonly halfLength: number;
  private readonly halfWidth: number;
  private spawnTimer = 0;
  private fresh = true;
  private lastPX = 0;
  private lastPY = 0;
  private tracked = false;
  private nextId = 1;

  constructor(
    readonly world: World,
    readonly city: City,
    readonly tuning: Tuning,
  ) {
    this.graph = city.graph;
    this.leftHand = city.manifest.driveSide === 'left';
    this.signals = buildSignals(this.graph, tuning, this.leftHand);
    this.rng = new Prng(tuning.traffic.seed);
    this.halfLength = (tuning.traffic.carLengthM * tuning.carScale) / 2;
    this.halfWidth = (tuning.traffic.carWidthM * tuning.carScale) / 2;
  }

  /** Registers a "car hit by player" listener; returns the unsubscribe function. */
  onHit(fn: TrafficHitListener): () => void {
    this.listeners.push(fn);
    return () => {
      const i = this.listeners.indexOf(fn);
      if (i >= 0) this.listeners.splice(i, 1);
    };
  }

  /** Signal clock in ms (specs/traffic.md "Hodiny"). */
  get clockMs(): number {
    return signalClockMs(this.stepCount, this.tuning.drive.stepHz);
  }

  /** Light shown on approach index a (LIGHT_GREEN / AMBER / RED). */
  light(a: number): number {
    const ap = this.signals.approaches[a]!;
    return lightState(this.signals.offsets[ap.signal]!, ap.group, this.clockMs, this.tuning.traffic);
  }

  /** Removes all cars and refills around the player on the next step. */
  reset(): void {
    for (const c of this.cars) this.world.destroyBody(c.body);
    this.cars.length = 0;
    this.fresh = true;
  }

  destroy(): void {
    this.reset();
    this.listeners.length = 0;
  }

  /** Before world.step: spawn/despawn, drive every car, set the kinematic velocities. */
  preStep(dt: number, player: Car): void {
    const t = this.tuning.traffic;
    this.stepCount++;
    const px = player.x, py = player.y;
    const jx = px - this.lastPX, jy = py - this.lastPY;
    if (this.tracked && jx * jx + jy * jy > t.teleportM * t.teleportM) this.reset();
    this.tracked = true;
    this.lastPX = px;
    this.lastPY = py;

    // Despawn far cars (swap-remove, no allocation).
    const d2 = t.despawnM * t.despawnM;
    for (let i = this.cars.length - 1; i >= 0; i--) {
      const c = this.cars[i]!;
      const dx = c.x - px, dy = c.y - py;
      if (!c.blocking && dx * dx + dy * dy > d2) this.remove(i);
    }
    this.spawn(dt, px, py);

    const k = 1 - Math.exp(-t.followRate * dt);
    for (let i = this.cars.length - 1; i >= 0; i--) {
      const c = this.cars[i]!;
      if (!this.drive(c, dt, k, player)) this.remove(i);
    }
  }

  /** After world.step: hit detection against the player (SAT on the two boxes). */
  postStep(player: Car): void {
    const t = this.tuning.traffic;
    const pv = player.body.getLinearVelocity();
    const ph = player.heading, pc = Math.cos(ph), ps = Math.sin(ph);
    const round = this.tuning.drive.bodyRoundM;
    const phl = player.halfLength + round, phw = player.halfWidth + round;
    const air = this.playerAirborne;
    for (const c of this.cars) {
      const same = this.solid && c.layer === player.layer;
      const touch = same && obbOverlap(
        player.x, player.y, pc, ps, phl, phw,
        c.x, c.y, Math.cos(c.heading), Math.sin(c.heading), c.halfLength, c.halfWidth, t.hitMarginM,
      );
      if (touch && !c.touching && !air) {
        const rvx = pv.x - Math.cos(c.heading) * c.speed, rvy = pv.y - Math.sin(c.heading) * c.speed;
        const impact = Math.sqrt(rvx * rvx + rvy * rvy);
        if (impact >= t.hitMinMps) {
          c.hitTimer = t.hitStopS;
          c.speed = 0;
          this.hits++;
          for (const fn of this.listeners) fn(c, impact);
        }
      }
      if (touch && !air) c.pushTimer = t.pushHoldS;
      c.touching = touch;
      this.setLoose(c, c.hitTimer > 0 || c.pushTimer > 0);
      this.setMask(c, same && !air);
    }
  }

  /** Dynamic while loose, kinematic otherwise (specs/traffic.md step 7). */
  private setLoose(c: TrafficCar, loose: boolean): void {
    if (loose === c.loose) return;
    c.loose = loose;
    if (loose) {
      c.body.setDynamic();
      c.body.setLinearDamping(this.tuning.traffic.pushLinearDamping);
      c.body.setAngularDamping(this.tuning.traffic.pushAngularDamping);
      c.body.setAwake(true);
      c.speed = 0;
    } else {
      c.body.setKinematic();
      c.s = this.projectS(c);
    }
  }

  private setMask(c: TrafficCar, same: boolean): void {
    const ground = c.layer === 0;
    // A loose car on the ground also stops at tram cars (they never move for it).
    const mask = (same ? CAT_CAR : 0) | (ground ? CAT_PARKED : 0) | (ground && c.loose ? CAT_BUILDINGS | CAT_TRAM : 0);
    if (mask === c.mask) return;
    c.mask = mask;
    c.fixture.setFilterData({ groupIndex: 0, categoryBits: CAT_TRAFFIC, maskBits: mask });
  }

  /** Distance along the travel direction of the car's own edge nearest to its position. */
  private projectS(c: TrafficCar): number {
    const e = c.edge;
    let best = Infinity, d = 0;
    for (let seg = 0; seg + 1 < e.pointCount; seg++) {
      const h = this.graph.project(e, seg, c.x, c.y);
      if (h.dist < best) {
        best = h.dist;
        d = h.t * e.length;
      }
    }
    return c.dir > 0 ? d : e.length - d;
  }

  // ---------- spawning

  private unit(): number {
    return this.rng.nextU32() / 4294967296;
  }

  private target(): number {
    const t = this.tuning.traffic;
    return Math.min(t.maxCars, Math.round(t.maxCars * (this.night ? t.nightFactor : 1)));
  }

  private spawn(dt: number, px: number, py: number): void {
    const t = this.tuning.traffic;
    if (this.fresh) {
      this.fresh = false;
      this.spawnTimer = 0;
      for (let i = 0; i < t.initialTries && this.cars.length < this.target(); i++) this.trySpawn(px, py, t.initialMinM);
      return;
    }
    this.spawnTimer += dt;
    if (this.spawnTimer < t.spawnIntervalS) return;
    this.spawnTimer = 0;
    for (let i = 0; i < t.spawnTries && this.cars.length < this.target(); i++) this.trySpawn(px, py, t.spawnMinM);
  }

  private trySpawn(px: number, py: number, rMin: number): boolean {
    const t = this.tuning.traffic;
    const a = this.unit() * TWO_PI, r = rMin + this.unit() * (t.spawnMaxM - rMin);
    const hit = this.graph.nearest(px + Math.cos(a) * r, py + Math.sin(a) * r, t.searchM, (e) => e.kept && e.length > 1);
    if (hit === null) return false;
    const e = hit.edge;
    if (this.unit() >= (t.classWeight[e.roadClass] ?? 0)) return false;
    if (Math.hypot(hit.x - px, hit.y - py) < rMin) return false;
    for (const c of this.cars) if (Math.hypot(c.x - hit.x, c.y - hit.y) < t.spawnClearM) return false;
    const fwd = canLeave(e, e.from), back = canLeave(e, e.to);
    if (!fwd && !back) return false;
    const dir = fwd && back ? (this.rng.nextInt(2) === 0 ? 1 : -1) : fwd ? 1 : -1;
    const lane = this.rng.nextInt(lanesPerDir(e, this.tuning));
    return this.addCar(e.index, dir, dir > 0 ? hit.t * e.length : (1 - hit.t) * e.length, lane) !== null;
  }

  /**
   * Puts a car on edge `edge` going `dir` (+1 from → to, −1 to → from), `s` metres along the
   * travel direction, in `lane`. Null when the edge is an alley, the direction is not allowed or
   * the max_cars cap is reached. Used by spawning; later features (police) may call it too.
   */
  addCar(edge: number, dir: number, s: number, lane: number): TrafficCar | null {
    const e = this.graph.edges[edge];
    if (!e || !e.kept || this.cars.length >= this.tuning.traffic.maxCars) return null;
    if (!canLeave(e, dir > 0 ? e.from : e.to)) return null;
    const colour = this.rng.nextInt(tokens.colorTrafficBodies.length);
    const carRng = new Prng(this.rng.nextU32());
    const body = this.world.createBody({ type: 'kinematic', position: { x: 0, y: 0 }, angle: 0 });
    const fixture = body.createFixture({
      shape: new Box(this.halfLength, this.halfWidth),
      density: this.tuning.traffic.massKg / (4 * this.halfLength * this.halfWidth),
      friction: this.tuning.drive.carFriction,
      restitution: this.tuning.drive.carRestitution,
      filterCategoryBits: CAT_TRAFFIC,
      filterMaskBits: CAT_CAR | CAT_PARKED,
    });
    const ln = Math.max(0, Math.min(lane, lanesPerDir(e, this.tuning) - 1));
    const c = new TrafficCar(this.nextId++, e, dir, Math.max(0, Math.min(s, e.length)), ln, carRng, colour, this.halfLength, this.halfWidth, body, fixture);
    c.seg = dir > 0 ? 0 : e.pointCount - 2;
    c.segStart = dir > 0 ? 0 : e.length - segLen(e, c.seg);
    this.place(c, 1);
    body.setTransform({ x: c.x, y: c.y }, c.heading);
    this.cars.push(c);
    return c;
  }

  /** Turns a car around on its edge (police U-turn): same point, opposite direction. */
  turnAround(c: TrafficCar): void {
    c.dir = -c.dir;
    c.s = Math.max(0, c.edge.length - c.s);
  }

  /**
   * Puts a car at an exact pose (x, y, heading) off its lane, e.g. a roadblock patrol across the
   * road (specs/roadblock.md); the car keeps its edge for the layer and later projection.
   */
  setPose(c: TrafficCar, x: number, y: number, heading: number): void {
    c.x = x;
    c.y = y;
    c.heading = heading;
    c.speed = 0;
    c.body.setTransform({ x, y }, heading);
    c.body.setLinearVelocity({ x: 0, y: 0 });
    c.body.setAngularVelocity(0);
  }

  /** Removes one car (e.g. a cleared roadblock); false when it is not in the traffic any more. */
  removeCar(c: TrafficCar): boolean {
    const i = this.cars.indexOf(c);
    if (i < 0) return false;
    this.remove(i);
    return true;
  }

  private remove(i: number): void {
    const c = this.cars[i]!;
    this.world.destroyBody(c.body);
    const last = this.cars.pop()!;
    if (last !== c) this.cars[i] = last;
  }

  // ---------- driving

  /** One step of one car; false = it has to disappear. */
  private drive(c: TrafficCar, dt: number, k: number, player: Car): boolean {
    const t = this.tuning.traffic;
    c.pushTimer = Math.max(0, c.pushTimer - dt);
    if (c.loose) {
      // Pushed or knocked: physics owns the pose until it settles (specs/traffic.md step 7).
      c.hitTimer = Math.max(0, c.hitTimer - dt);
      c.speed = 0;
      c.braking = false;
      const p = c.body.getPosition();
      c.x = p.x;
      c.y = p.y;
      c.heading = c.body.getAngle();
      return true;
    }
    if (c.blocking) {
      // A roadblock patrol stands where it was put (or where a push left it).
      c.hitTimer = Math.max(0, c.hitTimer - dt);
      c.speed = 0;
      c.braking = false;
      this.v.x = 0;
      this.v.y = 0;
      c.body.setLinearVelocity(this.v);
      c.body.setAngularVelocity(0);
      return true;
    }
    if (c.hitTimer > 0) {
      c.hitTimer = Math.max(0, c.hitTimer - dt);
      c.speed = 0;
    } else {
      const gap = this.gapAhead(c, player);
      let vmax = c.pursuing ? this.pursuitSpeed(c) : (t.classSpeedMps[c.edge.roadClass] ?? t.classSpeedMps[0]!);
      // Uphill steeper than 8 % at 0.8 × speed (specs/terrain.md "Svah"; no slope force for AI).
      if (c.edge.gradeOfSeg(c.seg) * c.dir > TERRAIN_SPEC.aiUphillGrade) vmax *= TERRAIN_SPEC.aiUphillFactor;
      const free = Math.max(0, gap - t.minGapM);
      const want = Math.min(vmax, free / t.headwayS, Math.sqrt(2 * t.brakeMps2 * free));
      const dv = want - c.speed;
      c.braking = dv < -t.accelMps2 * dt;
      c.speed = Math.max(0, c.speed + Math.min(t.accelMps2 * dt, Math.max(-t.brakeMps2 * dt, dv)));
    }
    c.s += c.speed * dt;
    // Edge transitions (a short edge may be crossed within one step).
    while (c.s >= c.edge.length) {
      const node = c.dir > 0 ? c.edge.to : c.edge.from;
      const next = c.pursuing
        ? chooseToward(this.graph, node, c.edge.index, c.goalX, c.goalY)
        : chooseNext(this.graph, node, c.edge.index, c.rng, this.scratch);
      if (next < 0) return false;
      c.s -= c.edge.length;
      const e = this.graph.edges[next]!;
      c.edge = e;
      c.dir = e.from === node ? 1 : -1;
      c.lane = Math.min(c.lane, lanesPerDir(e, this.tuning) - 1);
      c.seg = c.dir > 0 ? 0 : e.pointCount - 2;
      c.segStart = c.dir > 0 ? 0 : e.length - segLen(e, c.seg);
    }
    const ox = c.x, oy = c.y, oh = c.heading;
    this.place(c, k);
    this.v.x = (c.x - ox) / dt;
    this.v.y = (c.y - oy) / dt;
    c.body.setLinearVelocity(this.v);
    c.body.setAngularVelocity(wrap(c.heading - oh) / dt);
    return true;
  }

  /** Chase speed: pursuitMps, braking to a stop goalStopM from the goal (specs/police.md). */
  private pursuitSpeed(c: TrafficCar): number {
    const left = Math.max(0, Math.hypot(c.goalX - c.x, c.goalY - c.y) - c.goalStopM);
    return Math.min(c.pursuitMps, Math.sqrt(2 * this.tuning.traffic.brakeMps2 * left));
  }

  /** Moves the car's pose towards its lane point at s; k = 1 snaps. */
  private place(c: TrafficCar, k: number): void {
    const e = c.edge;
    const d = c.dir > 0 ? c.s : e.length - c.s;
    const last = e.pointCount - 2;
    let len = segLen(e, c.seg);
    while (c.seg < last && d > c.segStart + len) {
      c.segStart += len;
      c.seg++;
      len = segLen(e, c.seg);
    }
    while (c.seg > 0 && d < c.segStart) {
      c.seg--;
      len = segLen(e, c.seg);
      c.segStart -= len;
    }
    const i = 2 * c.seg;
    const ax = e.pts[i]!, ay = e.pts[i + 1]!, bx = e.pts[i + 2]!, by = e.pts[i + 3]!;
    const f = len > 0 ? Math.min(1, Math.max(0, (d - c.segStart) / len)) : 0;
    c.z = e.zOnSeg(c.seg, f);
    let ux = len > 0 ? (bx - ax) / len : 1, uy = len > 0 ? (by - ay) / len : 0;
    if (c.dir < 0) {
      ux = -ux;
      uy = -uy;
    }
    let off = laneOffset(e, c.lane, this.tuning, this.leftHand);
    // Right of the travel direction (ux, uy) is (uy, −ux).
    let tx = ax + (bx - ax) * f + uy * off, ty = ay + (by - ay) * f - ux * off;
    c.layer = e.layerAt(e.length > 0 ? d / e.length : 0);
    if (c.layer === 0 && this.parked.length > 0) {
      off = this.swerve(c, tx, ty, ux, uy);
      tx += uy * off;
      ty -= ux * off;
    }
    const th = Math.atan2(uy, ux);
    if (k >= 1) {
      c.x = tx;
      c.y = ty;
      c.heading = th;
    } else {
      c.x += (tx - c.x) * k;
      c.y += (ty - c.y) * k;
      c.heading = wrap(c.heading + wrap(th - c.heading) * k);
    }
  }

  /** Sideways shift round parked cars near the lane point (tx, ty) heading (ux, uy). */
  private swerve(c: TrafficCar, tx: number, ty: number, ux: number, uy: number): number {
    const t = this.tuning.traffic;
    const o = this.obs;
    const reach = t.swerveAheadM + 4 * c.halfLength;
    let n = 0;
    for (const p of this.parked) {
      const dx = p.x - tx, dy = p.y - ty;
      if (dx * dx + dy * dy > reach * reach) continue;
      const phl = p.hl ?? c.halfLength, phw = p.hw ?? c.halfWidth;
      const da = p.heading - Math.atan2(uy, ux);
      // Ahead of the car itself (its pose lags the lane point), sideways from the lane point.
      o[4 * n] = (p.x - c.x) * ux + (p.y - c.y) * uy;
      o[4 * n + 1] = dx * uy - dy * ux;
      o[4 * n + 2] = phl * Math.abs(Math.sin(da)) + phw * Math.abs(Math.cos(da));
      o[4 * n + 3] = phl;
      n++;
    }
    return n === 0 ? 0 : swerveShift(o, n, c.halfLength, c.halfWidth, t);
  }

  /** Free distance to the nearest obstacle ahead: the player, a car going our way, a tram, a stop line. */
  private gapAhead(c: TrafficCar, player: Car): number {
    const t = this.tuning.traffic;
    const look = t.lookAheadM;
    const hc = Math.cos(c.heading), hs = Math.sin(c.heading);
    let gap = look;
    // The player, whatever its heading.
    if (this.solid && !this.playerAirborne && player.layer === c.layer) {
      const g = this.gapTo(c, hc, hs, player.x, player.y, player.halfLength, player.halfWidth, look);
      if (g < gap) gap = g;
    }
    // Tram cars in the same layer, whatever their heading (v3); even a chasing patrol waits.
    for (const o of this.trams) {
      if (o.layer !== c.layer) continue;
      const g = this.gapTo(c, hc, hs, o.x, o.y, o.halfLength, o.halfWidth, look);
      if (g < gap) gap = g;
    }
    // A chasing patrol ignores other cars and the lights (sirens, specs/police.md).
    if (c.pursuing) return gap;
    for (const o of this.cars) {
      if (o === c || o.layer !== c.layer) continue;
      // Only cars going roughly our way (±60°); crossing traffic is ignored (spec, step 5).
      if (Math.cos(o.heading) * hc + Math.sin(o.heading) * hs < 0.5) continue;
      const g = this.gapTo(c, hc, hs, o.x, o.y, o.halfLength, o.halfWidth, look);
      if (g < gap) gap = g;
    }
    // The stop line of a red (or amber, unless committed) light at the end of the edge.
    const a = c.dir > 0 ? this.signals.approachTo[c.edge.index]! : this.signals.approachFrom[c.edge.index]!;
    if (a >= 0) {
      const state = this.light(a);
      if (state !== LIGHT_GREEN) {
        const extra = c.dir > 0 ? this.signals.extraTo[c.edge.index]! : this.signals.extraFrom[c.edge.index]!;
        const toLine = c.edge.length - c.s + extra - this.signals.approaches[a]!.stopM - c.halfLength;
        // Past the line (in the box): go on. Amber close to the line: go on.
        const committed = toLine < -c.halfLength || (state === LIGHT_AMBER && toLine < t.amberCommitM);
        if (!committed && toLine + t.minGapM < gap) gap = Math.max(0, toLine + t.minGapM);
      }
    }
    return gap;
  }

  private gapTo(c: TrafficCar, hc: number, hs: number, ox: number, oy: number, ohl: number, ohw: number, look: number): number {
    const dx = ox - c.x, dy = oy - c.y;
    const lx = dx * hc + dy * hs;
    if (lx <= 0 || lx > look + c.halfLength + ohl) return Infinity;
    const ly = -dx * hs + dy * hc;
    if (Math.abs(ly) > (c.halfWidth + ohw) * this.tuning.traffic.corridor) return Infinity;
    return Math.max(0, lx - c.halfLength - ohl);
  }
}

function segLen(e: RoadEdge, seg: number): number {
  const i = 2 * seg;
  const dx = e.pts[i + 2]! - e.pts[i]!, dy = e.pts[i + 3]! - e.pts[i + 1]!;
  return Math.sqrt(dx * dx + dy * dy);
}

/** Separating-axis test of two oriented boxes (centre, unit heading c/s, half extents), with margin. */
export function obbOverlap(
  ax: number, ay: number, ac: number, as: number, ahl: number, ahw: number,
  bx: number, by: number, bc: number, bs: number, bhl: number, bhw: number, margin: number,
): boolean {
  const dx = bx - ax, dy = by - ay;
  // Axes: a's length (ac, as), a's width (−as, ac), b's length, b's width.
  return (
    sepAxis(ac, as, dx, dy, ac, as, ahl, ahw, bc, bs, bhl, bhw, margin) &&
    sepAxis(-as, ac, dx, dy, ac, as, ahl, ahw, bc, bs, bhl, bhw, margin) &&
    sepAxis(bc, bs, dx, dy, ac, as, ahl, ahw, bc, bs, bhl, bhw, margin) &&
    sepAxis(-bs, bc, dx, dy, ac, as, ahl, ahw, bc, bs, bhl, bhw, margin)
  );
}

/** True when the projections on axis (nx, ny) overlap. */
function sepAxis(
  nx: number, ny: number, dx: number, dy: number, ac: number, as: number, ahl: number, ahw: number,
  bc: number, bs: number, bhl: number, bhw: number, margin: number,
): boolean {
  const ra = ahl * Math.abs(ac * nx + as * ny) + ahw * Math.abs(-as * nx + ac * ny);
  const rb = bhl * Math.abs(bc * nx + bs * ny) + bhw * Math.abs(-bs * nx + bc * ny);
  return Math.abs(dx * nx + dy * ny) <= ra + rb + margin;
}
