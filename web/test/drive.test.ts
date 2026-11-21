import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { beforeAll, describe, expect, it } from 'vitest';

import type { BenchRoute, CarSpec } from '../src/gen/schema';
import { Autopilot } from '../src/drive/autopilot';
import { resolveRoute } from '../src/drive/route';
import { Tuning } from '../src/gen/tuning';
import { DriveWorld } from '../src/drive/driveWorld';
import { chunkPath, type PackSource } from '../src/world/citypack';
import { prepareChunk, type ChunkData } from '../src/world/chunk';
import { City } from '../src/world/model';
import { ChunkWindow } from '../src/world/streaming';
import { parse } from 'yaml';

const root = join(__dirname, '..', '..');
const pack = join(root, 'build', 'packs', 'nyc');
const source: PackSource = { read: async (p) => new Uint8Array(readFileSync(join(pack, p))) };
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const car = JSON.parse(readFileSync(join(root, 'content', 'cars', 'm0_coupe.json'), 'utf8')) as CarSpec;

// The pack is built or pulled (citypack pull) before the tests; CI does it in web.yml.
describe.skipIf(!existsSync(pack))('NYC citypack in client W', () => {
  let city: City;
  const chunks: ChunkData[] = [];

  beforeAll(async () => {
    city = await City.load(source);
    for (const c of city.manifest.chunks) chunks.push(await prepareChunk(await source.read(chunkPath(c.x, c.y))));
  });

  it('decodes the whole pack', () => {
    expect(city.graph.edges.length).toBeGreaterThan(1000);
    expect(chunks.length).toBe(city.manifest.chunks.length);
    const buildings = chunks.reduce((s, c) => s + c.buildings.length, 0);
    expect(buildings).toBe(city.manifest.chunks.reduce((s, c) => s + c.buildings, 0));
    expect(city.districtAt(city.startX, city.startY)).not.toBeNull();
  });

  it('starts on a named ground road', () => {
    const hit = city.graph.nearest(city.startX, city.startY, tuning.layers.spawnSearchM, (e) => e.isGround);
    expect(hit).not.toBeNull();
    expect(hit!.dist).toBeLessThan(hit!.edge.width / 2);
    expect(hit!.edge.name).not.toBe('');
  });

  it('streams the start window', () => {
    const w = new ChunkWindow(city, tuning).wanted(city.startX, city.startY, city.startHeading);
    expect(w.length).toBeGreaterThan(9);
    const [cx, cy] = w[0]!;
    expect(cx).toBe(Math.floor(city.startX / city.chunkM));
    expect(cy).toBe(Math.floor(city.startY / city.chunkM));
  });

  function world(): DriveWorld {
    const d = new DriveWorld(city, car, tuning);
    for (const c of chunks) d.addChunk(c);
    return d;
  }

  it('auto-throttles to cruise speed and brakes to a stop', () => {
    const d = world();
    for (let i = 0; i < 60 * 8; i++) d.update(1 / 60);
    expect(d.car.speed).toBeGreaterThan(tuning.speedMps.cruise * 0.85);
    expect(d.car.speed).toBeLessThan(tuning.speedMps.cruise + tuning.drive.overspeedMps + 1);
    d.input.brake = 1;
    let t = 0;
    while (d.car.forwardSpeed > tuning.drive.brakeMinMps && t < 10) {
      d.input.brake = 1;
      d.update(1 / 60);
      t += 1 / 60;
    }
    expect(t).toBeLessThan(4);
  });

  it('cannot drive through buildings', () => {
    const d = world();
    // Turn hard right into the block: the car must stay on a road corridor or bounce off walls.
    for (let i = 0; i < 60 * 6; i++) {
      d.input.reset();
      d.input.steer = i < 60 ? 1 : 0;
      d.update(1 / 60);
    }
    const hit = city.graph.nearest(d.car.x, d.car.y, 80);
    expect(hit).not.toBeNull();
    expect(hit!.dist).toBeLessThan(hit!.edge.width / 2 + d.car.halfLength * 2);
  });

  it('drifts under handbrake', () => {
    const d = world();
    for (let i = 0; i < 60 * 3; i++) d.update(1 / 60);
    let maxSlip = 0;
    for (let i = 0; i < 40; i++) {
      d.input.reset();
      d.input.steer = 1;
      d.input.handbrake = true;
      d.update(1 / 60);
      maxSlip = Math.max(maxSlip, Math.abs(d.car.slipAngle));
    }
    expect(maxSlip).toBeGreaterThan(0.2);
  });
});

describe.skipIf(!existsSync(pack))('D1 benchmark route (specs/bench.md)', () => {
  it('resolves the NYC route and the autopilot drives it to the end', async () => {
    const city = await City.load(source);
    const route = resolveRoute(city.graph, JSON.parse(readFileSync(join(root, 'content', 'bench', 'nyc.json'), 'utf8')) as BenchRoute);
    expect(route.legs).toBe(5);
    expect(route.length).toBeGreaterThan(3000);
    expect(route.length).toBeLessThan(5000);
    const d = new DriveWorld(city, car, tuning);
    for (const c of city.manifest.chunks) d.addChunk(await prepareChunk(await source.read(chunkPath(c.x, c.y))));
    const pilot = new Autopilot(route, tuning);
    pilot.start(d);
    d.beforeStep = (step) => pilot.step(d, d.input, step);
    let t = 0;
    while (!pilot.finished && t < 600) {
      d.update(1 / 60);
      t += 1 / 60;
    }
    expect(pilot.finished).toBe(true);
    expect(pilot.respawns).toBeLessThanOrEqual(2);
    expect(t).toBeLessThan(400);
  }, 120_000);
});
