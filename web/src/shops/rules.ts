import type { TuningShops } from '../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../minigames/rules';
import type { Prng } from '../rules/prng';

/** specs/shops.md, version 1: snack bonus, souvenirs and beers in whole game seconds (P0, module `shops`). */
export type ShopKind = 'food' | 'souvenir' | 'bar';

export interface ShopItem {
  id: string;
  kind: ShopKind;
  price: number;
}

export interface ShopsConfig {
  snackPct: number;
  beerLimit: number;
  beerS: number;
  snackS: number;
  /** Shops of the city in spots.pb order. */
  items: ShopItem[];
}

export interface ShopsLast {
  op: '' | 'buy' | 'reward';
  amount: number;
}

export interface ShopsState {
  snackLeft: number;
  beers: number;
  beerLeft: number;
  drunk: boolean;
  owned: string[];
  last: ShopsLast;
}

export type ShopsAction =
  | { by: 'player'; op: 'load'; owned: string[] }
  | { by: 'player'; op: 'tick' }
  | { by: 'player'; op: 'buy'; shop: string; cash: number }
  | { by: 'player'; op: 'reward'; amount: number }
  | { by: 'player'; op: 'finish'; stars: number; aborted: boolean };

export const shopKinds: readonly ShopKind[] = ['food', 'souvenir', 'bar'];

/** Price of a shop kind (shops.price_food / price_souvenir / price_beer). */
export function shopPrice(t: TuningShops, kind: ShopKind): number {
  return kind === 'food' ? t.priceFood : kind === 'souvenir' ? t.priceSouvenir : t.priceBeer;
}

/** Config from tuning and the shops of the city (spots.pb order). */
export function shopsConfig(t: TuningShops, shops: ReadonlyArray<{ id: string; kind: ShopKind }>): ShopsConfig {
  return {
    snackPct: t.snackPct, beerLimit: t.beerLimit, beerS: t.beerS, snackS: t.snackS,
    items: shops.map((s) => ({ id: s.id, kind: s.kind, price: shopPrice(t, s.kind) })),
  };
}

const isInt = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v);
const noLast = (): ShopsLast => ({ op: '', amount: 0 });

export class ShopsRules implements Rules<ShopsState, ShopsAction, RulesResult, ShopsConfig> {
  readonly id = 'shops';
  readonly specVersion = 1;
  private cfg: ShopsConfig | null = null;

  get config(): ShopsConfig {
    if (!this.cfg) throw new Error('shops: init first');
    return this.cfg;
  }

  init(config: ShopsConfig, _seed = 0): ShopsState {
    this.cfg = config;
    return { snackLeft: 0, beers: 0, beerLeft: 0, drunk: false, owned: [], last: noLast() };
  }

  legalActions(s: ShopsState): ShopsAction[] {
    const out: ShopsAction[] = [
      { by: 'player', op: 'load', owned: [] },
      { by: 'player', op: 'tick' },
      { by: 'player', op: 'finish', stars: 1, aborted: false },
      { by: 'player', op: 'reward', amount: 0 },
    ];
    for (const it of this.config.items) {
      if (it.kind === 'souvenir' && s.owned.includes(it.id)) continue;
      out.push({ by: 'player', op: 'buy', shop: it.id, cash: it.price });
    }
    return out;
  }

  apply(state: ShopsState, a: ShopsAction): ShopsState {
    if (a.by !== 'player') throw new IllegalAction(this.id, a);
    const c = this.config;
    const s: ShopsState = { ...state, owned: [...state.owned], last: noLast() };
    switch (a.op) {
      case 'load': {
        if (!Array.isArray(a.owned) || !a.owned.every((x) => typeof x === 'string')) throw new IllegalAction(this.id, a);
        const souvenirs = new Set(c.items.filter((i) => i.kind === 'souvenir').map((i) => i.id));
        s.owned = [...new Set(a.owned.filter((x) => souvenirs.has(x)))];
        break;
      }
      case 'tick': {
        s.snackLeft = Math.max(0, s.snackLeft - 1);
        if (!s.drunk && s.beers > 0) {
          s.beerLeft -= 1;
          if (s.beerLeft <= 0) {
            s.beers -= 1;
            s.beerLeft = s.beers > 0 ? c.beerS : 0;
          }
        }
        break;
      }
      case 'buy': {
        const it = typeof a.shop === 'string' ? c.items.find((i) => i.id === a.shop) : undefined;
        if (!it || !isInt(a.cash) || a.cash < 0 || a.cash < it.price || (it.kind === 'souvenir' && s.owned.includes(it.id))) {
          throw new IllegalAction(this.id, a);
        }
        if (it.kind === 'food') s.snackLeft = c.snackS;
        else if (it.kind === 'souvenir') s.owned.push(it.id);
        else {
          if (s.beers === 0) s.beerLeft = c.beerS;
          s.beers += 1;
          if (s.beers > c.beerLimit) s.drunk = true;
        }
        s.last = { op: 'buy', amount: it.price };
        break;
      }
      case 'reward': {
        if (!isInt(a.amount) || a.amount < 0) throw new IllegalAction(this.id, a);
        let bonus = 0;
        if (s.snackLeft > 0) {
          bonus = Math.floor((a.amount * c.snackPct) / 100);
          s.snackLeft = 0;
        }
        s.last = { op: 'reward', amount: bonus };
        break;
      }
      case 'finish': {
        if (!isInt(a.stars) || a.stars < 0 || a.stars > 3 || typeof a.aborted !== 'boolean') throw new IllegalAction(this.id, a);
        if (s.drunk && a.stars >= 1 && !a.aborted) {
          s.drunk = false;
          s.beers = 0;
          s.beerLeft = 0;
        }
        break;
      }
      default:
        throw new IllegalAction(this.id, a);
    }
    return s;
  }

  aiAction(_s: ShopsState, _level: number, _ai: Prng): ShopsAction {
    throw new Error('shops: no opponent');
  }

  result(_s: ShopsState): RulesResult | null {
    return null;
  }
}
