import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { afterEach, describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { ArtIndex } from '../src/art/rules';
import { ControlInput } from '../src/drive/controls';
import { carIdValues, minigameCatalog } from '../src/gen/ids';
import type { MinigameResult } from '../src/gen/schema';
import { Tuning } from '../src/gen/tuning';
import { LoopBook } from '../src/loop/logic';
import { composeSave, freshSave, normalizeSave, saveConfig, SaveRules } from '../src/loop/save';
import { overlays, pausingOverlays } from '../src/pause';
import { rulesModules } from '../src/rules/vectors';
import { shopPrice, shopsConfig, ShopsRules, type ShopsAction, type ShopsConfig } from '../src/shops/rules';
import { barGames, drunkInput, shopInReach, shopsActive, shopsOf, ShopsWorld } from '../src/shops/shops';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));

afterEach(() => overlays.clear());

const cfg: ShopsConfig = {
  snackPct: 25, beerLimit: 2, beerS: 3, snackS: 4,
  items: [{ id: 'food_a', kind: 'food', price: 15 }, { id: 'souv_a', kind: 'souvenir', price: 120 }, { id: 'bar_a', kind: 'bar', price: 10 }],
};
const P = { by: 'player' } as const;
const run = (acts: ShopsAction[]) => {
  const r = new ShopsRules();
  let s = r.init(cfg, 0);
  for (const a of acts) s = r.apply(s, a);
  return { r, s };
};

describe('shops rules (specs/shops.md)', () => {
  it('registered for vectors with specVersion 1', () => {
    expect(rulesModules['shops']?.().specVersion).toBe(1);
  });

  it('config from tuning: prices by kind, spot order', () => {
    const c = shopsConfig(tuning.shops, [{ id: 'b', kind: 'bar' }, { id: 'f', kind: 'food' }, { id: 's', kind: 'souvenir' }]);
    expect(c.items).toEqual([
      { id: 'b', kind: 'bar', price: tuning.shops.priceBeer },
      { id: 'f', kind: 'food', price: tuning.shops.priceFood },
      { id: 's', kind: 'souvenir', price: tuning.shops.priceSouvenir },
    ]);
    expect(shopPrice(tuning.shops, 'food')).toBe(tuning.shops.priceFood);
    expect([c.snackPct, c.snackS, c.beerLimit, c.beerS]).toEqual([tuning.shops.snackPct, tuning.shops.snackS, tuning.shops.beerLimit, tuning.shops.beerS]);
  });

  it('load keeps known souvenirs only, first of duplicates', () => {
    const { s } = run([{ ...P, op: 'load', owned: ['souv_a', 'food_a', 'gone', 'souv_a'] }]);
    expect(s.owned).toEqual(['souv_a']);
  });

  it('snack: reward gives snackPct (rounded down) once, then nothing', () => {
    const { r, s } = run([{ ...P, op: 'buy', shop: 'food_a', cash: 15 }]);
    expect(s.last).toEqual({ op: 'buy', amount: 15 });
    let x = r.apply(s, { ...P, op: 'reward', amount: 99 });
    expect(x.last).toEqual({ op: 'reward', amount: 24 });
    x = r.apply(x, { ...P, op: 'reward', amount: 99 });
    expect(x.last.amount).toBe(0);
  });

  it('snack wears off after snackS ticks', () => {
    const { s } = run([{ ...P, op: 'buy', shop: 'food_a', cash: 99 }, ...Array<ShopsAction>(4).fill({ ...P, op: 'tick' }), { ...P, op: 'reward', amount: 100 }]);
    expect(s.last).toEqual({ op: 'reward', amount: 0 });
  });

  it('illegal: unknown shop, too little cash, souvenir twice, bad reward/finish', () => {
    const { r, s } = run([{ ...P, op: 'buy', shop: 'souv_a', cash: 120 }]);
    expect(() => r.apply(s, { ...P, op: 'buy', shop: 'nope', cash: 999 })).toThrow();
    expect(() => r.apply(s, { ...P, op: 'buy', shop: 'food_a', cash: 14 })).toThrow();
    expect(() => r.apply(s, { ...P, op: 'buy', shop: 'souv_a', cash: 999 })).toThrow();
    expect(() => r.apply(s, { ...P, op: 'reward', amount: -1 })).toThrow();
    expect(() => r.apply(s, { ...P, op: 'finish', stars: 4, aborted: false })).toThrow();
    expect(r.legalActions(s).filter((a) => a.op === 'buy').map((a) => (a as { shop: string }).shop)).toEqual(['food_a', 'bar_a']);
  });

  it('beers: up to the limit sober, one more drunk; only a won game sobers', () => {
    const beer: ShopsAction = { ...P, op: 'buy', shop: 'bar_a', cash: 10 };
    let { r, s } = run([beer, beer]);
    expect([s.beers, s.drunk]).toEqual([2, false]);
    s = r.apply(s, beer);
    expect(s.drunk).toBe(true);
    for (let i = 0; i < 10; i++) s = r.apply(s, { ...P, op: 'tick' });
    expect(s.beers).toBe(3);
    s = r.apply(s, { ...P, op: 'finish', stars: 0, aborted: false });
    s = r.apply(s, { ...P, op: 'finish', stars: 3, aborted: true });
    expect(s.drunk).toBe(true);
    s = r.apply(s, { ...P, op: 'finish', stars: 1, aborted: false });
    expect([s.drunk, s.beers, s.beerLeft]).toEqual([false, 0, 0]);
  });

  it('beers wear off one per beerS while sober', () => {
    const beer: ShopsAction = { ...P, op: 'buy', shop: 'bar_a', cash: 10 };
    let { r, s } = run([beer, beer]);
    for (let i = 0; i < 3; i++) s = r.apply(s, { ...P, op: 'tick' });
    expect([s.beers, s.beerLeft]).toEqual([1, 3]);
    for (let i = 0; i < 3; i++) s = r.apply(s, { ...P, op: 'tick' });
    expect([s.beers, s.beerLeft]).toEqual([0, 0]);
  });
});

const spot = (id: string, kind: string, x: number, minigame = '') => ({ id, kind, name: id.toUpperCase(), parkX: x * 10, parkY: 0, parkHeading: 0, minigame });

describe('shops in the world (specs/shops.md P1)', () => {
  const spots = [
    spot('a', 'plaza', 0, 'sipky'), spot('f', 'food', 100), spot('b1', 'bar', 200, 'sipky'), spot('s', 'souvenir', 300),
    spot('b2', 'bar', 400), spot('b3', 'bar', 500, 'oko'), spot('b4', 'bar', 600, 'sipky'),
  ];
  const shops = shopsOf(spots);

  it('shops in spot order; bar games distinct in spot order', () => {
    expect(shops.map((s) => `${s.id}:${s.kind}`)).toEqual(['f:food', 'b1:bar', 's:souvenir', 'b2:bar', 'b3:bar', 'b4:bar']);
    expect(barGames(shops, minigameCatalog)).toEqual(['sipky', 'oko']);
  });

  it('active only with shops.enabled, the city flag and some shops', () => {
    expect(shopsActive(tuning.shops, 'nyc', shops)).toBe(tuning.shops.enabled && tuning.shops.cities.nyc);
    expect(shopsActive(tuning.shops, 'prague', shops)).toBe(tuning.shops.enabled && tuning.shops.cities.prague);
    expect(shopsActive(tuning.shops, 'nyc', [])).toBe(false);
    expect(shopsActive(tuning.shops, 'atlantis', shops)).toBe(false);
  });

  it('reach: standing, layer 0, within loop.spot_radius_m', () => {
    const r = tuning.loop.spotRadiusM;
    expect(shopInReach(shops, 100 + r * 0.5, 0, 0, 0, tuning.loop)?.id).toBe('f');
    expect(shopInReach(shops, 100 + r * 1.5, 0, 0, 0, tuning.loop)).toBeNull();
    expect(shopInReach(shops, 100, 0, tuning.loop.stopSpeedMps + 1, 0, tuning.loop)).toBeNull();
    expect(shopInReach(shops, 100, 0, 0, 1, tuning.loop)).toBeNull();
  });

  it('world: buy takes cash, ticks per whole game second, sober event', () => {
    let cash = 1000;
    const w = new ShopsWorld(shops, tuning, { get: () => cash, set: (c) => (cash = c) });
    let sober = 0;
    w.onSober.push(() => sober++);
    expect(w.buy('s')).toBe(tuning.shops.priceSouvenir);
    expect(w.buy('s')).toBeNull();
    expect(cash).toBe(1000 - tuning.shops.priceSouvenir);
    for (let i = 0; i <= tuning.shops.beerLimit; i++) w.buy('b2');
    expect(w.drunk).toBe(true);
    w.update(0.6);
    w.update(0.6);
    expect(w.state.beers).toBe(tuning.shops.beerLimit + 1);
    w.finish(2, false);
    expect([w.drunk, sober]).toEqual([false, 1]);
    cash = 0;
    expect(w.canBuy('f')).toBe(false);
    expect(w.buy('f')).toBeNull();
  });

  it('drunk input: brakes while rolling, holds without reversing, no steering', () => {
    const i = new ControlInput();
    i.steer = 1;
    i.throttle = 1;
    drunkInput(i, 5, tuning.drive.brakeMinMps);
    expect([i.steer, i.throttle, i.brake, i.handbrake]).toEqual([0, 0, 1, true]);
    drunkInput(i, 0, tuning.drive.brakeMinMps);
    expect([i.brake, i.handbrake]).toEqual([0, true]);
  });

  it('pause kind shop', () => {
    expect(pausingOverlays).toContain('shop');
  });

  it('souvenir art lookup', () => {
    expect(new ArtIndex(['souvenirs/s.png']).souvenir('s')).toBe('souvenirs/s.png');
    expect(new ArtIndex().souvenir('s')).toBeNull();
  });
});

describe('loop with shops (specs/shops.md "Hotovost")', () => {
  const result = (stars: number, aborted = false): MinigameResult => ({ stars, score: 100, aborted } as MinigameResult);

  it('snack bonus after the reward is part of the loop cash, then finish sobers', () => {
    let cash = 500;
    const book = new LoopBook(tuning, { getCash: () => cash, setCash: (c) => (cash = c), stamp: () => false });
    const shops = shopsOf([spot('f', 'food', 0), spot('b', 'bar', 10)]);
    const w = new ShopsWorld(shops, tuning, { get: () => cash, set: (c) => (cash = c) });
    book.shops = { reward: (a) => w.reward(a), finish: (s, a) => w.finish(s, a) };
    w.buy('f');
    for (let i = 0; i <= tuning.shops.beerLimit; i++) w.buy('b');
    const before = cash;
    const o = book.finish({ spot: 'x', minigame: 'sipky', engine: minigameCatalog.sipky.engine, result: result(2), driveDm: 0 }, () => false);
    expect(o.snack).toBe(Math.floor((o.cash.amount * tuning.shops.snackPct) / 100));
    expect(o.snack).toBeGreaterThan(0);
    expect(cash).toBe(before + o.cash.amount + o.snack);
    expect(o.total).toBe(cash);
    expect(w.drunk).toBe(false);
    const o2 = book.finish({ spot: 'x', minigame: 'sipky', engine: minigameCatalog.sipky.engine, result: result(2), driveDm: 0 }, () => false);
    expect(o2.snack).toBe(0);
  });
});

describe('save v4 (specs/save.md v3)', () => {
  const sc = saveConfig(tuning, 'nyc', carIdValues);
  const v3 = {
    version: 3, cityId: 'nyc', cash: 300, cars: ['m0_coupe'], car: 'm0_coupe', stamps: [], best: {}, plays: {},
    feed: { prefs: {}, visits: {}, districts: [] }, npc: { vibe: {}, contacts: [], recent: [] }, settings: { scheme: 'b', night: false },
    stations: ['st'],
  };

  it('spec version 4, fresh save version 5 with no souvenirs', () => {
    expect(new SaveRules().specVersion).toBe(4);
    expect(freshSave(sc)).toMatchObject({ version: 5, souvenirs: [] });
  });

  it('migration 3 → 4 keeps everything, souvenirs = []', () => {
    const s = normalizeSave(sc, { ...v3, souvenirs: ['x'] });
    expect([s.version, s.cash, s.stations, s.souvenirs]).toEqual([5, 300, ['st'], []]);
  });

  it('v4: souvenirs without duplicates, missing = [], wrong type = fresh; round trip exact', () => {
    expect(normalizeSave(sc, { ...v3, version: 4, souvenirs: ['b', 'a', 'b'] }).souvenirs).toEqual(['b', 'a']);
    expect(normalizeSave(sc, { ...v3, version: 4 }).souvenirs).toEqual([]);
    expect(normalizeSave(sc, { ...v3, version: 4, souvenirs: ['a', 3] })).toEqual(freshSave(sc));
    const s = composeSave(sc, { cash: 9, cars: ['m0_coupe'], car: 'm0_coupe', stamps: [], best: {}, plays: {}, souvenirs: ['s1', 's2'] });
    expect(normalizeSave(sc, JSON.parse(JSON.stringify(s)))).toEqual(s);
  });
});
