import type { Tuning } from '../gen/tuning';
import type { DriveWorld } from '../drive/driveWorld';
import type { TrafficCar } from '../traffic/traffic';
import type { BuildingData, ChunkData } from '../world/chunk';
import { chunkKey } from '../world/model';
import { policeConfig, PoliceRules, type OffenceKind, type PoliceAction, type PoliceState } from './rules';
import { inView, onSidewalk, sightBlocked } from './sense';

/** Hooks for later features (specs/police.md "Události"). */
export interface PoliceEventMap {
  /** reason: an offence kind, "escape" or "busted". */
  wantedChanged: { level: number; prev: number; reason: string };
  offence: { kind: OffenceKind };
  fined: { amount: number };
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
  private readonly listeners: { [K in PoliceEvent]: Array<(e: PoliceEventMap[K]) => void> } = { wantedChanged: [], offence: [], fined: [] };
  private readonly uturnAt = new WeakMap<TrafficCar, number>();
  private readonly unsub: Array<() => void> = [];
  private acc = 0;
  private time = 0;
  private pickTimer = 0;
  private sidewalkT = 0;
  private sidewalkArmed = true;
  private crashX = 0;
  private crashY = 0;

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
    this.patrols(step);
    this.seen = this.anySees();

    // Sidewalk: on the band for sidewalk_s in one go → one offence, re-armed after leaving it.
    const walk = c.layer === 0 && c.speed >= t.sidewalkMinMps && onSidewalk(this.drive.city.graph.near(c.x, c.y, this.tuning.layers.searchM), this.tuning);
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

  // ---------- patrols

  private patrols(step: number): void {
    const t = this.tuning.police, tr = this.drive.traffic!, c = this.drive.car;
    const level = this.state.level;
    const want = t.patrols[Math.min(level, t.patrols.length - 1)] ?? 0;
    let n = 0;
    for (const p of tr.cars) {
      if (!p.police) continue;
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
