import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { gzipSync } from 'node:zlib';

import { create, toBinary, type DescMessage, type MessageShape } from '@bufbuild/protobuf';
import { beforeAll, describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { DriveWorld } from '../src/drive/driveWorld';
import { EdgeSchema, GraphSchema, LandmarksSchema, ManifestSchema, NodeSchema, RoadClass, SpawnSchema, SpotsSchema } from '../src/gen/pb/citypack_pb';
import type { CarSpec } from '../src/gen/schema';
import { Tuning } from '../src/gen/tuning';
import { Police, roadblockSpot } from '../src/police/police';
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
    expect(cfg.maxLevel).toBe(tuning.police.maxLevel);
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

  // police_box (Prompts/05 L-S12): three patrols round the standing player – ahead, behind and
  // alongside. After the busted card the player must get away (auto-throttle or rescue).
  it('police_box: three patrols box in the standing player; after busted the player drives off', () => {
    const { d, p } = world();
    const tr = d.traffic!;
    const hit = straight(d);
    const e = hit.edge;
    const s = Math.min(e.length - 40, Math.max(40, hit.t * e.length));
    tr.reset();
    const ahead = tr.addCar(e.index, 1, s + 7, 0)!;
    const behind = tr.addCar(e.index, 1, s - 7, 0)!;
    const side = tr.addCar(e.index, -1, e.length - s, 0) ?? tr.addCar(e.index, 1, s, 1)!;
    for (const c of [ahead, behind, side]) c.police = true;
    const px = (ahead.x + behind.x) / 2, py = (ahead.y + behind.y) / 2;
    d.spawn(px, py, ahead.heading);
    (p as unknown as { state: { level: number } }).state = { ...(p as unknown as { state: object }).state, level: 2 } as { level: number };
    let busted = -1;
    p.onFined(() => (busted = 0));
    let t = 0;
    for (let i = 0; i < 20 * 60 && busted < 0; i++, t++) {
      d.input.reset();
      d.input.brake = 1;
      d.update(1 / 60);
      p.update(1 / 60);
    }
    expect(busted).toBe(0);
    // The card is gone; the player lets the auto-throttle drive for 15 s.
    const bx = d.car.x, by = d.car.y;
    let far = 0;
    for (let i = 0; i < 15 * 60; i++) {
      d.input.reset();
      d.update(1 / 60);
      p.update(1 / 60);
      far = Math.max(far, Math.hypot(d.car.x - bx, d.car.y - by));
    }
    expect(p.wantedLevel).toBe(0);
    expect(far).toBeGreaterThan(30);
  }, 60000);

  // Soak (L-S12): 20 busts in a row at levels 1–3 (level 3 also puts up a roadblock); after each one
  // the player gets 30 m away within 15 s.
  it('soak: 20 busts in a row never trap the player', () => {
    const { d, p } = world();
    const tr = d.traffic!;
    let busts = 0;
    p.onFined(() => busts++);
    for (let k = 0; k < 20; k++) {
      const hit = straight(d);
      const e = hit.edge;
      const s = Math.min(e.length - 40, Math.max(40, hit.t * e.length));
      tr.reset();
      const ahead = tr.addCar(e.index, 1, s + 7, 0)!;
      const behind = tr.addCar(e.index, 1, s - 7, 0)!;
      for (const c of [ahead, behind]) c.police = true;
      d.spawn((ahead.x + behind.x) / 2, (ahead.y + behind.y) / 2, ahead.heading);
      (p as unknown as { state: { level: number } }).state = { ...(p as unknown as { state: object }).state, level: 1 + (k % 3) } as { level: number };
      const before = busts;
      for (let i = 0; i < 30 * 60 && busts === before; i++) {
        d.input.reset();
        d.input.brake = 1;
        d.update(1 / 60);
        p.update(1 / 60);
      }
      expect(busts, `bust ${k + 1}`).toBe(before + 1);
      const bx = d.car.x, by = d.car.y;
      let far = 0;
      for (let i = 0; i < 15 * 60 && far <= 30; i++) {
        d.input.reset();
        d.update(1 / 60);
        p.update(1 / 60);
        far = Math.max(far, Math.hypot(d.car.x - bx, d.car.y - by));
      }
      expect(far, `away after bust ${k + 1} (level ${1 + (k % 3)}, roadblock ${p.roadblock ? 'up' : 'none'})`).toBeGreaterThan(30);
    }
  }, 240000);
});

/**
 * Roadblock (specs/roadblock.md) on a synthetic city:
 *  0 (-200,0) ──e0── 1 (0,0) ──e1── 2 (200,0) ──e2── 3 (600,0) border
 *                    └─e3── 4 (0,400)
 *  dead end: 5 (-200,500) ──e4── 6 (-100,500)
 */
function blockGraph() {
  const n = (x: number, y: number, border = false) => create(NodeSchema, { x: x * 10, y: y * 10, border });
  const e = (from: number, to: number, pts: number[]) =>
    create(EdgeSchema, { from, to, points: pts.map((v) => v * 10), class: RoadClass.PRIMARY, lanes: 4, oneway: 0, kept: true, widthM: 30 });
  return create(GraphSchema, {
    names: [''],
    nodes: [n(-200, 0), n(0, 0), n(200, 0), n(600, 0, true), n(0, 400), n(-200, 500), n(-100, 500)],
    edges: [
      e(0, 1, [-200, 0, 0, 0]),
      e(1, 2, [0, 0, 200, 0]),
      e(2, 3, [200, 0, 600, 0]),
      e(1, 4, [0, 0, 0, 400]),
      e(5, 6, [-200, 500, -100, 500]),
    ],
  });
}

const gz = <D extends DescMessage>(schema: D, m: MessageShape<D>): Uint8Array => new Uint8Array(gzipSync(toBinary(schema, m)));

async function blockCity(): Promise<City> {
  const files: Record<string, Uint8Array> = {
    'manifest.pb': gz(ManifestSchema, create(ManifestSchema, {
      formatVersion: 1, cityId: 'test', chunkM: 256, driveSide: 'right', units: 'metric',
      start: create(SpawnSchema, { x: -1000, y: 0, headingRad: 0 }),
    })),
    'graph.pb': gz(GraphSchema, blockGraph()),
    'landmarks.pb': gz(LandmarksSchema, create(LandmarksSchema, {})),
    'spots.pb': gz(SpotsSchema, create(SpotsSchema, {})),
  };
  return City.load({
    read: async (p) => {
      const f = files[p];
      if (!f) throw new Error(p);
      return f;
    },
  });
}

type RawTuning = { police: Record<string, unknown> & { roadblock: Record<string, unknown> } };

/** Tuning with the wanted cap raised to 3 (the roadblock level), plus overrides. */
function tuning3(edit: (raw: RawTuning) => void = () => {}): Tuning {
  const raw = parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')) as RawTuning;
  raw.police.max_level = 3;
  edit(raw);
  return Tuning.fromJson(raw);
}

describe('police roadblock (specs/roadblock.md)', () => {
  let city: City;
  beforeAll(async () => {
    city = await blockCity();
  });
  const rb = tuning.police.roadblock;
  const search = tuning.layers.searchM;

  it('spot: ahead_m along the road, across a node by chooseToward; gives up at a border or a dead end', () => {
    const g = city.graph;
    const a = roadblockSpot(g, -100, 0, 0, 0, search, rb.aheadM, rb.probeM)!;
    expect(a.edge.index).toBe(1);
    expect(a.x).toBeCloseTo(-100 + rb.aheadM, 3);
    expect(a.y).toBeCloseTo(0, 3);
    expect(a.heading).toBeCloseTo(0, 6);
    // Heading west on e1: along e1 backwards, then e0.
    const b = roadblockSpot(g, 100, 2, Math.PI, 0, search, rb.aheadM, rb.probeM)!;
    expect(b.edge.index).toBe(0);
    expect(b.x).toBeCloseTo(100 - rb.aheadM, 3);
    // Heading north-east just before the crossing: the side road e3.
    const c = roadblockSpot(g, -5, 0, Math.PI / 2 - 0.3, 0, search, rb.aheadM, rb.probeM)!;
    expect(c.edge.index).toBe(3);
    // Border node 3 within ahead_m, a dead end, no road at all, another layer.
    expect(roadblockSpot(g, 550, 0, 0, 0, search, rb.aheadM, rb.probeM)).toBeNull();
    expect(roadblockSpot(g, -180, 500, 0, 0, search, rb.aheadM, rb.probeM)).toBeNull();
    expect(roadblockSpot(g, -100, 250, 0, 0, search, rb.aheadM, rb.probeM)).toBeNull();
    expect(roadblockSpot(g, -100, 0, 0, -1, search, rb.aheadM, rb.probeM)).toBeNull();
  });

  const world = (t: Tuning) => {
    const d = new DriveWorld(city, car, t);
    const p = new Police(d, t, null);
    d.spawn(-100, 0, 0);
    return { d, p };
  };
  /** Runs s seconds on the handbrake (brake alone reverses); hold > 0 keeps the wanted level there (nobody escapes). */
  const step = (d: DriveWorld, p: Police, s: number, hold = 0) => {
    for (let i = 0; i < Math.round(s * 60); i++) {
      if (hold > 0) p.state = { ...p.state, level: hold, unseen: 0 };
      d.input.reset();
      d.input.handbrake = true;
      d.update(1 / 60);
      p.update(1 / 60);
    }
  };

  it('stands at level 3: two patrols across the road ahead, standing, one event', () => {
    const t = tuning3();
    const { d, p } = world(t);
    const events: Array<{ x: number; y: number }> = [];
    p.on('roadblock', (e) => events.push(e));
    step(d, p, 0.5);
    expect(p.roadblock).toBeNull(); // level 0
    step(d, p, 2, 3);
    const b = p.roadblock!;
    expect(b).not.toBeNull();
    expect(events.length).toBe(1);
    expect(b.x).toBeCloseTo(-100 + t.police.roadblock.aheadM, 0);
    expect(b.y).toBeCloseTo(0, 3);
    const ys = b.cars.map((c) => c.y).sort((u, v) => u - v);
    expect(ys[0]).toBeCloseTo(-t.police.roadblock.lateralM, 3);
    expect(ys[1]).toBeCloseTo(t.police.roadblock.lateralM, 3);
    for (const c of b.cars) {
      expect(c.police && c.blocking).toBe(true);
      expect(c.x).toBeCloseTo(b.x, 3);
      expect(Math.abs(Math.cos(c.heading))).toBeLessThan(1e-6);
    }
    const before = b.cars.map((c) => [c.x, c.y, c.heading]);
    step(d, p, 5, 3);
    expect(p.roadblock).toBe(b);
    expect(events.length).toBe(1);
    b.cars.forEach((c, i) => {
      expect(c.speed).toBe(0);
      expect(c.pursuing).toBe(false);
      expect(c.x).toBeCloseTo(before[i]![0]!, 6);
      expect(c.y).toBeCloseTo(before[i]![1]!, 6);
      expect(c.heading).toBeCloseTo(before[i]![2]!, 6);
    });
  }, 30000);

  it('not counted in patrols[level]', () => {
    // patrols[3] = 2: if the two blocking cars counted, no traffic car would become a patrol.
    const t = tuning3((raw) => (raw.police.patrols = [0, 0, 0, 2]));
    const { d, p } = world(t);
    step(d, p, 20, 3);
    expect(p.roadblock).not.toBeNull();
    const cops = d.traffic!.cars.filter((c) => c.police);
    expect(cops.filter((c) => c.blocking).length).toBe(2);
    expect(cops.filter((c) => !c.blocking).length).toBe(2);
  }, 30000);

  it('cleared after escaping below level 3, then cooldown_s', () => {
    // No chasing patrols, so nobody sees the player (the roadblock is farther than view_m).
    const t = tuning3((raw) => (raw.police.patrols = [0, 0, 0, 0]));
    const { d, p } = world(t);
    step(d, p, 1, 3);
    const b = p.roadblock!;
    expect(b).not.toBeNull();
    // Nobody sees the player: escape_s later the level drops to 2 and the roadblock goes.
    step(d, p, t.police.escapeS + 1);
    expect(p.wantedLevel).toBe(2);
    expect(p.roadblock).toBeNull();
    for (const c of b.cars) expect(d.traffic!.cars.includes(c)).toBe(false);
    // Back at 3: no new roadblock within cooldown_s of the clear, then one.
    step(d, p, t.police.roadblock.cooldownS - 2, 3);
    expect(p.roadblock).toBeNull();
    step(d, p, 3, 3);
    expect(p.roadblock).not.toBeNull();
  }, 30000);

  it('cleared after ttl_s', () => {
    const t = tuning3();
    const { d, p } = world(t);
    step(d, p, 1, 3);
    expect(p.roadblock).not.toBeNull();
    step(d, p, t.police.roadblock.ttlS - 2, 3);
    expect(p.roadblock).not.toBeNull();
    step(d, p, 2, 3);
    expect(p.roadblock).toBeNull();
  }, 60000);

  it('cleared when the player is farther than clear_m; survives traffic despawn_m', () => {
    const hop = (d: DriveWorld, p: Police, xs: number[]) => {
      for (const x of xs) {
        d.spawn(x, 0, Math.PI);
        step(d, p, 0.2, 3);
      }
    };
    // Huge clear_m: beyond despawn_m the blocking cars stay.
    const t1 = tuning3((raw) => (raw.police.roadblock.clear_m = 5000.0));
    const w1 = world(t1);
    step(w1.d, w1.p, 1, 3);
    const b = w1.p.roadblock!;
    expect(b).not.toBeNull();
    hop(w1.d, w1.p, [-150, -200, -250, -300, -350]);
    expect(Math.abs(-350 - b.x)).toBeGreaterThan(t1.traffic.despawnM);
    expect(w1.p.roadblock).toBe(b);
    for (const c of b.cars) expect(w1.d.traffic!.cars.includes(c)).toBe(true);
    // Default clear_m: gone once the player is that far away.
    const t2 = tuning3();
    const w2 = world(t2);
    step(w2.d, w2.p, 1, 3);
    const b2 = w2.p.roadblock!;
    expect(b2).not.toBeNull();
    hop(w2.d, w2.p, [-150, -200]);
    expect(w2.p.roadblock).toBe(b2);
    hop(w2.d, w2.p, [-250]);
    expect(Math.abs(-250 - b2.x)).toBeGreaterThan(t2.police.roadblock.clearM);
    expect(w2.p.roadblock).toBeNull();
  }, 30000);

  it('a traffic reset drops it; clearRoadblock (respawn) too', () => {
    const t = tuning3();
    const { d, p } = world(t);
    step(d, p, 1, 3);
    expect(p.roadblock).not.toBeNull();
    d.traffic!.reset();
    step(d, p, 0.2, 3);
    expect(p.roadblock).toBeNull();
    step(d, p, t.police.roadblock.cooldownS + 1, 3);
    expect(p.roadblock).not.toBeNull();
    p.clearRoadblock();
    expect(p.roadblock).toBeNull();
  }, 60000);
});
