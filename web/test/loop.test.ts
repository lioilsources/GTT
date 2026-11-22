import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { carsConfig, CarsRules, type CarsState } from '../src/cars/rules';
import { minigameCatalog, carIdValues } from '../src/gen/ids';
import type { MinigameResult } from '../src/gen/schema';
import { Tuning } from '../src/gen/tuning';
import { EconomyRules, economyConfig } from '../src/loop/economy';
import { betterBest, LoopBook, loopDifficulty, nearestSpot, opponentIndex, spotInReach } from '../src/loop/logic';
import { composeSave, freshSave, normalizeSave, saveConfig } from '../src/loop/save';
import { MemorySaveStore } from '../src/loop/store';
import { aiPrng, type Action, type Rules, type RulesResult } from '../src/minigames/rules';
import { DamaRules, damaConfig } from '../src/minigames/dama/rules';
import { DesetitisicRules, desetitisicConfig } from '../src/minigames/desetitisic/rules';
import { KoulenaRules, koulenaConfig } from '../src/minigames/koulena/rules';
import { OkoRules, okoConfig } from '../src/minigames/oko/rules';
import { aiTarget, SipkyRules, sipkyConfig } from '../src/minigames/sipky/rules';
import { SirkyRules, sirkyConfig } from '../src/minigames/sirky/rules';
import { StrelniceRules, strelniceConfig } from '../src/minigames/strelnice/rules';
import { PassportTracker } from '../src/passport/tracker';
import { buildCandidates, feedConfig, FeedRules } from '../src/phone/feed';
import { canonical } from '../src/rules/vectors';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));

describe('economy (specs/economy.md)', () => {
  it('pays the feed card reward at three stars', () => {
    const r = new EconomyRules();
    r.init(economyConfig(tuning, 0));
    const driveDm = 26400;
    const card = tuning.feed.rewardBase + Math.floor((Math.floor(driveDm / tuning.feed.driveDmPerS) * tuning.feed.rewardPerMin) / 60);
    expect(r.reward({ engine: 'cards', stars: 3, score: 0, first: false, driveDm, aborted: false }).trip).toBe(card);
  });
});

describe('loop helpers (specs/loop.md)', () => {
  it('difficulty follows the card or the plays', () => {
    expect(loopDifficulty(4, 9, tuning.feed)).toBe(4);
    expect(loopDifficulty(null, 0, tuning.feed)).toBe(tuning.feed.difficultyBase);
    expect(loopDifficulty(null, 99, tuning.feed)).toBe(tuning.feed.difficultyMax);
  });
  it('picks the opponent by fnv1a of the spot', () => {
    // Same numbers in the Dart test (app/test/loop_test.dart).
    expect([opponentIndex('east_village_bar', 6), opponentIndex('pier_62', 6), opponentIndex('x', 0)]).toEqual([1, 0, -1]);
  });
  it('keeps the better best', () => {
    expect(betterBest(undefined, 0, 0)).toBe(true);
    expect(betterBest({ stars: 2, score: 10 }, 2, 11)).toBe(true);
    expect(betterBest({ stars: 2, score: 10 }, 1, 99)).toBe(false);
    expect(betterBest({ stars: 2, score: 10 }, 3, 0)).toBe(true);
  });
  it('finds a spot only while standing', () => {
    const spots = [{ id: 'a', minigame: 'dama', x: 0, y: 0 }, { id: 'g', minigame: '', x: 1, y: 1 }];
    expect(spotInReach(spots, 3, 4, 0, 0, tuning.loop)?.id).toBe('a');
    expect(spotInReach(spots, 3, 4, 10, 0, tuning.loop)).toBeNull();
    expect(spotInReach(spots, 3, 4, 0, 1, tuning.loop)).toBeNull();
    expect(nearestSpot(spots, 1, 1, 0.5)).toBeNull();
  });
});

// ---------- soak test, acceptance M1-A1 ("10 smyček za sebou bez pádu a bez zaseknutí")

type AnyRules = Rules<Record<string, unknown>, Action, RulesResult, unknown>;
const games: Record<string, () => { rules: AnyRules; config: unknown }> = {
  sirky: () => ({ rules: new SirkyRules() as unknown as AnyRules, config: sirkyConfig(tuning.minigames.sirky) }),
  oko: () => ({ rules: new OkoRules() as unknown as AnyRules, config: okoConfig(tuning.minigames.oko) }),
  dama: () => ({ rules: new DamaRules() as unknown as AnyRules, config: damaConfig(tuning.minigames.dama) }),
  desetitisic: () => ({ rules: new DesetitisicRules() as unknown as AnyRules, config: desetitisicConfig(tuning.minigames.desetitisic) }),
  sipky: () => ({ rules: new SipkyRules() as unknown as AnyRules, config: sipkyConfig(tuning.minigames.sipky) }),
  koulena: () => ({ rules: new KoulenaRules() as unknown as AnyRules, config: koulenaConfig(tuning.minigames.koulena) }),
  strelnice: () => ({ rules: new StrelniceRules() as unknown as AnyRules, config: strelniceConfig(tuning.minigames.strelnice) }),
};

/** Scripted play through the pure rules (specs/loop.md "Soak test"): the AI moves for both sides. */
function playOut(id: string, seed: number, level: number): RulesResult {
  const { rules, config } = games[id]!();
  const ai = aiPrng(seed);
  const me = aiPrng(seed ^ 0x1234);
  let s = rules.init(config, seed);
  for (let i = 0; i < 20000; i++) {
    const r = rules.result(s);
    if (r) return r;
    const legal = rules.legalActions(s);
    let a: Action;
    if (id === 'sipky') {
      a = s['turn'] === 'player' ? { by: 'player', ...aiTarget(s['player'] as number) } : rules.aiAction(s, level, ai);
    } else if (legal.length === 0) {
      a = rules.aiAction(s, level, ai);
    } else if (legal[0]!.by === 'ai') {
      a = rules.aiAction(s, level, ai);
    } else {
      const want = rules.aiAction(s, 5, me);
      a = legal.some((x) => canonical(x) === canonical(want)) ? want : legal[0]!;
    }
    s = rules.apply(s, a);
  }
  s = rules.apply(s, { by: 'timeout' });
  return rules.result(s)!;
}

const spots = Object.entries({
  east_village_bar: 'sirky', little_italy_club: 'oko', washington_square: 'dama', columbus_park: 'desetitisic',
  hells_kitchen_pub: 'sipky', pier_62: 'strelnice', seaport_boardwalk: 'koulena', penn_taxi_stand: 'taxi', midtown_garage: '',
}).map(([id, minigame], i) => ({ id, minigame, x: i * 1000, y: 500 }));

describe('soak: 10 loops in a row (M1-A1)', () => {
  it('stays consistent through feed → minigame → result → save → load', async () => {
    const prices: Record<string, number> = { hatch_pip: 6000, m0_coupe: 0, muscle_brute: 30000, pickup_hauler: 18000, taxi_metro: 15000 };
    const carsRules = new CarsRules();
    let cars: CarsState = carsRules.init(carsConfig(tuning.cars, prices), 0);
    const passport = new PassportTracker({ landmarks: [], districts: ['SoHo'], spotMinigames: spots.map((s) => s.minigame) }, tuning.passport);
    const book = new LoopBook(tuning, {
      getCash: () => cars.cash,
      setCash: (c) => (cars = { ...cars, cash: c }),
      stamp: (id, stars) => passport.minigame(id, stars),
    });
    const cfg = saveConfig(tuning, 'nyc', carIdValues);
    const store = new MemorySaveStore();
    const feed = new FeedRules();
    let prefs: Record<string, number> = {};
    const visits = new Map<string, number>();
    let paid = 0;
    const threeStar = new Set<string>();
    const bestSeen: Record<string, { stars: number; score: number }> = {};

    for (let loop = 0; loop < 10; loop++) {
      // Feed: deal, skip cards we cannot play here (taxi), accept the next one.
      const candidates = buildCandidates({
        cityId: 'nyc', spots, catalog: minigameCatalog, districtAt: () => '', landmarks: [], discovered: new Set(), visits,
        landmarkRadiusDm: tuning.feed.landmarkRadiusDm, distDm: (id) => 5000 + 700 * spots.findIndex((s) => s.id === id),
      });
      let deck = feed.init(feedConfig(tuning.feed, candidates, prefs, []), 100 + loop);
      while (!deck.over && !(deck.deck[deck.at]!.game in games)) deck = feed.apply(deck, { by: 'player', op: 'next' });
      expect(deck.over).toBe(false);
      deck = feed.apply(deck, { by: 'player', op: 'accept' });
      prefs = deck.prefs;
      const card = deck.deck.find((c) => c.spot === deck.accepted)!;
      // "Teleport" to the spot = arrived.
      visits.set(card.spot, (visits.get(card.spot) ?? 0) + 1);
      const spot = spots.find((s) => s.id === card.spot)!;
      const level = loopDifficulty(card.difficulty, book.plays[spot.id] ?? 0, tuning.feed);
      const aborted = loop === 4;
      const r = playOut(spot.minigame, 7 + loop * 31, level);
      const result: MinigameResult = aborted ? { stars: 0, score: 0, playedMs: 1, aborted: true } : { stars: r.stars, score: r.score, playedMs: 1000, aborted: false };
      const before = cars.cash;
      const o = book.finish(
        { spot: spot.id, minigame: spot.minigame, engine: minigameCatalog[spot.minigame as 'sirky'].engine, result, driveDm: card.distDm },
        (m) => passport.has('minigame', m),
      );
      expect(cars.cash - before).toBe(o.cash.amount);
      expect(o.cash.amount).toBe(o.cash.base + o.cash.trip + o.cash.band + o.cash.first);
      if (aborted) expect(o.cash.amount).toBe(0);
      paid += o.cash.amount;
      if (!aborted) {
        if (result.stars >= tuning.passport.starsForStamp) threeStar.add(spot.minigame);
        if (betterBest(bestSeen[spot.minigame], result.stars, result.score)) bestSeen[spot.minigame] = { stars: result.stars, score: result.score };
      }

      // Save → load round trip.
      const snap = composeSave(cfg, {
        cash: cars.cash, cars: cars.owned, car: cars.driving, stamps: passport.stamps, best: book.best, plays: book.plays,
        feed: { prefs, visits: Object.fromEntries(visits), districts: [] },
        npc: { vibe: { mia: loop }, contacts: [], recent: [] }, settings: { scheme: 'b', night: loop % 2 === 1 },
      });
      await store.write('nyc', snap);
      const loaded = normalizeSave(cfg, await store.read('nyc'));
      expect(canonical(loaded)).toBe(canonical(snap));
      // Load into fresh components and compose again: nothing may change.
      const cars2 = carsRules.init({ prices, cash: loaded.cash, owned: loaded.cars, driving: loaded.car }, 0);
      const passport2 = new PassportTracker({ landmarks: [], districts: ['SoHo'], spotMinigames: spots.map((s) => s.minigame) }, tuning.passport);
      passport2.restore(loaded.stamps);
      const book2 = new LoopBook(tuning, { getCash: () => cars2.cash, setCash: () => {}, stamp: () => false });
      book2.restore(loaded.best, loaded.plays);
      const again = composeSave(cfg, {
        cash: cars2.cash, cars: cars2.owned, car: cars2.driving, stamps: passport2.stamps, best: book2.best, plays: book2.plays,
        feed: loaded.feed, npc: loaded.npc, settings: loaded.settings,
      });
      expect(canonical(again)).toBe(canonical(snap));
    }

    expect(cars.cash).toBe(tuning.cars.startCash + paid);
    expect(passport.stamps.filter((s) => s.startsWith('minigame:')).sort()).toEqual([...threeStar].map((m) => `minigame:${m}`).sort());
    expect(canonical(book.best)).toBe(canonical(Object.fromEntries(Object.entries(bestSeen).sort(([a], [b]) => (a < b ? -1 : 1)))));
    expect(Object.values(book.plays).reduce((a, b) => a + b, 0)).toBe(9);
    expect(paid).toBeGreaterThan(0);
    expect(threeStar.size).toBeGreaterThan(0);
    // Buying a car with the earned cash goes through the cars rules.
    const cheapest = carsRules.buyable(cars)[0];
    if (cheapest) expect(carsRules.apply(cars, { by: 'player', op: 'buy', car: cheapest }).cash).toBe(cars.cash - prices[cheapest]!);
  });

  it('migrates a version-1 save and survives garbage', () => {
    const cfg = saveConfig(tuning, 'nyc', carIdValues);
    const v1 = { version: 1, cityId: 'nyc', cash: 90, stamps: ['minigame:oko'], cars: ['taxi_metro'], best: { oko: { stars: 3, score: 300 } } };
    const s = normalizeSave(cfg, v1);
    expect(s.version).toBe(2);
    expect([s.cash, s.cars, s.car, s.best['oko']?.stars]).toEqual([90, ['taxi_metro'], 'taxi_metro', 3]);
    expect(normalizeSave(cfg, '{')).toEqual(freshSave(cfg));
  });
});
