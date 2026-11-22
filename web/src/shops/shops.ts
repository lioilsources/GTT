// Shops and bars in the world (specs/shops.md P1): shop list, reach, bar minigames, the 1 s game
// tick and the drunk input. No DOM, no Babylon.
import type { ControlInput } from '../drive/controls';
import type { MinigameMeta } from '../gen/schema';
import type { Tuning, TuningLoop, TuningShops } from '../gen/tuning';
import { opponentIndex } from '../loop/logic';
import { shopKinds, shopsConfig, ShopsRules, type ShopKind, type ShopsState } from './rules';

/** A shop: spot `kind: food | souvenir | bar`, parking point in metres. */
export interface Shop {
  id: string;
  name: string;
  kind: ShopKind;
  x: number;
  y: number;
  /** The bar's own minigame ('' = none). */
  minigame: string;
}

interface SpotLike {
  id: string;
  kind: string;
  name: string;
  parkX: number;
  parkY: number;
  minigame: string;
}

const isShopKind = (k: string): k is ShopKind => (shopKinds as readonly string[]).includes(k);

/** Shops in spots.pb order. */
export function shopsOf(spots: readonly SpotLike[]): Shop[] {
  const out: Shop[] = [];
  for (const s of spots) {
    if (isShopKind(s.kind)) out.push({ id: s.id, name: s.name, kind: s.kind, x: s.parkX / 10, y: s.parkY / 10, minigame: s.kind === 'bar' ? s.minigame : '' });
  }
  return out;
}

/** True when the module runs in this city: shops.enabled, shops.cities.<city> and at least one shop. */
export function shopsActive(t: TuningShops, cityId: string, shops: readonly Shop[]): boolean {
  const cities = t.cities as unknown as Record<string, boolean | undefined>;
  return t.enabled && cities[cityId] === true && shops.length > 0;
}

/** Distinct catalog minigames of the city's bars, in spot order (the bar card's "Zahrát" rows). */
export function barGames(shops: readonly Shop[], catalog: Readonly<Record<string, MinigameMeta | undefined>>): string[] {
  const out: string[] = [];
  for (const s of shops) if (s.kind === 'bar' && s.minigame !== '' && catalog[s.minigame] && !out.includes(s.minigame)) out.push(s.minigame);
  return out;
}

/** The nearest shop within loop.spot_radius_m while the car stands on layer 0 (as "Hrát", specs/loop.md). */
export function shopInReach(shops: readonly Shop[], x: number, y: number, speed: number, layer: number, t: TuningLoop): Shop | null {
  if (speed > t.stopSpeedMps || layer !== 0) return null;
  let best: Shop | null = null;
  let bd = t.spotRadiusM * t.spotRadiusM;
  for (const s of shops) {
    const d = (s.x - x) ** 2 + (s.y - y) ** 2;
    if (d <= bd) {
      bd = d;
      best = s;
    }
  }
  return best;
}

/** Host of a shop card: characters[fnv1a(spotId) mod n], −1 without characters (as the booth host). */
export const shopHost = opponentIndex;

/**
 * Drunk driving (spec "Piva"): the player's input is ignored and the car brakes to a stop. Brake
 * while it still rolls forward (brake at a standstill would reverse), handbrake holds it (no
 * auto-throttle), no steering.
 */
export function drunkInput(input: ControlInput, forwardSpeed: number, brakeMinMps: number): void {
  input.reset();
  input.brake = forwardSpeed > brakeMinMps ? 1 : 0;
  input.handbrake = true;
}

/** The shops module of one session: state, game clock and cash through ports. */
export class ShopsWorld {
  readonly rules = new ShopsRules();
  state: ShopsState;
  /** Game seconds not yet ticked. */
  private acc = 0;
  /** Called when the player sobers up (toast `shopsSober`). */
  onSober: Array<() => void> = [];

  constructor(readonly shops: readonly Shop[], tuning: Tuning, readonly cash: { get(): number; set(c: number): void }) {
    this.state = this.rules.init(shopsConfig(tuning.shops, shops), 0);
  }

  get drunk(): boolean {
    return this.state.drunk;
  }

  get owned(): readonly string[] {
    return this.state.owned;
  }

  price(id: string): number {
    return this.rules.config.items.find((i) => i.id === id)?.price ?? 0;
  }

  /** Souvenirs from the save; unknown ones are dropped. */
  load(owned: readonly string[]): void {
    this.state = this.rules.apply(this.state, { by: 'player', op: 'load', owned: [...owned] });
  }

  /** Advances the game clock by `stepDt` (0 while paused) and ticks once per whole second. */
  update(stepDt: number): void {
    this.acc += Math.max(0, stepDt);
    while (this.acc >= 1) {
      this.acc -= 1;
      this.state = this.rules.apply(this.state, { by: 'player', op: 'tick' });
    }
  }

  /** True when `buy` is legal with the current cash. */
  canBuy(id: string): boolean {
    const it = this.rules.config.items.find((i) => i.id === id);
    if (!it) return false;
    return this.cash.get() >= it.price && !(it.kind === 'souvenir' && this.state.owned.includes(id));
  }

  /** Buys at the shop with the cars-state cash; returns the price paid, null when not possible. */
  buy(id: string): number | null {
    if (!this.canBuy(id)) return null;
    const cash = this.cash.get();
    this.state = this.rules.apply(this.state, { by: 'player', op: 'buy', shop: id, cash });
    this.cash.set(cash - this.state.last.amount);
    return this.state.last.amount;
  }

  /** The loop's economy reward; returns the snack bonus (the caller adds it to the cash). */
  reward(amount: number): number {
    this.state = this.rules.apply(this.state, { by: 'player', op: 'reward', amount: Math.max(0, Math.floor(amount)) });
    return this.state.last.amount;
  }

  /** Loop result; a won game sobers the player up. */
  finish(stars: number, aborted: boolean): void {
    const was = this.state.drunk;
    const s = Math.max(0, Math.min(3, Math.floor(stars)));
    this.state = this.rules.apply(this.state, { by: 'player', op: 'finish', stars: s, aborted });
    if (was && !this.state.drunk) for (const f of this.onSober) f();
  }
}
