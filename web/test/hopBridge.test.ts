import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { gzipSync } from 'node:zlib';

import { create, toBinary, type DescMessage, type MessageShape } from '@bufbuild/protobuf';
import { Box } from 'planck';
import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { CAT_BUILDINGS, CAT_CAR, CAT_TRAM } from '../src/drive/car';
import { DriveWorld } from '../src/drive/driveWorld';
import { EdgeSchema, GraphSchema, LandmarksSchema, ManifestSchema, NodeSchema, RoadClass, SpawnSchema, SpotsSchema } from '../src/gen/pb/citypack_pb';
import type { CarSpec } from '../src/gen/schema';
import { Tuning } from '../src/gen/tuning';
import { TERRAIN_N } from '../src/world/chunk';
import { City } from '../src/world/model';

/** Hop on a bridge deck (specs/hop.md v2): over a standing tram, back onto the deck. */

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const car = (id: string): CarSpec => JSON.parse(readFileSync(join(root, 'content', 'cars', `${id}.json`), 'utf8')) as CarSpec;
const vega = car('vega_roadster');
const coupe = car('m0_coupe');

const gz = <D extends DescMessage>(schema: D, m: MessageShape<D>): Uint8Array => new Uint8Array(gzipSync(toBinary(schema, m)));

/** The bridge of specs/terrain.md bridge_7: ground −400…−100, ramp to 7 m at 0, deck to 100, ramp down to 200, ground. */
const NODES = [{ x: -400, z: 0 }, { x: -100, z: 0 }, { x: 0, z: 7 }, { x: 100, z: 7 }, { x: 200, z: 0 }, { x: 500, z: 0 }];
const LAYERS = [[0, 0, false], [0, 1, true], [1, 1, true], [1, 0, true], [0, 0, false]] as const;
const DECK_Z = 7;

async function bridgeCity(terrain: boolean): Promise<City> {
  const nodes = NODES.map((n) => create(NodeSchema, { x: Math.round(n.x * 10), y: 0, zDm: terrain ? Math.round(n.z * 10) : 0 }));
  const edges = LAYERS.map(([lf, lt, bridge], i) => {
    const a = NODES[i]!, b = NODES[i + 1]!;
    const k = Math.max(1, Math.ceil((b.x - a.x) / 16));
    const points: number[] = [], zDm: number[] = [];
    for (let s = 0; s <= k; s++) {
      points.push(Math.round((a.x + ((b.x - a.x) * s) / k) * 10), 0);
      zDm.push(terrain ? Math.round((a.z + ((b.z - a.z) * s) / k) * 10) : 0);
    }
    return create(EdgeSchema, {
      from: i, to: i + 1, points, zDm, class: RoadClass.PRIMARY, lanes: 2, oneway: 0, kept: true, widthM: 20,
      layerFrom: lf, layerTo: lt, bridge,
    });
  });
  const files: Record<string, Uint8Array> = {
    'manifest.pb': gz(ManifestSchema, create(ManifestSchema, {
      formatVersion: 1, cityId: 'test', chunkM: 256, driveSide: 'right', units: 'metric', terrainVersion: terrain ? 1 : 0, z0M: 0,
      exaggeration: 1, terrainGridM: 8, start: create(SpawnSchema, { x: 0, y: 0, headingRad: 0 }),
    })),
    'graph.pb': gz(GraphSchema, create(GraphSchema, { names: [''], nodes, edges })),
    'landmarks.pb': gz(LandmarksSchema, create(LandmarksSchema, {})),
    'spots.pb': gz(SpotsSchema, create(SpotsSchema, {})),
  };
  return City.load({ read: async (p) => files[p] ?? Promise.reject(new Error(p)) });
}

/** On the deck at x = 20 (layer 1) at cruise, a tram car standing 18 m ahead and a building under the deck. */
async function onDeck(spec: CarSpec, terrain: boolean): Promise<{ d: DriveWorld; tramFar: number; tramNear: number }> {
  const city = await bridgeCity(terrain);
  const d = new DriveWorld(city, spec, tuning);
  const N = TERRAIN_N, cm = city.chunkM;
  for (let cx = -3; cx <= 2; cx++) {
    for (let cy = -1; cy <= 0; cy++) {
      d.addChunk({ x: cx, y: cy, buildings: [], ground: [], barriers: [], terrain: terrain ? new Float32Array(N * N) : null, shade: null });
    }
  }
  d.props.clear();
  if (d.traffic) {
    d.traffic.solid = false;
    d.traffic.cars.length = 0;
  }
  d.spawn(-150, 0, 0);
  const dt = 1 / tuning.drive.stepHz;
  for (let i = 0; i < 60 * 20 && d.car.x < 20; i++) {
    d.input.reset();
    d.car.body.setLinearVelocity({ x: tuning.speedMps.cruise, y: 0 });
    d.update(dt);
  }
  expect(d.car.layer).toBe(1);
  const tramX = d.car.x + 18, half = tuning.trams.carLengthM / 2;
  const tram = d.world.createBody({ type: 'static', position: { x: tramX, y: 0 } });
  tram.createFixture({ shape: new Box(half, tuning.trams.carWidthM / 2), filterCategoryBits: CAT_TRAM, filterMaskBits: CAT_CAR });
  // A building under the deck (layer 0 only): the flight on layer 1 must not hit it.
  const house = d.world.createBody({ type: 'static', position: { x: tramX + 8, y: 0 } });
  house.createFixture({ shape: new Box(4, 4), filterCategoryBits: CAT_BUILDINGS, filterMaskBits: CAT_CAR });
  d.car.body.setLinearVelocity({ x: tuning.speedMps.cruise, y: 0 });
  return { d, tramFar: tramX + half + d.car.halfLength, tramNear: tramX - half - d.car.halfLength };
}

describe('hop on a bridge (specs/hop.md v2)', () => {
  for (const terrain of [false, true]) {
    it(`flies over a tram on the deck and lands on the deck${terrain ? ' (relief)' : ''}`, async () => {
      const { d, tramFar } = await onDeck(vega, terrain);
      expect(d.canHop).toBe(true);
      expect(d.tryHop()).toBe(true);
      const dt = 1 / tuning.drive.stepHz;
      let minZ = Infinity;
      while (d.hop.airborne) {
        d.input.reset();
        d.update(dt);
        expect(d.car.layer).toBe(1); // the layer is kept in the air
        expect(Math.abs(d.car.y)).toBeLessThan(10); // rails hold it on the deck
        if (terrain) minZ = Math.min(minZ, d.groundZ());
        expect(d.jump.airborne).toBe(false); // the terrain jump model is suspended
      }
      expect(d.car.x).toBeGreaterThan(tramFar);
      expect(d.car.layer).toBe(1);
      expect(d.water.sinking).toBe(false);
      if (terrain) {
        expect(minZ).toBeCloseTo(DECK_Z, 1);
        expect(d.groundZ()).toBeCloseTo(DECK_Z, 1);
        expect(d.jump.z).toBeCloseTo(DECK_Z, 1);
      }
      // Drives off along the deck and down the ramp.
      for (let i = 0; i < 60 * 3; i++) {
        d.input.reset();
        d.update(dt);
      }
      expect(Math.abs(d.car.y)).toBeLessThan(10);
      expect(d.lastLanding ?? 0).toBeLessThan(tuning.slopePhysics.hardLanding);
    });
  }

  it('rails hold a sideways flight on the deck (no fall into the river)', async () => {
    const { d } = await onDeck(vega, true);
    d.car.body.setLinearVelocity({ x: tuning.speedMps.cruise, y: 12 });
    expect(d.tryHop()).toBe(true);
    let maxY = 0;
    while (d.hop.airborne) {
      d.input.reset();
      d.update(1 / tuning.drive.stepHz);
      maxY = Math.max(maxY, Math.abs(d.car.y));
    }
    expect(maxY).toBeLessThan(10);
    expect(d.car.layer).toBe(1);
    expect(d.groundZ()).toBeCloseTo(DECK_Z, 1);
  });

  it('a normal car stops at the tram', async () => {
    const { d, tramNear } = await onDeck(coupe, false);
    expect(d.canHop).toBe(false);
    for (let i = 0; i < 60 * 3; i++) {
      d.input.reset();
      d.update(1 / 60);
    }
    expect(d.car.x).toBeLessThan(tramNear + 0.5);
  });
});
