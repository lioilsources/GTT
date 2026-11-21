import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { create } from '@bufbuild/protobuf';
import { beforeAll, describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { DriveWorld } from '../src/drive/driveWorld';
import { EdgeSchema, GraphSchema, NodeSchema, RoadClass } from '../src/gen/pb/citypack_pb';
import type { CarSpec } from '../src/gen/schema';
import { Tuning } from '../src/gen/tuning';
import { Police } from '../src/police/police';
import { fine, OFFENCE_KINDS, policeConfig, PoliceRules } from '../src/police/rules';
import { inView, onSidewalk, segmentsCross, sightBlocked } from '../src/police/sense';
import { lightPhase } from '../src/police/view';
import { chooseToward } from '../src/traffic/roadRules';
import { chunkPath, type PackSource } from '../src/world/citypack';
import { prepareChunk, type BuildingData, type ChunkData } from '../src/world/chunk';
import { City, RoadGraph } from '../src/world/model';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));

/**
 * The same synthetic crossing as test/traffic.test.ts (and packages/drive_core/test/police_test.dart):
 *            2 (0,40)
 *  3 ──e2── 0 ──e0── 1 (100,0) ──e4 alley── 5 (100,100)
 *            4 (0,-100) border; e3 one-way 4→0; e5 2→5
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

/** A square building from (x0, y0) to (x1, y1). */
function box(x0: number, y0: number, x1: number, y1: number, collide = true): BuildingData {
  const xy = Float32Array.from([x0, y0, x1, y0, x1, y1, x0, y1]);
  const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
  return {
    xy, ringEnds: Int32Array.from([4]), roof: new Uint16Array(), height: 10, minHeight: 0, landmark: 0, collide, seed: 0,
    cx, cy, radius: Math.hypot(x1 - cx, y1 - cy), wallU: new Float32Array(4),
  };
}

describe('police rules (specs/police.md)', () => {
  const cfg = policeConfig(tuning.police);

  it('config turns seconds into ticks', () => {
    const p = tuning.police;
    expect(cfg.escapeTicks).toBe(Math.round(p.escapeS * p.tickHz));
    expect(cfg.captureTicks).toBe(Math.round(p.captureS * p.tickHz));
    expect(cfg.maxLevel).toBe(2);
    expect(Object.keys(cfg.levels)).toEqual([...OFFENCE_KINDS]);
  });

  it('fine by level, clamped to the table', () => {
    expect(fine(0, [0, 100, 250])).toBe(0);
    expect(fine(2, [0, 100, 250])).toBe(250);
    expect(fine(5, [0, 100, 250])).toBe(250);
    expect(fine(1, [])).toBe(0);
  });

  it('escape from level 2 takes two escape windows', () => {
    const r = new PoliceRules();
    let s = r.init(cfg, 0);
    s = r.apply(s, { by: 'player', op: 'offence', kind: 'hitrun', seen: true });
    expect(s.level).toBe(2);
    const tick = { by: 'player', op: 'tick', seen: false, near: false, away: false } as const;
    for (let i = 0; i < cfg.escapeTicks; i++) s = r.apply(s, tick);
    expect(s.level).toBe(1);
    for (let i = 0; i < cfg.escapeTicks; i++) s = r.apply(s, tick);
    expect(s.level).toBe(0);
  });

  it('legal actions: 8 offences then 8 ticks; unknown kind is illegal', () => {
    const r = new PoliceRules();
    const s = r.init(cfg, 0);
    const a = r.legalActions(s);
    expect(a.length).toBe(16);
    expect(a[0]).toEqual({ by: 'player', op: 'offence', kind: 'crash', seen: false });
    expect(a[15]).toEqual({ by: 'player', op: 'tick', seen: true, near: true, away: true });
    expect(() => r.apply(s, { by: 'player', op: 'offence', kind: 'speeding' as 'crash', seen: true })).toThrow();
  });
});

describe('police geometry', () => {
  const g = crossing();

  it('sidewalk band of a kept edge, not the carriageway, not an alley', () => {
    // e0: width 42, carriage half = max(42 − 10, 8) / 2 = 16, + margin 1 = 17.
    expect(onSidewalk(g.near(50, 10, 30), tuning)).toBe(false);
    expect(onSidewalk(g.near(50, 18, 30), tuning)).toBe(true);
    expect(onSidewalk(g.near(50, 22, 30), tuning)).toBe(false); // beyond width/2 = 21
    expect(onSidewalk(g.near(100, 50, 30), tuning)).toBe(false); // alley only
  });

  it('sight blocked by a colliding building between the cars', () => {
    expect(segmentsCross(0, 0, 10, 0, 5, -1, 5, 1)).toBe(true);
    expect(segmentsCross(0, 0, 10, 0, 11, -1, 11, 1)).toBe(false);
    const b = [box(20, -5, 30, 5)];
    expect(sightBlocked(0, 0, 50, 0, b)).toBe(true);
    expect(sightBlocked(0, 10, 50, 10, b)).toBe(false);
    expect(sightBlocked(0, 0, 50, 0, [box(20, -5, 30, 5, false)])).toBe(false);
    expect(inView(0, 0, 0, 60, 0, 0, 70)).toBe(true);
    expect(inView(0, 0, 0, 71, 0, 0, 70)).toBe(false);
    expect(inView(0, 0, -1, 10, 0, 0, 70)).toBe(false);
    expect(inView(0, 0, 1, 10, 0, 0, 70)).toBe(true);
  });

  it('chooseToward heads for the goal, may U-turn, ignores one-way, stops at the border', () => {
    expect(chooseToward(g, 0, 0, 100, 5)).toBe(0); // back along e0 (U-turn)
    expect(chooseToward(g, 0, 1, 100, 5)).toBe(0);
    expect(chooseToward(g, 0, 0, -100, 0)).toBe(2);
    expect(chooseToward(g, 0, 0, 0, -100)).toBe(3); // against the one-way 4→0
    expect(chooseToward(g, 0, 0, 0, 50)).toBe(1);
    expect(chooseToward(g, 4, 3, 0, 0)).toBe(-1);
  });

  it('light bar phase', () => {
    expect(lightPhase(false, 1, 0.25)).toBe(-1);
    expect(lightPhase(true, 0.1, 0.25)).toBe(0);
    expect(lightPhase(true, 0.3, 0.25)).toBe(1);
    expect(lightPhase(true, 0.55, 0.25)).toBe(0);
  });
});

const pack = join(root, 'build', 'packs', 'nyc');
const source: PackSource = { read: async (p) => new Uint8Array(readFileSync(join(pack, p))) };
const car = JSON.parse(readFileSync(join(root, 'content', 'cars', 'm0_coupe.json'), 'utf8')) as CarSpec;

describe.skipIf(!existsSync(pack))('police in the NYC pack', () => {
  let city: City;
  const chunks: ChunkData[] = [];
  beforeAll(async () => {
    city = await City.load(source);
    const cx = Math.floor(city.startX / city.chunkM), cy = Math.floor(city.startY / city.chunkM);
    for (const c of city.manifest.chunks) {
      if (Math.abs(c.x - cx) > 2 || Math.abs(c.y - cy) > 2) continue;
      chunks.push(await prepareChunk(await source.read(chunkPath(c.x, c.y))));
    }
  }, 120000);
  const world = (): { d: DriveWorld; p: Police } => {
    const d = new DriveWorld(city, car, tuning);
    const p = new Police(d, tuning, null);
    for (const c of chunks) {
      d.addChunk(c);
      p.addChunk(c);
    }
    return { d, p };
  };
  /** A straight kept ground edge near the start, the player on it heading along it. */
  const straight = (d: DriveWorld) => {
    const hit = city.graph.nearest(d.car.x, d.car.y, 300, (e) => e.kept && e.isGround && e.oneway >= 0 && e.length > 80)!;
    return hit;
  };

  it('flags patrols among the traffic, far from the player', () => {
    const { d, p } = world();
    d.input.brake = 1;
    for (let i = 0; i < 5 * 60; i++) {
      d.update(1 / 60);
      p.update(1 / 60);
    }
    const patrols = d.traffic!.cars.filter((c) => c.police);
    expect(patrols.length).toBe(tuning.police.patrols[0]);
    expect(patrols.every((c) => !c.pursuing)).toBe(true);
  });

  it('a crash seen by a patrol raises the level, the patrol catches the stopped player', () => {
    const { d, p } = world();
    const tr = d.traffic!;
    const hit = straight(d);
    const e = hit.edge;
    d.spawn(hit.x, hit.y, 0);
    d.update(1 / 60);
    const s = Math.min(e.length - 10, hit.t * e.length + 25);
    tr.reset();
    const target = tr.addCar(e.index, 1, s, 0)!;
    const hx = Math.cos(target.heading), hy = Math.sin(target.heading);
    d.spawn(target.x - hx * 25, target.y - hy * 25, target.heading);
    // A patrol behind the player on the same edge.
    const cop = tr.addCar(e.index, 1, Math.max(0, s - 55), 1)!;
    cop.police = true;
    const levels: number[] = [];
    const fines: number[] = [];
    p.onWantedChanged((w) => levels.push(w.level));
    p.onFined((f) => fines.push(f.amount));
    for (let i = 0; i < 6 * 60 && tr.hits === 0; i++) {
      d.input.reset();
      d.input.boost = true;
      d.update(1 / 60);
      p.update(1 / 60);
    }
    expect(tr.hits).toBeGreaterThan(0);
    expect(p.wantedLevel).toBeGreaterThanOrEqual(1);
    // Stop and wait: the patrol pulls up and the player is busted.
    for (let i = 0; i < 20 * 60 && fines.length === 0; i++) {
      d.input.reset();
      d.input.brake = 1;
      d.input.handbrake = true;
      d.update(1 / 60);
      p.update(1 / 60);
    }
    expect(levels[0]).toBe(1);
    expect(fines.length).toBe(1);
    expect(fines[0]).toBeGreaterThan(0);
    expect(p.wantedLevel).toBe(0);
  }, 30000);
});
