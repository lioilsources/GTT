import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { create } from '@bufbuild/protobuf';
import { beforeAll, describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { DriveWorld } from '../src/drive/driveWorld';
import { EdgeSchema, GraphSchema, NodeSchema, RoadClass } from '../src/gen/pb/citypack_pb';
import type { CarSpec } from '../src/gen/schema';
import { Tuning } from '../src/gen/tuning';
import { Prng } from '../src/rules/prng';
import {
  buildSignals, chooseNext, cycleMs, laneOffset, lanesPerDir, LIGHT_AMBER, LIGHT_GREEN, LIGHT_RED, lightState,
  signalClockMs, signalOffset, swerveShift,
} from '../src/traffic/roadRules';
import { obbOverlap } from '../src/traffic/traffic';
import { chunkPath, type PackSource } from '../src/world/citypack';
import { prepareChunk, type ChunkData } from '../src/world/chunk';
import { City, RoadGraph } from '../src/world/model';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const t = tuning.traffic;

/**
 * Synthetic crossing (metres; the pb holds dm). The same graph and the same expected values are in
 * packages/drive_core/test/traffic_test.dart, so both clients are checked against one table.
 *
 *            2 (0,40)
 *            |  e1 primary 2→0, two-way; e6 residential 2→5
 *  3 ──e2── 0 ──e0── 1 (100,0) ──e4 alley── 5
 *  (-100,0)  |  e0 primary 0→1 two-way; e2 residential one-way 0→3
 *            4 (0,-100) border; e3 secondary one-way 4→0
 */
function crossing(): RoadGraph {
  const n = (x: number, y: number, border = false) => create(NodeSchema, { x: x * 10, y: y * 10, border });
  const e = (from: number, to: number, pts: number[], cls: RoadClass, lanes: number, oneway: number, kept: boolean, widthM: number) =>
    create(EdgeSchema, { from, to, points: pts.map((v) => v * 10), class: cls, lanes, oneway, kept, widthM });
  return RoadGraph.fromPb(create(GraphSchema, {
    names: [''],
    nodes: [n(0, 0), n(100, 0), n(0, 40), n(-100, 0), n(0, -100, true), n(100, 100)],
    edges: [
      e(0, 1, [0, 0, 50, 0, 100, 0], RoadClass.PRIMARY, 4, 0, true, 42),
      e(2, 0, [0, 40, 0, 0], RoadClass.PRIMARY, 4, 0, true, 42),
      e(0, 3, [0, 0, -100, 0], RoadClass.RESIDENTIAL, 2, 1, true, 26),
      e(4, 0, [0, -100, 0, 0], RoadClass.SECONDARY, 2, 1, true, 26),
      e(1, 5, [100, 0, 100, 100], RoadClass.SERVICE, 1, 0, false, 12),
      e(2, 5, [0, 40, 100, 100], RoadClass.RESIDENTIAL, 2, 0, true, 26),
    ],
  }));
}

describe('traffic rules (specs/traffic.md)', () => {
  it('signal offsets are a fixed function of the node id', () => {
    expect(cycleMs(t)).toBe(2 * (t.greenMs + t.amberMs + t.allRedMs));
    expect([0, 1, 7, 12345, 987654].map((n) => signalOffset(n, 7919, 37000))).toEqual(OFFSETS);
  });

  it('two-phase light: group 1 is half a cycle behind group 0', () => {
    const g = t.greenMs, a = t.amberMs, half = cycleMs(t) / 2;
    expect(lightState(0, 0, 0, t)).toBe(LIGHT_GREEN);
    expect(lightState(0, 0, g - 1, t)).toBe(LIGHT_GREEN);
    expect(lightState(0, 0, g, t)).toBe(LIGHT_AMBER);
    expect(lightState(0, 0, g + a, t)).toBe(LIGHT_RED);
    expect(lightState(0, 0, half, t)).toBe(LIGHT_RED);
    expect(lightState(0, 1, 0, t)).toBe(LIGHT_RED);
    expect(lightState(0, 1, half, t)).toBe(LIGHT_GREEN);
    expect(lightState(0, 1, half + g, t)).toBe(LIGHT_AMBER);
    expect(lightState(100, 0, g - 100, t)).toBe(LIGHT_AMBER);
    // Never green for both groups at once.
    for (let ms = 0; ms < cycleMs(t); ms += 250) {
      expect(lightState(1234, 0, ms, t) === LIGHT_GREEN && lightState(1234, 1, ms, t) === LIGHT_GREEN).toBe(false);
    }
    expect(signalClockMs(61, 60)).toBe(1016);
  });

  it('finds the signalled crossing and groups its approaches', () => {
    const s = buildSignals(crossing(), tuning, false);
    expect(s.nodes).toEqual([0]);
    expect(s.approaches.map((a) => [a.edge, a.group])).toEqual([[0, 0], [1, 1], [3, 1]]);
    const a0 = s.approaches[0]!;
    expect(a0.stopM).toBeCloseTo(21 + t.stopMarginM, 5);
    // East arm, travel west: the indicator is on the right = north side of the carriageway.
    expect(a0.x).toBeCloseTo(a0.stopM, 4);
    expect(a0.y).toBeCloseTo(16 + t.lightSideM, 4);
    expect(s.approachFrom[0]).toBe(0);
    expect(s.approachTo[0]).toBe(-1);
    expect(s.approachTo[3]).toBe(2);
    // e5 → node 2 → e1 → signal: an unbranched chain, the light is 40 m past the end of e5.
    expect(s.approachFrom[5]).toBe(1);
    expect(s.extraFrom[5]).toBeCloseTo(40, 4);
    expect(s.approachTo[5]).toBe(-1);
    const left = buildSignals(crossing(), tuning, true).approaches[0]!;
    expect(left.y).toBeCloseTo(-(16 + t.lightSideM), 4);
  });

  it('lane offsets follow the markings and the drive side', () => {
    const g = crossing();
    expect(lanesPerDir(g.edges[0]!, tuning)).toBe(2);
    expect(laneOffset(g.edges[0]!, 0, tuning, false)).toBeCloseTo(4, 6);
    expect(laneOffset(g.edges[0]!, 1, tuning, false)).toBeCloseTo(12, 6);
    expect(lanesPerDir(g.edges[2]!, tuning)).toBe(2);
    expect(laneOffset(g.edges[2]!, 0, tuning, false)).toBeCloseTo(4, 6);
    expect(laneOffset(g.edges[2]!, 1, tuning, false)).toBeCloseTo(-4, 6);
    expect(laneOffset(g.edges[0]!, 1, tuning, true)).toBeCloseTo(-12, 6);
  });

  it('chooses the next edge with the shared PRNG, never an alley', () => {
    const g = crossing();
    const rng = new Prng(42);
    const picks = Array.from({ length: 12 }, () => chooseNext(g, 0, 3, rng));
    expect(picks).toEqual(PICKS);
    expect(chooseNext(g, 1, 0, new Prng(1))).toBe(0); // only an alley ahead: U-turn
    expect(chooseNext(g, 3, 2, new Prng(1))).toBe(-1); // one-way dead end
    expect(chooseNext(g, 4, 3, new Prng(1))).toBe(-1); // roadblock
    expect(chooseNext(g, 2, 1, new Prng(7))).toBe(5);
  });

  it('box overlap', () => {
    expect(obbOverlap(0, 0, 1, 0, 5, 2, 9.9, 0, 1, 0, 5, 2, 0)).toBe(true);
    expect(obbOverlap(0, 0, 1, 0, 5, 2, 10.5, 0, 1, 0, 5, 2, 0)).toBe(false);
    expect(obbOverlap(0, 0, 1, 0, 5, 2, 10.5, 0, 1, 0, 5, 2, 0.6)).toBe(true);
    expect(obbOverlap(0, 0, 1, 0, 5, 2, 0, 6.9, 0, 1, 5, 2, 0)).toBe(true);
    expect(obbOverlap(0, 0, 1, 0, 5, 2, 0, 7.1, 0, 1, 5, 2, 0)).toBe(false);
  });

  it('swerves round parked cars (step 8); same table as traffic_test.dart', () => {
    const st = { swerveAheadM: 22, swerveMarginM: 0.6, swerveMaxM: 7 };
    const sh = (...o: number[]): number => swerveShift(o, o.length / 4, 5.75, 2.375, st);
    expect(sh(10, 3, 2.4, 6)).toBeCloseTo(-2.375, 9); // parked on the right: move left
    expect(sh(10, -1, 2.4, 6)).toBeCloseTo(4.375, 9); // on the left: move right
    expect(sh(0, 0, 2.4, 6)).toBeCloseTo(-5.375, 9);
    expect(sh(40, 3, 2.4, 6)).toBe(0); // too far ahead
    expect(sh(-12, 3, 2.4, 6)).toBe(0); // passed
    expect(sh(10, 6, 2.4, 6)).toBe(0); // clear of the lane
    expect(sh(10, 3, 2.4, 6, 5, -1, 2.4, 6)).toBeCloseTo(4.375, 9); // the bigger shift wins
    expect(sh(10, 0, 4, 6)).toBeCloseTo(-6.975, 9);
    expect(sh(10, 0, 4.1, 6)).toBe(0); // over swerve_max_m: not attempted
    expect(sh()).toBe(0);
  });
});

// Recorded from this client; the Dart test holds the same numbers.
const OFFSETS = [14417, 5153, 2912, 27192, 23321];
const PICKS = [0, 1, 0, 2, 0, 0, 0, 1, 1, 2, 1, 1];

const pack = join(root, 'build', 'packs', 'nyc');
const source: PackSource = { read: async (p) => new Uint8Array(readFileSync(join(pack, p))) };
const car = JSON.parse(readFileSync(join(root, 'content', 'cars', 'm0_coupe.json'), 'utf8')) as CarSpec;

describe.skipIf(!existsSync(pack))('traffic in the NYC pack', () => {
  let city: City;
  const chunks: ChunkData[] = [];
  beforeAll(async () => {
    city = await City.load(source);
    // Buildings only matter for the player; the chunks around the start are enough.
    const cx = Math.floor(city.startX / city.chunkM), cy = Math.floor(city.startY / city.chunkM);
    for (const c of city.manifest.chunks) {
      if (Math.abs(c.x - cx) > 2 || Math.abs(c.y - cy) > 2) continue;
      chunks.push(await prepareChunk(await source.read(chunkPath(c.x, c.y))));
    }
  }, 120000);
  const world = (): DriveWorld => {
    const d = new DriveWorld(city, car, tuning);
    for (const c of chunks) d.addChunk(c);
    return d;
  };

  it('Manhattan has signals on avenues', () => {
    const d = world();
    expect(d.traffic!.signals.nodes.length).toBeGreaterThan(200);
  });

  it('fills to the cap, keeps kept edges, cars move and obey the cap', () => {
    const d = world();
    const tr = d.traffic!;
    d.input.brake = 1; // the player stays put
    let moving = 0;
    for (let i = 0; i < 20 * 60; i++) {
      d.update(1 / 60);
      expect(tr.cars.length).toBeLessThanOrEqual(t.maxCars);
      if (i % 60 === 0) for (const c of tr.cars) expect(c.edge.kept).toBe(true);
    }
    for (const c of tr.cars) if (c.speed > 1) moving++;
    expect(tr.cars.length).toBeGreaterThan(t.maxCars / 2);
    expect(moving).toBeGreaterThan(0);
    tr.night = true;
    for (let i = 0; i < 2 * 60; i++) d.update(1 / 60);
    expect(tr.cars.length).toBeLessThanOrEqual(t.maxCars);
  });

  it('no car drives through a red light', () => {
    const d = world();
    const tr = d.traffic!;
    // Cars at the start of the approaches nearest to the player (the player rolls off at cruise
    // and ends against a building, out of the lanes).
    d.update(1 / 60);
    tr.reset();
    const near = tr.signals.approaches
      .map((a, i) => ({ i, d: Math.hypot(a.x - d.car.x, a.y - d.car.y) }))
      .sort((p, q) => p.d - q.d);
    for (const { i, d: dist } of near) {
      const ap = tr.signals.approaches[i]!;
      const e = city.graph.edges[ap.edge]!;
      if (dist < 200) tr.addCar(ap.edge, e.to === ap.node ? 1 : -1, 0, 0);
    }
    const added = tr.cars.length;
    const last = new Map<number, { edge: number; dir: number; s: number }>();
    let checked = 0;
    for (let i = 0; i < 40 * 60; i++) {
      d.update(1 / 60);
      for (const c of tr.cars) {
        const a = c.dir > 0 ? tr.signals.approachTo[c.edge.index]! : tr.signals.approachFrom[c.edge.index]!;
        const prev = last.get(c.id);
        if (a >= 0 && prev && prev.edge === c.edge.index && tr.light(a) === LIGHT_RED) {
          const extra = c.dir > 0 ? tr.signals.extraTo[c.edge.index]! : tr.signals.extraFrom[c.edge.index]!;
          const line = c.edge.length + extra - tr.signals.approaches[a]!.stopM - c.halfLength;
          // A car before the line on red never ends up past it (amber commits are already past).
          if (prev.s < line - 0.5) {
            checked++;
            expect(c.s).toBeLessThan(line + 0.5);
          }
        }
        last.set(c.id, { edge: c.edge.index, dir: c.dir, s: c.s });
      }
    }
    expect(added).toBeGreaterThan(3);
    expect(checked).toBeGreaterThan(0);
  });

  it('a car hit by the player stops and fires the hit event', () => {
    const d = world();
    const tr = d.traffic!;
    const hit = city.graph.nearest(d.car.x, d.car.y, 300, (e) => e.kept && e.isGround && e.oneway >= 0 && e.length > 80)!;
    const e = hit.edge;
    d.spawn(hit.x, hit.y, 0);
    d.update(1 / 60); // first fill around the player
    const s = Math.min(e.length - 10, hit.t * e.length + 25);
    tr.reset(); // make room under the cap; the rest refills on the next step
    const target = tr.addCar(e.index, 1, s, 0)!;
    expect(target).not.toBeNull();
    // Player 25 m behind the traffic car, in its lane, same heading; drives at cruise into it.
    const hx = Math.cos(target.heading), hy = Math.sin(target.heading);
    d.spawn(target.x - hx * 25, target.y - hy * 25, target.heading);
    const events: number[] = [];
    tr.onHit((c, v) => {
      if (c === target) events.push(v);
    });
    let stopped = false;
    for (let i = 0; i < 6 * 60 && events.length === 0; i++) {
      d.input.reset();
      d.input.boost = true;
      d.update(1 / 60);
    }
    expect(events.length).toBe(1);
    expect(tr.hits).toBeGreaterThan(0);
    for (let i = 0; i < 30; i++) {
      d.input.reset();
      d.input.brake = 1;
      d.update(1 / 60);
      if (target.speed === 0) stopped = true;
    }
    expect(stopped).toBe(true);
    expect(target.hitTimer).toBeGreaterThan(0);
  });

  it('the player pushes a car it touches; it settles back into its lane (step 7)', () => {
    const d = world();
    const tr = d.traffic!;
    const hit = city.graph.nearest(d.car.x, d.car.y, 300, (e) => e.kept && e.isGround && e.oneway >= 0 && e.length > 80)!;
    const e = hit.edge;
    d.spawn(hit.x, hit.y, 0);
    d.update(1 / 60);
    tr.reset();
    const target = tr.addCar(e.index, 1, Math.min(e.length - 10, hit.t * e.length + 25), 0)!;
    const hx = Math.cos(target.heading), hy = Math.sin(target.heading);
    d.spawn(target.x - hx * 25, target.y - hy * 25, target.heading);
    let loose = false;
    let x0 = 0, y0 = 0;
    for (let i = 0; i < 6 * 60; i++) {
      d.input.reset();
      d.input.boost = true;
      d.update(1 / 60);
      if (!loose && target.loose) {
        loose = true;
        x0 = target.x;
        y0 = target.y;
      }
      // Keep pushing for two seconds after the first touch.
      if (loose && Math.hypot(target.x - x0, target.y - y0) > 3) break;
    }
    expect(loose).toBe(true);
    expect(Math.hypot(target.x - x0, target.y - y0)).toBeGreaterThan(3);
    // Back off: the car turns kinematic again and drives on.
    for (let i = 0; i < 8 * 60; i++) {
      d.input.reset();
      d.input.brake = 1;
      d.update(1 / 60);
    }
    expect(target.loose).toBe(false);
  });

  it('cars drive round a parked car in their lane instead of through it (step 8)', () => {
    const d = world();
    const tr = d.traffic!;
    const hit = city.graph.nearest(d.car.x, d.car.y, 300, (e) => e.kept && e.isGround && e.oneway >= 0 && e.length > 120)!;
    const e = hit.edge;
    d.spawn(hit.x, hit.y, 0);
    d.update(1 / 60);
    tr.reset();
    tr.solid = false; // the player is a ghost to traffic here
    const c = tr.addCar(e.index, 1, 5, 0)!;
    // A parked car right in the lane 40 m ahead, shifted a little to the curb side.
    const probe = tr.addCar(e.index, 1, 45, 0)!;
    const px = probe.x + Math.sin(probe.heading) * 1.5, py = probe.y - Math.cos(probe.heading) * 1.5, ph = probe.heading;
    tr.cars.splice(tr.cars.indexOf(probe), 1);
    d.world.destroyBody(probe.body);
    tr.parked = [{ x: px, y: py, heading: ph, hl: 5.6, hw: 2.4 }];
    let overlaps = 0, passed = false;
    for (let i = 0; i < 10 * 60 && !passed; i++) {
      d.update(1 / 60);
      if (!tr.cars.includes(c)) break;
      if (obbOverlap(c.x, c.y, Math.cos(c.heading), Math.sin(c.heading), c.halfLength, c.halfWidth, px, py, Math.cos(ph), Math.sin(ph), 5.6, 2.4, 0)) overlaps++;
      if ((c.x - px) * Math.cos(ph) + (c.y - py) * Math.sin(ph) > 15) passed = true;
    }
    expect(passed).toBe(true);
    expect(overlaps).toBe(0);
  });
});
