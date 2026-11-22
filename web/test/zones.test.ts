import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { World } from 'planck';
import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { GroundKind } from '../src/gen/pb/citypack_pb';
import type { CarSpec } from '../src/gen/schema';
import { Tuning } from '../src/gen/tuning';
import { CAT_CAR, CAT_ZONE, Car, zoneMask } from '../src/drive/car';
import { ControlInput } from '../src/drive/controls';
import { pointInMesh, ZoneWorld } from '../src/drive/zones';
import { bollardPoints } from '../src/render/geometry';
import type { ChunkData } from '../src/world/chunk';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const coupe = JSON.parse(readFileSync(join(root, 'content', 'cars', 'm0_coupe.json'), 'utf8')) as CarSpec;
const micro: CarSpec = { ...coupe, class: 'micro' };

/** Square zone 20..40 × −10..10 as two triangles. */
const zoneXY = Float32Array.from([20, -10, 40, -10, 40, 10, 20, 10]);
const zoneIdx = Uint32Array.from([0, 1, 2, 0, 2, 3]);

/** One chunk with a bollard line across the road at x = 20 (the zone's west edge). */
function chunk(): ChunkData {
  return {
    x: 0, y: 0, buildings: [],
    ground: [{ kind: GroundKind.PEDESTRIAN, xy: zoneXY, indices: zoneIdx }],
    barriers: [Float32Array.from([20, -10, 20, 0, 20, 10])],
  };
}

function setup(spec: CarSpec, x: number): { world: World; zones: ZoneWorld; car: Car } {
  const world = new World({ gravity: { x: 0, y: 0 } });
  const zones = new ZoneWorld(world, tuning.drive);
  zones.addChunk(chunk());
  const car = new Car(world, spec, tuning.drive, x, 0, 0, tuning.carScale);
  return { world, zones, car };
}

/** Drives east for `seconds`, applying the zone mask before each step like DriveWorld. */
function drive(s: { world: World; zones: ZoneWorld; car: Car }, seconds: number): void {
  const d = tuning.drive, step = 1 / d.stepHz, input = new ControlInput();
  const r = Math.hypot(s.car.halfLength, s.car.halfWidth) + d.bodyRoundM;
  let inside = false;
  for (let t = 0; t < seconds; t += step) {
    inside = s.zones.insideFor(s.car.x, s.car.y, r, inside);
    s.car.setZone(zoneMask(s.car.spec.class, inside));
    s.car.drive(input, step, tuning.speedMps.cruise, tuning.speedMps.topDefault);
    s.world.step(step, d.velocityIterations, d.positionIterations);
  }
}

describe('pedestrian zones (specs/zones.md)', () => {
  it('zoneMask: only non-micro cars outside a zone collide with bollards', () => {
    const table: [CarSpec['class'], boolean, boolean][] = [
      ['coupe', false, true],
      ['coupe', true, false],
      ['sedan', false, true],
      ['bus', false, true],
      ['micro', false, false],
      ['micro', true, false],
    ];
    for (const [cls, inside, want] of table) expect(zoneMask(cls, inside), `${cls} ${inside}`).toBe(want);
  });

  it('point in zone on a small mesh', () => {
    expect(pointInMesh(zoneXY, zoneIdx, 30, 0)).toBe(true);
    expect(pointInMesh(zoneXY, zoneIdx, 21, 9)).toBe(true);
    expect(pointInMesh(zoneXY, zoneIdx, 39, -9)).toBe(true);
    expect(pointInMesh(zoneXY, zoneIdx, 19, 0)).toBe(false);
    expect(pointInMesh(zoneXY, zoneIdx, 30, 11)).toBe(false);
    const z = new ZoneWorld(new World({ gravity: { x: 0, y: 0 } }), tuning.drive);
    z.addChunk(chunk());
    expect(z.inside(30, 0)).toBe(true);
    expect(z.inside(0, 0)).toBe(false);
    z.removeChunk(chunk());
    expect(z.inside(30, 0)).toBe(false);
  });

  it('a barrier becomes CAT_ZONE fixtures that go away with the chunk', () => {
    const world = new World({ gravity: { x: 0, y: 0 } });
    const z = new ZoneWorld(world, tuning.drive);
    const before = world.getBodyCount();
    z.addChunk(chunk());
    expect(world.getBodyCount()).toBe(before + 1);
    const body = z.bodyOf(0, 0)!;
    expect(body.isStatic()).toBe(true);
    let n = 0;
    for (let f = body.getFixtureList(); f; f = f.getNext()) {
      expect(f.getFilterCategoryBits()).toBe(CAT_ZONE);
      expect(f.getFilterMaskBits()).toBe(CAT_CAR);
      n++;
    }
    expect(n).toBe(1);
    z.removeChunk(chunk());
    expect(world.getBodyCount()).toBe(before);
    expect(z.bodyOf(0, 0)).toBeUndefined();
    expect(z.bodyCount).toBe(0);
  });

  it('a chunk without barriers adds no body', () => {
    const world = new World({ gravity: { x: 0, y: 0 } });
    const z = new ZoneWorld(world, tuning.drive);
    z.addChunk({ x: 1, y: 0, buildings: [], ground: [], barriers: [] });
    expect(world.getBodyCount()).toBe(0);
  });

  it('a car is stopped by the bollards, a micro vehicle passes', () => {
    const car = setup(coupe, 0);
    drive(car, 5);
    expect(car.car.x).toBeLessThan(20);
    const m = setup(micro, 0);
    drive(m, 5);
    expect(m.car.x).toBeGreaterThan(25);
  });

  it('a car inside a zone drives out through the bollards', () => {
    const s = setup(coupe, 30);
    s.car.body.setTransform({ x: 30, y: 0 }, Math.PI);
    drive(s, 5);
    expect(s.car.x).toBeLessThan(15);
  });

  it('after leaving a zone the bollards stay off until the car clears them (hold-off)', () => {
    const world = new World({ gravity: { x: 0, y: 0 } });
    const z = new ZoneWorld(world, tuning.drive);
    z.addChunk(chunk());
    expect(z.nearBarrier(21, 0, 2)).toBe(true);
    expect(z.nearBarrier(25, 0, 2)).toBe(false);
    expect(z.insideFor(21, 0, 2, true)).toBe(true);
    expect(z.insideFor(21, 0, 2, false)).toBe(z.inside(21, 0));
    expect(z.insideFor(25, 0, 2, true)).toBe(z.inside(25, 0));
  });

  it('micro handbrake gives no yaw impulse', () => {
    const yaw = (spec: CarSpec): number => {
      const world = new World({ gravity: { x: 0, y: 0 } });
      const car = new Car(world, spec, tuning.drive, 0, 0, 0, tuning.carScale);
      car.body.setLinearVelocity({ x: 20, y: 0 });
      const input = new ControlInput();
      input.handbrake = true;
      input.steer = 1;
      car.drive(input, 1 / tuning.drive.stepHz, tuning.speedMps.cruise, tuning.speedMps.topDefault);
      return Math.abs(car.body.getAngularVelocity());
    };
    expect(yaw(micro)).toBeLessThan(yaw(coupe));
  });

  it('bollards every bollard_spacing_m along a barrier', () => {
    const p = bollardPoints(chunk(), 5);
    expect(Array.from(p)).toEqual([20, -10, 20, -5, 20, 0, 20, 5, 20, 10]);
  });
});
