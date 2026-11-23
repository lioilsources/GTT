import type { CarSpec } from '../gen/schema';
import { tokens } from '../gen/tokens';
import type { TuningGarage } from '../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../minigames/rules';
import type { Prng } from '../rules/prng';

/** specs/garage.md, version 2: upgrade levels and looks of the player's cars (P0, module `garage`). */
export type GarageSlot = 'engine' | 'tyres' | 'brakes' | 'weight' | 'drift';
export type LookPart = 'paint' | 'decal' | 'wheels' | 'glow' | 'smoke';

export const garageSlots: readonly GarageSlot[] = ['engine', 'tyres', 'brakes', 'weight', 'drift'];
/** Parts in their fixed order (spec "Vzhled"). */
export const lookParts: readonly LookPart[] = ['paint', 'decal', 'wheels', 'glow', 'smoke'];

export type Levels = Partial<Record<GarageSlot, number>>;
export type Look = Partial<Record<LookPart, number>>;

export interface GarageConfig {
  /** Every catalog car with its tuning_slots (JSON order). */
  cars: Record<string, string[]>;
  maxLevel: number;
  prices: Record<string, number[]>;
  /** Number of choices per part (0 = stock included). */
  parts: Record<string, number>;
  lookPrices: Record<string, number>;
}

export interface GarageLast {
  op: '' | 'upgrade' | 'look';
  amount: number;
}

export interface GarageState {
  upgrades: Record<string, Record<string, number>>;
  looks: Record<string, Record<string, number>>;
  last: GarageLast;
}

export type GarageAction =
  | { by: 'player'; op: 'load'; upgrades: unknown; looks: unknown }
  | { by: 'player'; op: 'upgrade'; car: string; slot: string; cash: number }
  | { by: 'player'; op: 'look'; car: string; part: string; value: number; cash: number };

/** Price list of a slot (garage.price_<slot>). */
export function slotPrices(t: TuningGarage, slot: GarageSlot): number[] {
  switch (slot) {
    case 'engine': return t.priceEngine;
    case 'tyres': return t.priceTyres;
    case 'brakes': return t.priceBrakes;
    case 'weight': return t.priceWeight;
    case 'drift': return t.priceDrift;
  }
}

/** Price of a non-stock choice of a part (garage.look_price_<part>). */
export function lookPrice(t: TuningGarage, part: LookPart): number {
  switch (part) {
    case 'paint': return t.lookPricePaint;
    case 'decal': return t.lookPriceDecal;
    case 'wheels': return t.lookPriceWheels;
    case 'glow': return t.lookPriceGlow;
    case 'smoke': return t.lookPriceSmoke;
  }
}

/** Decal ids by choice (specs/garage.md v2 "Vzhled"; 0 = none): sprite `garage/decals/<id>.png`. */
export const decalIds = ['', 'stripes', 'flames', 'checker', 'stars', 'lightning', 'waves', 'camo', 'halftone'] as const;
/** Wheel ids by choice (0 = stock): sprite `garage/wheels/<id>.png`. */
export const wheelIds = ['', 'sport', 'whitewall', 'five_spoke', 'mesh', 'turbine', 'offroad'] as const;

/** Number of choices of each part from the colour tokens and the decal table (spec "Vzhled"). */
export function partCounts(): Record<LookPart, number> {
  return {
    paint: 1 + tokens.colorGaragePaints.length,
    decal: decalIds.length,
    wheels: tokens.colorGarageWheels.length,
    glow: 1 + tokens.colorGarageGlow.length,
    smoke: 1 + tokens.colorGarageSmoke.length,
  };
}

/** Config from tuning and the car catalog. */
export function garageConfig(t: TuningGarage, specs: Iterable<CarSpec>): GarageConfig {
  const cars: Record<string, string[]> = {};
  for (const s of specs) cars[s.id] = [...s.tuning_slots];
  const prices: Record<string, number[]> = {};
  for (const s of garageSlots) prices[s] = [...slotPrices(t, s)];
  const lookPrices: Record<string, number> = {};
  for (const p of lookParts) lookPrices[p] = lookPrice(t, p);
  return { cars, maxLevel: t.maxLevel, prices, parts: partCounts(), lookPrices };
}

/**
 * Effective car parameters (spec "Účinek na jízdu", P1): the catalog values times the level
 * multipliers; multipliers of one parameter multiply. Same id and everything else as [spec].
 */
export function tunedSpec(spec: CarSpec, levels: Levels, t: TuningGarage): CarSpec {
  const l = (s: GarageSlot): number => (spec.tuning_slots.includes(s) ? Math.max(0, levels[s] ?? 0) : 0);
  const e = l('engine'), ty = l('tyres'), b = l('brakes'), w = l('weight'), d = l('drift');
  if (e + ty + b + w + d === 0) return spec;
  const grip = 1 + t.tyresStep * ty;
  return {
    ...spec,
    power: spec.power * (1 + t.enginePowerStep * e) * (1 + t.weightPowerStep * w),
    top_speed: spec.top_speed * (1 + t.engineTopStep * e),
    grip_front: spec.grip_front * grip,
    grip_rear: spec.grip_rear * grip,
    brake: spec.brake * (1 + t.brakesStep * b),
    mass: spec.mass * (1 - t.weightMassStep * w),
    steer_speed: spec.steer_speed * (1 + t.weightSteerStep * w),
    drift_bias: spec.drift_bias * (1 - t.driftStep * d),
  };
}

type Obj = Record<string, unknown>;
const isObj = (v: unknown): v is Obj => typeof v === 'object' && v !== null && !Array.isArray(v);
const isInt = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v);
const cmp = (a: string, b: string): number => (a < b ? -1 : a > b ? 1 : 0);
const noLast = (): GarageLast => ({ op: '', amount: 0 });

/** A two-level map of ints, or null when it is not one (load: illegal). */
function intMaps(v: unknown): Record<string, Record<string, number>> | null {
  if (!isObj(v)) return null;
  for (const inner of Object.values(v)) {
    if (!isObj(inner) || !Object.values(inner).every(isInt)) return null;
  }
  return v as Record<string, Record<string, number>>;
}

/** Sets [key] of [car] in a nested map, dropping zeros and empty cars. */
function put(m: Record<string, Record<string, number>>, car: string, key: string, v: number): Record<string, Record<string, number>> {
  const out = { ...m };
  const inner = { ...(out[car] ?? {}) };
  if (v === 0) delete inner[key];
  else inner[key] = v;
  if (Object.keys(inner).length === 0) delete out[car];
  else out[car] = inner;
  return out;
}

export class GarageRules implements Rules<GarageState, GarageAction, RulesResult, GarageConfig> {
  readonly id = 'garage';
  readonly specVersion = 1;
  private cfg: GarageConfig | null = null;

  get config(): GarageConfig {
    if (!this.cfg) throw new Error('garage: init first');
    return this.cfg;
  }

  init(config: GarageConfig, _seed = 0): GarageState {
    this.cfg = config;
    return { upgrades: {}, looks: {}, last: noLast() };
  }

  /** Current level of a slot (0 when not set). */
  level(s: GarageState, car: string, slot: string): number {
    return s.upgrades[car]?.[slot] ?? 0;
  }

  /** Current choice of a part (0 = stock). */
  look(s: GarageState, car: string, part: string): number {
    return s.looks[car]?.[part] ?? 0;
  }

  /** Price of the next level of a slot, or null when not upgradable (not a slot, or maxed). */
  upgradePrice(s: GarageState, car: string, slot: string): number | null {
    const c = this.config;
    const slots = c.cars[car];
    if (!slots || !slots.includes(slot)) return null;
    const lvl = this.level(s, car, slot);
    if (lvl >= c.maxLevel) return null;
    return c.prices[slot]?.[lvl] ?? null;
  }

  /** Price of a choice of a part (0 for stock). */
  lookPrice(part: string, value: number): number {
    return value === 0 ? 0 : (this.config.lookPrices[part] ?? 0);
  }

  legalActions(s: GarageState): GarageAction[] {
    const c = this.config;
    const out: GarageAction[] = [{ by: 'player', op: 'load', upgrades: {}, looks: {} }];
    const ids = Object.keys(c.cars).sort(cmp);
    for (const car of ids) {
      for (const slot of c.cars[car]!) {
        const price = this.upgradePrice(s, car, slot);
        if (price !== null) out.push({ by: 'player', op: 'upgrade', car, slot, cash: price });
      }
    }
    for (const car of ids) {
      for (const part of lookParts) {
        const n = c.parts[part];
        if (n === undefined) continue;
        const cur = this.look(s, car, part);
        for (let v = 0; v < n; v++) {
          if (v !== cur) out.push({ by: 'player', op: 'look', car, part, value: v, cash: this.lookPrice(part, v) });
        }
      }
    }
    return out;
  }

  apply(state: GarageState, a: GarageAction): GarageState {
    if (a.by !== 'player') throw new IllegalAction(this.id, a);
    const c = this.config;
    switch (a.op) {
      case 'load': {
        const up = intMaps(a.upgrades), lk = intMaps(a.looks);
        if (!up || !lk) throw new IllegalAction(this.id, a);
        let upgrades: GarageState['upgrades'] = {};
        for (const [car, slots] of Object.entries(up)) {
          const known = c.cars[car];
          if (!known) continue;
          for (const [slot, v] of Object.entries(slots)) {
            if (known.includes(slot)) upgrades = put(upgrades, car, slot, Math.min(c.maxLevel, Math.max(0, v)));
          }
        }
        let looks: GarageState['looks'] = {};
        for (const [car, parts] of Object.entries(lk)) {
          if (!c.cars[car]) continue;
          for (const [part, v] of Object.entries(parts)) {
            const n = c.parts[part];
            if (n !== undefined && v >= 0 && v < n) looks = put(looks, car, part, v);
          }
        }
        return { upgrades, looks, last: noLast() };
      }
      case 'upgrade': {
        const price = typeof a.car === 'string' && typeof a.slot === 'string' ? this.upgradePrice(state, a.car, a.slot) : null;
        if (price === null || !isInt(a.cash) || a.cash < 0 || a.cash < price) throw new IllegalAction(this.id, a);
        return {
          upgrades: put(state.upgrades, a.car, a.slot, this.level(state, a.car, a.slot) + 1),
          looks: state.looks,
          last: { op: 'upgrade', amount: price },
        };
      }
      case 'look': {
        const n = typeof a.part === 'string' ? c.parts[a.part] : undefined;
        if (typeof a.car !== 'string' || !c.cars[a.car] || n === undefined || !isInt(a.value) || a.value < 0 || a.value >= n ||
          a.value === this.look(state, a.car, a.part) || !isInt(a.cash) || a.cash < 0) {
          throw new IllegalAction(this.id, a);
        }
        const price = this.lookPrice(a.part, a.value);
        if (a.cash < price) throw new IllegalAction(this.id, a);
        return { upgrades: state.upgrades, looks: put(state.looks, a.car, a.part, a.value), last: { op: 'look', amount: price } };
      }
      default:
        throw new IllegalAction(this.id, a);
    }
  }

  aiAction(_s: GarageState, _level: number, _ai: Prng): GarageAction {
    throw new Error('garage: no opponent');
  }

  result(_s: GarageState): RulesResult | null {
    return null;
  }
}
