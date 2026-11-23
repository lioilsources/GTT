import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { beforeAll, describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { DriveWorld } from '../src/drive/driveWorld';
import { RoutePath } from '../src/drive/route';
import type { CarSpec } from '../src/gen/schema';
import { Tuning } from '../src/gen/tuning';
import { chunkPath, type PackSource } from '../src/world/citypack';
import { prepareChunk } from '../src/world/chunk';
import { City } from '../src/world/model';

// Cruise hold on real Prague hills (specs/drive.md v2 step 2): with no input the car holds
// speed_mps.cruise downhill. Pure pursuit steers along the street; throttle, brake and boost stay 0.

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const spec = JSON.parse(readFileSync(join(root, 'content', 'cars', `${tuning.cars.startCar}.json`), 'utf8')) as CarSpec;
const dir = join(root, 'build', 'packs', 'prague');
const source: PackSource = { read: async (p) => new Uint8Array(readFileSync(join(dir, p))) };
const dt = 1 / tuning.drive.stepHz;
const cruise = tuning.speedMps.cruise;
const TOL = 1.5;

/** Polyline of the edges in order, each flipped to continue from the previous end. */
function chain(city: City, ids: number[], startNode: number): RoutePath {
  const out: number[] = [];
  let at = startNode;
  for (const id of ids) {
    const e = city.graph.edges[id]!;
    const n = e.pts.length >> 1;
    const rev = e.to === at;
    if (!rev && e.from !== at) throw new Error(`edge ${id} does not continue the chain`);
    for (let k = 0; k < n; k++) {
      const i = rev ? n - 1 - k : k;
      if (out.length > 0 && k === 0) continue;
      out.push(e.pts[2 * i]!, e.pts[2 * i + 1]!);
    }
    at = rev ? e.from : e.to;
  }
  return new RoutePath(new Float64Array(out), 1);
}

interface Trace {
  samples: { s: number; z: number; grade: number; v: number }[];
  min: number;
  max: number;
  length: number;
}

async function ride(city: City, route: RoutePath, startV: number): Promise<Trace> {
  const d = new DriveWorld(city, spec, tuning);
  if (d.traffic) d.traffic.solid = false;
  if (d.trams) d.trams.solid = false;
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (let i = 0; i < route.count; i++) {
    x0 = Math.min(x0, route.pts[2 * i]!); x1 = Math.max(x1, route.pts[2 * i]!);
    y0 = Math.min(y0, route.pts[2 * i + 1]!); y1 = Math.max(y1, route.pts[2 * i + 1]!);
  }
  const c = city.chunkM;
  for (const ch of city.manifest.chunks) {
    if ((ch.x + 1) * c < x0 - c || ch.x * c > x1 + c || (ch.y + 1) * c < y0 - c || ch.y * c > y1 + c) continue;
    d.addChunk(await prepareChunk(await source.read(chunkPath(ch.x, ch.y))));
  }
  const p = route.at(0);
  d.spawn(p.x, p.y, p.dir);
  d.car.body.setLinearVelocity({ x: Math.cos(p.dir) * startV, y: Math.sin(p.dir) * startV });
  const b = tuning.bench;
  let s = 0, nextSample = 0, min = Infinity, max = -Infinity;
  const samples: Trace['samples'] = [];
  for (let i = 0; i < 120 / dt && s < route.length - b.arriveM; i++) {
    const car = d.car;
    s = route.project(car.x, car.y, s - b.searchBackM, s + b.searchAheadM);
    const target = route.at(s + b.lookaheadM + b.lookaheadPerMps * car.speed);
    let e = Math.atan2(target.y - car.y, target.x - car.x) - car.heading;
    while (e > Math.PI) e -= 2 * Math.PI;
    while (e < -Math.PI) e += 2 * Math.PI;
    d.input.reset();
    d.input.steer = Math.min(1, Math.max(-1, -b.steerGain * e));
    d.update(dt);
    const v = d.car.speed;
    min = Math.min(min, v);
    max = Math.max(max, v);
    if (s >= nextSample) {
      // Grade along the heading, + = uphill.
      const grade = d.grad.x * Math.cos(d.car.heading) + d.grad.y * Math.sin(d.car.heading);
      samples.push({ s: Math.round(s), z: +d.groundZ().toFixed(1), grade: Math.round(grade * 100), v: +v.toFixed(2) });
      nextSample += 25;
    }
  }
  return { samples, min, max, length: route.length };
}

describe.skipIf(!existsSync(join(dir, 'manifest.pb')))('cruise hold on Prague hills (specs/drive.md v2)', () => {
  let city: City;
  beforeAll(async () => {
    city = await City.load(source);
  }, 120000);

  const show = (name: string, t: Trace): void => {
    console.log(`${name}: ${t.length.toFixed(0)} m, v ${t.min.toFixed(2)}..${t.max.toFixed(2)} m/s (cruise ${cruise})`);
    console.log(t.samples.map((q) => `s${q.s} z${q.z} g${q.grade}% v${q.v}`).join(' | '));
  };

  it('Nerudova downhill (from the castle end, no input): cruise ± 1.5 m/s', async () => {
    // Upper Nerudova is one-way uphill; ridden down here (traffic off) for the steepest stretch.
    const t = await ride(city, chain(city, [5678, 6051, 6052, 6053, 6054], 4915), cruise);
    show('Nerudova', t);
    expect(t.max).toBeLessThanOrEqual(cruise + TOL);
    expect(t.min).toBeGreaterThanOrEqual(cruise - TOL);
  }, 120000);

  it('Chotkova descent (castle to Klárov, no input): cruise ± 1.5 m/s', async () => {
    const t = await ride(city, chain(city, [6523, 6544, 6515, 6516, 6517], 5643), cruise);
    show('Chotkova', t);
    expect(t.max).toBeLessThanOrEqual(cruise + TOL);
    expect(t.min).toBeGreaterThanOrEqual(cruise - TOL);
  }, 120000);
});
