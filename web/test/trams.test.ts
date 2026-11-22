import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { create } from '@bufbuild/protobuf';
import { World } from 'planck';
import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { Car } from '../src/drive/car';
import { DriveWorld } from '../src/drive/driveWorld';
import { EdgeSchema, GraphSchema, NodeSchema, RoadClass, TramEdgeSchema, TramGraphSchema, TramStopSchema } from '../src/gen/pb/citypack_pb';
import type { CarSpec } from '../src/gen/schema';
import { Tuning } from '../src/gen/tuning';
import { Prng } from '../src/rules/prng';
import { Traffic } from '../src/traffic/traffic';
import { articulate, chooseNextTrack, nextStopAhead, Trail } from '../src/trams/trackRules';
import { Trams } from '../src/trams/trams';
import type { PackSource } from '../src/world/citypack';
import { City, RoadGraph, TrackGraph } from '../src/world/model';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const t = tuning.trams;
const spec = JSON.parse(readFileSync(join(root, 'content', 'cars', 'm0_coupe.json'), 'utf8')) as CarSpec;
const dt = 1 / tuning.drive.stepHz;

const node = (x: number, y: number, border = false) => create(NodeSchema, { x: x * 10, y: y * 10, border });
const track = (from: number, to: number, pts: number[]) => create(TramEdgeSchema, { from, to, points: pts.map((v) => v * 10) });
const stop = (edge: number, sM: number) => create(TramStopSchema, { edge, sM });

/**
 * Tiny track graph (metres). The same graph and expected values belong in the Dart test of F-030.
 *
 *                 3 (100,100) terminus
 *                 | e2 3→1
 *  0 ──e0── 1 (100,0) ──e1── 2 (200,0) border
 *  (0,0)      \ e3 1→4 (150,-80)      e4: loop at 1
 */
function junction(): TrackGraph {
  return TrackGraph.fromPb(create(TramGraphSchema, {
    nodes: [node(0, 0), node(100, 0), node(200, 0, true), node(100, 100), node(150, -80)],
    edges: [
      track(0, 1, [0, 0, 100, 0]),
      track(1, 2, [100, 0, 200, 0]),
      track(3, 1, [100, 100, 100, 0]),
      track(1, 4, [100, 0, 150, -80]),
      track(1, 1, [100, 0, 120, 20, 80, 20, 100, 0]),
    ],
  }));
}

/** One straight track 0 → 1 of `len` metres along +x, with stops at the given s. */
function line(len: number, stops: number[] = []): TrackGraph {
  return TrackGraph.fromPb(create(TramGraphSchema, {
    nodes: [node(0, 0), node(len, 0)],
    edges: [track(0, 1, [0, 0, len / 2, 0, len, 0])],
    stops: stops.map((s) => stop(0, s)),
  }));
}

/** One fixed step of trams (and optionally traffic) around a player that does not drive itself. */
function step(world: World, player: Car, trams: Trams | null, traffic: Traffic | null = null): void {
  traffic?.preStep(dt, player);
  trams?.preStep(dt, player);
  world.step(dt, tuning.drive.velocityIterations, tuning.drive.positionIterations);
  traffic?.postStep(player);
  trams?.postStep(player);
}

describe('tram rules (specs/trams.md)', () => {
  it('chooses the next track edge with the shared PRNG, never a loop', () => {
    const g = junction();
    const rng = new Prng(42);
    expect(Array.from({ length: 12 }, () => chooseNextTrack(g, 1, 0, rng))).toEqual(PICKS_42);
    const r7 = new Prng(7);
    expect(Array.from({ length: 6 }, () => chooseNextTrack(g, 1, 3, r7))).toEqual(PICKS_7);
    expect(chooseNextTrack(g, 3, 2, new Prng(1))).toBe(2); // terminus: turn back
    expect(chooseNextTrack(g, 0, 0, new Prng(1))).toBe(0);
    expect(chooseNextTrack(g, 2, 1, new Prng(1))).toBe(-1); // border node: the tram disappears
  });

  it('articulates the cars along a straight trail', () => {
    const tr = new Trail(8);
    tr.reset(30, 0, 1, 0);
    tr.pushOldest(0, 0);
    const p0 = articulate(tr, 0, 14, 0.6);
    expect(p0.x).toBeCloseTo(23, 9);
    expect(p0.y).toBeCloseTo(0, 9);
    expect(p0.heading).toBeCloseTo(0, 9);
    const p1 = articulate(tr, 1, 14, 0.6);
    expect(p1.x).toBeCloseTo(8.4, 9);
    // Past the oldest point the trail runs on straight.
    const p2 = articulate(tr, 2, 14, 0.6);
    expect(p2.x).toBeCloseTo(-6.2, 9);
    expect(p2.heading).toBeCloseTo(0, 9);
  });

  it('articulates the cars along a bent trail', () => {
    const tr = new Trail(8);
    tr.reset(0, 10, 0, 1);
    tr.push(-20, 0);
    tr.push(0, 0); // newest fixed vertex: the corner the head passed
    expect(tr.count).toBe(3);
    const p0 = articulate(tr, 0, 14, 0.6);
    // Front joint at the head (0, 10), rear joint 10 m down and 4 m west of the corner.
    expect(p0.x).toBeCloseTo(-2, 9);
    expect(p0.y).toBeCloseTo(5, 9);
    expect(p0.heading).toBeCloseTo(Math.atan2(10, 4), 9);
    const p1 = articulate(tr, 1, 14, 0.6);
    expect(p1.x).toBeCloseTo(-11.6, 9);
    expect(p1.y).toBeCloseTo(0, 9);
    expect(p1.heading).toBeCloseTo(0, 9);
    // The ring keeps only the newest capacity − 1 vertices.
    const small = new Trail(2);
    small.reset(5, 0, 1, 0);
    small.push(1, 0);
    small.push(2, 0);
    expect(small.count).toBe(2);
    expect(small.x(1)).toBe(2);
  });

  it('picks the next stop ahead beyond stop_commit_m', () => {
    const g = line(200, [50, 120]);
    expect(g.stopsByEdge[0]).toEqual([0, 1]);
    expect(nextStopAhead(g, 0, 1, 0, 4)).toBe(0);
    expect(nextStopAhead(g, 0, 1, 45.9, 4)).toBe(0);
    expect(nextStopAhead(g, 0, 1, 46, 4)).toBe(1); // exactly commit: already passing
    expect(nextStopAhead(g, 0, 1, 47, 4)).toBe(1);
    expect(nextStopAhead(g, 0, 1, 0, 4, 0)).toBe(1); // just served
    expect(nextStopAhead(g, 0, 1, 130, 4)).toBe(-1);
    // Going to → from: stop 1 is at 80 m, stop 0 at 150 m.
    expect(nextStopAhead(g, 0, -1, 0, 4)).toBe(1);
    expect(nextStopAhead(g, 0, -1, 90, 4)).toBe(0);
    expect(nextStopAhead(g, 1, 1, 0, 4)).toBe(-1); // no such edge
    expect(g.stops[1]!.x).toBeCloseTo(120, 4);
  });
});

describe('trams in a planck world', () => {
  it('stand at a stop for dwell_s, then leave', () => {
    const world = new World({ gravity: { x: 0, y: 0 } });
    // The player stands well off the track (not in the corridor, out of the spawn ring).
    const player = new Car(world, spec, tuning.drive, 150, 40, 0, tuning.carScale);
    const trams = new Trams(world, line(300, [100]), tuning);
    const tr = trams.addTram(0, 1, 30)!;
    expect(tr).not.toBeNull();
    expect(tr.cars.length).toBe(t.carsPerTram);
    let arrived = -1, left = -1, sAt = 0;
    for (let i = 0; i < 60 / dt && left < 0; i++) {
      step(world, player, trams);
      if (arrived < 0 && tr.dwellTimer > 0) {
        arrived = i;
        sAt = tr.s;
      }
      if (arrived >= 0 && tr.dwellTimer === 0 && tr.speed > 0) left = i;
    }
    expect(trams.trams.length).toBe(1);
    expect(arrived).toBeGreaterThan(0);
    expect(sAt).toBeCloseTo(100, 1);
    expect(left).toBeGreaterThan(arrived);
    expect((left - arrived) * dt).toBeGreaterThan(t.dwellS - 3 * dt);
    expect((left - arrived) * dt).toBeLessThan(t.dwellS + 3 * dt);
    // It never stops at the same stop twice.
    for (let i = 0; i < 2 / dt; i++) step(world, player, trams);
    expect(tr.dwellTimer).toBe(0);
    expect(tr.speed).toBeGreaterThan(0);
  });

  it('waits behind the player on the track and cannot be pushed', () => {
    const world = new World({ gravity: { x: 0, y: 0 } });
    const player = new Car(world, spec, tuning.drive, 90, 0, 0, tuning.carScale);
    const trams = new Trams(world, line(400), tuning);
    const tr = trams.addTram(0, 1, 10)!;
    const hits: number[] = [];
    trams.onHit((_, v) => hits.push(v));
    for (let i = 0; i < 20 / dt; i++) step(world, player, trams);
    expect(tr.speed).toBe(0);
    expect(tr.trail.headX).toBeLessThan(player.x - player.halfLength);
    expect(hits.length).toBe(0);
    // The player drives into the standing tram head-on for three seconds.
    const before = tr.cars.map((c) => [c.x, c.y, c.heading]);
    for (let i = 0; i < 3 / dt; i++) {
      player.body.setLinearVelocity({ x: -8, y: 0 });
      step(world, player, trams);
    }
    expect(hits.length).toBeGreaterThanOrEqual(1);
    expect(hits[0]!).toBeGreaterThanOrEqual(t.hitMinMps);
    expect(trams.hits).toBe(hits.length);
    expect(tr.hitTimer).toBeGreaterThan(0);
    tr.cars.forEach((c, k) => {
      expect(c.body.isKinematic()).toBe(true);
      expect(c.x).toBeCloseTo(before[k]![0]!, 6);
      expect(c.y).toBeCloseTo(before[k]![1]!, 6);
      expect(c.heading).toBeCloseTo(before[k]![2]!, 6);
    });
    // The player stays outside the tram's nose.
    expect(player.x - player.halfLength).toBeGreaterThan(tr.trail.headX - 0.5);
  });

  it('a traffic car stops behind a tram crossing its lane (specs/traffic.md v3)', () => {
    const world = new World({ gravity: { x: 0, y: 0 } });
    const graph = RoadGraph.fromPb(create(GraphSchema, {
      names: [''],
      nodes: [node(0, 0), node(400, 0)],
      edges: [create(EdgeSchema, { from: 0, to: 1, points: [0, 0, 4000, 0], class: RoadClass.RESIDENTIAL, lanes: 2, oneway: 0, kept: true, widthM: 26 })],
    }));
    const city = { graph, manifest: { driveSide: 'right' } } as unknown as City;
    const traffic = new Traffic(world, city, tuning);
    traffic.solid = false; // the player is a ghost here
    const player = new Car(world, spec, tuning.drive, 200, 120, 0, tuning.carScale);
    const tram = { x: 150, y: 0, heading: Math.PI / 2, layer: 0, halfLength: t.carLengthM / 2, halfWidth: t.carWidthM / 2 };
    traffic.trams = [tram];
    const c = traffic.addCar(0, 1, 10, 0)!;
    expect(c).not.toBeNull();
    for (let i = 0; i < 30 / dt; i++) {
      step(world, player, null, traffic);
      expect(c.x + c.halfLength).toBeLessThan(tram.x - tram.halfLength + 0.5);
    }
    expect(traffic.cars).toContain(c);
    expect(c.speed).toBeLessThan(0.1);
    // Without the tram it drives on.
    traffic.trams = [];
    let maxX = c.x;
    for (let i = 0; i < 10 / dt; i++) {
      step(world, player, null, traffic);
      maxX = Math.max(maxX, c.x);
    }
    expect(maxX).toBeGreaterThan(tram.x + 10);
  });
});

// Recorded from this client; the Dart test of F-030 should hold the same numbers.
const PICKS_42 = [1, 2, 1, 3, 1, 1, 1, 2, 2, 3, 2, 2];
const PICKS_7 = [0, 1, 1, 0, 1, 0];

const packSource = (dir: string, missing: string[] = []): PackSource => ({
  read: async (p) => {
    if (missing.includes(p)) throw new Error(`${p}: not found`);
    return new Uint8Array(readFileSync(join(dir, p)));
  },
});
const nyc = join(root, 'build', 'packs', 'nyc');
const prague = join(root, 'build', 'packs', 'prague');

describe.skipIf(!existsSync(nyc))('trams.pb loading', () => {
  it('an old pack without trams.pb gives an empty track graph', async () => {
    const city = await City.load(packSource(nyc, ['trams.pb']));
    expect(city.trams.isEmpty).toBe(true);
    expect(city.trams.stops.length).toBe(0);
    expect(new DriveWorld(city, spec, tuning).trams).toBeNull();
  }, 120000);
});

describe.skipIf(!existsSync(join(prague, 'trams.pb')))('trams in the Prague pack', () => {
  it('has tracks and stops, and trams fill around the player', async () => {
    const city = await City.load(packSource(prague));
    const g = city.trams;
    expect(g.edges.length).toBeGreaterThan(100);
    expect(g.stops.length).toBeGreaterThan(10);
    for (const st of g.stops) expect(st.s).toBeLessThanOrEqual(g.edges[st.edge]!.length);
    const d = new DriveWorld(city, spec, tuning);
    const trams = d.trams!;
    expect(trams).not.toBeNull();
    const st = g.stops[0]!;
    // Beside the track, so the player does not block it.
    d.spawn(st.x - st.dirY * 30, st.y + st.dirX * 30, 0);
    d.input.brake = 1;
    for (let i = 0; i < 30 / dt; i++) {
      d.update(dt);
      expect(trams.trams.length).toBeLessThanOrEqual(t.maxTrams);
      expect(trams.items.length).toBe(trams.trams.length * t.carsPerTram);
    }
    expect(trams.trams.length).toBeGreaterThan(0);
  }, 120000);
});
