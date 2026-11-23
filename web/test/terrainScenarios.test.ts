import { appendFileSync, existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { gzipSync } from 'node:zlib';

import { create, toBinary, type DescMessage, type MessageShape } from '@bufbuild/protobuf';
import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { DriveWorld } from '../src/drive/driveWorld';
import { EdgeSchema, GraphSchema, LandmarksSchema, ManifestSchema, NodeSchema, RoadClass, SpawnSchema, SpotsSchema } from '../src/gen/pb/citypack_pb';
import type { CarSpec } from '../src/gen/schema';
import { Tuning } from '../src/gen/tuning';
import { TERRAIN_N } from '../src/world/chunk';
import { City } from '../src/world/model';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const sedan = JSON.parse(readFileSync(join(root, 'content', 'cars', 'sedan_regent.json'), 'utf8')) as CarSpec;

// ---------- synthetic track (specs/terrain.md "Scénáře"), shared with packages/drive_core

const gz = <D extends DescMessage>(schema: D, m: MessageShape<D>): Uint8Array => new Uint8Array(gzipSync(toBinary(schema, m)));

/** A straight road along y = 0: node x positions with heights, layers per edge (from, to). */
interface Track {
  /** Terrain height under x (m); the same for every y. */
  terrain: (x: number) => number;
  nodes: Array<{ x: number; z: number }>;
  /** Per edge: layer_from, layer_to, bridge. */
  edges: Array<{ lf: number; lt: number; bridge: boolean }>;
}

/** Road edges densified every 16 m, heights linear between the nodes. */
function graphOf(t: Track) {
  const nodes = t.nodes.map((n) => create(NodeSchema, { x: Math.round(n.x * 10), y: 0, zDm: Math.round(n.z * 10) }));
  const edges = t.edges.map((e, i) => {
    const a = t.nodes[i]!, b = t.nodes[i + 1]!;
    const k = Math.max(1, Math.ceil((b.x - a.x) / 16));
    const points: number[] = [], zDm: number[] = [];
    for (let s = 0; s <= k; s++) {
      points.push(Math.round((a.x + ((b.x - a.x) * s) / k) * 10), 0);
      zDm.push(Math.round((a.z + ((b.z - a.z) * s) / k) * 10));
    }
    return create(EdgeSchema, {
      from: i, to: i + 1, points, zDm, class: RoadClass.PRIMARY, lanes: 2, oneway: 0, kept: true, widthM: 20,
      layerFrom: e.lf, layerTo: e.lt, bridge: e.bridge,
    });
  });
  return create(GraphSchema, { names: [''], nodes, edges });
}

async function trackCity(t: Track): Promise<City> {
  const files: Record<string, Uint8Array> = {
    'manifest.pb': gz(ManifestSchema, create(ManifestSchema, {
      formatVersion: 1, cityId: 'test', chunkM: 256, driveSide: 'right', units: 'metric', terrainVersion: 1, z0M: 0,
      exaggeration: 1, terrainGridM: 8, start: create(SpawnSchema, { x: 0, y: 0, headingRad: 0 }),
    })),
    'graph.pb': gz(GraphSchema, graphOf(t)),
    'landmarks.pb': gz(LandmarksSchema, create(LandmarksSchema, {})),
    'spots.pb': gz(SpotsSchema, create(SpotsSchema, {})),
  };
  return City.load({ read: async (p) => files[p] ?? Promise.reject(new Error(p)) });
}

/** A ground road on a profile: nodes every 64 m from −512 to 512 m, all on layer 0. */
const ground = (z: (x: number) => number): Track => {
  const xs: number[] = [];
  for (let x = -512; x <= 512; x += 64) xs.push(x);
  return { terrain: z, nodes: xs.map((x) => ({ x, z: z(x) })), edges: xs.slice(1).map(() => ({ lf: 0, lt: 0, bridge: false })) };
};

/** Crest at x = 0: up at `up` before, down at `down` after. */
const crest = (up: number, down: number) => (x: number): number => (x < 0 ? up * x : -down * x);

/** Bridge with 7 % ramps: ground −400…−100, ramp up to 7 m at 0, deck to 100, ramp down to 200, ground to 500. */
const BRIDGE: Track = {
  terrain: () => 0,
  nodes: [{ x: -400, z: 0 }, { x: -100, z: 0 }, { x: 0, z: 7 }, { x: 100, z: 7 }, { x: 200, z: 0 }, { x: 500, z: 0 }],
  edges: [{ lf: 0, lt: 0, bridge: false }, { lf: 0, lt: 1, bridge: true }, { lf: 1, lt: 1, bridge: true }, { lf: 1, lt: 0, bridge: true }, { lf: 0, lt: 0, bridge: false }],
};

interface Setup {
  track: Track;
  /** Start x (on y = 0, heading east), speed (m/s) and length (s). */
  x: number;
  v: number;
  s: number;
}

/** Start and track of every scenario (specs/terrain.md "Scénáře"). */
const SETUPS: Record<string, Setup> = {
  // From rest the car would hold (below stop_speed without throttle): it starts at stop_speed.
  downhill_coast: { track: ground((x) => -0.1 * x), x: -100, v: 0.5, s: 40 },
  uphill_launch: { track: ground((x) => 0.15 * x), x: -100, v: 0, s: 30 },
  jump_30_15: { track: ground(crest(0.15, 0.15)), x: -2, v: 30.3, s: 3 },
  jump_40_20: { track: ground(crest(0.2, 0.2)), x: -2, v: 40.4, s: 3 },
  hold_20: { track: ground((x) => 0.2 * x), x: 0, v: 0, s: 5 },
  // v3: starts at cruise; the down ramp tests the cruise hold (specs/drive.md v2).
  bridge_7: { track: BRIDGE, x: -300, v: tuning.speedMps.cruise, s: 50 },
};

interface Scenario {
  module: string;
  name: string;
  car?: string;
  inputs: Array<{ t: number; throttle?: number; steer?: number; brake?: number; boost?: number; coast?: number }>;
  expect: Record<string, { value: number | null; tol: number }>;
}

const DEFAULT_INPUTS: Record<string, Scenario['inputs']> = {
  downhill_coast: [{ t: 0, coast: 1 }],
  uphill_launch: [{ t: 0, throttle: 1, boost: 1 }],
  jump_30_15: [{ t: 0, coast: 1 }],
  jump_40_20: [{ t: 0, coast: 1 }],
  hold_20: [{ t: 0, coast: 1 }],
  bridge_7: [{ t: 0 }],
};

const round = (v: number): number => Math.round(v * 1000) / 1000;

/** Runs one scenario on the synthetic track; returns its metrics. */
async function runScenario(name: string, inputs: Scenario['inputs']): Promise<Record<string, number>> {
  const st = SETUPS[name]!;
  const city = await trackCity(st.track);
  const d = new DriveWorld(city, sedan, tuning);
  const N = TERRAIN_N, cm = city.chunkM, step = cm / (N - 1);
  for (let cx = -3; cx <= 2; cx++) {
    for (let cy = -1; cy <= 0; cy++) {
      const terrain = new Float32Array(N * N);
      for (let j = 0; j < N; j++) for (let i = 0; i < N; i++) terrain[j * N + i] = st.track.terrain(cx * cm + i * step);
      d.addChunk({ x: cx, y: cy, buildings: [], ground: [], barriers: [], terrain, shade: null });
    }
  }
  d.props.clear(); // the track has no street furniture
  if (d.traffic) {
    d.traffic.solid = false;
    d.traffic.cars.length = 0;
  }
  d.spawn(st.x, 0, 0);
  d.car.body.setLinearVelocity({ x: st.v, y: 0 });
  const dt = 1 / tuning.drive.stepHz;
  const m: Record<string, number> = {};
  let k = 0, airS = 0, airM = 0, takeoff = -1, t20 = -1, maxGap = 0;
  const marks = name === 'bridge_7' ? [-100, 0, 100, 200, 300] : [];
  const seen = new Set<number>();
  const steps = Math.round(st.s / dt);
  for (let i = 0; i < steps; i++) {
    while (k + 1 < inputs.length && inputs[k + 1]!.t <= d.time + 1e-9) k++;
    const inp = inputs[k]!;
    d.input.reset();
    d.input.throttle = inp.throttle ?? 0;
    d.input.steer = inp.steer ?? 0;
    d.input.brake = inp.brake ?? 0;
    d.input.boost = (inp.boost ?? 0) > 0;
    d.input.coast = (inp.coast ?? 0) > 0;
    const px = d.car.x, py = d.car.y;
    const wasAir = d.jump.airborne;
    d.update(dt);
    if (d.jump.airborne) {
      if (!wasAir && takeoff < 0) takeoff = d.car.speed;
      airS += dt;
      airM += Math.hypot(d.car.x - px, d.car.y - py);
    }
    maxGap = Math.max(maxGap, d.jump.gap);
    if (t20 < 0 && d.car.speed >= 20) t20 = d.time;
    for (const x of marks) {
      if (!seen.has(x) && d.car.x >= x) {
        seen.add(x);
        m[`v_at_${x < 0 ? 'm' : ''}${Math.abs(x)}_mps`] = round(d.car.speed);
      }
    }
    if (process.env['TERRAIN_TRACE'] === name && i % 6 === 0) console.log(d.time.toFixed(2), d.car.x.toFixed(2), d.car.speed.toFixed(2), d.jump.z.toFixed(2), d.jump.gap.toFixed(2), d.car.layer, d.rideEdge?.index ?? -1);
    if (name === 'downhill_coast' && d.car.x >= st.x + 200) {
      m['end_speed_mps'] = round(d.car.speed);
      m['time_s'] = round(d.time);
      break;
    }
  }
  if (name === 'uphill_launch') m['t_20_mps_s'] = round(t20);
  if (name.startsWith('jump_')) {
    m['takeoff_mps'] = round(takeoff);
    m['air_s'] = round(airS);
    m['air_m'] = round(airM);
    m['landing_mps'] = round(d.lastLanding);
    m['after_mps'] = round(d.car.speed);
  }
  if (name === 'hold_20') m['drift_m'] = round(Math.hypot(d.car.x - st.x, d.car.y));
  if (name === 'bridge_7') m['max_gap_m'] = round(maxGap);
  return m;
}

describe('terrain scenarios on the synthetic track (scenarios/terrain, ±5 %)', () => {
  for (const name of Object.keys(SETUPS)) {
    it(name, async () => {
      const file = join(root, 'scenarios', 'terrain', `${name}.json`);
      const sc = existsSync(file) ? (JSON.parse(readFileSync(file, 'utf8')) as Scenario) : null;
      const m = await runScenario(name, sc?.inputs ?? DEFAULT_INPUTS[name]!);
      const rec = process.env['TERRAIN_RECORD'];
      if (rec) appendFileSync(rec, `${name} ${JSON.stringify(m)}\n`);
      // The control table of specs/terrain.md holds for the pure model (terrain.test.ts, ±2 %); the
      // real car also loses speed to drag in the air, so its flight is a few per cent shorter.
      // Air drag at 40 m/s is ~3.5 m/s², so the distance is up to 11 % short of the table.
      const near = (a: number | undefined, b: number, tol: number): void => expect(Math.abs(a! - b), `${a} vs ${b}`).toBeLessThanOrEqual(b * tol);
      if (name === 'jump_30_15') {
        near(m['air_s'], 0.77, 0.06);
        near(m['air_m'], 23, 0.12);
        near(m['landing_mps'], 8.7, 0.06);
      } else if (name === 'jump_40_20') {
        near(m['air_s'], 1.53, 0.06);
        near(m['air_m'], 61, 0.12);
        near(m['landing_mps'], 15.7, 0.06);
        expect(m['after_mps']).toBeLessThan(m['takeoff_mps']! * 0.85);
      } else if (name === 'hold_20') {
        expect(m['drift_m']).toBeLessThanOrEqual(0.05);
      } else if (name === 'bridge_7') {
        expect(m['max_gap_m']).toBeLessThan(tuning.slopePhysics.suspensionTravel);
      }
      for (const [key, e] of Object.entries(sc?.expect ?? {})) {
        if (e.value === null) continue;
        expect(m[key], key).toBeDefined();
        expect(Math.abs(m[key]! - e.value), key).toBeLessThanOrEqual(Math.abs(e.value) * e.tol + (e.value === 0 ? e.tol : 1e-9));
      }
    });
  }
});
