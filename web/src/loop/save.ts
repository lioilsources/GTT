import type { BestResult, Save } from '../gen/schema';
import type { Tuning } from '../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../minigames/rules';

/** specs/save.md, version 4: save format 5, migration from 1–4, normalisation (P0, module `save`). */
export const SAVE_VERSION = 5;

export interface SaveConfig {
  cityId: string;
  startCash: number;
  startOwned: string[];
  startCar: string;
  /** Every car id of the catalog. */
  cars: string[];
}

export interface SaveAction {
  by: 'player';
  op: 'load';
  save: unknown;
  [k: string]: unknown;
}

export function saveConfig(t: Tuning, cityId: string, cars: readonly string[]): SaveConfig {
  return { cityId, startCash: t.cars.startCash, startOwned: [...t.cars.startOwned], startCar: t.cars.startCar, cars: [...cars] };
}

type Obj = Record<string, unknown>;
const isObj = (v: unknown): v is Obj => typeof v === 'object' && v !== null && !Array.isArray(v);
const isInt = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v);
const isStrList = (v: unknown): v is string[] => Array.isArray(v) && v.every((x) => typeof x === 'string');
const isIntMap = (v: unknown): v is Record<string, number> => isObj(v) && Object.values(v).every(isInt);
const isIntMaps = (v: unknown): v is Record<string, Record<string, number>> => isObj(v) && Object.values(v).every(isIntMap);
const isBestMap = (v: unknown): v is Record<string, BestResult> =>
  isObj(v) && Object.values(v).every((b) => isObj(b) && isInt(b['stars']) && isInt(b['score']));
const cmp = (a: string, b: string): number => (a < b ? -1 : a > b ? 1 : 0);
const unique = (xs: readonly string[]): string[] => [...new Set(xs)];

/** A map with sorted keys (canonical JSON in both clients). */
function sorted<T>(m: Record<string, T>, f: (v: T) => T = (v) => v): Record<string, T> {
  const out: Record<string, T> = {};
  for (const k of Object.keys(m).sort(cmp)) out[k] = f(m[k]!);
  return out;
}

/** Nested int maps with sorted keys, negatives → 0 (unknown cars and slots are left to `garage`). */
function sortedMaps(m: Record<string, Record<string, number>>): Record<string, Record<string, number>> {
  return sorted(m, (inner) => sorted(inner, (n) => Math.max(0, n)));
}

export function freshSave(c: SaveConfig): Save {
  return composeSave(c, { cash: c.startCash, cars: [], car: c.startCar, stamps: [], best: {}, plays: {} });
}

export interface SaveParts {
  cash: number;
  cars: string[];
  car: string;
  stamps: string[];
  best: Record<string, BestResult>;
  plays: Record<string, number>;
  feed?: Save['feed'];
  npc?: Save['npc'];
  settings?: Save['settings'];
  /** Unlocked metro stations in unlock order (specs/travel.md). */
  stations?: string[];
  /** Bought souvenirs in purchase order (specs/shops.md). */
  souvenirs?: string[];
  /** Tuning levels per car and slot (specs/garage.md). */
  upgrades?: Record<string, Record<string, number>>;
  /** Looks per car and part (specs/garage.md). */
  looks?: Record<string, Record<string, number>>;
}

/** Composes a save from the live parts (same normalisation as load, so a round trip is exact). */
export function composeSave(c: SaveConfig, p: SaveParts): Save {
  const known = new Set(c.cars);
  let cars = unique(p.cars.filter((x) => known.has(x)));
  if (cars.length === 0) cars = unique(c.startOwned.filter((x) => known.has(x)));
  const car = cars.includes(p.car) ? p.car : (cars[0] ?? c.startCar);
  const feed = p.feed ?? { prefs: {}, visits: {}, districts: [] };
  const npc = p.npc ?? { vibe: {}, contacts: [], recent: [] };
  const st = p.settings ?? { scheme: 'a', night: false };
  return {
    version: SAVE_VERSION,
    cityId: c.cityId,
    cash: Math.max(0, p.cash),
    cars,
    car,
    stamps: unique(p.stamps),
    best: sorted(p.best, (b) => ({ stars: Math.min(3, Math.max(0, b.stars)), score: b.score })),
    plays: sorted(p.plays, (n) => Math.max(0, n)),
    feed: { prefs: sorted(feed.prefs), visits: sorted(feed.visits, (n) => Math.max(0, n)), districts: [...feed.districts] },
    npc: { vibe: sorted(npc.vibe), contacts: [...npc.contacts], recent: [...npc.recent] },
    settings: { scheme: (['a', 'b', 'c'] as const).includes(st.scheme) ? st.scheme : 'a', night: st.night },
    stations: unique(p.stations ?? []),
    souvenirs: unique(p.souvenirs ?? []),
    upgrades: sortedMaps(p.upgrades ?? {}),
    looks: sortedMaps(p.looks ?? {}),
  };
}

/** Any JSON value → a normalised version-5 save of this city (specs/save.md "load"). */
export function normalizeSave(c: SaveConfig, raw: unknown): Save {
  const v = isObj(raw) ? raw['version'] : undefined;
  if (!isObj(raw) || (v !== 1 && v !== 2 && v !== 3 && v !== 4 && v !== 5) || raw['cityId'] !== c.cityId) return freshSave(c);
  const s = raw;
  if (!isInt(s['cash']) || !isStrList(s['stamps']) || !isStrList(s['cars']) || !isBestMap(s['best'])) return freshSave(c);
  if (s['version'] === 1) {
    return composeSave(c, { cash: s['cash'], cars: s['cars'], car: '', stamps: s['stamps'], best: s['best'], plays: {} });
  }
  const feed = s['feed'], npc = s['npc'], st = s['settings'];
  if (typeof s['car'] !== 'string' || !isIntMap(s['plays']) ||
    !isObj(feed) || !isIntMap(feed['prefs']) || !isIntMap(feed['visits']) || !isStrList(feed['districts']) ||
    !isObj(npc) || !isIntMap(npc['vibe']) || !isStrList(npc['contacts']) || !isStrList(npc['recent']) ||
    !isObj(st) || typeof st['scheme'] !== 'string' || typeof st['night'] !== 'boolean') {
    return freshSave(c);
  }
  // Version 3: `stations` is optional (missing = []); migration 2 → 3 sets it to [].
  const stations = (v === 3 || v === 4 || v === 5) && s['stations'] !== undefined ? s['stations'] : [];
  if (!isStrList(stations)) return freshSave(c);
  // Version 4: `souvenirs` is optional (missing = []); migration 3 → 4 sets it to [].
  const souvenirs = (v === 4 || v === 5) && s['souvenirs'] !== undefined ? s['souvenirs'] : [];
  if (!isStrList(souvenirs)) return freshSave(c);
  // Version 5: `upgrades` and `looks` are optional (missing = {}); migration 4 → 5 sets them to {}.
  const upgrades = v === 5 && s['upgrades'] !== undefined ? s['upgrades'] : {};
  const looks = v === 5 && s['looks'] !== undefined ? s['looks'] : {};
  if (!isIntMaps(upgrades) || !isIntMaps(looks)) return freshSave(c);
  return composeSave(c, {
    cash: s['cash'],
    cars: s['cars'],
    car: s['car'],
    stamps: s['stamps'],
    best: s['best'],
    plays: s['plays'],
    feed: { prefs: feed['prefs'], visits: feed['visits'], districts: feed['districts'] },
    npc: { vibe: npc['vibe'], contacts: npc['contacts'], recent: npc['recent'] },
    settings: { scheme: st['scheme'] as Save['settings']['scheme'], night: st['night'] },
    stations,
    souvenirs,
    upgrades,
    looks,
  });
}

export class SaveRules implements Rules<Save & object, SaveAction, RulesResult, SaveConfig> {
  readonly id = 'save';
  readonly specVersion = 4;
  private cfg: SaveConfig | null = null;

  init(config: SaveConfig, _seed = 0): Save {
    this.cfg = config;
    return freshSave(config);
  }

  legalActions(): SaveAction[] {
    return [];
  }

  apply(_s: Save, a: SaveAction): Save {
    if (!this.cfg) throw new Error('save: init first');
    if (a.by !== 'player' || a.op !== 'load') throw new IllegalAction(this.id, a);
    return normalizeSave(this.cfg, a.save);
  }

  aiAction(): SaveAction {
    throw new Error('save: no opponent');
  }

  result(): RulesResult | null {
    return null;
  }
}
