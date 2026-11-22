import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { beforeAll, describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { routeGraphFromPb } from '../src/drive/gps';
import { Tuning } from '../src/gen/tuning';
import { taxiConfig, taxiFare, TaxiRules, taxiStars, type TaxiState } from '../src/minigames/taxi/rules';
import { spawnPassenger, taxiDests, TaxiShift, type TaxiDest, type TaxiPose } from '../src/minigames/taxi/shift';
import { edgeLengthsDm } from '../src/phone/nav';
import { canonical, replayers, replayResult, type VectorFile } from '../src/rules/vectors';
import type { PackSource } from '../src/world/citypack';
import { City } from '../src/world/model';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const tt = tuning.minigames.taxi;
const cfg = taxiConfig(tt, ['a', 'b', 'c']);

describe('taxi rules (specs/minigames/taxi.md)', () => {
  it('fare: meter, time bonus capped, late penalty capped, tip minus hits', () => {
    // 2 km: meter = 6 + 20000 * 20 / 10000 = 46; expected 15 + 20000/70 = 300 s.
    const fast = taxiFare(cfg, 20000, 100_000, 0);
    expect(fast.meter).toBe(46);
    expect(fast.expectS).toBe(300);
    expect(fast.time).toBe(Math.floor((46 * tt.bonusMaxPct) / 100));
    expect(fast.tip).toBe(Math.floor((46 * tt.tipPct) / 100));
    const late = taxiFare(cfg, 20000, 310_999, 2);
    expect(late.rideS).toBe(310);
    expect(late.time).toBe(-10);
    expect(late.tip).toBe(Math.floor((46 * (tt.tipPct - 2 * tt.hitTipPct)) / 100));
    const crawl = taxiFare(cfg, 20000, 10_000_000, 99);
    expect(crawl.time).toBe(-Math.floor((46 * tt.lateMaxPct) / 100));
    expect(crawl.tip).toBe(0);
    expect(crawl.fare).toBeGreaterThanOrEqual(0);
  });

  it('stars from the fare thresholds', () => {
    const [s3, s2, s1] = tt.starFares as [number, number, number];
    expect([0, s1 - 1, s1, s2, s3 - 1, s3, s3 * 2].map((f) => taxiStars(cfg, f))).toEqual([0, 0, 1, 2, 2, 3, 3]);
  });

  it('pickup picks an allowed destination, never the last one twice, dropoff pays', () => {
    const r = new TaxiRules();
    let s: TaxiState = r.init(cfg, 5);
    s = r.apply(s, { by: 'player', op: 'pickup', atMs: 0, allow: ['b', 'c'] });
    expect(['b', 'c']).toContain(s.dest);
    expect(s.line).toBeGreaterThanOrEqual(0);
    expect(s.line).toBeLessThan(tt.lines);
    const first = s.dest;
    s = r.apply(s, { by: 'player', op: 'dropoff', atMs: 30_000, distDm: 5000 });
    expect(s.rides).toBe(1);
    expect(s.fare).toBe(s.last.fare);
    for (let i = 0; i < 10; i++) {
      s = r.apply(s, { by: 'player', op: 'pickup', atMs: s.clockMs, allow: ['b', 'c'] });
      expect(s.dest).not.toBe(i === 0 ? first : s.lastDest);
      s = r.apply(s, { by: 'player', op: 'dropoff', atMs: s.clockMs + 1000, distDm: 100 });
    }
  });

  it('rejects illegal actions', () => {
    const r = new TaxiRules();
    const s = r.init(cfg, 1);
    expect(() => r.apply(s, { by: 'player', op: 'dropoff', atMs: 1, distDm: 1 })).toThrow();
    expect(() => r.apply(s, { by: 'player', op: 'hit' })).toThrow();
    expect(() => r.apply(s, { by: 'player', op: 'pickup', atMs: 0, allow: ['nowhere'] })).toThrow();
    const ride = r.apply(s, { by: 'player', op: 'pickup', atMs: 50, allow: [] });
    expect(() => r.apply(ride, { by: 'player', op: 'dropoff', atMs: 10, distDm: 1 })).toThrow();
    expect(() => r.apply(ride, { by: 'player', op: 'dropoff', atMs: 60, distDm: -1 })).toThrow();
    const over = r.apply(ride, { by: 'timeout' });
    expect(r.result(over)).toEqual({ winner: 'draw', stars: 0, score: 0, rides: 0 });
    expect(() => r.apply(over, { by: 'timeout' })).toThrow();
    expect(r.result(s)).toBeNull();
  });

  // Ungated until parity.yaml marks F-027 done: replays the recording with this client.
  it('replays vectors/taxi.json', () => {
    const v = JSON.parse(readFileSync(join(root, 'vectors', 'taxi.json'), 'utf8')) as VectorFile;
    for (const c of v.cases) {
      const states = replayers['taxi']!(c);
      c.steps.forEach((s, i) => expect(canonical(states[i]), `${c.name} step ${i}`).toBe(canonical(s.state)));
      expect(canonical(replayResult('taxi', c) ?? null)).toBe(canonical(c.result));
    }
  });
});

const pack = join(root, 'build', 'packs', 'nyc');
const source: PackSource = { read: async (p) => new Uint8Array(readFileSync(join(pack, p))) };

describe.skipIf(!existsSync(pack))('a scripted taxi shift in NYC', () => {
  let city: City;
  let dests: TaxiDest[];
  beforeAll(async () => {
    city = await City.load(source);
    dests = taxiDests(city.graph, city.landmarks.items, tt.destSearchM);
  });

  it('destinations are hero landmarks with a road, by their real names', () => {
    const heroes = city.landmarks.items.filter((l) => l.hero);
    expect(dests.length).toBeGreaterThan(10);
    expect(dests.length).toBeLessThanOrEqual(heroes.length);
    for (const d of dests) expect(heroes.find((l) => l.id === d.id)?.name).toBe(d.name);
    expect(dests.map((d) => d.name)).toContain('Empire State Building');
  });

  it('teleports the car to passengers and destinations, then the shift ends with the rules result', () => {
    const stand = city.spots.items.find((s) => s.minigame === 'taxi')!;
    expect(stand).toBeDefined();
    const world = {
      graph: city.graph,
      route: routeGraphFromPb(city.graphPb, tuning.route.classCost),
      lensDm: edgeLengthsDm(city.graphPb),
      straightPct: tuning.feed.straightPct,
      searchM: tuning.nav.searchM,
    };
    const shift = new TaxiShift(world, tt, dests, 2024);
    const car: TaxiPose = { x: stand.parkX / 10, y: stand.parkY / 10, heading: stand.parkHeading, speed: 0, layer: 0 };
    const at = (x: number, y: number): void => {
      car.x = x;
      car.y = y;
    };
    const hit = () => city.graph.nearest(car.x, car.y, 30, (e) => e.isGround);
    const step = (s: number): ReturnType<TaxiShift['update']> => shift.update(s, car, hit());

    let paid = 0;
    let rides = 0;
    for (let ride = 0; ride < 3; ride++) {
      // A passenger appears at the curb near the car, the car drives there and stops.
      car.speed = 8;
      const ev = step(1);
      const p = shift.passenger!;
      expect(p, `passenger ${ride}`).not.toBeNull();
      if (ride === 0) expect(ev.map((e) => e.kind)).toEqual(['spawn']);
      const d0 = Math.hypot(p.x - car.x, p.y - car.y);
      expect(d0).toBeGreaterThanOrEqual(tt.pickupMinM - p.halfWidth - tt.curbM - 1);
      at(p.target.parkX / 10, p.target.parkY / 10);
      car.speed = 0;
      const up = step(5);
      const pick = up.find((e) => e.kind === 'pickup');
      expect(pick, `pickup ${ride}`).toBeDefined();
      if (pick?.kind !== 'pickup') return;
      expect(dests.map((d) => d.id)).toContain(pick.dest.id);
      expect(pick.distDm).toBeGreaterThan(0);
      // Crash once on the first ride: the tip goes down.
      if (ride === 0) shift.hit();
      // Drive (teleport) to the destination in 60 s, stop there.
      car.speed = 10;
      step(59);
      at(pick.dest.parkX / 10, pick.dest.parkY / 10);
      car.speed = 0;
      const down = step(1);
      const drop = down.find((e) => e.kind === 'dropoff');
      expect(drop, `dropoff ${ride}`).toBeDefined();
      if (drop?.kind !== 'dropoff') return;
      expect(drop.ride.dest).toBe(pick.dest.id);
      expect(drop.ride.rideS).toBe(60);
      expect(drop.ride.fare).toBe(taxiFare(taxiConfig(tt, []), pick.distDm, 60_000, ride === 0 ? 1 : 0).fare);
      paid += drop.ride.fare;
      rides++;
    }
    // The rest of the shift passes without a pickup; the timer ends it.
    car.speed = 12;
    let over = null;
    for (let i = 0; i < 1000 && !over; i++) {
      const ev = step(1);
      over = ev.find((e) => e.kind === 'over') ?? null;
    }
    expect(over).not.toBeNull();
    if (over?.kind !== 'over') return;
    expect(shift.over).toBe(true);
    expect(over.result.score).toBe(paid);
    expect(over.result.rides).toBe(rides);
    expect(over.result.stars).toBe(taxiStars(taxiConfig(tt, []), paid));
    expect(shift.clock).toBeGreaterThanOrEqual(tt.shiftS);
    // The action log replays to the same state with the pure rules alone.
    const r = new TaxiRules();
    let s = r.init(taxiConfig(tt, dests.map((d) => d.id)), 2024);
    for (const a of shift.log) s = r.apply(s, a);
    expect(canonical(s)).toBe(canonical(shift.state));
  });

  it('spawns a passenger near the taxi stand', () => {
    const stand = city.spots.items.find((s) => s.minigame === 'taxi')!;
    const p = spawnPassenger(city.graph, { x: stand.parkX / 10, y: stand.parkY / 10, heading: stand.parkHeading, speed: 0, layer: 0 }, tt);
    expect(p).not.toBeNull();
  });
});
