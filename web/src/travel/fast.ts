// Fast travel in the world (specs/travel.md P1): stations, unlocking by passing, metro and taxi
// choices, the move itself. No DOM, no Babylon: the client feeds the car pose.
import type { MinigameMeta } from '../gen/schema';
import type { Tuning, TuningLoop } from '../gen/tuning';
import type { TaxiLandmark } from '../minigames/taxi/shift';
import type { RoadGraph } from '../world/model';
import { metroFare, taxiFare, travelConfig, travelDistDm, TravelRules, type TravelConfig, type TravelState } from './rules';

/** A place the player can be moved to: parking point in metres and its heading. */
export interface TravelPoint {
  id: string;
  name: string;
  x: number;
  y: number;
  heading: number;
}

/** A taxi destination: a minigame spot or a hero landmark. */
export interface TaxiTarget extends TravelPoint {
  kind: 'spot' | 'landmark';
}

interface SpotLike {
  id: string;
  kind: string;
  name: string;
  parkX: number;
  parkY: number;
  parkHeading: number;
  minigame: string;
}

/** Stations = spots `kind: subway` in spots.pb order (parking point in metres). */
export function stationsOf(spots: readonly SpotLike[]): TravelPoint[] {
  return spots.filter((s) => s.kind === 'subway').map((s) => ({ id: s.id, name: s.name, x: s.parkX / 10, y: s.parkY / 10, heading: s.parkHeading }));
}

/**
 * Taxi destinations: spots with a catalog minigame (spots.pb order), then hero landmarks with a kept
 * ground road within `searchM` (landmarks.pb order; the stop point is the projection on that road,
 * heading along the edge, against it on a reverse one-way).
 */
export function taxiTargets(
  spots: readonly SpotLike[],
  catalog: Readonly<Record<string, MinigameMeta | undefined>>,
  graph: RoadGraph,
  landmarks: readonly TaxiLandmark[],
  searchM: number,
): TaxiTarget[] {
  const out: TaxiTarget[] = spots
    .filter((s) => s.minigame !== '' && catalog[s.minigame] !== undefined)
    .map((s) => ({ kind: 'spot', id: s.id, name: s.name, x: s.parkX / 10, y: s.parkY / 10, heading: s.parkHeading }));
  for (const l of landmarks) {
    if (!l.hero) continue;
    const hit = graph.nearest(l.x / 10, l.y / 10, searchM, (e) => e.kept && e.isGround);
    if (!hit) continue;
    const back = hit.edge.oneway === -1;
    out.push({ kind: 'landmark', id: l.id, name: l.name, x: hit.x, y: hit.y, heading: Math.atan2(back ? -hit.dirY : hit.dirY, back ? -hit.dirX : hit.dirX) });
  }
  return out;
}

/** A choice in the metro card or the taxi app. */
export interface TravelChoice<P extends TravelPoint = TravelPoint> {
  point: P;
  distDm: number;
  fare: number;
  /** False = greyed: the cash does not cover the fare. */
  affordable: boolean;
}

/** Taxi list: targets with fare from the car, sorted by distance (ties keep the list order). */
export function taxiChoices<P extends TravelPoint>(targets: readonly P[], carX: number, carY: number, cash: number, c: TravelConfig): TravelChoice<P>[] {
  return targets
    .map((p, i) => {
      const distDm = travelDistDm(carX, carY, p.x, p.y);
      const fare = taxiFare(c, distDm);
      return { i, choice: { point: p, distDm, fare, affordable: cash >= fare } };
    })
    .sort((a, b) => a.choice.distDm - b.choice.distDm || a.i - b.i)
    .map((x) => x.choice);
}

/** True when the car may use a station like "Hrát" at a spot (specs/loop.md): standing, layer 0, in reach. */
export function stationInReach(p: TravelPoint, x: number, y: number, speed: number, layer: number, t: TuningLoop): boolean {
  return speed <= t.stopSpeedMps && layer === 0 && (p.x - x) ** 2 + (p.y - y) ** 2 <= t.spotRadiusM ** 2;
}

/** Fast travel is not offered during a minigame, the Taxi shift or while wanted (spec "Kdy ne"). */
export function travelOffered(s: { busy: boolean; inWorldGame: boolean; wanted: number }): boolean {
  return !s.busy && !s.inWorldGame && s.wanted <= 0;
}

/** The travel module of one session: unlocked stations, fares, cash through the cars state. */
export class TravelWorld {
  readonly rules = new TravelRules();
  readonly config: TravelConfig;
  state: TravelState;
  private readonly byId: Map<string, TravelPoint>;

  constructor(readonly stations: readonly TravelPoint[], tuning: Tuning, private readonly cash: { get(): number; set(c: number): void }) {
    this.config = travelConfig(tuning.travel, stations.map((s) => s.id));
    this.state = this.rules.init(this.config, 0);
    this.byId = new Map(stations.map((s) => [s.id, s]));
  }

  /** Stations from the save (unknown ones drop silently). */
  load(unlocked: readonly string[]): void {
    this.state = this.rules.apply(this.state, { by: 'player', op: 'load', unlocked: [...unlocked] });
  }

  get unlocked(): readonly string[] {
    return this.state.unlocked;
  }

  isUnlocked(id: string): boolean {
    return this.state.unlocked.includes(id);
  }

  station(id: string): TravelPoint | undefined {
    return this.byId.get(id);
  }

  /**
   * Unlocks every locked station whose parking point is within `unlockM` of a car on layer 0;
   * returns the newly unlocked ones (toast, save).
   */
  pass(x: number, y: number, layer: number, unlockM: number): TravelPoint[] {
    if (layer !== 0) return [];
    const out: TravelPoint[] = [];
    for (const s of this.stations) {
      if (this.isUnlocked(s.id) || (s.x - x) ** 2 + (s.y - y) ** 2 > unlockM * unlockM) continue;
      this.state = this.rules.apply(this.state, { by: 'player', op: 'unlock', station: s.id });
      out.push(s);
    }
    return out;
  }

  /** The unlocked station within the "Hrát" reach of the car, or null. */
  stationAt(x: number, y: number, speed: number, layer: number, t: TuningLoop): TravelPoint | null {
    for (const id of this.state.unlocked) {
      const s = this.byId.get(id)!;
      if (stationInReach(s, x, y, speed, layer, t)) return s;
    }
    return null;
  }

  /** Metro card: the other unlocked stations in unlock order with the fare from `from`. */
  metroChoices(from: string): TravelChoice[] {
    const a = this.byId.get(from);
    if (!a) return [];
    const cash = this.cash.get();
    return this.state.unlocked
      .filter((id) => id !== from)
      .map((id) => {
        const p = this.byId.get(id)!;
        const distDm = travelDistDm(a.x, a.y, p.x, p.y);
        const fare = metroFare(this.config, distDm);
        return { point: p, distDm, fare, affordable: cash >= fare };
      });
  }

  /** True when some station is still locked (the card shows the travelLocked hint). */
  get anyLocked(): boolean {
    return this.state.unlocked.length < this.stations.length;
  }

  /** Metro ride: pays the fare from the cars-state cash; null when it is not legal (cash, locked). */
  metro(from: string, to: string): number | null {
    const a = this.byId.get(from), b = this.byId.get(to);
    if (!a || !b) return null;
    return this.pay({ by: 'player', op: 'metro', from, to, distDm: travelDistDm(a.x, a.y, b.x, b.y), cash: this.cash.get() });
  }

  /** Taxi ride over `distDm`: pays the fare; null when the cash does not cover it. */
  taxi(distDm: number): number | null {
    return this.pay({ by: 'player', op: 'taxi', distDm, cash: this.cash.get() });
  }

  private pay(a: Parameters<TravelRules['apply']>[1] & { cash: number }): number | null {
    try {
      this.state = this.rules.apply(this.state, a);
    } catch {
      return null;
    }
    const fare = this.state.last.amount;
    this.cash.set(a.cash - fare);
    return fare;
  }
}

/** What the move touches (DriveWorld, PedestrianWorld, police): a seam for tests. */
export interface MoveWorld {
  drive: { spawn(x: number, y: number, heading: number): void; traffic: { reset(): void } | null };
  peds: { clear(): void } | null;
  police: { clearRoadblock(): void } | null;
}

/**
 * The move (spec "Přesun"): a new body at rest on the target's parking point facing its heading
 * (the same car spec, layer from the ground), traffic with its patrols, the roadblock and
 * pedestrians reset like after a teleport.
 */
export function moveTo(w: MoveWorld, p: TravelPoint): void {
  w.police?.clearRoadblock();
  w.drive.spawn(p.x, p.y, p.heading);
  w.drive.traffic?.reset();
  w.peds?.clear();
}
