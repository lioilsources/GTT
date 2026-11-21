import type { Prng } from '../rules/prng';
import type { TuningCars } from '../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../minigames/rules';

/** specs/cars.md, version 1: car ownership, switching and the garage (P0, module `cars`). */
export interface CarsConfig {
  prices: Record<string, number>;
  cash: number;
  owned: string[];
  driving: string;
}

export interface CarsState {
  cash: number;
  owned: string[];
  driving: string;
  stolen: boolean;
  thefts: number;
}

export type CarOwner = 'player' | 'npc';

export type CarsAction =
  | { by: 'player'; op: 'board'; car: string; owner: CarOwner }
  | { by: 'player'; op: 'select'; car: string }
  | { by: 'player'; op: 'buy'; car: string };

/** The module never ends; the type only satisfies the rules shape. */
export type CarsResult = RulesResult;

/** Start config from tuning (cars.start_*) and the prices of the loaded car specs. */
export function carsConfig(t: TuningCars, prices: Record<string, number>): CarsConfig {
  return { prices: { ...prices }, cash: t.startCash, owned: [...t.startOwned], driving: t.startCar };
}

export class CarsRules implements Rules<CarsState, CarsAction, CarsResult, CarsConfig> {
  readonly id = 'cars';
  readonly specVersion = 1;
  private cfg: CarsConfig | null = null;

  init(config: CarsConfig, _seed: number): CarsState {
    this.cfg = config;
    return { cash: config.cash, owned: [...config.owned], driving: config.driving, stolen: false, thefts: 0 };
  }

  private get prices(): Record<string, number> {
    if (!this.cfg) throw new Error('cars: init first');
    return this.cfg.prices;
  }

  private known(car: string): boolean {
    return Object.prototype.hasOwnProperty.call(this.prices, car);
  }

  /** Cars the player could buy now (garage API for M1-S11), alphabetical by id. */
  buyable(s: CarsState): string[] {
    return Object.keys(this.prices)
      .sort()
      .filter((c) => !s.owned.includes(c) && s.cash >= this.prices[c]!);
  }

  legalActions(s: CarsState): CarsAction[] {
    const sel = s.owned.filter((c) => c !== s.driving || s.stolen).map((car): CarsAction => ({ by: 'player', op: 'select', car }));
    const buy = this.buyable(s).map((car): CarsAction => ({ by: 'player', op: 'buy', car }));
    return [...sel, ...buy];
  }

  apply(s: CarsState, a: CarsAction): CarsState {
    if (a.by !== 'player' || typeof a.car !== 'string' || !this.known(a.car)) throw new IllegalAction(this.id, a);
    switch (a.op) {
      case 'board': {
        if (a.owner === 'player') {
          if (!s.owned.includes(a.car)) throw new IllegalAction(this.id, a);
          return { ...s, driving: a.car, stolen: false };
        }
        if (a.owner !== 'npc') throw new IllegalAction(this.id, a);
        return { ...s, driving: a.car, stolen: true, thefts: s.thefts + 1 };
      }
      case 'select':
        if (!s.owned.includes(a.car) || (a.car === s.driving && !s.stolen)) throw new IllegalAction(this.id, a);
        return { ...s, driving: a.car, stolen: false };
      case 'buy': {
        const price = this.prices[a.car]!;
        if (s.owned.includes(a.car) || s.cash < price) throw new IllegalAction(this.id, a);
        return { ...s, owned: [...s.owned, a.car], cash: s.cash - price };
      }
      default:
        throw new IllegalAction(this.id, a);
    }
  }

  aiAction(_s: CarsState, _level: number, _ai: Prng): CarsAction {
    throw new Error('cars: no opponent');
  }

  result(_s: CarsState): CarsResult | null {
    return null;
  }
}
