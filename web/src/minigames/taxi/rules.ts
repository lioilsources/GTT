// Taxi shift bookkeeping (specs/minigames/taxi.md, version 1): pure P0 rules, no DOM, no Babylon.
import type { TuningMinigamesTaxi } from '../../gen/tuning';
import { Prng } from '../../rules/prng';
import { IllegalAction, withRng, type Rules } from '../rules';

export interface TaxiConfig {
  /** Destination ids in pack order (hero landmarks with a road nearby). */
  dests: string[];
  /** Number of passenger lines taxiLine1..N. */
  lines: number;
  fareBase: number;
  farePerKm: number;
  expectBaseS: number;
  expectDmPerS: number;
  bonusPerS: number;
  bonusMaxPct: number;
  latePerS: number;
  lateMaxPct: number;
  tipPct: number;
  hitTipPct: number;
  /** Shift fare for 3, 2, 1 stars. */
  starFares: number[];
}

export interface TaxiRide {
  dest: string;
  distDm: number;
  rideS: number;
  expectS: number;
  meter: number;
  time: number;
  tip: number;
  fare: number;
}

export type TaxiPhase = 'wait' | 'ride' | 'over';

export interface TaxiState {
  rng: number;
  phase: TaxiPhase;
  clockMs: number;
  fare: number;
  rides: number;
  dest: string;
  line: number;
  pickMs: number;
  hits: number;
  lastDest: string;
  last: TaxiRide;
}

export type TaxiAction =
  | { by: 'player'; op: 'pickup'; atMs: number; allow: string[] }
  | { by: 'player'; op: 'hit' }
  | { by: 'player'; op: 'dropoff'; atMs: number; distDm: number }
  | { by: 'timeout' };

export interface TaxiResult {
  winner: 'player' | 'ai' | 'draw';
  stars: number;
  score: number;
  rides: number;
}

const idiv = (a: number, b: number): number => Math.floor(a / b);
const isInt = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v);
const emptyRide = (): TaxiRide => ({ dest: '', distDm: 0, rideS: 0, expectS: 0, meter: 0, time: 0, tip: 0, fare: 0 });

/** Rules config from tuning (minigames.taxi) and the destination ids of the city. */
export function taxiConfig(t: TuningMinigamesTaxi, dests: readonly string[]): TaxiConfig {
  return {
    dests: [...dests],
    lines: t.lines,
    fareBase: t.fareBase,
    farePerKm: t.farePerKm,
    expectBaseS: t.expectBaseS,
    expectDmPerS: t.expectDmPerS,
    bonusPerS: t.bonusPerS,
    bonusMaxPct: t.bonusMaxPct,
    latePerS: t.latePerS,
    lateMaxPct: t.lateMaxPct,
    tipPct: t.tipPct,
    hitTipPct: t.hitTipPct,
    starFares: [...t.starFares],
  };
}

/** Fare of one ride (specs/minigames/taxi.md "apply – dropoff"). */
export function taxiFare(c: TaxiConfig, distDm: number, rideMs: number, hits: number): Omit<TaxiRide, 'dest'> {
  const rideS = idiv(rideMs, 1000);
  const expectS = c.expectBaseS + idiv(distDm, c.expectDmPerS);
  const meter = c.fareBase + idiv(distDm * c.farePerKm, 10000);
  const diff = expectS - rideS;
  const time = diff >= 0
    ? Math.min(diff * c.bonusPerS, idiv(meter * c.bonusMaxPct, 100))
    : -Math.min(-diff * c.latePerS, idiv(meter * c.lateMaxPct, 100));
  const tip = idiv(meter * Math.max(0, c.tipPct - hits * c.hitTipPct), 100);
  return { distDm, rideS, expectS, meter, time, tip, fare: meter + time + tip };
}

/** Stars for a shift fare: starFares is [3★, 2★, 1★]. */
export function taxiStars(c: TaxiConfig, fare: number): number {
  for (let i = 0; i < 3; i++) if (fare >= (c.starFares[i] ?? Infinity)) return 3 - i;
  return 0;
}

export class TaxiRules implements Rules<TaxiState, TaxiAction, TaxiResult, TaxiConfig> {
  readonly id = 'taxi';
  readonly specVersion = 1;
  private cfg: TaxiConfig | null = null;

  get config(): TaxiConfig {
    if (!this.cfg) throw new Error('taxi: init first');
    return this.cfg;
  }

  init(config: TaxiConfig, seed: number): TaxiState {
    this.cfg = config;
    return {
      rng: new Prng(seed).state, phase: 'wait', clockMs: 0, fare: 0, rides: 0, dest: '', line: -1, pickMs: 0, hits: 0,
      lastDest: '', last: emptyRide(),
    };
  }

  legalActions(s: TaxiState): TaxiAction[] {
    if (s.phase === 'wait') return [{ by: 'player', op: 'pickup', atMs: s.clockMs, allow: [] }, { by: 'timeout' }];
    if (s.phase === 'ride') return [{ by: 'player', op: 'hit' }, { by: 'timeout' }];
    return [];
  }

  apply(s: TaxiState, a: TaxiAction): TaxiState {
    const c = this.config;
    if (s.phase === 'over') throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s, phase: 'over' };
    if (a.by !== 'player') throw new IllegalAction(this.id, a);
    switch (a.op) {
      case 'pickup': {
        if (s.phase !== 'wait' || !isInt(a.atMs) || a.atMs < s.clockMs || !Array.isArray(a.allow) ||
          a.allow.some((d) => typeof d !== 'string' || !c.dests.includes(d)) || c.dests.length === 0) {
          throw new IllegalAction(this.id, a);
        }
        let pool = a.allow.length === 0 ? [...c.dests] : c.dests.filter((d) => a.allow.includes(d));
        if (pool.length > 1) pool = pool.filter((d) => d !== s.lastDest);
        const { value, rng } = withRng(s.rng, (r) => ({ dest: pool[r.nextInt(pool.length)]!, line: r.nextInt(c.lines) }));
        return { ...s, rng, phase: 'ride', dest: value.dest, line: value.line, pickMs: a.atMs, clockMs: a.atMs, hits: 0 };
      }
      case 'hit':
        if (s.phase !== 'ride') throw new IllegalAction(this.id, a);
        return { ...s, hits: s.hits + 1 };
      case 'dropoff': {
        if (s.phase !== 'ride' || !isInt(a.atMs) || a.atMs < s.pickMs || !isInt(a.distDm) || a.distDm < 0) {
          throw new IllegalAction(this.id, a);
        }
        const last: TaxiRide = { dest: s.dest, ...taxiFare(c, a.distDm, a.atMs - s.pickMs, s.hits) };
        return {
          ...s, phase: 'wait', fare: s.fare + last.fare, rides: s.rides + 1, lastDest: s.dest, dest: '', line: -1, hits: 0,
          clockMs: a.atMs, last,
        };
      }
      default:
        throw new IllegalAction(this.id, a);
    }
  }

  aiAction(): TaxiAction {
    throw new Error('taxi: no opponent');
  }

  result(s: TaxiState): TaxiResult | null {
    if (s.phase !== 'over') return null;
    const stars = taxiStars(this.config, s.fare);
    return { winner: stars >= 1 ? 'player' : 'draw', stars, score: s.fare, rides: s.rides };
  }
}
