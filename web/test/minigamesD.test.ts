import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { beforeAll, describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { routeGraphFromPb } from '../src/drive/gps';
import { Tuning } from '../src/gen/tuning';
import { driftConfig, DriftRules, driftThresholds, type DriftState } from '../src/minigames/drift/rules';
import { DriftSession, slipMrad } from '../src/minigames/drift/session';
import { beatGap, beatTimes, DoubledutchRules, doubledutchConfig, doubledutchMax, type DoubledutchState } from '../src/minigames/doubledutch/rules';
import { inputErr } from '../src/minigames/doubledutch/game';
import { aiPrng } from '../src/minigames/rules';
import { sprintConfig, sprintPar, SprintRules, sprintStars, type SprintState } from '../src/minigames/sprint/rules';
import { SprintRace, sprintPlan, sprintRoute } from '../src/minigames/sprint/race';
import { StickballRules, stickballConfig, swingGrade, type StickballState } from '../src/minigames/stickball/rules';
import { laneAt } from '../src/minigames/stickball/game';
import { taxiDests, type TaxiDest } from '../src/minigames/taxi/shift';
import { edgeLengthsDm } from '../src/phone/nav';
import { canonical } from '../src/rules/vectors';
import type { PackSource } from '../src/world/citypack';
import { City } from '../src/world/model';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const tm = tuning.minigames;

describe('drift rules (specs/minigames/drift.md)', () => {
  const cfg = driftConfig(tm.drift, 3);
  const fresh = (): { r: DriftRules; s: DriftState } => {
    const r = new DriftRules();
    return { r, s: r.init(cfg) };
  };
  const sample = (atMs: number, slipMrad: number, speedCms: number, inZone = true) =>
    ({ by: 'player', op: 'sample', atMs, slipMrad, speedCms, inZone }) as const;

  it('scores a drift sample by clipped dt, capped slip and speed; multiplier grows with chain time', () => {
    const { r, s } = fresh();
    // First sample: dt = atMs capped at maxDtMs.
    const a = r.apply(s, sample(1000, 900, 3000));
    const pts = Math.floor((Math.floor((cfg.maxDtMs * cfg.maxSlipMrad) / 1000) * cfg.maxSpeedCms) / cfg.ptsDiv);
    expect(a.chain).toBe(pts);
    expect(a.chainMs).toBe(cfg.maxDtMs);
    expect(a.lastDriftMs).toBe(1000);
    let b = a;
    for (let t = 1100; b.mult < cfg.maxMult; t += 100) b = r.apply(b, sample(t, 500, 1500));
    expect(b.mult).toBe(cfg.maxMult);
    // Far past maxMult the multiplier stays capped.
    for (let i = 0; i < 200; i++) b = r.apply(b, sample(b.clockMs + 100, 500, 1500));
    expect(b.mult).toBe(cfg.maxMult);
  });

  it('banks after graceMs without drifting, loses the chain to a hit', () => {
    const { r, s } = fresh();
    let a = r.apply(s, sample(100, 500, 1500));
    const chain = a.chain;
    a = r.apply(a, sample(100 + cfg.graceMs, 0, 1500));
    expect(a.chain).toBe(chain);
    a = r.apply(a, sample(101 + cfg.graceMs, 0, 1500));
    expect(a.chain).toBe(0);
    expect(a.score).toBe(chain);
    expect(a.drifts).toBe(1);
    expect(a.best).toBe(chain);
    a = r.apply(a, sample(a.clockMs + 100, 500, 1500));
    a = r.apply(a, { by: 'player', op: 'hit', atMs: a.clockMs + 10 });
    expect(a.chain).toBe(0);
    expect(a.hits).toBe(1);
    expect(a.score).toBe(chain);
  });

  it('leaving the zone ends the drift; timeout banks the open chain', () => {
    const { r, s } = fresh();
    let a = r.apply(s, sample(100, 500, 1500));
    a = r.apply(a, sample(200, 500, 1500, false));
    expect(a.lastDriftMs).toBe(100);
    a = r.apply(a, { by: 'timeout' });
    expect(a.phase).toBe('over');
    expect(a.score).toBeGreaterThan(0);
    expect(r.result(a)?.drifts).toBe(1);
  });

  it('stars by level thresholds; illegal actions throw', () => {
    const { r, s } = fresh();
    const t = driftThresholds(cfg);
    expect(t).toEqual(cfg.starScores);
    const end = (score: number) => r.result({ ...s, score, phase: 'over' })!;
    expect([t[0]!, t[1]!, t[2]!, t[2]! - 1].map((x) => end(x).stars)).toEqual([3, 2, 1, 0]);
    expect(end(0).winner).toBe('draw');
    expect(driftThresholds(driftConfig(tm.drift, 1))[0]).toBe(Math.floor((cfg.starScores[0]! * cfg.levelPct[0]!) / 100));
    const a = r.apply(s, sample(500, 0, 0));
    expect(() => r.apply(a, sample(400, 0, 0))).toThrow();
    expect(() => r.apply(a, sample(600, -1, 0))).toThrow();
    expect(() => r.apply(a, { by: 'player', op: 'hit', atMs: 1 })).toThrow();
    expect(() => r.aiAction(a, 1, aiPrng(1))).toThrow();
    expect(() => r.apply(r.apply(a, { by: 'timeout' }), { by: 'timeout' })).toThrow();
  });

  it('session: samples at sample_hz in drive time, β from heading and velocity, zone ring', () => {
    expect(slipMrad({ x: 0, y: 0, heading: 0, vx: 10, vy: 10, layer: 0 })).toBe(Math.floor((Math.PI / 4) * 1000));
    expect(slipMrad({ x: 0, y: 0, heading: 0, vx: 0.3, vy: 0.3, layer: 0 })).toBe(0);
    const ses = new DriftSession(tm.drift, 3, 0, 0);
    const car = { x: 0, y: 0, heading: 0, vx: 15, vy: 10, layer: 0 };
    for (let i = 0; i < 60; i++) ses.update(1 / 60, car);
    const samples = ses.log.filter((a) => a.by === 'player' && a.op === 'sample');
    expect(samples.length).toBeGreaterThanOrEqual(tm.drift.sampleHz - 1);
    expect(samples.length).toBeLessThanOrEqual(tm.drift.sampleHz);
    expect(ses.state.chain).toBeGreaterThan(0);
    car.x = tm.drift.zoneM + 1;
    for (let i = 0; i < 60; i++) ses.update(1 / 60, car);
    expect(ses.inZone).toBe(false);
    expect(ses.state.score).toBeGreaterThan(0);
    let over = false;
    for (let i = 0; i < 100 * 60 && !over; i++) over = ses.update(1 / 60, car).some((e) => e.kind === 'over');
    expect(over).toBe(true);
    const r = new DriftRules();
    let s = r.init(driftConfig(tm.drift, 3));
    for (const a of ses.log) s = r.apply(s, a);
    expect(canonical(s)).toBe(canonical(ses.state));
  });
});

describe('sprint rules (specs/minigames/sprint.md)', () => {
  const cfg = sprintConfig(tm.sprint, ['a', 'b', 'c'], 3);
  const go = (r: SprintRules, s: SprintState, distDm: number, cps: number): SprintState => {
    const p = r.apply(s, { by: 'player', op: 'pick', allow: [] });
    return r.apply(p, { by: 'player', op: 'go', atMs: 3000, distDm, cps });
  };

  it('pick from allow (empty = all), empty pool ends without a destination', () => {
    const r = new SprintRules();
    const s = r.init(cfg, 9);
    for (let seed = 0; seed < 20; seed++) {
      const p = r.apply(r.init(cfg, seed), { by: 'player', op: 'pick', allow: ['c'] });
      expect(p.dest).toBe('c');
      expect(p.phase).toBe('ready');
    }
    expect(['a', 'b', 'c']).toContain(r.apply(s, { by: 'player', op: 'pick', allow: [] }).dest);
    const r0 = new SprintRules();
    const e = r0.apply(r0.init(sprintConfig(tm.sprint, [], 3), 1), { by: 'player', op: 'pick', allow: [] });
    expect(e.phase).toBe('over');
    expect(r0.result(e)).toMatchObject({ stars: 0, score: 0, dest: '' });
    expect(() => r.apply(s, { by: 'player', op: 'pick', allow: ['x'] })).toThrow();
  });

  it('checkpoints in order, finish after the last, hits add time, stars against par', () => {
    const r = new SprintRules();
    let s = go(r, r.init(cfg, 1), 20000, 2);
    expect(s.parMs).toBe(sprintPar(cfg, 20000));
    expect(() => r.apply(s, { by: 'player', op: 'cp', atMs: 4000, index: 1 })).toThrow();
    expect(() => r.apply(s, { by: 'player', op: 'finish', atMs: 4000 })).toThrow();
    s = r.apply(s, { by: 'player', op: 'cp', atMs: 10000, index: 0 });
    s = r.apply(s, { by: 'player', op: 'hit', atMs: 11000 });
    s = r.apply(s, { by: 'player', op: 'cp', atMs: 20000, index: 1 });
    expect(s.splits).toEqual([7000, 17000]);
    s = r.apply(s, { by: 'player', op: 'finish', atMs: 30000 });
    expect(s.timeMs).toBe(27000 + cfg.hitPenaltyMs);
    const res = r.result(s)!;
    expect(res.stars).toBe(sprintStars(cfg, s.timeMs, s.parMs));
    expect(res.score).toBe(Math.floor(Math.max(0, 2 * s.parMs - s.timeMs) / 100));
    const par = 10000;
    expect([par, par + 1, Math.floor((par * 120) / 100), Math.floor((par * 145) / 100), Math.floor((par * 145) / 100) + 1].map((tms) => sprintStars(cfg, tms, par))).toEqual([3, 2, 2, 1, 0]);
  });

  it('cps = 0 finishes straight away; timeout in any phase gives 0 stars', () => {
    const r = new SprintRules();
    const s = go(r, r.init(cfg, 1), 100, 0);
    expect(r.legalActions(s).map((a) => (a.by === 'player' ? a.op : a.by))).toEqual(['hit', 'finish', 'timeout']);
    const f = r.apply(s, { by: 'player', op: 'finish', atMs: 3500 });
    expect(r.result(f)!.stars).toBe(3);
    for (const st of [r.init(cfg, 1), r.apply(r.init(cfg, 1), { by: 'player', op: 'pick', allow: [] }), s]) {
      expect(r.result(r.apply(st, { by: 'timeout' }))).toMatchObject({ stars: 0, score: 0, winner: 'draw' });
    }
    expect(() => r.aiAction(s, 1, aiPrng(1))).toThrow();
  });
});

describe('stickball rules (specs/minigames/stickball.md)', () => {
  const cfg = stickballConfig(tm.stickball, 3);
  const pitch = (r: StickballRules, s: StickballState, zone: boolean, lane: number): StickballState =>
    r.apply(s, { by: 'ai', op: 'pitch', zone, lane, flightMs: 700 });
  const swing = (r: StickballRules, s: StickballState, lane: number, errMs: number): StickballState =>
    r.apply(s, { by: 'player', op: 'swing', lane, errMs });

  it('grades swings by timing, lane distance and zone', () => {
    expect([0, cfg.perfectMs, cfg.goodMs, cfg.okMs, cfg.foulMs, cfg.foulMs + 1].map((e) => swingGrade(cfg, -e))).toEqual([3, 3, 2, 1, 0, -1]);
    const r = new StickballRules();
    const s = r.init(cfg, 1);
    expect(swing(r, pitch(r, s, true, 1), 1, 0).last).toBe('homer');
    expect(swing(r, pitch(r, s, false, 1), 1, 0).last).toBe('double');
    expect(swing(r, pitch(r, s, true, 2), 1, 0).last).toBe('double');
    expect(swing(r, pitch(r, s, true, 2), 0, 0).last).toBe('single');
    expect(swing(r, pitch(r, s, true, 2), 0, cfg.goodMs).last).toBe('foul');
    expect(swing(r, pitch(r, s, true, 2), 0, cfg.foulMs).last).toBe('strike');
  });

  it('bases: homer clears the bases, walk forces runners, foul with two strikes keeps the count', () => {
    const r = new StickballRules();
    const s = r.init(cfg, 1);
    const loaded = { ...s, bases: 7 };
    const gs = swing(r, pitch(r, loaded, true, 0), 0, 0);
    expect(gs.runs).toBe(4);
    expect(gs.bases).toBe(0);
    expect(gs.homers).toBe(1);
    let w = { ...loaded, balls: cfg.ballsWalk - 1 };
    w = r.apply(pitch(r, w, false, 0), { by: 'player', op: 'take' });
    expect(w.last).toBe('walk');
    expect(w.runs).toBe(1);
    expect(w.bases).toBe(7);
    let w2 = { ...s, bases: 2 | 4, balls: cfg.ballsWalk - 1 };
    w2 = r.apply(pitch(r, w2, false, 0), { by: 'player', op: 'take' });
    expect(w2.bases).toBe(7);
    expect(w2.runs).toBe(0);
    const two = { ...s, strikes: cfg.strikesOut - 1 };
    const f = swing(r, pitch(r, two, true, 0), 0, cfg.foulMs);
    expect(f.last).toBe('foul');
    expect(f.strikes).toBe(cfg.strikesOut - 1);
    const k = r.apply(pitch(r, two, true, 0), { by: 'player', op: 'take' });
    expect(k.last).toBe('strikeout');
    expect(k.outs).toBe(1);
    expect(k.strikes).toBe(0);
    const d = swing(r, pitch(r, { ...s, bases: 1 }, true, 1), 1, cfg.goodMs);
    expect(d.bases).toBe(2 | 4);
  });

  it('a grade-1 hit rolls the catch; maxOuts ends the game; the AI draws zone, lane, flight', () => {
    const r = new StickballRules();
    const s = r.init(cfg, 1);
    const kinds = new Set<string>();
    for (let seed = 1; seed < 60; seed++) {
      const x = swing(r, pitch(r, r.init(cfg, seed), true, 1), 1, cfg.okMs);
      kinds.add(x.last);
      expect(x.rng).not.toBe(r.init(cfg, seed).rng);
    }
    expect([...kinds].sort()).toEqual(['catch', 'single']);
    const last = r.apply(pitch(r, { ...s, outs: cfg.maxOuts - 1, strikes: cfg.strikesOut - 1 }, true, 0), { by: 'player', op: 'take' });
    expect(last.phase).toBe('over');
    expect(r.result(last)).toMatchObject({ stars: 0, winner: 'ai' });
    const ai = aiPrng(7);
    const a = r.aiAction(s, 2, ai);
    expect(a.by).toBe('ai');
    if (a.by === 'ai') {
      expect(a.flightMs).toBeGreaterThanOrEqual(cfg.flightMin[1]!);
      expect(a.flightMs).toBeLessThanOrEqual(cfg.flightMin[1]! + cfg.flightVar[1]!);
    }
    expect(() => r.apply(s, { by: 'player', op: 'take' })).toThrow();
    expect(laneAt(0, 100)).toBe(2);
    expect(laneAt(99, 100)).toBe(0);
  });
});

describe('doubledutch rules (specs/minigames/doubledutch.md)', () => {
  const cfg = doubledutchConfig(tm.doubledutch, 3);

  it('chart: intro beats plain, one draw per later beat even at trickPct 0', () => {
    const r = new DoubledutchRules();
    const s = r.init(cfg, 5);
    expect(s.kinds.slice(0, cfg.introBeats).every((k) => k === 0)).toBe(true);
    expect(s.kinds.length).toBe(cfg.beats);
    const l1 = r.init(doubledutchConfig(tm.doubledutch, 1), 5);
    expect(l1.kinds.every((k) => k === 0)).toBe(true);
    expect(l1.rng).toBe(s.rng);
  });

  it('judges hits, combo multiplier, wrong input and late input are trips', () => {
    const r = new DoubledutchRules();
    let s: DoubledutchState = { ...r.init(cfg, 5), kinds: new Array(cfg.beats).fill(0) };
    s = r.apply(s, { by: 'player', op: 'hit', input: 0, errMs: -cfg.perfectMs });
    s = r.apply(s, { by: 'player', op: 'hit', input: 0, errMs: cfg.goodMs });
    s = r.apply(s, { by: 'player', op: 'hit', input: 0, errMs: cfg.okMs });
    expect([s.perfect, s.good, s.ok, s.score]).toEqual([1, 1, 1, cfg.perfectPts + cfg.goodPts + cfg.okPts]);
    s = r.apply(s, { by: 'player', op: 'hit', input: 1, errMs: 0 });
    expect(s.trips).toBe(1);
    expect(s.combo).toBe(0);
    s = r.apply(s, { by: 'player', op: 'hit', input: 0, errMs: cfg.okMs + 1 });
    expect(s.trips).toBe(2);
    s = r.apply(s, { by: 'player', op: 'miss' });
    expect(s.over).toBe(true);
    expect(s.misses).toBe(3);
    expect(() => r.apply(s, { by: 'player', op: 'miss' })).toThrow();
    const m = r.init(cfg, 1);
    expect(() => r.apply(m, { by: 'player', op: 'hit', input: 2, errMs: 0 })).toThrow();
    expect(() => r.aiAction(m, 1, aiPrng(1))).toThrow();
  });

  it('all perfect = maxScore = 100 %; beat gaps shrink to the minimum', () => {
    const r = new DoubledutchRules();
    let s = r.init(cfg, 3);
    while (!s.over) s = r.apply(s, { by: 'player', op: 'hit', input: s.kinds[s.next]!, errMs: 0 });
    expect(s.score).toBe(doubledutchMax(cfg, s.kinds));
    expect(r.result(s)).toMatchObject({ stars: 3, pct: 100, bestCombo: cfg.beats, winner: 'player' });
    expect(beatGap(cfg, 1)).toBe(cfg.startGapMs[2]);
    expect(beatGap(cfg, 10_000)).toBe(cfg.minGapMs[2]);
    const times = beatTimes(cfg, 1500);
    expect(times[0]).toBe(1500);
    expect(times[1]).toBe(1500 + beatGap(cfg, 1));
    expect(inputErr(times, 0, 1500 - cfg.okMs - 1, cfg.okMs)).toBeNull();
    expect(inputErr(times, 0, 1500 - cfg.okMs, cfg.okMs)).toBe(-cfg.okMs);
    expect(inputErr(times, 0, 1600.7, cfg.okMs)).toBe(100);
  });
});

const pack = join(root, 'build', 'packs', 'nyc');
const source: PackSource = { read: async (p) => new Uint8Array(readFileSync(join(pack, p))) };

describe.skipIf(!existsSync(pack))('a scripted sprint in NYC', () => {
  let city: City;
  let dests: TaxiDest[];
  beforeAll(async () => {
    city = await City.load(source);
    dests = taxiDests(city.graph, city.landmarks.items, tm.sprint.destSearchM);
  });

  it('picks a destination in range, plans gates along the route and finishes through them', () => {
    const spot = city.spots.items.find((s) => s.minigame === 'sprint')!;
    expect(spot).toBeDefined();
    const world = { graph: city.graph, route: routeGraphFromPb(city.graphPb, tuning.route.classCost), lensDm: edgeLengthsDm(city.graphPb), searchM: tuning.nav.searchM };
    const race = new SprintRace(world, tm.sprint, dests, 3, 77);
    const start = { hit: null, x: spot.parkX / 10, y: spot.parkY / 10, heading: spot.parkHeading };
    const ev = race.begin(start);
    expect(ev.map((e) => e.kind)).toEqual(['picked']);
    const p = race.plan!;
    const air = Math.hypot(p.dest.parkX / 10 - start.x, p.dest.parkY / 10 - start.y);
    expect(air).toBeGreaterThanOrEqual(tm.sprint.destMinM);
    expect(air).toBeLessThanOrEqual(tm.sprint.destMaxM);
    expect(p.distDm).toBeGreaterThan(0);
    const every = tm.sprint.cpEveryM * 10;
    p.gates.forEach((g, i) => {
      expect(g.atDm).toBeGreaterThanOrEqual((i + 1) * every);
      expect((p.distDm - g.atDm) * 2).toBeGreaterThan(every);
    });
    expect(p.gates.length).toBeGreaterThan(0);
    expect(sprintPlan(world, tm.sprint, p.dest, sprintRoute(world, start, p.dest)!).gates.length).toBe(p.gates.length);
    const car = { x: start.x, y: start.y, heading: start.heading, layer: 0 };
    // Countdown, then go.
    let kinds: string[] = [];
    for (let i = 0; i < 4 * 60 && race.state.phase === 'ready'; i++) kinds.push(...race.update(1 / 60, car).map((e) => e.kind));
    expect(kinds).toEqual(['go']);
    expect(race.state.cps).toBe(p.gates.length);
    // Teleport through every gate, then onto the finish.
    kinds = [];
    for (const g of [...p.gates, p.finish]) {
      race.update(5, car);
      car.x = g.x;
      car.y = g.y;
      kinds.push(...race.update(0.1, car).map((e) => e.kind));
    }
    expect(kinds).toEqual([...p.gates.map(() => 'cp'), 'over']);
    expect(race.state.finished).toBe(true);
    const r = new SprintRules();
    let s = r.init(sprintConfig(tm.sprint, dests.map((d) => d.id), 3), 77);
    for (const a of race.log) s = r.apply(s, a);
    expect(canonical(s)).toBe(canonical(race.state));
  });
});
