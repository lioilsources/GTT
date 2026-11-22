import type { TuningTravel } from '../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../minigames/rules';
import type { Prng } from '../rules/prng';

/** specs/travel.md, version 1: metro and taxi fares, stations unlocked by visiting (P0, module `travel`). */
export interface TravelConfig {
  /** Station spot ids of the city in spots.pb order. */
  stations: string[];
  fareBase: number;
  farePerKm: number;
  taxiBase: number;
  taxiPerKm: number;
}

export interface TravelLast {
  op: '' | 'metro' | 'taxi';
  amount: number;
}

export interface TravelState {
  /** Unlocked stations in unlock order. */
  unlocked: string[];
  /** Fares paid this session. */
  paid: number;
  last: TravelLast;
}

export type TravelAction =
  | { by: 'player'; op: 'load'; unlocked: string[] }
  | { by: 'player'; op: 'unlock'; station: string }
  | { by: 'player'; op: 'metro'; from: string; to: string; distDm: number; cash: number }
  | { by: 'player'; op: 'taxi'; distDm: number; cash: number };

/** Config from tuning and the station ids of the city (spots.pb order). */
export function travelConfig(t: TuningTravel, stations: readonly string[]): TravelConfig {
  return { stations: [...stations], fareBase: t.fareBase, farePerKm: t.farePerKm, taxiBase: t.taxiBase, taxiPerKm: t.taxiPerKm };
}

/** Metro fare: fareBase + distDm × farePerKm ÷ 10000 (integer division). */
export function metroFare(c: Pick<TravelConfig, 'fareBase' | 'farePerKm'>, distDm: number): number {
  return c.fareBase + Math.floor((distDm * c.farePerKm) / 10000);
}

/** Taxi fare: taxiBase + distDm × taxiPerKm ÷ 10000 (integer division). */
export function taxiFare(c: Pick<TravelConfig, 'taxiBase' | 'taxiPerKm'>, distDm: number): number {
  return c.taxiBase + Math.floor((distDm * c.taxiPerKm) / 10000);
}

/** Straight distance of two points (metres) in whole dm: floor(sqrt(dx² + dy²)) of rounded dm (specs/travel.md). */
export function travelDistDm(ax: number, ay: number, bx: number, by: number): number {
  const dm = (v: number): number => Math.floor(v * 10 + 0.5);
  const dx = dm(bx) - dm(ax), dy = dm(by) - dm(ay);
  return Math.floor(Math.sqrt(dx * dx + dy * dy));
}

const isInt = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v);
const noLast = (): TravelLast => ({ op: '', amount: 0 });

export class TravelRules implements Rules<TravelState, TravelAction, RulesResult, TravelConfig> {
  readonly id = 'travel';
  readonly specVersion = 1;
  private cfg: TravelConfig | null = null;

  get config(): TravelConfig {
    if (!this.cfg) throw new Error('travel: init first');
    return this.cfg;
  }

  init(config: TravelConfig, _seed = 0): TravelState {
    this.cfg = config;
    return { unlocked: [], paid: 0, last: noLast() };
  }

  legalActions(s: TravelState): TravelAction[] {
    const out: TravelAction[] = [{ by: 'player', op: 'load', unlocked: [] }];
    for (const st of this.config.stations) if (!s.unlocked.includes(st)) out.push({ by: 'player', op: 'unlock', station: st });
    return out;
  }

  apply(state: TravelState, a: TravelAction): TravelState {
    if (a.by !== 'player') throw new IllegalAction(this.id, a);
    const c = this.config;
    const s: TravelState = { unlocked: [...state.unlocked], paid: state.paid, last: noLast() };
    switch (a.op) {
      case 'load': {
        if (!Array.isArray(a.unlocked) || !a.unlocked.every((x) => typeof x === 'string')) throw new IllegalAction(this.id, a);
        const known = new Set(c.stations);
        s.unlocked = [...new Set(a.unlocked.filter((x) => known.has(x)))];
        break;
      }
      case 'unlock': {
        if (typeof a.station !== 'string' || !c.stations.includes(a.station)) throw new IllegalAction(this.id, a);
        if (!s.unlocked.includes(a.station)) s.unlocked.push(a.station);
        break;
      }
      case 'metro': {
        if (typeof a.from !== 'string' || typeof a.to !== 'string' || !isInt(a.distDm) || !isInt(a.cash) ||
          !s.unlocked.includes(a.from) || !s.unlocked.includes(a.to) || a.from === a.to || a.distDm < 0 || a.cash < 0) {
          throw new IllegalAction(this.id, a);
        }
        const fare = metroFare(c, a.distDm);
        if (a.cash < fare) throw new IllegalAction(this.id, a);
        s.paid += fare;
        s.last = { op: 'metro', amount: fare };
        break;
      }
      case 'taxi': {
        if (!isInt(a.distDm) || !isInt(a.cash) || a.distDm < 0 || a.cash < 0) throw new IllegalAction(this.id, a);
        const fare = taxiFare(c, a.distDm);
        if (a.cash < fare) throw new IllegalAction(this.id, a);
        s.paid += fare;
        s.last = { op: 'taxi', amount: fare };
        break;
      }
      default:
        throw new IllegalAction(this.id, a);
    }
    return s;
  }

  aiAction(_s: TravelState, _level: number, _ai: Prng): TravelAction {
    throw new Error('travel: no opponent');
  }

  result(_s: TravelState): RulesResult | null {
    return null;
  }
}
