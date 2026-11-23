import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { gzipSync } from 'node:zlib';

import { create, toBinary, type DescMessage, type MessageShape } from '@bufbuild/protobuf';
import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { DriveWorld } from '../src/drive/driveWorld';
import {
  easeHeading, FlowState, RESCUE_GRACE_S, rewindIndex, roadSpot, stuckLine, TRAIL_MAX, wallResponse, type StuckKind, type TrailPoint,
} from '../src/drive/flow';
import { EdgeSchema, GraphSchema, LandmarksSchema, ManifestSchema, NodeSchema, RoadClass, SpawnSchema, SpotsSchema } from '../src/gen/pb/citypack_pb';
import type { CarSpec } from '../src/gen/schema';
import { Tuning } from '../src/gen/tuning';
import type { BuildingData } from '../src/world/chunk';
import { City, RoadGraph } from '../src/world/model';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const sedan = JSON.parse(readFileSync(join(root, 'content', 'cars', 'sedan_regent.json'), 'utf8')) as CarSpec;
const wall = tuning.flow.wall;
const rescue = tuning.flow.rescue;

describe('wall response (specs/flow.md "Náraz do pevné překážky")', () => {
  it('30° at 20 m/s slides along the wall with at least 14.72 m/s', () => {
    const a = (30 * Math.PI) / 180;
    const r = wallResponse(20 * Math.cos(a), 20 * Math.sin(a), 0, -1, wall)!;
    expect(r.slide).toBe(true);
    expect(r.vy).toBeCloseTo(0, 9);
    expect(r.vx).toBeGreaterThanOrEqual(20 * wall.slideSpeedKeep * Math.cos(a));
    expect(r.tx).toBeCloseTo(1, 9);
  });

  it('head-on bounces with restitution, keeps the tangential part', () => {
    const a = (80 * Math.PI) / 180;
    const r = wallResponse(10 * Math.cos(a), 10 * Math.sin(a), 0, -1, wall)!;
    expect(r.slide).toBe(false);
    expect(r.vy).toBeCloseTo(-10 * Math.sin(a) * wall.restitution, 9);
    expect(r.vx).toBeCloseTo(10 * Math.cos(a), 9);
  });

  it('no response when moving away or standing', () => {
    expect(wallResponse(0, 5, 0, 1, wall)).toBeNull();
    expect(wallResponse(0, 0, 0, 1, wall)).toBeNull();
  });

  it('heading eases to the nearer wall direction at 6 rad/s', () => {
    const h = easeHeading(0.5, 1, 0, 1 / 60);
    expect(h).toBeCloseTo(0.5 * Math.exp(-6 / 60), 9);
    // Nose pointing backwards along the wall: eases to π, not 0.
    expect(easeHeading(3, 1, 0, 1)).toBeGreaterThan(3);
  });
});

describe('trail and rescue rules (specs/flow.md "Vyproštění")', () => {
  const line = (n: number, step: number): TrailPoint[] => Array.from({ length: n }, (_, i) => ({ x: i * step, y: 0, heading: 0, t: 0 }));

  it('rewind picks the point closest to the distance along the trail, else the oldest', () => {
    const tr = line(10, 5); // 0..45
    expect(rewindIndex(tr, 47, 0, 8)).toBe(8); // 47→45 (2), →40 (7), →35 (12): 7 is closest to 8
    expect(rewindIndex(tr, 47, 0, 20)).toBe(5); // 17 vs 22: 22 − 20 = 2 < 3
    expect(rewindIndex(tr, 47, 0, 100)).toBe(0);
    expect(rewindIndex([], 0, 0, 8)).toBe(-1);
  });

  const car = (o: Partial<{ x: number; y: number; heading: number; speed: number; braking: boolean; airborne: boolean }> = {}) =>
    ({ x: 0, y: 0, heading: 0, speed: 10, braking: false, airborne: false, ...o });

  it('samples every 0.25 s above 3 m/s on the ground and keeps 20 points', () => {
    const f = new FlowState(rescue);
    const dt = 1 / 60;
    for (let i = 0; i < 60; i++) f.step(dt, i * dt, car({ x: i }), false);
    expect(f.trail.length).toBe(4);
    for (let i = 0; i < 60; i++) f.step(dt, 1 + i * dt, car({ speed: 3 }), false);
    for (let i = 0; i < 60; i++) f.step(dt, 2 + i * dt, car({ airborne: true }), false);
    expect(f.trail.length).toBe(4);
    for (let i = 0; i < 600; i++) f.step(dt, 3 + i * dt, car(), false);
    expect(f.trail.length).toBe(TRAIL_MAX);
  });

  it('stuck without brake: rewind 8 m, then 20 m, then the road; brake and context buttons hold it off', () => {
    const f = new FlowState(rescue);
    const dt = 1 / 60;
    let t = 0;
    for (let i = 0; i < 120; i++, t += dt) f.step(dt, t, car({ x: i * 0.5 }), false);
    const run = (o: Parameters<typeof car>[0], blocked = false, s = 3): StuckKind | null => {
      for (let i = 0; i < s * 60; i++, t += dt) {
        const p = f.step(dt, t, car({ x: 60, speed: 0.2, ...o }), blocked);
        if (p) return p.kind;
      }
      return null;
    };
    expect(run({}, true, 2)).toBeNull();
    expect(run({})).toBe('auto1');
    expect(f.graceT).toBeCloseTo(RESCUE_GRACE_S, 6);
    // Between attempts the car drives back towards the trap (new trail points).
    const back = (): void => {
      for (let i = 0; i < 60; i++, t += dt) f.step(dt, t, car({ x: 50 + i * 0.16 }), false);
    };
    back();
    expect(run({})).toBe('auto2');
    back();
    expect(run({})).toBe('road');
    expect(f.trail.length).toBe(0);
    expect(f.events.map((e) => e.kind)).toEqual(['auto1', 'auto2', 'road']);
    expect(f.count10(t)).toBe(3);
    expect(f.count10(t + 601)).toBe(0);
    // Later than 5 s after the last rescue: a first attempt again.
    for (let i = 0; i < 6 * 60; i++, t += dt) f.step(dt, t, car({ x: 200 }), false);
    expect(run({ x: 200 })).toBe('auto1');
    for (let i = 0; i < 2 * 60; i++, t += dt) f.step(dt, t, car({ x: 300 }), false);
    expect(run({ x: 300, braking: true }, false, 3.5)).toBeNull();
    expect(f.buttonShown).toBe(true);
  });

  it('stuck.log line', () => {
    expect(stuckLine(1700000000.7, 'nyc', { t: 3, kind: 'road', x: 1.234, y: -5.06 })).toBe('{"t":1700000000,"city":"nyc","x":1.2,"y":-5.1,"kind":"road"}');
  });
});

// ---------- synthetic track (specs/flow.md "Scénáře"), shared with packages/drive_core

const gz = <D extends DescMessage>(schema: D, m: MessageShape<D>): Uint8Array => new Uint8Array(gzipSync(toBinary(schema, m)));

/** 0 (−200,0) ──e0── 1 (0,0) ──e1── 2 (200,0): primary, 2 lanes, kept, 20 m wide. */
function flowGraph() {
  const n = (x: number, y: number) => create(NodeSchema, { x: x * 10, y: y * 10 });
  const e = (from: number, to: number, pts: number[]) =>
    create(EdgeSchema, { from, to, points: pts.map((v) => v * 10), class: RoadClass.PRIMARY, lanes: 2, oneway: 0, kept: true, widthM: 20 });
  return create(GraphSchema, { names: [''], nodes: [n(-200, 0), n(0, 0), n(200, 0)], edges: [e(0, 1, [-200, 0, 0, 0]), e(1, 2, [0, 0, 200, 0])] });
}

async function flowCity(): Promise<City> {
  const files: Record<string, Uint8Array> = {
    'manifest.pb': gz(ManifestSchema, create(ManifestSchema, {
      formatVersion: 1, cityId: 'test', chunkM: 256, driveSide: 'right', units: 'metric',
      start: create(SpawnSchema, { x: -1500, y: 0, headingRad: 0 }),
    })),
    'graph.pb': gz(GraphSchema, flowGraph()),
    'landmarks.pb': gz(LandmarksSchema, create(LandmarksSchema, {})),
    'spots.pb': gz(SpotsSchema, create(SpotsSchema, {})),
  };
  return City.load({ read: async (p) => files[p] ?? Promise.reject(new Error(p)) });
}

function box(x0: number, y0: number, x1: number, y1: number): BuildingData {
  const xy = Float32Array.from([x0, y0, x1, y0, x1, y1, x0, y1]);
  const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
  return {
    xy, ringEnds: Int32Array.from([4]), roof: new Uint16Array(), height: 10, minHeight: 0, landmark: 0, collide: true, seed: 0,
    cx, cy, radius: Math.hypot(x1 - cx, y1 - cy), wallU: new Float32Array(4),
  };
}

/** Wall W (face y = 40, x −100..60) and block B (face x = 60, y 15..40): a concave corner at (60, 40). */
const BUILDINGS = [box(-100, 40, 60, 60), box(60, 15, 80, 60)];

interface Scenario {
  module: string;
  name: string;
  car?: string;
  inputs: Array<{ t: number; throttle?: number; steer?: number; brake?: number }>;
  expect: Record<string, { value: number | null; tol: number }>;
}

/** Start pose and speed of each scenario (specs/flow.md "Scénáře"). */
const STARTS: Record<string, { x: number; y: number; deg: number; v: number; s: number }> = {
  wall_30: { x: 0, y: 33.8, deg: 30, v: 20, s: 2 },
  wall_head_on: { x: 0, y: 5, deg: 90, v: 0, s: 8 },
  corner_3x: { x: 20, y: 0, deg: 47, v: 0, s: 20 },
};

const KIND: Record<StuckKind, number> = { auto1: 1, auto2: 2, road: 3, button: 4 };

/** Runs one scenario on the synthetic track; returns its metrics. */
async function runScenario(name: string, inputs: Scenario['inputs']): Promise<Record<string, number>> {
  const city = await flowCity();
  const d = new DriveWorld(city, sedan, tuning);
  d.addChunk({ x: 0, y: 0, buildings: BUILDINGS, ground: [], barriers: [] });
  d.props.clear(); // the track has no street furniture
  if (d.traffic) d.traffic.solid = false;
  const st = STARTS[name]!;
  const h = (st.deg * Math.PI) / 180;
  d.spawn(st.x, st.y, h);
  d.car.body.setLinearVelocity({ x: st.v * Math.cos(h), y: st.v * Math.sin(h) });
  const rescues: Array<{ t: number; kind: StuckKind; fromX: number; fromY: number; x: number; y: number; heading: number }> = [];
  let pre = { x: 0, y: 0 };
  d.onRescue = (kind) => rescues.push({ t: d.time, kind, fromX: pre.x, fromY: pre.y, x: d.car.x, y: d.car.y, heading: d.car.heading });
  const dt = 1 / tuning.drive.stepHz;
  let firstContact = -1, alongFirst = 0, alongMin = Infinity;
  const steps = Math.round(st.s / dt);
  let k = 0;
  for (let i = 0; i < steps; i++) {
    while (k + 1 < inputs.length && inputs[k + 1]!.t <= d.time + 1e-9) k++;
    const inp = inputs[k]!;
    d.input.reset();
    d.input.throttle = inp.throttle ?? 0;
    d.input.steer = inp.steer ?? 0;
    d.input.brake = inp.brake ?? 0;
    pre = { x: d.car.x, y: d.car.y };
    d.update(dt);
    const v = d.car.body.getLinearVelocity();
    if (firstContact < 0 && (d as unknown as { wallContact: boolean }).wallContact) {
      firstContact = d.time;
      alongFirst = v.x;
    }
    if (firstContact >= 0 && d.time <= firstContact + 1 + 1e-9) alongMin = Math.min(alongMin, v.x);
    if (process.env['FLOW_TRACE'] === name && i % 3 === 0) console.log(d.time.toFixed(3), d.car.x.toFixed(2), d.car.y.toFixed(2), v.x.toFixed(2), v.y.toFixed(2), d.flow.stuckT.toFixed(2));
  }
  const m: Record<string, number> = { first_contact_s: round(firstContact) };
  if (name === 'wall_30') {
    m['along_wall_mps'] = round(alongFirst);
    m['along_wall_min_1s_mps'] = round(alongMin);
    m['rescues'] = rescues.length;
  } else if (name === 'wall_head_on') {
    const r = rescues[0];
    m['rescue_after_contact_s'] = r ? round(r.t - firstContact) : -1;
    m['rescue_kind'] = r ? KIND[r.kind] : 0;
    m['rewind_m'] = r ? round(Math.hypot(r.x - r.fromX, r.y - r.fromY)) : -1;
    m['trail_offset_m'] = r ? round(Math.abs(r.x - st.x)) : -1;
  } else {
    rescues.slice(0, 3).forEach((r, i) => {
      m[`rescue${i + 1}_kind`] = KIND[r.kind];
      m[`rescue${i + 1}_t_s`] = round(r.t);
    });
    const r3 = rescues[2];
    if (r3) {
      const g = city.graph;
      let best = Infinity;
      for (let n = 0; n < g.nodeXY.length / 2; n++) best = Math.min(best, Math.hypot(g.nodeXY[2 * n]! - r3.x, g.nodeXY[2 * n + 1]! - r3.y));
      m['rescue3_road_dist_m'] = round(best);
      const hit = g.nearest(r3.x, r3.y, 1);
      m['rescue3_on_road'] = hit !== null && hit.edge.kept ? 1 : 0;
    }
  }
  return m;
}

const round = (v: number): number => Math.round(v * 1000) / 1000;

const DEFAULT_INPUTS: Record<string, Scenario['inputs']> = {
  wall_30: [{ t: 0, throttle: 0, steer: 0, brake: 0 }],
  wall_head_on: [{ t: 0, throttle: 1, steer: 0, brake: 0 }],
  corner_3x: [{ t: 0, throttle: 0, steer: 0, brake: 0 }],
};

describe('flow scenarios on the synthetic track (scenarios/flow, ±5 %)', () => {
  for (const name of Object.keys(STARTS)) {
    it(name, async () => {
      const file = join(root, 'scenarios', 'flow', `${name}.json`);
      const sc = existsSync(file) ? (JSON.parse(readFileSync(file, 'utf8')) as Scenario) : null;
      const m = await runScenario(name, sc?.inputs ?? DEFAULT_INPUTS[name]!);
      if (process.env['FLOW_RECORD']) console.log(name, JSON.stringify(m));
      // The plan's acceptance (Prompts/04-METROPOLE_FLOW_PLAN.md 6).
      if (name === 'wall_30') {
        expect(m['along_wall_min_1s_mps']).toBeGreaterThanOrEqual(14.7);
        expect(m['rescues']).toBe(0);
      } else if (name === 'wall_head_on') {
        expect(m['rescue_kind']).toBe(1);
        expect(m['rescue_after_contact_s']).toBeLessThanOrEqual(2.5);
        expect(m['trail_offset_m']).toBeLessThan(0.5);
      } else {
        expect([m['rescue1_kind'], m['rescue2_kind'], m['rescue3_kind']]).toEqual([1, 2, 3]);
        expect(m['rescue3_on_road']).toBe(1);
      }
      // Recorded values: within the scenario's tolerance (relative, P1 ±5 %).
      for (const [k, e] of Object.entries(sc?.expect ?? {})) {
        if (e.value === null) continue;
        expect(m[k], k).toBeDefined();
        expect(Math.abs(m[k]! - e.value), k).toBeLessThanOrEqual(Math.abs(e.value) * e.tol + 1e-9);
      }
    });
  }
});

describe('road move (specs/flow.md "Přesun na silnici")', () => {
  it('nearest kept ground node, facing the GPS route or the first edge', async () => {
    const city = await flowCity();
    const g: RoadGraph = city.graph;
    const a = roadSpot(g, 60, 40, null, tuning.layers.searchM)!;
    expect([a.node, a.x, a.y, a.heading]).toEqual([1, 0, 0, Math.PI]);
    const b = roadSpot(g, 60, 40, [-50, 0, 150, 0], tuning.layers.searchM)!;
    expect(b.heading).toBe(0);
  });
});
