import type { Tuning } from '../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../minigames/rules';

/** specs/economy.md, version 1: loop reward, tow fee and police fine (P0, integers only). */
export interface EconomyConfig {
  cash: number;
  base: number;
  enginePct: Record<string, number>;
  starPct: number[];
  scoreBands: number[];
  bandBonus: number[];
  firstBonus: number;
  firstMinStars: number;
  rewardBase: number;
  rewardPerMin: number;
  driveDmPerS: number;
  towFee: number;
}

export interface EconomyLast {
  op: string;
  amount: number;
  base: number;
  trip: number;
  band: number;
  first: number;
}

export interface EconomyState {
  cash: number;
  earned: number;
  paid: number;
  last: EconomyLast;
}

export type EconomyAction =
  | { by: 'player'; op: 'reward'; engine: string; stars: number; score: number; first: boolean; driveDm: number; aborted: boolean }
  | { by: 'player'; op: 'tow' }
  | { by: 'player'; op: 'fine'; amount: number };

const idiv = (a: number, b: number): number => Math.floor(a / b);
const isInt = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v);
const emptyLast = (op = ''): EconomyLast => ({ op, amount: 0, base: 0, trip: 0, band: 0, first: 0 });

/** Config from tuning (economy.* and the feed's trip money) with the current cash. */
export function economyConfig(t: Tuning, cash: number): EconomyConfig {
  const e = t.economy, f = t.feed;
  return {
    cash,
    base: e.base,
    enginePct: e.enginePct.toJson() as Record<string, number>,
    starPct: [...e.starPct],
    scoreBands: [...e.scoreBands],
    bandBonus: [...e.bandBonus],
    firstBonus: e.firstBonus,
    firstMinStars: e.firstMinStars,
    rewardBase: f.rewardBase,
    rewardPerMin: f.rewardPerMin,
    driveDmPerS: f.driveDmPerS,
    towFee: e.towFee,
  };
}

export class EconomyRules implements Rules<EconomyState, EconomyAction, RulesResult, EconomyConfig> {
  readonly id = 'economy';
  readonly specVersion = 1;
  private cfg: EconomyConfig | null = null;

  init(config: EconomyConfig, _seed = 0): EconomyState {
    this.cfg = config;
    return { cash: config.cash, earned: 0, paid: 0, last: emptyLast() };
  }

  private get c(): EconomyConfig {
    if (!this.cfg) throw new Error('economy: init first');
    return this.cfg;
  }

  /** The reward parts for a loop result (specs/economy.md "apply – reward"). */
  reward(a: { engine: string; stars: number; score: number; first: boolean; driveDm: number; aborted: boolean }): EconomyLast {
    const c = this.c;
    if (a.aborted || a.stars === 0) return emptyLast('reward');
    const sp = c.starPct[a.stars] ?? 0;
    const pct = Object.prototype.hasOwnProperty.call(c.enginePct, a.engine) ? c.enginePct[a.engine]! : 100;
    const base = idiv(idiv(c.base * pct, 100) * sp, 100);
    const trip = a.driveDm > 0 ? idiv((c.rewardBase + idiv(idiv(a.driveDm, c.driveDmPerS) * c.rewardPerMin, 60)) * sp, 100) : 0;
    const band = c.bandBonus[c.scoreBands.filter((b) => b <= a.score).length] ?? 0;
    const first = a.first && a.stars >= c.firstMinStars ? c.firstBonus : 0;
    return { op: 'reward', amount: base + trip + band + first, base, trip, band, first };
  }

  legalActions(_s: EconomyState): EconomyAction[] {
    return [{ by: 'player', op: 'tow' }];
  }

  apply(s: EconomyState, a: EconomyAction): EconomyState {
    if (a.by !== 'player') throw new IllegalAction(this.id, a);
    switch (a.op) {
      case 'reward': {
        if (!isInt(a.stars) || a.stars < 0 || a.stars > 3 || !isInt(a.score) || !isInt(a.driveDm) || a.driveDm < 0 ||
          typeof a.engine !== 'string' || typeof a.first !== 'boolean' || typeof a.aborted !== 'boolean') {
          throw new IllegalAction(this.id, a);
        }
        const last = this.reward(a);
        return { cash: s.cash + last.amount, earned: s.earned + last.amount, paid: s.paid, last };
      }
      case 'tow':
        return this.pay(s, 'tow', this.c.towFee);
      case 'fine':
        if (!isInt(a.amount) || a.amount < 0) throw new IllegalAction(this.id, a);
        return this.pay(s, 'fine', a.amount);
      default:
        throw new IllegalAction(this.id, a);
    }
  }

  private pay(s: EconomyState, op: string, amount: number): EconomyState {
    const fee = Math.min(s.cash, amount);
    return { cash: s.cash - fee, earned: s.earned, paid: s.paid + fee, last: { ...emptyLast(op), amount: fee } };
  }

  aiAction(): EconomyAction {
    throw new Error('economy: no opponent');
  }

  result(_s: EconomyState): RulesResult | null {
    return null;
  }
}
