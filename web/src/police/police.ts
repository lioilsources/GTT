import type { Tuning } from '../gen/tuning';
import type { DriveWorld } from '../drive/driveWorld';
import type { TrafficCar } from '../traffic/traffic';
import type { BuildingData, ChunkData } from '../world/chunk';
import { chooseToward } from '../traffic/roadRules';
import { chunkKey, type RoadEdge, type RoadGraph } from '../world/model';
import { policeConfig, PoliceRules, type OffenceKind, type PoliceAction, type PoliceState } from './rules';
import { inView, onSidewalk, sightBlocked } from './sense';

/** Hooks for later features (specs/police.md "Události"). */
export interface PoliceEventMap {
  /** reason: an offence kind, "escape" or "busted". */
  wantedChanged: { level: number; prev: number; reason: string };
  offence: { kind: OffenceKind };
  fined: { amount: number };
  /** A roadblock was put up at (x, y) (specs/roadblock.md). */
  roadblock: { x: number; y: number };
}

/** Where a roadblock stands: a point on a ground edge and the edge's heading there. */
export interface RoadblockSpot {
  edge: RoadEdge;
  x: number;
  y: number;
  /** Heading of the edge from → to at the point (the patrols stand at heading + π/2). */
  heading: number;
}

/** A standing roadblock: its two patrols, its spot and its age in seconds. */
export interface Roadblock {
  readonly cars: [TrafficCar, TrafficCar];
  readonly x: number;
  readonly y: number;
  age: number;
}

/**
 * Point `d` metres from the `from` end of edge e, with the unit direction from → to of its segment.
 */
export function pointAlong(e: RoadEdge, d: number): { x: number; y: number; ux: number; uy: number } {
  let left = Math.max(0, Math.min(d, e.length));
  const last = e.pointCount - 2;
  for (let seg = 0; seg <= last; seg++) {
    const i = 2 * seg;
    const ax = e.pts[i]!, ay = e.pts[i + 1]!, bx = e.pts[i + 2]!, by = e.pts[i + 3]!;
    const l = Math.hypot(bx - ax, by - ay);
    if (left <= l || seg === last) {
      const f = l > 0 ? Math.min(1, left / l) : 0;
      return { x: ax + (bx - ax) * f, y: ay + (by - ay) * f, ux: l > 0 ? (bx - ax) / l : 1, uy: l > 0 ? (by - ay) / l : 0 };
    }
    left -= l;
  }
  return { x: e.pts[0]!, y: e.pts[1]!, ux: 1, uy: 0 };
}

/**
 * The roadblock spot ahead of the player (specs/roadblock.md "Kde"): from the player's
 * projection on the nearest kept edge in its layer (graph.near within searchM), along the driving
 * direction (sign of dot(edge, heading)), choosing each next edge with chooseToward towards
 * player + probeM · heading, until aheadM is walked. Null = give up: no edge, a border node, a
 * dead end (chooseToward turns back onto the same edge) or a final edge off the ground layer.
 */
export function roadblockSpot(
  graph: RoadGraph, x: number, y: number, heading: number, layer: number, searchM: number, aheadM: number, probeM: number,
): RoadblockSpot | null {
  let best: { edge: RoadEdge; t: number; dirX: number; dirY: number; dist: number } | null = null;
  for (const h of graph.near(x, y, searchM)) {
    if (!h.edge.kept || h.edge.layerAt(h.t) !== layer) continue;
    if (best === null || h.dist < best.dist) best = h;
  }
  if (best === null) return null;
  const hc = Math.cos(heading), hs = Math.sin(heading);
  const gx = x + probeM * hc, gy = y + probeM * hs;
  let e = best.edge;
  let dir = best.dirX * hc + best.dirY * hs >= 0 ? 1 : -1;
  // Distance from the from-end and what is left of the edge in the driving direction.
  let d0 = best.t * e.length;
  let left = aheadM;
  for (let guard = 0; guard <= graph.edges.length; guard++) {
    const rest = dir > 0 ? e.length - d0 : d0;
    if (rest >= left) {
      if (!e.isGround) return null;
      const p = pointAlong(e, dir > 0 ? d0 + left : d0 - left);
      return { edge: e, x: p.x, y: p.y, heading: Math.atan2(p.uy, p.ux) };
    }
    left -= rest;
    const node = dir > 0 ? e.to : e.from;
    const next = chooseToward(graph, node, e.index, gx, gy);
    if (next < 0 || next === e.index) return null;
    e = graph.edges[next]!;
    dir = e.from === node ? 1 : -1;
    d0 = dir > 0 ? 0 : e.length;
  }
  return null;
}
export type PoliceEvent = keyof PoliceEventMap;

/** Something that emits "stolen" (CarFleet.on('stolen')). */
export interface StolenSource {
  on(event: 'stolen', fn: (e: { car: string; x: number; y: number }) => void): () => void;
}

/**
 * Police of one session (specs/police.md): the P0 wanted rules driven at police.tick_hz, patrol
 * cars flagged among the traffic, line of sight, sidewalk and hit-and-run detection, pursuit and
 * capture. No UI; the HUD listens to the events.
 */
export class Police {
  readonly rules = new PoliceRules();
  state: PoliceState;
  /** True while some patrol sees the player (refreshed every tick). */
  seen = false;
  private readonly buildings = new Map<number, BuildingData[]>();
  private readonly listeners: { [K in PoliceEvent]: Array<(e: PoliceEventMap[K]) => void> } = { wantedChanged: [], offence: [], fined: [], roadblock: [] };
  private readonly uturnAt = new WeakMap<TrafficCar, number>();
  private readonly unsub: Array<() => void> = [];
  private acc = 0;
  private time = 0;
  private pickTimer = 0;
  private sidewalkT = 0;
  private sidewalkArmed = true;
  private crashX = 0;
  private crashY = 0;
  private block: Roadblock | null = null;
  /** Seconds left before the next roadblock may stand (0 at the start). */
  private blockCool = 0;
  /** Seconds since the last roadblock attempt (ready at the start). */
  private blockTry = Infinity;

  constructor(
    readonly drive: DriveWorld,
    readonly tuning: Tuning,
    cars: StolenSource | null,
  ) {
    this.state = this.rules.init(policeConfig(tuning.police), 0);
    if (!tuning.police.enabled) return;
    const tr = drive.traffic;
    if (tr) {
      this.unsub.push(tr.onHit(() => {
        this.crashX = drive.car.x;
        this.crashY = drive.car.y;
        this.offence('crash');
      }));
    }
    if (cars) this.unsub.push(cars.on('stolen', () => this.offence('theft')));
  }

  get wantedLevel(): number {
    return this.state.level;
  }

  get enabled(): boolean {
    return this.tuning.police.enabled;
  }

  on<K extends PoliceEvent>(event: K, fn: (e: PoliceEventMap[K]) => void): () => void {
    const list = this.listeners[event] as Array<(e: PoliceEventMap[K]) => void>;
    list.push(fn);
    return () => list.splice(list.indexOf(fn) >>> 0, 1);
  }

  onWantedChanged(fn: (e: PoliceEventMap['wantedChanged']) => void): () => void {
    return this.on('wantedChanged', fn);
  }

  onFined(fn: (e: PoliceEventMap['fined']) => void): () => void {
    return this.on('fined', fn);
  }

  private emit<K extends PoliceEvent>(event: K, e: PoliceEventMap[K]): void {
    for (const fn of this.listeners[event] as Array<(e: PoliceEventMap[K]) => void>) fn(e);
  }

  destroy(): void {
    for (const u of this.unsub) u();
    this.unsub.length = 0;
  }

  // ---------- buildings for the line of sight

  addChunk(c: ChunkData): void {
    this.buildings.set(chunkKey(c.x, c.y), c.buildings);
  }

  removeChunk(c: ChunkData): void {
    this.buildings.delete(chunkKey(c.x, c.y));
  }

  private *buildingsAlong(ax: number, ay: number, bx: number, by: number): Generator<BuildingData> {
    const cm = this.drive.city.chunkM;
    // One chunk of slack: a building belongs to one chunk but may reach into the next.
    const x0 = Math.floor(Math.min(ax, bx) / cm) - 1, x1 = Math.floor(Math.max(ax, bx) / cm) + 1;
    const y0 = Math.floor(Math.min(ay, by) / cm) - 1, y1 = Math.floor(Math.max(ay, by) / cm) + 1;
    for (let cx = x0; cx <= x1; cx++) {
      for (let cy = y0; cy <= y1; cy++) {
        const list = this.buildings.get(chunkKey(cx, cy));
        if (list) yield* list;
      }
    }
  }

  /** Patrol p sees the player (specs/police.md "Dohled"). */
  sees(p: TrafficCar): boolean {
    const c = this.drive.car;
    if (!inView(p.x, p.y, p.layer, c.x, c.y, c.layer, this.tuning.police.viewM)) return false;
    return !sightBlocked(p.x, p.y, c.x, c.y, this.buildingsAlong(p.x, p.y, c.x, c.y));
  }

  private anySees(): boolean {
    const tr = this.drive.traffic;
    if (!tr) return false;
    for (const p of tr.cars) if (p.police && this.sees(p)) return true;
    return false;
  }

  // ---------- rules

  private act(a: PoliceAction): void {
    const prev = this.state;
    const s = (this.state = this.rules.apply(prev, a));
    if (s.offences > prev.offences) this.emit('offence', { kind: s.last as OffenceKind });
    if (s.busted > prev.busted) this.emit('fined', { amount: s.fined - prev.fined });
    if (s.level !== prev.level) {
      const reason = s.busted > prev.busted ? 'busted' : s.level > prev.level ? s.last : 'escape';
      this.emit('wantedChanged', { level: s.level, prev: prev.level, reason });
    }
  }

  /** An offence happened now; a patrol has to see it to count. */
  offence(kind: OffenceKind): void {
    if (!this.enabled) return;
    this.act({ by: 'player', op: 'offence', kind, seen: this.anySees() });
  }

  /** Per frame with the (scaled) driving dt; runs whole ticks at police.tick_hz. */
  update(dt: number): void {
    if (!this.enabled || !this.drive.traffic) return;
    const step = 1 / this.tuning.police.tickHz;
    this.acc = Math.min(this.acc + dt, step * 10);
    while (this.acc >= step) {
      this.acc -= step;
      this.tick(step);
    }
  }

  private tick(step: number): void {
    const t = this.tuning.police, c = this.drive.car;
    this.time += step;
    this.roadblocks(step);
    this.patrols(step);
    this.seen = this.anySees();

    // Sidewalk: on the band for sidewalk_s in one go → one offence, re-armed after leaving it.
    // A hop over the sidewalk is not driving on it (specs/hop.md).
    const walk = c.layer === 0 && !c.airborne && c.speed >= t.sidewalkMinMps && onSidewalk(this.drive.city.graph.near(c.x, c.y, this.tuning.layers.searchM), this.tuning);
    if (walk) {
      this.sidewalkT += step;
      if (this.sidewalkArmed && this.sidewalkT >= t.sidewalkS) {
        this.sidewalkArmed = false;
        this.act({ by: 'player', op: 'offence', kind: 'sidewalk', seen: this.seen });
      }
    } else {
      this.sidewalkT = 0;
      this.sidewalkArmed = true;
    }

    const away = (c.x - this.crashX) ** 2 + (c.y - this.crashY) ** 2 > t.hitRunM * t.hitRunM;
    this.act({ by: 'player', op: 'tick', seen: this.seen, near: this.near(), away });
  }

  /** A patrol is within capture_m of the slow player (same layer), while wanted. */
  private near(): boolean {
    const t = this.tuning.police, c = this.drive.car;
    if (this.state.level === 0 || c.speed > t.captureMps) return false;
    for (const p of this.drive.traffic!.cars) {
      if (p.police && p.layer === c.layer && (p.x - c.x) ** 2 + (p.y - c.y) ** 2 <= t.captureM * t.captureM) return true;
    }
    return false;
  }

  // ---------- roadblock (specs/roadblock.md)

  /** The standing roadblock, or null. */
  get roadblock(): Readonly<Roadblock> | null {
    return this.block;
  }

  /** Removes the roadblock (both cars) and starts cooldown_s; respawn calls it too. */
  clearRoadblock(): void {
    const b = this.block;
    if (!b) return;
    this.block = null;
    this.blockCool = this.tuning.police.roadblock.cooldownS;
    const tr = this.drive.traffic;
    if (tr) for (const p of b.cars) tr.removeCar(p);
  }

  private roadblocks(step: number): void {
    const rb = this.tuning.police.roadblock, tr = this.drive.traffic!, c = this.drive.car;
    this.blockCool = Math.max(0, this.blockCool - step);
    this.blockTry += step;
    const b = this.block;
    if (b) {
      b.age += step;
      // A traffic reset (teleport, respawn) took the cars: the roadblock is gone.
      const gone = !tr.cars.includes(b.cars[0]) || !tr.cars.includes(b.cars[1]);
      const far = (c.x - b.x) ** 2 + (c.y - b.y) ** 2 > rb.clearM * rb.clearM;
      if (gone || far || this.state.level < rb.level || b.age > rb.ttlS) this.clearRoadblock();
      return;
    }
    if (this.state.level < rb.level || this.blockCool > 0 || this.blockTry < this.tuning.police.pickIntervalS) return;
    this.blockTry = 0;
    this.block = this.buildRoadblock();
    if (this.block) this.emit('roadblock', { x: this.block.x, y: this.block.y });
  }

  private buildRoadblock(): Roadblock | null {
    const rb = this.tuning.police.roadblock, tr = this.drive.traffic!, c = this.drive.car;
    const spot = roadblockSpot(this.drive.city.graph, c.x, c.y, c.heading, c.layer, this.tuning.layers.searchM, rb.aheadM, rb.probeM);
    if (!spot || this.drive.zones.inside(spot.x, spot.y)) return null;
    const e = spot.edge;
    const s = e.length * 0.5;
    const nx = -Math.sin(spot.heading), ny = Math.cos(spot.heading);
    const across = spot.heading + Math.PI / 2;
    const cars: TrafficCar[] = [];
    for (const side of [1, -1]) {
      const p = tr.addCar(e.index, 1, s, 0) ?? tr.addCar(e.index, -1, s, 0);
      if (!p) {
        for (const q of cars) tr.removeCar(q);
        return null;
      }
      p.police = true;
      p.blocking = true;
      tr.setPose(p, spot.x + nx * rb.lateralM * side, spot.y + ny * rb.lateralM * side, across);
      cars.push(p);
    }
    return { cars: [cars[0]!, cars[1]!], x: spot.x, y: spot.y, age: 0 };
  }

  // ---------- patrols

  private patrols(step: number): void {
    const t = this.tuning.police, tr = this.drive.traffic!, c = this.drive.car;
    const level = this.state.level;
    const want = t.patrols[Math.min(level, t.patrols.length - 1)] ?? 0;
    let n = 0;
    for (const p of tr.cars) {
      if (!p.police || p.blocking) continue;
      n++;
      const dx = c.x - p.x, dy = c.y - p.y;
      const d2 = dx * dx + dy * dy;
      p.pursuing = level > 0 && d2 <= t.pursuitM * t.pursuitM;
      if (!p.pursuing) continue;
      p.goalX = c.x;
      p.goalY = c.y;
      p.pursuitMps = t.pursuitMps[Math.min(level, t.pursuitMps.length - 1)] ?? 0;
      p.goalStopM = t.captureM / 2;
      // Goal behind and far enough: turn around on the edge, at most once per uturn_s.
      const behind = Math.cos(p.heading) * dx + Math.sin(p.heading) * dy < 0;
      if (behind && d2 > t.uturnM * t.uturnM && this.time - (this.uturnAt.get(p) ?? -Infinity) >= t.uturnS) {
        this.uturnAt.set(p, this.time);
        tr.turnAround(p);
      }
    }
    this.pickTimer += step;
    if (n >= want || this.pickTimer < t.pickIntervalS) return;
    this.pickTimer = 0;
    const min2 = t.pickMinM * t.pickMinM;
    for (const p of tr.cars) {
      if (p.police || (p.x - c.x) ** 2 + (p.y - c.y) ** 2 < min2) continue;
      p.police = true;
      return;
    }
  }
}
