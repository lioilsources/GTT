import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { gzipSync } from 'node:zlib';

import { create, toBinary, type DescMessage, type MessageShape } from '@bufbuild/protobuf';
import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { DriveWorld } from '../src/drive/driveWorld';
import { surfaceEffect, treeHit, treePush, TreeContacts, WaterFall } from '../src/drive/nature';
import {
  ChunkSchema, EdgeSchema, GraphSchema, GreenClass, GroundKind, LandmarksSchema, ManifestSchema, MeshSchema, NodeSchema,
  RoadClass, SpawnSchema, SpotsSchema, Surface, WaterClass,
} from '../src/gen/pb/citypack_pb';
import type { CarSpec } from '../src/gen/schema';
import { Tuning } from '../src/gen/tuning';
import { prepareChunk, type ChunkData } from '../src/world/chunk';
import { decodeTrees, inPiece, NatureMap, prepareNature } from '../src/world/nature';
import { City } from '../src/world/model';
import { groundTris, Tris } from '../src/render/geometry';
import { bankTris, crownJitter, greenTris, visibleTrees, waterTris } from '../src/render/natureGeometry';
import { dayPalette, rgba } from '../src/render/palette';
import { tokens } from '../src/gen/tokens';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const sedan = JSON.parse(readFileSync(join(root, 'content', 'cars', 'sedan_regent.json'), 'utf8')) as CarSpec;
const th = tuning.flow.treeHit;
const CM = 256;

const gz = <D extends DescMessage>(schema: D, m: MessageShape<D>): Uint8Array => new Uint8Array(gzipSync(toBinary(schema, m)));

describe('nature data (specs/nature.md "Data v balíčku")', () => {
  it('decodes trees: x, y from the south-west corner, size in the low 2 bits, jitter above', () => {
    const t = decodeTrees(Uint8Array.from([10, 20, 1 | (5 << 2), 255, 0, 2]), -1, 2, CM);
    expect(t).toEqual([
      { x: -246, y: 532, size: 1, jitter: 5, key: '-1_2/0' },
      { x: -1, y: 512, size: 2, jitter: 0, key: '-1_2/1' },
    ]);
  });

  it('a pack without nature (nature_version 0) has no nature part', () => {
    const c = create(ChunkSchema, { x: 0, y: 0, trees: Uint8Array.from([1, 1, 1]) });
    expect(prepareNature(c, CM, 0)).toBeNull();
    expect(prepareNature(c, CM, 1)!.trees.length).toBe(1);
  });

  it('point queries: water, smallest green, park name, surface', () => {
    const c = create(ChunkSchema, {
      x: 0, y: 0,
      ground: [
        rectMesh(GroundKind.PARK, 0, 0, 100, 100, { greenClass: GreenClass.GREEN_PARKLAND, surface: Surface.GRASS, name: 'Park' }),
        rectMesh(GroundKind.PARK, 10, 10, 20, 20, { greenClass: GreenClass.GREEN_SAND, surface: Surface.SAND }),
        rectMesh(GroundKind.WATER, 150, 0, 200, 50, { waterClass: WaterClass.WATER_RIVER, name: 'River' }),
      ],
    });
    const m = new NatureMap(CM);
    m.add(prepareNature(c, CM, 1)!);
    expect(m.surfaceAt(50, 50)).toBe('grass');
    expect(m.surfaceAt(15, 15)).toBe('sand');
    expect(m.surfaceAt(120, 50)).toBe('asphalt');
    expect(m.parkAt(15, 15)).toBe('Park');
    expect(m.waterAt(160, 10)?.name).toBe('River');
    expect(m.waterAt(140, 10)).toBeNull();
    expect(inPiece(m.waterAt(160, 10)!, 199.9, 49.9)).toBe(true);
    m.remove(0, 0);
    expect(m.surfaceAt(50, 50)).toBe('asphalt');
  });
});

describe('soft trees (specs/flow.md "Strom jako měkká překážka")', () => {
  it('M/L: speed × speed_keep, side from the cross product, yaw away, push away from the trunk', () => {
    const h = treeHit(20, 0, 0, 0, 2, 1, 1, th); // trunk ahead-left
    expect(h.vx).toBeCloseTo(20 * th.speedKeep, 9);
    expect(h.side).toBe(1);
    expect(h.yaw).toBeCloseTo((-th.yawKickDeg * Math.PI) / 180, 9);
    expect([h.ax, h.ay]).toEqual([0, -1]);
    const r = treeHit(20, 0, 0, 0, 2, -1, 2, th);
    expect(r.side).toBe(-1);
    expect([r.ax, r.ay]).toEqual([-0, 1]);
    // Dead ahead counts as left (+1): pushed to the right.
    expect(treeHit(0, 10, 0, 0, 0, 3, 1, th).side).toBe(1);
  });

  it('never below min_speed_mps when it was above; a sapling only slows and falls', () => {
    expect(Math.hypot(treeHit(5, 0, 0, 0, 1, 0, 1, th).vx, 0)).toBeCloseTo(th.minSpeedMps, 9);
    expect(treeHit(3, 0, 0, 0, 1, 0, 1, th).vx).toBeCloseTo(3 * th.speedKeep, 9);
    const s = treeHit(10, 0, 0, 0, 1, 0, 0, th);
    expect([s.vx, s.fell, s.side, s.yaw]).toEqual([10 * th.saplingSpeedKeep, true, 0, 0]);
  });

  it('push keeps the away component at push_mps, never adds on top', () => {
    expect(treePush(15, 0, 0, -1, 8)).toEqual({ vx: 15, vy: -8 });
    expect(treePush(15, -9, 0, -1, 8)).toEqual({ vx: 15, vy: -9 });
  });

  it('cooldown per tree, one hit per overlap, sapling stays down 60 s', () => {
    const m = new NatureMap(CM);
    const c = create(ChunkSchema, { x: 0, y: 0, trees: Uint8Array.from([50, 50, 1, 60, 50, 0]) });
    m.add(prepareNature(c, CM, 1)!);
    const tc = new TreeContacts();
    const car = { x: 49, y: 50, vx: 10, vy: 0, halfWidth: 0.9 };
    const r1 = tc.step(1 / 60, 0, m, car, tuning)!;
    expect(r1.vx).toBeCloseTo(7.5, 9);
    expect(tc.hits).toBe(1);
    // Still overlapping: pushed, not hit again.
    const r2 = tc.step(1 / 60, 1 / 60, m, { ...car, vx: 7.5, vy: 0 }, tuning)!;
    expect(r2.vy).toBeCloseTo(-th.pushMps, 9);
    expect(tc.hits).toBe(1);
    // Leave and come back within the cooldown: no hit.
    tc.step(1 / 60, 0.05, m, { ...car, x: 40 }, tuning);
    tc.step(1 / 60, 0.1, m, car, tuning);
    expect(tc.hits).toBe(1);
    // The sapling falls once and is ignored afterwards.
    tc.step(1 / 60, 1, m, { ...car, x: 59.5 }, tuning);
    expect(tc.hits).toBe(2);
    expect(tc.fallen.has('0_0/1')).toBe(true);
    tc.step(1, 2, m, { ...car, x: 300 }, tuning);
    tc.step(1, 3, m, { ...car, x: 59.5 }, tuning);
    expect(tc.hits).toBe(2);
    tc.step(1, 62, m, { ...car, x: 300 }, tuning);
    expect(tc.fallen.has('0_0/1')).toBe(false);
  });

  it('surfaces: nature.grip; forest grip and speed factor from flow.forest', () => {
    expect(surfaceEffect('asphalt', tuning)).toEqual({ grip: 1, speed: 1 });
    expect(surfaceEffect('sand', tuning).grip).toBe(tuning.nature.grip.sand);
    expect(surfaceEffect('forest', tuning)).toEqual({ grip: tuning.flow.forest.grip, speed: tuning.flow.forest.speedFactor });
  });

  it('water fall: velocity runs out linearly over sink_s', () => {
    const w = new WaterFall();
    w.start(10, 0);
    expect(w.step(0.6, 1.2)).toBe(false);
    expect(w.velocity(1.2).x).toBeCloseTo(5, 9);
    expect(w.step(0.6, 1.2)).toBe(true);
  });
});

// ---------- synthetic track (specs/nature.md "Scénáře", specs/flow.md "Scénáře"), shared with packages/drive_core

interface Rect {
  kind: GroundKind;
  x0: number;
  y0: number;
  x1: number;
  y1: number;
  opt: Partial<{ waterClass: WaterClass; greenClass: GreenClass; surface: Surface; name: string }>;
}

function rectMesh(kind: GroundKind, x0: number, y0: number, x1: number, y1: number, opt: Rect['opt']) {
  return create(MeshSchema, {
    kind, vertices: [x0, y0, x1, y0, x1, y1, x0, y1].map((v) => Math.round(v * 10)), indices: [0, 1, 2, 0, 2, 3], ...opt,
  });
}

/** Chunks of the scenario: rectangles clipped to the chunk grid, trees in the chunk of their trunk (in list order). */
async function natureChunks(rects: Rect[], trees: Array<{ x: number; y: number; size: number }>): Promise<ChunkData[]> {
  const out: ChunkData[] = [];
  for (let cx = -2; cx <= 1; cx++) {
    for (let cy = -2; cy <= 1; cy++) {
      const ground = [];
      for (const r of rects) {
        const x0 = Math.max(r.x0, cx * CM), x1 = Math.min(r.x1, (cx + 1) * CM), y0 = Math.max(r.y0, cy * CM), y1 = Math.min(r.y1, (cy + 1) * CM);
        if (x1 > x0 && y1 > y0) ground.push(rectMesh(r.kind, x0, y0, x1, y1, r.opt));
      }
      const tb: number[] = [];
      for (const t of trees) {
        if (Math.floor(t.x / CM) !== cx || Math.floor(t.y / CM) !== cy) continue;
        tb.push(t.x - cx * CM, t.y - cy * CM, t.size);
      }
      const c = create(ChunkSchema, { x: cx, y: cy, ground, trees: Uint8Array.from(tb) });
      out.push(await prepareChunk(gz(ChunkSchema, c), { chunkM: CM, version: 1 }));
    }
  }
  return out;
}

/** 0 (−200,0) ──e0── 1 (0,0) ──e1── 2 (200,0): primary, 2 lanes, kept, 20 m wide (as specs/flow.md). */
async function trackCity(): Promise<City> {
  const n = (x: number, y: number) => create(NodeSchema, { x: x * 10, y: y * 10 });
  const e = (from: number, to: number, pts: number[]) =>
    create(EdgeSchema, { from, to, points: pts.map((v) => v * 10), class: RoadClass.PRIMARY, lanes: 2, oneway: 0, kept: true, widthM: 20 });
  const graph = create(GraphSchema, { names: [''], nodes: [n(-200, 0), n(0, 0), n(200, 0)], edges: [e(0, 1, [-200, 0, 0, 0]), e(1, 2, [0, 0, 200, 0])] });
  const files: Record<string, Uint8Array> = {
    'manifest.pb': gz(ManifestSchema, create(ManifestSchema, {
      formatVersion: 1, cityId: 'test', chunkM: CM, driveSide: 'right', units: 'metric', natureVersion: 1,
      start: create(SpawnSchema, { x: -1500, y: 0, headingRad: 0 }),
    })),
    'graph.pb': gz(GraphSchema, graph),
    'landmarks.pb': gz(LandmarksSchema, create(LandmarksSchema, {})),
    'spots.pb': gz(SpotsSchema, create(SpotsSchema, {})),
  };
  return City.load({ read: async (p) => files[p] ?? Promise.reject(new Error(p)) });
}

type Inputs = Array<{ t: number; throttle?: number; steer?: number; brake?: number; boost?: number }>;

interface Setup {
  start: { x: number; y: number; deg: number; v: number };
  s: number;
  rects: Rect[];
  trees: Array<{ x: number; y: number; size: number }>;
}

const grass = (s: Surface, cls: GreenClass): Rect => ({ kind: GroundKind.PARK, x0: -200, y0: 80, x1: 200, y1: 120, opt: { greenClass: cls, surface: s } });

/** Parkland trees: a 10 × 10 grid at 9 m from (−100, 60), sizes (i + j) mod 3. */
const PARK_TREES = Array.from({ length: 100 }, (_, k) => ({ x: -100 + 9 * (k % 10), y: 60 + 9 * Math.floor(k / 10), size: ((k % 10) + Math.floor(k / 10)) % 3 }));
/** Forest lane: medium trees every 11 m on y = 100 from x = 11 to 198. */
const FOREST_TREES = Array.from({ length: 18 }, (_, k) => ({ x: 11 * (k + 1), y: 100, size: 1 }));

const SETUPS: Record<string, Setup> = {
  'nature/brake_asphalt': { start: { x: -100, y: 100, deg: 0, v: 20 }, s: 4, rects: [], trees: [] },
  'nature/brake_grass': { start: { x: -100, y: 100, deg: 0, v: 20 }, s: 4, rects: [grass(Surface.GRASS, GreenClass.GREEN_GRASS)], trees: [] },
  'nature/brake_sand': { start: { x: -100, y: 100, deg: 0, v: 20 }, s: 4, rects: [grass(Surface.SAND, GreenClass.GREEN_SAND)], trees: [] },
  'nature/water_fall': {
    start: { x: 60, y: 0, deg: 90, v: 10 }, s: 5,
    rects: [{ kind: GroundKind.WATER, x0: -200, y0: 30, x1: 200, y1: 200, opt: { waterClass: WaterClass.WATER_RIVER, name: 'Řeka' } }], trees: [],
  },
  'nature/parkland_trees': {
    start: { x: -120, y: 100, deg: 0, v: 12 }, s: 8,
    rects: [{ kind: GroundKind.PARK, x0: -200, y0: 40, x1: 200, y1: 200, opt: { greenClass: GreenClass.GREEN_PARKLAND, surface: Surface.GRASS, name: 'Park' } }],
    trees: PARK_TREES,
  },
  'flow/forest_200': {
    start: { x: 0, y: 100, deg: 0, v: 15 }, s: 20,
    rects: [{ kind: GroundKind.PARK, x0: -50, y0: 60, x1: 250, y1: 140, opt: { greenClass: GreenClass.GREEN_WOOD, surface: Surface.FOREST } }],
    trees: FOREST_TREES,
  },
  'flow/tree_head_on': { start: { x: -3, y: 100, deg: 0, v: 20 }, s: 2, rects: [], trees: [{ x: 0, y: 100, size: 1 }] },
};

const DEFAULT_INPUTS: Record<string, Inputs> = {
  'nature/brake_asphalt': [{ t: 0, brake: 1 }],
  'nature/brake_grass': [{ t: 0, brake: 1 }],
  'nature/brake_sand': [{ t: 0, brake: 1 }],
  'nature/water_fall': [{ t: 0 }],
  'nature/parkland_trees': [{ t: 0 }, { t: 1, steer: 0.4 }, { t: 2.2, steer: -0.4 }, { t: 4, steer: 0.2 }, { t: 5.5, steer: 0 }],
  'flow/forest_200': [{ t: 0, throttle: 1, boost: 1 }],
  'flow/tree_head_on': [{ t: 0 }],
};

const round = (v: number): number => Math.round(v * 1000) / 1000;

async function runScenario(id: string, inputs: Inputs): Promise<Record<string, number>> {
  const st = SETUPS[id]!;
  const city = await trackCity();
  const d = new DriveWorld(city, sedan, tuning);
  for (const c of await natureChunks(st.rects, st.trees)) d.addChunk(c);
  d.props.clear();
  if (d.traffic) d.traffic.solid = false;
  const h = (st.start.deg * Math.PI) / 180;
  d.spawn(st.start.x, st.start.y, h);
  d.car.body.setLinearVelocity({ x: st.start.v * Math.cos(h), y: st.start.v * Math.sin(h) });
  const dt = 1 / tuning.drive.stepHz;
  const steps = Math.round(st.s / dt);
  let rescues = 0, sunk: { t: number; node: number; x: number; y: number; heading: number } | null = null, entry = -1, entryY = 0;
  d.onRescue = () => rescues++;
  d.onWater = () => {
    entry = d.time;
    entryY = d.car.y;
  };
  d.onSunk = (node) => (sunk = { t: d.time, node, x: d.car.x, y: d.car.y, heading: d.car.heading });
  let k = 0, brakeM = -1, brakeS = -1, minSpeed = Infinity, t200 = -1, minTrunk = Infinity, before = 0, after = -1;
  for (let i = 0; i < steps; i++) {
    while (k + 1 < inputs.length && inputs[k + 1]!.t <= d.time + 1e-9) k++;
    const inp = inputs[k]!;
    d.input.reset();
    d.input.throttle = inp.throttle ?? 0;
    d.input.steer = inp.steer ?? 0;
    d.input.brake = inp.brake ?? 0;
    d.input.boost = (inp.boost ?? 0) > 0;
    const hits0 = d.trees.hits;
    const v0 = d.car.body.getLinearVelocity();
    const pre = { vx: v0.x, vy: v0.y };
    d.update(dt);
    const c = d.car, sp = c.speed;
    if (brakeM < 0 && (inp.brake ?? 0) > 0 && sp < tuning.drive.brakeMinMps) {
      brakeM = round(Math.hypot(c.x - st.start.x, c.y - st.start.y));
      brakeS = round(d.time);
    }
    if (id === 'flow/forest_200' && t200 < 0) {
      minSpeed = Math.min(minSpeed, sp);
      if (c.x >= 200) t200 = round(d.time);
    }
    if (id === 'flow/tree_head_on') {
      minTrunk = Math.min(minTrunk, Math.hypot(c.x - 0, c.y - 100));
      if (d.trees.hits > hits0 && after < 0) {
        const s0 = Math.hypot(pre.vx, pre.vy);
        before = s0;
        const v = c.body.getLinearVelocity();
        after = (v.x * pre.vx + v.y * pre.vy) / s0;
      }
    }
    if (id === 'nature/parkland_trees') minSpeed = Math.min(minSpeed, sp);
  }
  const m: Record<string, number> = {};
  if (id.startsWith('nature/brake_')) {
    m['brake_m'] = brakeM;
    m['brake_s'] = brakeS;
  } else if (id === 'nature/water_fall') {
    const s = sunk as { t: number; node: number; x: number; y: number; heading: number } | null;
    m['falls'] = d.water.falls;
    m['entry_y_m'] = round(entryY);
    m['sink_s'] = s ? round(s.t - entry) : -1;
    m['respawn_node'] = s ? s.node : -1;
    m['respawn_heading_deg'] = s ? round((((s.heading * 180) / Math.PI) % 360 + 360) % 360) : -1;
    m['rescues'] = rescues;
  } else if (id === 'nature/parkland_trees') {
    m['tree_hits'] = d.trees.hits;
    m['saplings_fallen'] = d.trees.fallen.size;
    m['min_speed_mps'] = round(minSpeed);
    m['rescues'] = rescues;
  } else if (id === 'flow/forest_200') {
    m['min_speed_mps'] = round(minSpeed);
    m['time_200_s'] = t200;
    m['tree_hits'] = d.trees.hits;
    m['rescues'] = rescues;
  } else {
    m['speed_before_mps'] = round(before);
    m['speed_after_mps'] = round(after);
    m['min_trunk_dist_m'] = round(minTrunk);
    m['passed'] = d.car.x > 5 ? 1 : 0;
    m['tree_hits'] = d.trees.hits;
  }
  return m;
}

interface Scenario {
  inputs: Inputs;
  expect: Record<string, { value: number | null; tol: number }>;
}

describe('nature and forest scenarios on the synthetic track (scenarios/nature, scenarios/flow, ±5 %)', () => {
  const results: Record<string, Record<string, number>> = {};
  for (const id of Object.keys(SETUPS)) {
    it(id, async () => {
      const file = join(root, 'scenarios', `${id}.json`);
      const sc = existsSync(file) ? (JSON.parse(readFileSync(file, 'utf8')) as Scenario) : null;
      const m = (results[id] = await runScenario(id, sc?.inputs ?? DEFAULT_INPUTS[id]!));
      if (process.env['NATURE_RECORD']) console.log(id, JSON.stringify(m));
      // Acceptance (specs/nature.md, specs/flow.md "Scénáře").
      if (id === 'nature/water_fall') {
        expect(m['falls']).toBe(1);
        expect(m['respawn_node']).toBe(1);
        expect(m['sink_s']).toBeCloseTo(tuning.nature.waterFall.sinkS, 1);
        expect(m['rescues']).toBe(0);
      } else if (id === 'flow/forest_200') {
        expect(m['min_speed_mps']).toBeGreaterThanOrEqual(th.minSpeedMps);
        expect(m['time_200_s']).toBeGreaterThan(0);
        expect(m['rescues']).toBe(0);
      } else if (id === 'flow/tree_head_on') {
        expect(m['speed_after_mps']).toBeGreaterThan(15 * 0.95);
        expect(m['speed_after_mps']).toBeLessThan(15 * 1.05);
        expect(m['passed']).toBe(1);
        expect(m['min_trunk_dist_m']).toBeGreaterThan(tuning.nature.trunkRadiusM);
      } else if (id === 'nature/parkland_trees') {
        expect(m['tree_hits']).toBeGreaterThan(0);
        expect(m['rescues']).toBe(0);
      }
      for (const [key, e] of Object.entries(sc?.expect ?? {})) {
        if (e.value === null) continue;
        expect(m[key], key).toBeDefined();
        expect(Math.abs(m[key]! - e.value), key).toBeLessThanOrEqual(Math.abs(e.value) * e.tol + 1e-9);
      }
    });
  }
  it('brake distance: grass and sand longer than asphalt', () => {
    const a = results['nature/brake_asphalt']?.['brake_m'] ?? 0;
    expect(results['nature/brake_grass']!['brake_m']).toBeGreaterThan(a);
    expect(results['nature/brake_sand']!['brake_m']).toBeGreaterThan(results['nature/brake_grass']!['brake_m']!);
  });
});

describe('nature drawing geometry (specs/nature.md "Vykreslení shora", P2)', () => {
  const chunk = (x0: number, x1: number) => prepareNature(create(ChunkSchema, {
    x: 0, y: 0, trees: Uint8Array.from([10, 10, 0, 200, 200, 1, 100, 100, 2]),
    ground: [
      rectMesh(GroundKind.WATER, x0, 0, x1, 100, { waterClass: WaterClass.WATER_RIVER }),
      rectMesh(GroundKind.PARK, 0, 150, 100, 250, { greenClass: GreenClass.GREEN_WOOD, surface: Surface.FOREST }),
    ],
  }), CM, 1)!;

  it('bank line: outer water edges only, none on the chunk grid', () => {
    // Water x 0..100 touches the chunk edges x = 0 and y = 0: the edges x = 100 and y = 100 remain.
    const t = new Tris();
    bankTris(chunk(0, 100), CM, dayPalette, t);
    expect(t.idx.length / 3).toBe(2 * (2 + 6));
    // Water x 50..100: also its west edge.
    const t2 = new Tris();
    bankTris(chunk(50, 100), CM, dayPalette, t2);
    expect(t2.idx.length / 3).toBe(3 * (2 + 6));
  });

  it('green fills by class; the old ground draw skips water and parks of a chunk with nature', () => {
    const n = chunk(0, 100);
    const g = new Tris();
    greenTris(n, dayPalette, g);
    expect(g.col.slice(0, 3)).toEqual([...rgba(tokens.colorGreenWood)].slice(0, 3));
    const plain = new Tris();
    const tri = { xy: new Float32Array([0, 0, 1, 0, 1, 1]), indices: new Uint32Array([0, 1, 2]) };
    groundTris({ x: 0, y: 0, buildings: [], barriers: [], ground: [{ kind: GroundKind.WATER, ...tri }, { kind: GroundKind.PARK, ...tri }], nature: n }, dayPalette, plain);
    expect(plain.empty).toBe(true);
    groundTris({ x: 0, y: 0, buildings: [], barriers: [], ground: [{ kind: GroundKind.WATER, ...tri }] }, dayPalette, plain);
    expect(plain.empty).toBe(false);
  });

  it('water plane carries the wave strength; trees capped nearest first', () => {
    const m = new NatureMap(CM);
    m.add(chunk(0, 100));
    const w = new Tris();
    waterTris(m, dayPalette, w);
    expect(w.col[3]).toBe(1);
    expect(visibleTrees(m, 0, 0, 300, 2, () => false).map((t) => t.key)).toEqual(['0_0/0', '0_0/2']);
    expect(visibleTrees(m, 0, 0, 300, 10, (t) => t.size === 0).length).toBe(2);
    for (let j = 0; j < 64; j++) for (const c of crownJitter(j)) expect(c).toBeGreaterThan(0.8);
  });
});
