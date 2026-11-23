import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

import { Box } from 'planck';
import { parse } from 'yaml';
import { beforeAll, describe, expect, it } from 'vitest';

import { CarFleet } from '../src/cars/fleet';
import { carShape } from '../src/cars/shape';
import { CAT_CAR, CAT_TRAFFIC } from '../src/drive/car';
import { DriveWorld } from '../src/drive/driveWorld';
import { canHop, hopArc, hopCharges, hopFlip, HopState } from '../src/drive/hop';
import type { CarSpec } from '../src/gen/schema';
import { Tuning } from '../src/gen/tuning';
import { chunkPath, type PackSource } from '../src/world/citypack';
import { prepareChunk, type ChunkData } from '../src/world/chunk';
import { City } from '../src/world/model';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const specs = new Map<string, CarSpec>(
  readdirSync(join(root, 'content', 'cars')).map((f) => {
    const s = JSON.parse(readFileSync(join(root, 'content', 'cars', f), 'utf8')) as CarSpec;
    return [s.id, s];
  }),
);
const vega = specs.get('vega_roadster')!;
const coupe = specs.get('m0_coupe')!;
const ht = tuning.hop;

describe('hop rules (specs/hop.md)', () => {
  it('only the Vega Roadster has an air tank', () => {
    expect(hopCharges(vega)).toBe(3);
    for (const s of specs.values()) if (s.id !== 'vega_roadster') expect(hopCharges(s), s.id).toBeNull();
  });

  it('canHop table', () => {
    const v = ht.minSpeedMps;
    const rows: Array<[Pick<CarSpec, 'hop'>, number, number, number, number, boolean]> = [
      [vega, 3, 0, 0, v, true],
      [vega, 1, 0, 0, v + 10, true],
      [vega, 0, 0, 0, v, false], // empty tank
      [vega, 3, 0.5, 0, v, false], // already in the air
      [vega, 3, 0, 1, v, true], // on a bridge (v2)
      [vega, 3, 0, -1, v, true], // in a tunnel (v2)
      [vega, 3, 0, 1, v - 0.01, false], // on a bridge, too slow
      [vega, 3, 0, 0, v - 0.01, false], // too slow
      [coupe, 3, 0, 0, v, false], // no hop
      [{ hop: { charges: 0 } }, 3, 0, 0, v, false],
    ];
    for (const [spec, charges, air, layer, speed, want] of rows) {
      expect(canHop(spec, charges, air, layer, speed, ht), JSON.stringify([spec.hop, charges, air, layer, speed])).toBe(want);
    }
  });

  it('hopArc = 4·h·(t/T)·(1 − t/T); the flip turns the body over at half time', () => {
    expect(hopArc(0, 1.4, 7)).toBe(0);
    expect(hopArc(0.7, 1.4, 7)).toBeCloseTo(7, 12);
    expect(hopArc(0.35, 1.4, 7)).toBeCloseTo(5.25, 12);
    expect(hopArc(1.05, 1.4, 7)).toBeCloseTo(5.25, 12);
    expect(hopArc(1.4, 1.4, 7)).toBe(0);
    expect(hopArc(2, 1.4, 7)).toBe(0);
    expect(hopArc(ht.airS / 2, ht.airS, ht.heightM)).toBeCloseTo(ht.heightM, 12);
    expect(hopFlip(0, 1.4, 1)).toBeCloseTo(1, 12);
    expect(hopFlip(0.35, 1.4, 1)).toBeCloseTo(0, 12);
    expect(hopFlip(0.7, 1.4, 1)).toBeCloseTo(-1, 12);
    expect(hopFlip(1.4, 1.4, 1)).toBeCloseTo(1, 12);
  });

  it('charges go down per hop and block at 0; the flight lasts air_s; refill fills up', () => {
    const s = new HopState();
    s.fill(vega);
    expect(s.charges).toBe(3);
    for (let n = 3; n > 0; n--) {
      expect(s.start(vega, 0, ht.minSpeedMps, ht)).toBe(true);
      expect(s.charges).toBe(n - 1);
      expect(s.start(vega, 0, ht.minSpeedMps, ht)).toBe(false); // not twice in the air
      let steps = 0;
      while (!s.step(1 / tuning.drive.stepHz)) steps++;
      expect(steps + 1).toBe(Math.round(ht.airS * tuning.drive.stepHz));
      expect(s.airborne).toBe(false);
    }
    expect(s.start(vega, 0, ht.minSpeedMps, ht)).toBe(false);
    expect(s.charges).toBe(0);
    expect(s.refill(vega)).toBe(true);
    expect(s.charges).toBe(3);
    expect(s.refill(vega)).toBe(false);
    expect(s.refill(coupe)).toBe(false);
    s.fill(coupe);
    expect(s.charges).toBe(0);
  });

  it('the supersport class draws a full car shape', () => {
    const parts = carShape(vega.class, 5, 2, vega.length_m).map((r) => r.part);
    for (const p of ['shadow', 'body', 'cabin', 'glass', 'head', 'tail'] as const) expect(parts, p).toContain(p);
  });
});

const pack = join(root, 'build', 'packs', 'nyc');
const source: PackSource = { read: async (p) => new Uint8Array(readFileSync(join(pack, p))) };

describe.skipIf(!existsSync(pack))('hop over traffic in NYC (planck)', () => {
  let city: City;
  const chunks: ChunkData[] = [];
  beforeAll(async () => {
    city = await City.load(source);
    const cx = Math.floor(city.startX / city.chunkM), cy = Math.floor(city.startY / city.chunkM);
    for (const c of city.manifest.chunks) {
      if (Math.abs(c.x - cx) <= 2 && Math.abs(c.y - cy) <= 2) chunks.push(await prepareChunk(await source.read(chunkPath(c.x, c.y))));
    }
  });

  function world(spec: CarSpec): DriveWorld {
    const d = new DriveWorld(city, spec, tuning);
    for (const c of chunks) d.addChunk(c);
    // Only our own blocker stands in the way.
    if (d.traffic) d.traffic.solid = false;
    if (d.trams) d.trams.solid = false;
    return d;
  }

  /** At cruise speed, a car-sized kinematic block (traffic category) 22 m ahead across the lane. */
  function run(spec: CarSpec, hop: boolean): { along: number; blockFar: number; blockNear: number; maxAir: number } {
    const d = world(spec);
    const h = d.car.heading, ux = Math.cos(h), uy = Math.sin(h);
    const x0 = d.car.x, y0 = d.car.y;
    d.car.body.setLinearVelocity({ x: ux * tuning.speedMps.cruise, y: uy * tuning.speedMps.cruise });
    const blockHalf = 4;
    const block = d.world.createBody({ type: 'static', position: { x: x0 + ux * 22, y: y0 + uy * 22 }, angle: h });
    block.createFixture({ shape: new Box(blockHalf, d.car.halfWidth * 2), filterCategoryBits: CAT_TRAFFIC, filterMaskBits: CAT_CAR });
    if (hop) expect(d.tryHop()).toBe(true);
    let maxAir = 0;
    for (let i = 0; i < 60 * 3; i++) {
      d.input.reset();
      d.update(1 / 60);
      maxAir = Math.max(maxAir, d.hop.t);
    }
    const along = (d.car.x - x0) * ux + (d.car.y - y0) * uy;
    return { along, blockFar: 22 + blockHalf + d.car.halfLength, blockNear: 22 - blockHalf - d.car.halfLength, maxAir };
  }

  it('the Roadster hops over a car in its path and lands beyond it; a normal car stops', () => {
    const r = run(vega, true);
    expect(r.maxAir).toBeGreaterThan(ht.airS * 0.9);
    expect(r.along).toBeGreaterThan(r.blockFar);
    const n = run(coupe, false);
    expect(n.along).toBeLessThan(n.blockNear + 0.5);
  });

  it('in the air: no input, no spin, mask back on landing; charges block at 0', () => {
    const d = world(vega);
    const h = d.car.heading;
    d.car.body.setLinearVelocity({ x: Math.cos(h) * tuning.speedMps.cruise, y: Math.sin(h) * tuning.speedMps.cruise });
    expect(d.canHop).toBe(true);
    for (let n = 3; n > 0; n--) {
      expect(d.tryHop()).toBe(true);
      expect(d.hop.charges).toBe(n - 1);
      expect(d.car.airborne).toBe(true);
      expect(d.traffic?.playerAirborne ?? true).toBe(true);
      expect(d.canHop).toBe(false);
      const v0 = d.car.speed;
      for (let i = 0; i < 10; i++) {
        d.input.reset();
        d.input.steer = 1;
        d.input.brake = 1;
        d.update(1 / 60);
        expect(d.car.body.getAngularVelocity()).toBe(0);
      }
      // Brake ignored: only drag slows it down.
      expect(d.car.speed).toBeGreaterThan(v0 * 0.9);
      while (d.hop.airborne) {
        d.input.reset();
        d.update(1 / 60);
      }
      expect(d.car.airborne).toBe(false);
      expect(d.traffic?.playerAirborne ?? false).toBe(false);
      d.car.body.setLinearVelocity({ x: Math.cos(d.car.heading) * tuning.speedMps.cruise, y: Math.sin(d.car.heading) * tuning.speedMps.cruise });
    }
    expect(d.hop.charges).toBe(0);
    expect(d.canHop).toBe(false);
    expect(d.tryHop()).toBe(false);
  });

  it('the garage refills the tank for free; boarding a hop car fills it', () => {
    const d = world(coupe);
    const fleet = new CarFleet(d, specs, tuning, { id: 'g', x: d.car.x, y: d.car.y, heading: d.car.heading });
    expect(fleet.canRefillHop()).toBe(false);
    fleet.state = { ...fleet.state, owned: ['m0_coupe', 'vega_roadster'] };
    fleet.select('vega_roadster');
    expect(d.spec.id).toBe('vega_roadster');
    expect(d.hop.charges).toBe(3);
    expect(fleet.canRefillHop()).toBe(false);
    d.hop.charges = 0;
    const cash = fleet.state.cash;
    expect(fleet.canRefillHop()).toBe(true);
    expect(fleet.refillHop()).toBe(true);
    expect(d.hop.charges).toBe(3);
    expect(fleet.state.cash).toBe(cash);
    expect(fleet.canRefillHop()).toBe(false);
    // A respawn keeps the tank, a car change refills it.
    d.hop.charges = 1;
    d.spawn(city.startX, city.startY, city.startHeading);
    expect(d.hop.charges).toBe(1);
    fleet.select('m0_coupe');
    expect(d.hop.charges).toBe(0);
    fleet.select('vega_roadster');
    expect(d.hop.charges).toBe(3);
  });
});
