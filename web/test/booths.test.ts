import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { gzipSync } from 'node:zlib';

import { create, toBinary, type DescMessage, type MessageShape } from '@bufbuild/protobuf';
import { afterEach, beforeAll, describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { boothGames, boothHost, boothInReach, boothsOf, BoothWorld, nearBooths } from '../src/booths/booths';
import { boothsConfig, BoothsRules, type BoothsAction, type BoothsConfig } from '../src/booths/rules';
import { DriveWorld } from '../src/drive/driveWorld';
import {
  EdgeSchema, GraphSchema, LandmarksSchema, ManifestSchema, NodeSchema, RoadClass, SpawnSchema, SpotSchema, SpotsSchema,
} from '../src/gen/pb/citypack_pb';
import { minigameCatalog } from '../src/gen/ids';
import type { CarSpec, MinigameResult } from '../src/gen/schema';
import { Tuning } from '../src/gen/tuning';
import { LoopBook } from '../src/loop/logic';
import { overlays, PauseGate, pausingOverlays } from '../src/pause';
import { City } from '../src/world/model';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const car = JSON.parse(readFileSync(join(root, 'content', 'cars', 'm0_coupe.json'), 'utf8')) as CarSpec;

afterEach(() => overlays.clear());

const cfg: BoothsConfig = { booths: 3, gapMin: 2, gapMax: 4, retry: 2, ringS: 3, bonus: 150, games: ['a', 'b'] };
const tick = (near: number[]): BoothsAction => ({ by: 'player', op: 'tick', near });

/** Ticks with `near` until a booth rings (at most n ticks). */
function ringUp(r: BoothsRules, s: ReturnType<BoothsRules['init']>, near: number[], n = 50) {
  for (let i = 0; i < n && s.ringing < 0; i++) s = r.apply(s, tick(near));
  return s;
}

describe('booths rules (specs/booths.md)', () => {
  it('init: silence, a gap in [gapMin, gapMax], no offer', () => {
    const r = new BoothsRules();
    for (let seed = 0; seed < 40; seed++) {
      const s = r.init(cfg, seed);
      expect(s.ringing).toBe(-1);
      expect(s.next).toBeGreaterThanOrEqual(cfg.gapMin);
      expect(s.next).toBeLessThanOrEqual(cfg.gapMax);
      expect(s.offer).toEqual({ spot: '', bonus: 0 });
      expect([s.left, s.answered, s.missed, s.paid, s.last]).toEqual([0, 0, 0, 0, 0]);
    }
  });

  it('config from tuning', () => {
    const c = boothsConfig(tuning.booths, 5, ['x']);
    expect(c).toEqual({ booths: 5, gapMin: tuning.booths.gapMinS, gapMax: tuning.booths.gapMaxS, retry: tuning.booths.retryS,
      ringS: tuning.booths.ringS, bonus: tuning.booths.bonus, games: ['x'] });
  });

  it('empty near at the attempt retries; with near a booth from near rings for ringS', () => {
    const r = new BoothsRules();
    let s = r.init(cfg, 3);
    const n0 = s.next;
    for (let i = 0; i < n0; i++) s = r.apply(s, tick([]));
    expect(s.ringing).toBe(-1);
    expect(s.next).toBe(cfg.retry);
    s = ringUp(r, s, [1, 2]);
    expect([1, 2]).toContain(s.ringing);
    expect(s.left).toBe(cfg.ringS);
    for (let i = 0; i < cfg.ringS; i++) s = r.apply(s, tick([]));
    expect(s.ringing).toBe(-1);
    expect(s.missed).toBe(1);
  });

  it('no games: never rings', () => {
    const r = new BoothsRules();
    let s = r.init({ ...cfg, games: [] }, 9);
    for (let i = 0; i < 30; i++) s = r.apply(s, tick([0, 1, 2]));
    expect(s.ringing).toBe(-1);
  });

  it('answer: offer from games, bonus; illegal on a silent or another booth', () => {
    const r = new BoothsRules();
    let s = r.init(cfg, 12);
    expect(() => r.apply(s, { by: 'player', op: 'answer', booth: 0 })).toThrow();
    s = ringUp(r, s, [0, 1]);
    const other = s.ringing === 0 ? 1 : 0;
    expect(() => r.apply(s, { by: 'player', op: 'answer', booth: other })).toThrow();
    expect(r.legalActions(s).map((a) => a.op)).toEqual(['clear', 'tick', 'answer']);
    s = r.apply(s, { by: 'player', op: 'answer', booth: s.ringing });
    expect(cfg.games).toContain(s.offer.spot);
    expect(s.offer.bonus).toBe(cfg.bonus);
    expect([s.ringing, s.left, s.answered]).toEqual([-1, 0, 1]);
    expect(r.legalActions(s).map((a) => a.op)).toEqual(['clear', 'tick']);
  });

  it('finish: bonus only on the offered spot with 1★ and not aborted; last resets on the next action', () => {
    const r = new BoothsRules();
    let s = ringUp(r, r.init(cfg, 4), [2]);
    s = r.apply(s, { by: 'player', op: 'answer', booth: 2 });
    const spot = s.offer.spot;
    const other = spot === 'a' ? 'b' : 'a';
    s = r.apply(s, { by: 'player', op: 'finish', spot: other, stars: 3, aborted: false });
    expect([s.last, s.offer.spot]).toEqual([0, spot]);
    const zero = r.apply(s, { by: 'player', op: 'finish', spot, stars: 0, aborted: false });
    expect([zero.last, zero.paid, zero.offer.spot]).toEqual([0, 0, '']);
    const aborted = r.apply(s, { by: 'player', op: 'finish', spot, stars: 3, aborted: true });
    expect([aborted.last, aborted.offer.spot]).toEqual([0, '']);
    s = r.apply(s, { by: 'player', op: 'finish', spot, stars: 1, aborted: false });
    expect([s.last, s.paid, s.offer.spot]).toEqual([150, 150, '']);
    s = r.apply(s, { by: 'player', op: 'clear' });
    expect(s.last).toBe(0);
  });

  it('illegal: bad near, bad finish, unknown op, by ≠ player', () => {
    const r = new BoothsRules();
    const s = r.init(cfg, 1);
    for (const near of [[1, 0], [1, 1], [3], [-1], [0.5]]) expect(() => r.apply(s, tick(near))).toThrow();
    const bad = [
      { by: 'player', op: 'finish', spot: 'a', stars: 4, aborted: false },
      { by: 'player', op: 'finish', spot: 'a', stars: -1, aborted: false },
      { by: 'player', op: 'finish', spot: 'a', stars: 1, aborted: 'no' },
      { by: 'player', op: 'finish', spot: 7, stars: 1, aborted: false },
      { by: 'player', op: 'ring' },
      { by: 'ai', op: 'clear' },
    ];
    for (const a of bad) expect(() => r.apply(s, a as unknown as BoothsAction)).toThrow();
    expect(r.result(s)).toBeNull();
  });
});

// ---------- synthetic city: one straight road west–east, two minigame spots and three booths
const gz = <D extends DescMessage>(schema: D, m: MessageShape<D>): Uint8Array => new Uint8Array(gzipSync(toBinary(schema, m)));
const spot = (id: string, kind: string, x: number, minigame = '') =>
  create(SpotSchema, { id, kind, name: id, x: x * 10, y: 0, edge: 0, parkX: x * 10, parkY: 0, parkHeading: 0, minigame });
const spots = [
  spot('booth_w', 'booth', -300),
  spot('bar', 'bar', -100, 'oko'),
  spot('booth_c', 'booth', 100),
  spot('pier', 'pier', 200, 'sipky'),
  spot('booth_e', 'booth', 500),
];

async function boothCity(): Promise<City> {
  const files: Record<string, Uint8Array> = {
    'manifest.pb': gz(ManifestSchema, create(ManifestSchema, {
      formatVersion: 1, cityId: 'test', chunkM: 256, driveSide: 'right', units: 'metric',
      start: create(SpawnSchema, { x: 0, y: 0, headingRad: 0 }),
    })),
    'graph.pb': gz(GraphSchema, create(GraphSchema, {
      names: [''],
      nodes: [create(NodeSchema, { x: -8000, y: 0 }), create(NodeSchema, { x: 8000, y: 0 })],
      edges: [create(EdgeSchema, { from: 0, to: 1, points: [-8000, 0, 8000, 0], class: RoadClass.PRIMARY, lanes: 4, oneway: 0, kept: true, widthM: 42 })],
    })),
    'landmarks.pb': gz(LandmarksSchema, create(LandmarksSchema, {})),
    'spots.pb': gz(SpotsSchema, create(SpotsSchema, { items: spots })),
  };
  return City.load({
    read: async (p) => {
      const f = files[p];
      if (!f) throw new Error(p);
      return f;
    },
  });
}

describe('booths in the world (synthetic city)', () => {
  let city: City;
  beforeAll(async () => {
    city = await boothCity();
  });
  const b = tuning.booths;

  it('booths in spots.pb order; games = catalog minigame spots in order', () => {
    const booths = boothsOf(city.spots.items);
    expect(booths.map((x) => x.id)).toEqual(['booth_w', 'booth_c', 'booth_e']);
    expect(booths[1]).toMatchObject({ x: 100, y: 0 });
    expect(boothGames(city.spots.items, minigameCatalog)).toEqual(['bar', 'pier']);
  });

  it('near: ring_min_m ≤ d ≤ ring_max_m from the parking point, ascending', () => {
    const booths = boothsOf(city.spots.items);
    // From x = 0: booth_w 300 m, booth_c 100 m, booth_e 500 m.
    expect(nearBooths(booths, 0, 0, b.ringMinM, b.ringMaxM)).toEqual([0, 1]);
    // Standing next to booth_c (closer than ring_min_m): it is not near.
    expect(nearBooths(booths, 100 + b.ringMinM / 2, 0, b.ringMinM, b.ringMaxM)).not.toContain(1);
    expect(nearBooths(booths, 100 + b.ringMinM, 0, b.ringMinM, b.ringMaxM)).toContain(1);
    expect(nearBooths(booths, 100 + b.ringMaxM + 1, 0, b.ringMinM, b.ringMaxM)).not.toContain(1);
  });

  it('answer reach: the "Hrát" conditions (speed, layer 0, loop.spot_radius_m)', () => {
    const booth = boothsOf(city.spots.items)[1]!;
    const l = tuning.loop;
    expect(boothInReach(booth, 100 + l.spotRadiusM - 1, 0, 0, 0, l)).toBe(true);
    expect(boothInReach(booth, 100 + l.spotRadiusM + 1, 0, 0, 0, l)).toBe(false);
    expect(boothInReach(booth, 100, 0, l.stopSpeedMps + 0.1, 0, l)).toBe(false);
    expect(boothInReach(booth, 100, 0, 0, 1, l)).toBe(false);
  });

  it('host: characters[fnv1a(boothId) mod n] like the loop opponent', () => {
    expect(boothHost('east_village_bar', 6)).toBe(1);
    expect(boothHost('x', 0)).toBe(-1);
  });

  it('ticks once per game second; rings a near booth, toast event; picks up the offer', () => {
    const drive = new DriveWorld(city, car, tuning);
    drive.spawn(0, 0, 0);
    const booths = boothsOf(city.spots.items);
    const w = new BoothWorld(booths, tuning, boothGames(city.spots.items, minigameCatalog), 77);
    const rings: string[] = [];
    w.onRing.push((x) => rings.push(x.id));
    const near = () => nearBooths(booths, drive.car.x, drive.car.y, b.ringMinM, b.ringMaxM);
    const next0 = w.state.next;
    w.update(0.5, near);
    w.update(0.49, near);
    expect(w.state.next).toBe(next0);
    w.update(0.01 + 1e-9, near);
    expect(w.state.next).toBe(next0 - 1);
    for (let i = 0; i < 200 * 60 && !w.ringing; i++) w.update(1 / 60, near);
    expect(w.ringing).not.toBeNull();
    expect(['booth_w', 'booth_c']).toContain(w.ringing!.id);
    expect(rings).toEqual([w.ringing!.id]);
    expect(w.answer(w.state.ringing === 0 ? 1 : 0)).toBeNull();
    const offer = w.answer(w.state.ringing)!;
    expect(['bar', 'pier']).toContain(offer.spot);
    expect(offer.bonus).toBe(b.bonus);
    expect(w.ringing).toBeNull();
    w.clear();
    expect(w.offer).toBeNull();
  });

  it('suppressed (navigation, minigame, Taxi, wanted): near is empty, a ringing booth rings out', () => {
    const booths = boothsOf(city.spots.items);
    const w = new BoothWorld(booths, tuning, ['bar'], 5);
    for (let i = 0; i < 400 && !w.ringing; i++) w.update(1, () => []);
    expect(w.ringing).toBeNull();
    expect(w.state.next).toBeLessThanOrEqual(b.retryS);
    for (let i = 0; i < 400 && !w.ringing; i++) w.update(1, () => [1]);
    expect(w.ringing!.id).toBe('booth_c');
    w.update(b.ringS, () => []);
    expect(w.ringing).toBeNull();
    expect(w.state.missed).toBe(1);
  });

  it('pause: the booth offer card pauses; game dt 0 stops the booth clock', () => {
    expect(pausingOverlays).toContain('booth');
    const gate = new PauseGate(overlays);
    const w = new BoothWorld(boothsOf(city.spots.items), tuning, ['bar'], 8);
    const next0 = w.state.next;
    const release = overlays.open('booth');
    for (let i = 0; i < 300; i++) w.update(gate.frame(1 / 60, null), () => [0]);
    expect(w.state.next).toBe(next0);
    release();
    for (let i = 0; i < 60; i++) w.update(gate.frame(1 / 60, null), () => [0]);
    expect(w.state.next).toBe(next0 - 1);
  });

  it('bonus in the loop: finish after reward adds last to the cars-state cash and the outcome', () => {
    const w = new BoothWorld(boothsOf(city.spots.items), tuning, ['bar'], 21);
    for (let i = 0; i < 400 && !w.ringing; i++) w.update(1, () => [0]);
    const offer = w.answer(w.state.ringing)!;
    expect(offer.spot).toBe('bar');
    let cash = 1000;
    const book = new LoopBook(tuning, { getCash: () => cash, setCash: (c) => (cash = c), stamp: () => false });
    book.bonus = (spot, stars, aborted) => w.finish(spot, stars, aborted);
    const res = (stars: number, aborted = false): MinigameResult => ({ stars, score: 10, aborted } as MinigameResult);
    // Another spot first: no bonus, the offer stays.
    const o0 = book.finish({ spot: 'pier', minigame: 'sipky', engine: 'flick', result: res(3), driveDm: 0 }, () => false);
    expect(o0.booth).toBe(0);
    expect(w.offer?.spot).toBe('bar');
    const before = cash;
    const o = book.finish({ spot: 'bar', minigame: 'oko', engine: 'cards', result: res(1), driveDm: 0 }, () => false);
    expect(o.booth).toBe(b.bonus);
    expect(cash).toBe(before + o.cash.amount + b.bonus);
    expect(o.total).toBe(cash);
    expect(w.offer).toBeNull();
    expect(w.state.paid).toBe(b.bonus);
    // Aborted on the offered spot: no bonus, offer gone.
    for (let i = 0; i < 400 && !w.ringing; i++) w.update(1, () => [2]);
    w.answer(w.state.ringing);
    const o2 = book.finish({ spot: 'bar', minigame: 'oko', engine: 'cards', result: res(3, true), driveDm: 0 }, () => false);
    expect(o2.booth).toBe(0);
    expect(w.offer).toBeNull();
  });
});
