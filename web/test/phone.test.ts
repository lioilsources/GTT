import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { create } from '@bufbuild/protobuf';
import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { routeGraphFromPb } from '../src/drive/gps';
import { GraphSchema } from '../src/gen/pb/citypack_pb';
import { Tuning } from '../src/gen/tuning';
import { bandScore, buildCandidates, feedConfig, FeedRules, type FeedCandidate } from '../src/phone/feed';
import { driveMinutes, edgeArrow, edgeLengthsDm, feedDistDm, formatDistance, navGoal, navPath, navStart, Navigator } from '../src/phone/nav';
import { mapFit } from '../src/phone/mapView';
import {
  easeOutCubic, hintOpacity, lockAxis, releaseVelocity, sideRelease, stripOffset, tiltDeg, verticalRelease,
} from '../src/phone/feedView';
import { RoadGraph } from '../src/world/model';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));

const cand = (spot: string, engine: string, distDm: number, extra: Partial<FeedCandidate> = {}): FeedCandidate => ({
  spot, game: engine === 'drive' ? 'taxi' : 'dama', engine, local: false, district: '', distDm, visits: 0, landmark: false, ...extra,
});

describe('feed rules (specs/feed.md)', () => {
  const cfg = (cands: FeedCandidate[], deckSize = 6) => ({ ...feedConfig(tuning.feed, cands, {}, []), deckSize });

  it('scores the distance band with integer falloff', () => {
    const c = cfg([]);
    expect(bandScore(c, c.bandMinS - 1)).toBe(c.nearPoints);
    expect(bandScore(c, c.bandMinS)).toBe(c.bandPoints);
    expect(bandScore(c, c.bandMaxS)).toBe(c.bandPoints);
    expect(bandScore(c, c.bandMaxS + c.bandFalloffS / 2)).toBe(c.bandPoints / 2);
    expect(bandScore(c, c.bandMaxS + 10 * c.bandFalloffS)).toBe(0);
  });

  it('always deals a local game and a driving challenge when there are some', () => {
    const cands = [
      ...['a', 'b', 'c', 'd', 'e', 'f', 'g'].map((s) => cand(s, 'board', 11000)),
      cand('local', 'flick', 500000, { local: true, visits: 4 }),
      cand('drive', 'drive', 500000, { visits: 4 }),
    ];
    const s = new FeedRules().init(cfg(cands), 3);
    expect(s.deck).toHaveLength(6);
    expect(s.deck.map((c) => c.spot)).toContain('local');
    expect(s.deck.map((c) => c.spot)).toContain('drive');
    expect(s.deck.at(-1)!.score).toBeLessThanOrEqual(s.deck[0]!.score);
  });

  it('is deterministic for a seed and varies with it', () => {
    const cands = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'].map((s) => cand(s, 'board', 11000));
    const r = new FeedRules();
    expect(r.init(cfg(cands), 9)).toEqual(r.init(cfg(cands), 9));
    const orders = new Set([1, 2, 3, 4, 5].map((seed) => r.init(cfg(cands), seed).deck.map((c) => c.spot).join()));
    expect(orders.size).toBeGreaterThan(1);
  });

  it('handles actions and ends the deck without endless scrolling', () => {
    const r = new FeedRules();
    let s = r.init(cfg([cand('a', 'board', 9000), cand('b', 'dice', 9000)]), 1);
    expect(r.legalActions(s).map((a) => a.op)).toEqual(['next', 'like', 'less', 'accept']);
    s = r.apply(s, { by: 'player', op: 'like' });
    expect(r.legalActions(s).map((a) => a.op)).toEqual(['next', 'less', 'accept']);
    expect(() => r.apply(s, { by: 'player', op: 'like' })).toThrow();
    s = r.apply(s, { by: 'player', op: 'next' });
    expect(r.legalActions(s).map((a) => a.op)).toEqual(['next', 'prev', 'like', 'less', 'accept']);
    s = r.apply(s, { by: 'player', op: 'less' });
    expect(s.over).toBe(true);
    expect(() => r.apply(s, { by: 'player', op: 'prev' })).toThrow();
    expect(s.accepted).toBe('');
    expect(r.legalActions(s)).toEqual([]);
    expect(r.result()).toBeNull();
  });

  it('prev goes back without re-counting (v2), illegal on the first card', () => {
    const r = new FeedRules();
    const s0 = r.init(cfg([cand('a', 'board', 9000), cand('b', 'dice', 9000), cand('c', 'flick', 9000)]), 2);
    expect(r.legalActions(s0).map((a) => a.op)).not.toContain('prev');
    expect(() => r.apply(s0, { by: 'player', op: 'prev' })).toThrow();
    let s = r.apply(s0, { by: 'player', op: 'like' });
    const liked = s.deck[0]!.spot;
    s = r.apply(s, { by: 'player', op: 'less' });
    const prefs = { ...s.prefs };
    s = r.apply(s, { by: 'player', op: 'prev' });
    expect(s.at).toBe(0);
    expect(s.prefs).toEqual(prefs);
    expect(s.liked).toEqual([liked]);
    expect(r.legalActions(s).map((a) => a.op)).toEqual(['next', 'less', 'accept']);
    s = r.apply(s, { by: 'player', op: 'next' });
    expect(s.at).toBe(1);
    expect(s.prefs).toEqual(prefs);
    expect(s.over).toBe(false);
  });

  it('a one-card deck never allows prev', () => {
    const r = new FeedRules();
    const s = r.init(cfg([cand('a', 'board', 9000)]), 1);
    expect(r.legalActions(s).map((a) => a.op)).toEqual(['next', 'like', 'less', 'accept']);
    expect(r.apply(s, { by: 'player', op: 'next' }).over).toBe(true);
  });

  it('an empty city gives an empty, finished deck', () => {
    const s = new FeedRules().init(cfg([]), 1);
    expect(s.deck).toEqual([]);
    expect(s.over).toBe(true);
  });

  it('builds candidates with local flags and a challenge placeholder', () => {
    const base = {
      cityId: 'nyc',
      catalog: { koulena: { engine: 'flick', cities: ['nyc'] }, dama: { engine: 'board', cities: [] } },
      districtAt: (x: number) => (x < 0 ? 'West' : 'East'),
      landmarks: [{ id: 'l1', x: 100, y: 0 }],
      discovered: new Set<string>(),
      visits: new Map([['k', 2]]),
      landmarkRadiusDm: 200,
      distDm: () => 1234,
    };
    const out = buildCandidates({
      ...base,
      spots: [
        { id: 'k', minigame: 'koulena', x: 0, y: 0 },
        { id: 'd', minigame: 'dama', x: -500, y: 0 },
        { id: 'p', minigame: '', x: 50, y: 0 },
        { id: 'u', minigame: 'unknown', x: 0, y: 0 },
      ],
    });
    expect(out.map((c) => [c.spot, c.game, c.engine, c.local, c.district, c.visits, c.landmark])).toEqual([
      ['k', 'koulena', 'flick', true, 'East', 2, true],
      ['d', 'dama', 'board', false, 'West', 0, false],
      ['p', 'challenge', 'drive', false, 'East', 0, true],
    ]);
  });
});

// 0 —e0— 1 —e1 (one-way 1→2)— 2 —e2— 3, along the x axis every 100 m; e3 is an alley 1—3 off to the north.
function testGraph() {
  const pb = create(GraphSchema, {
    nodes: [0, 1000, 2000, 3000].map((x) => ({ x, y: 0 })),
    edges: [
      { from: 0, to: 1, points: [0, 0, 500, 0, 1000, 0], class: 3, oneway: 0, kept: true, widthM: 10 },
      { from: 1, to: 2, points: [1000, 0, 2000, 0], class: 3, oneway: 1, kept: true, widthM: 10 },
      { from: 2, to: 3, points: [2000, 0, 2500, 0, 3000, 0], class: 3, oneway: 0, kept: true, widthM: 10 },
      { from: 1, to: 3, points: [1000, 0, 2000, 800, 3000, 0], class: 7, oneway: 0, kept: false, widthM: 6 },
    ],
    names: [''],
  });
  return { pb, g: RoadGraph.fromPb(pb), rg: routeGraphFromPb(pb, tuning.route.classCost) };
}

describe('navigation (specs/phone.md "Navigace")', () => {
  const { pb, g, rg } = testGraph();
  const spot = { id: 's', name: 'Spot', edge: 2, parkX: 2800, parkY: 30 };

  it('starts at the end ahead of the car, respecting one-ways and skipping alleys', () => {
    const hit = g.nearest(30, 0, 10)!;
    expect(navStart(g, hit, 30, 0, 0, 60)!.node).toBe(1);
    expect(navStart(g, hit, 30, 0, Math.PI, 60)!.node).toBe(0);
    const one = g.nearest(150, 0, 5, (e) => e.index === 1)!;
    expect(navStart(g, one, 150, 0, Math.PI, 60)!.node).toBe(2);
    const alley = g.nearest(200, 80, 5)!;
    expect(alley.edge.kept).toBe(false);
    expect(navStart(g, alley, 200, 80, 0, 100)!.hit.edge.kept).toBe(true);
  });

  it('aims at the end of the spot edge nearer the parking point', () => {
    expect(navGoal(g, spot).node).toBe(3);
    expect(navGoal(g, { ...spot, parkX: 2100 }).node).toBe(2);
  });

  it('draws car → route → parking point and tracks progress to arrival', () => {
    const hit = g.nearest(30, 0, 10)!;
    const s = navStart(g, hit, 30, 0, 0, 60)!;
    const goal = navGoal(g, spot);
    const n = new Navigator(g, rg, tuning.route, tuning.nav);
    expect(n.start(spot, 30, 0, 0, hit)).toBe(true);
    // car → 50 → 100 → 200 → 250 → 300 → back along e2 to the projection 280 → park point.
    expect(n.path.filter((_, i) => i % 2 === 0)).toEqual([30, 50, 100, 200, 250, 300, 280, 280]);
    expect(navPath(g, s, { cost: 0, nodes: [1, 2, 3], edges: [1, 2] }, goal, 280, 3)).toEqual(n.path);
    expect(n.remaining).toBeCloseTo(270 + 20 + 3, 5);
    expect(n.update(120, 0, 0, g.nearest(120, 0, 10), 0.016)).toBeNull();
    expect(n.remaining).toBeCloseTo(180 + 20 + 3, 5);
    expect(n.update(275, 2, 0, g.nearest(275, 2, 10), 0.016)).toBe('arrived');
  });

  it('drives straight along the spot edge when the parking point is ahead', () => {
    const hit = g.nearest(210, 0, 10)!;
    const n = new Navigator(g, rg, tuning.route, tuning.nav);
    n.start(spot, 210, 0, 0, hit);
    expect(n.path.filter((_, i) => i % 2 === 0)).toEqual([210, 250, 280, 280]);
  });

  it('reroutes after staying off the route long enough', () => {
    const n = new Navigator(g, rg, tuning.route, tuning.nav);
    n.start(spot, 30, 0, 0, g.nearest(30, 0, 10));
    const far = tuning.route.rerouteM + 5;
    expect(n.update(60, far, 0, g.nearest(60, 0, 10), tuning.route.rerouteS / 2)).toBeNull();
    expect(n.update(60, far, 0, g.nearest(60, 0, 10), tuning.route.rerouteS)).toBe('rerouted');
  });

  it('measures feed distance over the route, or a stretched straight line', () => {
    const lens = edgeLengthsDm(pb);
    const hit = g.nearest(30, 0, 10)!;
    const s = navStart(g, hit, 30, 0, 0, 60);
    expect(feedDistDm(rg, lens, s, navGoal(g, spot), 30, 0, spot, 140)).toBe(2000);
    const back = navStart(g, g.nearest(250, 0, 10), 250, 0, 0, 60)!;
    const toWest = { ...spot, edge: 0, parkX: 400, parkY: 0 };
    // From node 3 the one-way blocks the way west: 3 → 2 only, then nothing.
    expect(feedDistDm(rg, lens, { ...back, node: 2 }, { ...navGoal(g, toWest), node: 1 }, 250, 0, toWest, 140)).toBe(Math.floor((2100 * 140) / 100));
  });

  it('formats distances by city units', () => {
    expect(formatDistance(234, false, tuning.nav)).toEqual({ key: 'distanceM', args: { m: 230 } });
    expect(formatDistance(1260, false, tuning.nav)).toEqual({ key: 'distanceKm', args: { km: '1.3' } });
    expect(formatDistance(100, true, tuning.nav)).toEqual({ key: 'distanceFt', args: { ft: 350 } });
    expect(formatDistance(3218.7, true, tuning.nav)).toEqual({ key: 'distanceMi', args: { mi: '2.0' } });
    expect([driveMinutes(0), driveMinutes(89), driveMinutes(90)]).toEqual([1, 1, 2]);
  });

  it('puts the edge arrow where the ray to the target leaves the screen', () => {
    expect(edgeArrow(100, 100, 400, 800, 20, 200, 576)).toBeNull();
    const a = edgeArrow(200, -1000, 400, 800, 20, 200, 576)!;
    expect(a.x).toBeCloseTo(200);
    expect(a.y).toBeCloseTo(20);
    expect(a.angle).toBeCloseTo(-Math.PI / 2);
    const b = edgeArrow(2000, 576, 400, 800, 20, 200, 576)!;
    expect([b.x, b.y]).toEqual([380, 576]);
  });

  it('fits the city into the map north up', () => {
    const f = mapFit([0, 0, 100, 0, 100, 200, 0, 200], 120, 220, 10);
    expect(f.s).toBe(1);
    expect([0 * f.s + f.ox, -0 * f.s + f.oy]).toEqual([10, 210]);
  });
});

describe('feed card gestures (specs/phone.md v5)', () => {
  const ph = tuning.phone;
  const H = 800;

  it('locks the axis only after feed_axis_lock_px, by the larger component', () => {
    const l = ph.feedAxisLockPx;
    expect(lockAxis(l - 1, -(l - 1), l)).toBeNull();
    expect(lockAxis(3, -l, l)).toBe('v');
    expect(lockAxis(l, l, l)).toBe('v');
    expect(lockAxis(-l - 1, l, l)).toBe('h');
  });

  it('measures release velocity over the last feed_velocity_ms', () => {
    const w = ph.feedVelocityMs;
    const s = [{ t: 0, p: 0 }, { t: 1000 - w - 1, p: -500 }, { t: 1000 - w, p: -100 }, { t: 1000, p: -200 }];
    expect(releaseVelocity(s, w)).toBeCloseTo((-100 * 1000) / w);
    expect(releaseVelocity([{ t: 5, p: 9 }], w)).toBe(0);
    expect(releaseVelocity([], w)).toBe(0);
  });

  it('follows the finger 1:1 towards a page and rubber-bands otherwise', () => {
    expect(stripOffset(-120, false, true, ph)).toBe(-120);
    expect(stripOffset(120, true, true, ph)).toBe(120);
    expect(stripOffset(120, false, true, ph)).toBeCloseTo(120 * ph.feedRubber);
    expect(stripOffset(-120, false, false, ph)).toBeCloseTo(-120 * ph.feedRubber);
  });

  it('commits a vertical release by distance or flick, else springs back', () => {
    const far = (H * ph.feedCommitPct) / 100 + 1;
    const near = (H * ph.feedCommitPct) / 100 - 1;
    expect(verticalRelease(-far, 0, H, true, true, ph)).toBe('next');
    expect(verticalRelease(far, 0, H, true, true, ph)).toBe('prev');
    expect(verticalRelease(-near, 0, H, true, true, ph)).toBeNull();
    expect(verticalRelease(-near, -(ph.feedFlickPxS + 1), H, true, true, ph)).toBe('next');
    expect(verticalRelease(-near, ph.feedFlickPxS + 1, H, true, true, ph)).toBeNull();
    // first card: no page above; feedDone: no page either way
    expect(verticalRelease(far, ph.feedFlickPxS + 1, H, false, true, ph)).toBeNull();
    expect(verticalRelease(-far, 0, H, false, false, ph)).toBeNull();
  });

  it('flies a card sideways past swipe_px or on a flick, with tilt and hint', () => {
    expect(sideRelease(ph.swipePx + 1, 0, ph)).toBe('accept');
    expect(sideRelease(-ph.swipePx - 1, 0, ph)).toBe('less');
    expect(sideRelease(ph.swipePx - 1, 0, ph)).toBeNull();
    expect(sideRelease(-5, -(ph.feedFlickPxS + 1), ph)).toBe('less');
    expect(sideRelease(5, -(ph.feedFlickPxS + 1), ph)).toBeNull();
    expect(tiltDeg(400, 400, ph)).toBeCloseTo(ph.feedTiltDeg);
    expect(tiltDeg(-200, 400, ph)).toBeCloseTo(-ph.feedTiltDeg / 2);
    expect(hintOpacity(ph.swipePx / 2, ph)).toBeCloseTo(0.5);
    expect(hintOpacity(-3 * ph.swipePx, ph)).toBe(1);
  });

  it('eases out without overshoot', () => {
    expect(easeOutCubic(0)).toBe(0);
    expect(easeOutCubic(1)).toBe(1);
    for (let u = 0; u <= 1; u += 0.05) expect(easeOutCubic(u)).toBeLessThanOrEqual(1);
    expect(easeOutCubic(0.5)).toBeGreaterThan(0.5);
  });
});
