import { Body, Box } from 'planck';

import type { CarSpec } from '../gen/schema';
import type { Tuning } from '../gen/tuning';
import { CAT_BUILDINGS, CAT_CAR, CAT_PARKED, CAT_TRAFFIC } from '../drive/car';
import type { DriveWorld } from '../drive/driveWorld';
import type { ChunkData } from '../world/chunk';
import { chunkKey } from '../world/model';
import { boardCandidate, generateParked, type ParkedCar } from './parked';
import { carsConfig, CarsRules, type CarOwner, type CarsAction, type CarsState } from './rules';

/** Hooks for later features: police reads `stolen`, dialogues play the owner's quip. */
export interface CarEventMap {
  stolen: { car: string; x: number; y: number };
  ownerQuip: { car: string; x: number; y: number };
  carChanged: { car: string };
  /** A car bought in the garage (M1-S11: the loop saves). */
  bought: { car: string; price: number };
}
export type CarEvent = keyof CarEventMap;

/** The garage's parking point (spot kind `garage`), metres. */
export interface GaragePoint {
  id: string;
  x: number;
  y: number;
  heading: number;
}

/**
 * Cars of one session (specs/cars.md): the P0 ownership state, parked cars as dynamic bodies,
 * boarding and the garage. No UI; the HUD asks `candidate()` / `atGarage()` and calls `board` / `select`.
 */
export class CarFleet {
  readonly rules = new CarsRules();
  state: CarsState;
  readonly parked: ParkedCar[] = [];
  /** Bumped when the parked set changes (the renderer rebuilds its mesh). */
  version = 0;
  private readonly bodies = new Map<ParkedCar, Body>();
  private readonly listeners: { [K in CarEvent]: Array<(e: CarEventMap[K]) => void> } = { stolen: [], ownerQuip: [], carChanged: [], bought: [] };

  constructor(
    readonly drive: DriveWorld,
    readonly specs: ReadonlyMap<string, CarSpec>,
    readonly tuning: Tuning,
    readonly garage: GaragePoint | null,
  ) {
    const prices: Record<string, number> = {};
    for (const [id, s] of specs) prices[id] = s.price;
    this.state = this.rules.init(carsConfig(tuning.cars, prices), 0);
    // Traffic drives round parked cars (specs/traffic.md step 8).
    if (drive.traffic) drive.traffic.parked = this.parked;
  }

  get spec(): CarSpec {
    return this.specs.get(this.state.driving)!;
  }

  on<K extends CarEvent>(event: K, fn: (e: CarEventMap[K]) => void): () => void {
    const list = this.listeners[event] as Array<(e: CarEventMap[K]) => void>;
    list.push(fn);
    return () => list.splice(list.indexOf(fn) >>> 0, 1);
  }

  private emit<K extends CarEvent>(event: K, e: CarEventMap[K]): void {
    for (const fn of this.listeners[event] as Array<(e: CarEventMap[K]) => void>) fn(e);
  }

  private apply(a: CarsAction): void {
    this.state = this.rules.apply(this.state, a);
  }

  // ---------- parked cars

  addChunk(c: ChunkData): void {
    const key = chunkKey(c.x, c.y);
    if (this.parked.some((p) => p.chunk === key)) return;
    const car = this.drive.car;
    const kept = this.parked.filter((p) => p.chunk === null);
    for (const p of generateParked(this.drive.city.graph, c.x, c.y, key, this.tuning, this.specs, kept, { x: car.x, y: car.y })) {
      this.addParked(p);
    }
  }

  removeChunk(c: ChunkData): void {
    const key = chunkKey(c.x, c.y);
    for (const p of this.parked.filter((q) => q.chunk === key)) this.removeParked(p);
  }

  /** Forgets cars the player left behind once they are far away (cars.parked.forget_m). */
  update(): void {
    // Pushed cars: copy the pose of awake bodies back (specs/cars.md v2).
    for (const [p, b] of this.bodies) {
      if (!b.isAwake()) continue;
      const q = b.getPosition(), a = b.getAngle();
      if (Math.abs(q.x - p.x) + Math.abs(q.y - p.y) + Math.abs(a - p.heading) < 1e-3) continue;
      p.x = q.x;
      p.y = q.y;
      p.heading = a;
      this.version++;
    }
    const c = this.drive.car, f = this.tuning.cars.parked.forgetM;
    for (const p of [...this.parked]) {
      if (p.chunk === null && (p.x - c.x) ** 2 + (p.y - c.y) ** 2 > f * f) this.removeParked(p);
    }
  }

  private addParked(p: ParkedCar): void {
    const spec = this.specs.get(p.carId);
    if (!spec) return;
    const s = this.tuning.carScale, d = this.tuning.drive, t = this.tuning.cars.parked;
    p.hl = (spec.length_m * s) / 2;
    p.hw = (spec.width_m * s) / 2;
    const body = this.drive.world.createBody({
      type: 'dynamic',
      position: { x: p.x, y: p.y },
      angle: p.heading,
      linearDamping: t.linearDamping,
      angularDamping: t.angularDamping,
    });
    body.createFixture({
      shape: new Box(p.hl, p.hw),
      density: (spec.mass * t.massFactor) / (4 * p.hl * p.hw),
      friction: d.carFriction,
      restitution: d.carRestitution,
      filterCategoryBits: CAT_PARKED,
      filterMaskBits: CAT_CAR | CAT_BUILDINGS | CAT_PARKED | CAT_TRAFFIC,
    });
    this.bodies.set(p, body);
    this.parked.push(p);
    this.version++;
  }

  private removeParked(p: ParkedCar): void {
    const i = this.parked.indexOf(p);
    if (i < 0) return;
    this.parked.splice(i, 1);
    const b = this.bodies.get(p);
    if (b) this.drive.world.destroyBody(b);
    this.bodies.delete(p);
    this.version++;
  }

  // ---------- boarding

  private stopped(limit: number): boolean {
    const c = this.drive.car;
    return c.layer === 0 && c.speed <= limit;
  }

  /** The parked car the player can switch to now, or null. */
  candidate(): ParkedCar | null {
    const t = this.tuning.cars;
    if (!this.stopped(t.boardSpeedMps)) return null;
    const c = this.drive.car;
    return boardCandidate(this.parked, c.x, c.y, t.boardDistanceM);
  }

  private seen: ParkedCar | null = null;
  private boardAge = Infinity;
  private garageAge = Infinity;

  /**
   * The context button with hysteresis (cars.action_hold_s, specs/cars.md): call once per HUD
   * tick with the time since the last call. Board wins over the garage.
   */
  action(dt: number): { kind: 'board'; car: ParkedCar } | { kind: 'garage' } | null {
    const t = this.tuning.cars, c = this.drive.car;
    const now = this.candidate();
    if (now) {
      this.seen = now;
      this.boardAge = 0;
    } else {
      this.boardAge += dt;
    }
    this.garageAge = this.atGarage() ? 0 : this.garageAge + dt;
    const s = this.seen;
    if (s && this.boardAge <= t.actionHoldS && c.layer === 0 && this.parked.includes(s) && (s.x - c.x) ** 2 + (s.y - c.y) ** 2 <= t.boardDistanceM ** 2) {
      return { kind: 'board', car: s };
    }
    const g = this.garage;
    if (g && this.garageAge <= t.actionHoldS && c.layer === 0 && (c.x - g.x) ** 2 + (c.y - g.y) ** 2 <= t.garageRadiusM ** 2) {
      return { kind: 'garage' };
    }
    return null;
  }

  /** Who owns the car the player drives now, if it were left parked. */
  private currentOwner(): CarOwner {
    return this.state.owned.includes(this.state.driving) && !this.state.stolen ? 'player' : 'npc';
  }

  /** "Přesednout": the current car stays parked, the player drives the parked one. */
  board(p: ParkedCar): void {
    const c = this.drive.car;
    const left: ParkedCar = { carId: this.state.driving, owner: this.currentOwner(), x: c.x, y: c.y, heading: c.heading, chunk: null };
    this.apply({ by: 'player', op: 'board', car: p.carId, owner: p.owner });
    this.removeParked(p);
    this.drive.replaceCar(this.spec, p.x, p.y, p.heading);
    this.addParked(left);
    if (p.owner === 'npc') {
      this.emit('stolen', { car: p.carId, x: p.x, y: p.y });
      this.emit('ownerQuip', { car: p.carId, x: p.x, y: p.y });
    }
    this.emit('carChanged', { car: p.carId });
  }

  // ---------- garage

  atGarage(): boolean {
    const g = this.garage;
    if (!g || !this.stopped(this.tuning.cars.garageSpeedMps)) return false;
    const c = this.drive.car, r = this.tuning.cars.garageRadiusM;
    return (c.x - g.x) ** 2 + (c.y - g.y) ** 2 <= r * r;
  }

  /** Owned cars in the garage list, in the order they were acquired. */
  get owned(): readonly string[] {
    return this.state.owned;
  }

  /** True when the garage would let the player drive out with [car]. */
  canSelect(car: string): boolean {
    return this.rules.legalActions(this.state).some((a) => a.op === 'select' && a.car === car);
  }

  /** Cars for sale (M1-S11 shows them once there is cash). */
  buyable(): string[] {
    return this.rules.buyable(this.state);
  }

  buy(car: string): void {
    const before = this.state.cash;
    this.apply({ by: 'player', op: 'buy', car });
    this.emit('bought', { car, price: before - this.state.cash });
  }

  /** Cash lives in the cars state (specs/economy.md); the economy writes it back here. */
  setCash(cash: number): void {
    this.state = { ...this.state, cash: Math.max(0, Math.floor(cash)) };
  }

  /** Loads a saved ownership state (specs/save.md); swaps the driven body when the car differs. */
  restore(s: { cash: number; owned: readonly string[]; driving: string }): void {
    const prices: Record<string, number> = {};
    for (const [id, spec] of this.specs) prices[id] = spec.price;
    const owned = s.owned.filter((c) => this.specs.has(c));
    if (owned.length === 0) return;
    const driving = owned.includes(s.driving) ? s.driving : owned[0]!;
    this.state = this.rules.init({ prices, cash: Math.max(0, s.cash), owned, driving }, 0);
    if (this.drive.spec.id !== driving) {
      const c = this.drive.car;
      this.drive.replaceCar(this.spec, c.x, c.y, c.heading);
      this.emit('carChanged', { car: driving });
    }
  }

  /** Drive out of the garage with an owned car; the current one stays inside (or is towed away). */
  select(car: string): void {
    const g = this.garage;
    if (!g) return;
    this.apply({ by: 'player', op: 'select', car });
    for (const p of this.parked.filter((q) => q.chunk === null && q.owner === 'player' && q.carId === car)) this.removeParked(p);
    this.drive.replaceCar(this.spec, g.x, g.y, g.heading);
    this.emit('carChanged', { car });
  }
}
