// Taxi shift in the world (specs/minigames/taxi.md "Svět"): passengers, pickup, dropoff and the shift
// clock over the pure rules. No DOM, no Babylon: the client feeds the car pose every frame.
import type { RouteGraph } from '../../drive/gps';
import type { TuningMinigamesTaxi } from '../../gen/tuning';
import { feedDistDm, navGoal, navStart, type NavTarget } from '../../phone/nav';
import type { EdgeHit, RoadGraph } from '../../world/model';
import { taxiConfig, TaxiRules, type TaxiAction, type TaxiResult, type TaxiRide, type TaxiState } from './rules';

/** A destination: NavTarget of a hero landmark (parking point on its nearest kept road, dm). */
export type TaxiDest = NavTarget;

/** Landmark as the pack stores it (dm). */
export interface TaxiLandmark {
  id: string;
  name: string;
  x: number;
  y: number;
  hero: boolean;
}

/** Hero landmarks with a kept road within dest_search_m, in pack order. */
export function taxiDests(g: RoadGraph, landmarks: readonly TaxiLandmark[], searchM: number): TaxiDest[] {
  const out: TaxiDest[] = [];
  for (const l of landmarks) {
    if (!l.hero) continue;
    const h = g.nearest(l.x / 10, l.y / 10, searchM, (e) => e.kept && e.isGround);
    if (!h) continue;
    out.push({ id: l.id, name: l.name, edge: h.edge.index, parkX: Math.round(h.x * 10), parkY: Math.round(h.y * 10) });
  }
  return out;
}

export interface TaxiPose {
  x: number;
  y: number;
  heading: number;
  speed: number;
  layer: number;
}

/** A waiting passenger: curb point (m) and the road point the navigation leads to. */
export interface TaxiPassenger {
  x: number;
  y: number;
  /** Half the road width there: pickup within pickup_radius_m + this. */
  halfWidth: number;
  target: NavTarget;
}

export type TaxiEvent =
  | { kind: 'spawn'; passenger: TaxiPassenger }
  | { kind: 'pickup'; dest: TaxiDest; line: number; distDm: number }
  | { kind: 'dropoff'; ride: TaxiRide }
  | { kind: 'over'; result: TaxiResult };

/** What the shift needs from the city: the road graph, the GPS graph and edge lengths. */
export interface TaxiWorld {
  graph: RoadGraph;
  route: RouteGraph;
  lensDm: Int32Array;
  /** feed.straight_pct: fallback distance without a road route. */
  straightPct: number;
  /** nav.search_m: start edge search radius. */
  searchM: number;
}

/** One 4-minute shift. `update` once per frame with the world dt (scaled like driving). */
export class TaxiShift {
  readonly rules = new TaxiRules();
  state: TaxiState;
  /** Shift time, seconds. */
  clock = 0;
  passenger: TaxiPassenger | null = null;
  /** The destination of the passenger aboard. */
  dest: TaxiDest | null = null;
  /** Route length (dm) from the pickup point, sent with the dropoff. */
  distDm = 0;
  /** Every action applied, in order (debug, tests). */
  readonly log: TaxiAction[] = [];
  private readonly byId: Map<string, TaxiDest>;

  constructor(
    readonly world: TaxiWorld,
    readonly t: TuningMinigamesTaxi,
    readonly dests: readonly TaxiDest[],
    seed: number,
  ) {
    this.byId = new Map(dests.map((d) => [d.id, d]));
    this.state = this.rules.init(taxiConfig(t, dests.map((d) => d.id)), seed);
  }

  get over(): boolean {
    return this.state.phase === 'over';
  }
  get left(): number {
    return Math.max(0, this.t.shiftS - this.clock);
  }
  get ms(): number {
    return Math.floor(this.clock * 1000);
  }
  /** Where the navigation should lead now (the passenger or the destination). */
  get target(): NavTarget | null {
    return this.state.phase === 'ride' ? this.dest : this.passenger?.target ?? null;
  }

  private act(a: TaxiAction): void {
    this.state = this.rules.apply(this.state, a);
    this.log.push(a);
  }

  /** Traffic onHit while a passenger is aboard reduces the tip. */
  hit(): void {
    if (this.state.phase === 'ride') this.act({ by: 'player', op: 'hit' });
  }

  /** Ends the shift now (timer or the player boarded another car); returns the result. */
  end(): TaxiResult {
    if (!this.over) this.act({ by: 'timeout' });
    return this.rules.result(this.state)!;
  }

  update(dt: number, car: TaxiPose, hit: EdgeHit | null): TaxiEvent[] {
    const ev: TaxiEvent[] = [];
    if (this.over) return ev;
    this.clock += dt;
    if (this.clock >= this.t.shiftS) {
      ev.push({ kind: 'over', result: this.end() });
      return ev;
    }
    const stopped = car.speed <= this.t.stopSpeedMps && car.layer === 0;
    if (this.state.phase === 'wait') {
      if (!this.passenger && this.dests.length > 0) {
        this.passenger = spawnPassenger(this.world.graph, car, this.t);
        if (this.passenger) ev.push({ kind: 'spawn', passenger: this.passenger });
      }
      const p = this.passenger;
      if (p && stopped && Math.hypot(p.x - car.x, p.y - car.y) <= this.t.pickupRadiusM + p.halfWidth) {
        const allow = this.dests
          .filter((d) => {
            const s = Math.hypot(d.parkX / 10 - car.x, d.parkY / 10 - car.y);
            return s >= this.t.destMinM && s <= this.t.destMaxM;
          })
          .map((d) => d.id);
        this.act({ by: 'player', op: 'pickup', atMs: this.ms, allow });
        this.passenger = null;
        this.dest = this.byId.get(this.state.dest)!;
        const w = this.world;
        const start = navStart(w.graph, hit, car.x, car.y, car.heading, w.searchM);
        this.distDm = feedDistDm(w.route, w.lensDm, start, navGoal(w.graph, this.dest), car.x, car.y, this.dest, w.straightPct);
        ev.push({ kind: 'pickup', dest: this.dest, line: this.state.line, distDm: this.distDm });
      }
    } else if (this.state.phase === 'ride' && this.dest && stopped) {
      const d = this.dest;
      if (Math.hypot(d.parkX / 10 - car.x, d.parkY / 10 - car.y) <= this.t.dropRadiusM) {
        this.act({ by: 'player', op: 'dropoff', atMs: Math.max(this.ms, this.state.pickMs), distDm: this.distDm });
        this.dest = null;
        ev.push({ kind: 'dropoff', ride: this.state.last });
      }
    }
    return ev;
  }
}

/**
 * The next passenger: from the car's heading in 45° steps (0, +45, −45, +90 …), the nearest kept
 * ground edge to the point (pickup_min_m + pickup_max_m) / 2 away that lies pickup_min_m … pickup_max_m
 * from the car; the passenger stands at the curb on the right of the edge direction.
 */
export function spawnPassenger(g: RoadGraph, car: TaxiPose, t: TuningMinigamesTaxi): TaxiPassenger | null {
  const mid = (t.pickupMinM + t.pickupMaxM) / 2, search = (t.pickupMaxM - t.pickupMinM) / 2;
  for (const k of [0, 1, -1, 2, -2, 3, -3, 4]) {
    const a = car.heading + (k * Math.PI) / 4;
    const h = g.nearest(car.x + Math.cos(a) * mid, car.y + Math.sin(a) * mid, search, (e) => e.kept && e.isGround);
    if (!h) continue;
    const d = Math.hypot(h.x - car.x, h.y - car.y);
    if (d < t.pickupMinM || d > t.pickupMaxM) continue;
    const half = h.edge.width / 2;
    // Right-hand normal of the segment direction.
    const nx = h.dirY, ny = -h.dirX;
    return {
      x: h.x + nx * (half + t.curbM),
      y: h.y + ny * (half + t.curbM),
      halfWidth: half,
      target: { id: 'taxi:passenger', name: '', edge: h.edge.index, parkX: Math.round(h.x * 10), parkY: Math.round(h.y * 10) },
    };
  }
  return null;
}
