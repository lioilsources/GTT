import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

import { beforeAll, describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { Autopilot } from '../src/drive/autopilot';
import { routeGraphFromPb } from '../src/drive/gps';
import { DriveWorld } from '../src/drive/driveWorld';
import { resolveRoute, routeFile } from '../src/drive/route';
import type { BenchRoute, CarSpec } from '../src/gen/schema';
import { Tuning } from '../src/gen/tuning';
import { chunkPath, type PackSource } from '../src/world/citypack';
import { prepareChunk } from '../src/world/chunk';
import { City } from '../src/world/model';
import { Navigator } from '../src/phone/nav';
import { HILL_KEYS, hillYaml } from '../src/drive/hillPanel';

// L-S1 / M5-S10: the three Prague hill routes (specs/bench.md v2 "Další trasy"). The autopilot
// drives each on the real pack and must arrive without any rescue, autopilot respawn or water fall.
const root = join(__dirname, '..', '..');
const pack = join(root, 'build', 'packs', 'prague');
const source: PackSource = { read: async (p) => new Uint8Array(readFileSync(join(pack, p))) };
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const car = JSON.parse(readFileSync(join(root, 'content', 'cars', `${tuning.cars.startCar}.json`), 'utf8')) as CarSpec;
const benchDir = join(root, 'content', 'bench');
const routes = readdirSync(benchDir)
  .filter((f) => f.startsWith('prague-') && f.endsWith('.json'))
  .map((f) => JSON.parse(readFileSync(join(benchDir, f), 'utf8')) as BenchRoute);
const report = process.env.HILLS_REPORT;

interface Run {
  id: string;
  lengthM: number;
  timeS: number;
  minMps: number;
  maxMps: number;
  maxGradePct: number;
  maxRealGradePct: number;
  climbM: number;
  airborne: number;
  rescues: number;
  respawns: number;
  waterFalls: number;
}

describe.skipIf(!existsSync(pack))('Prague hill routes (specs/bench.md v2)', () => {
  let city: City;
  beforeAll(async () => {
    city = await City.load(source);
  });

  it('has the three routes, each named after its file', () => {
    expect(routes.map((r) => r.id).sort()).toEqual(['hradcany', 'letna', 'petrin']);
    for (const r of routes) {
      expect(r.city).toBe('prague');
      expect(existsSync(join(benchDir, routeFile(r.city, r.id)))).toBe(true);
    }
  });

  it.each(routes.map((r) => [r.id, r] as const))('%s resolves over kept ground roads that climb', (_, r) => {
    const route = resolveRoute(city.graph, r);
    expect(route.edges.length).toBeGreaterThan(0);
    for (const ei of route.edges) {
      const e = city.graph.edges[ei]!;
      expect(e.kept, `${e.name} #${ei} kept`).toBe(true);
      expect(e.stairs || e.tunnel, `${e.name} #${ei} drivable`).toBe(false);
    }
    expect(route.length).toBeGreaterThan(500);
    expect(route.length).toBeLessThan(3000);
  });

  it('?route= navigation follows the route polyline to its end', () => {
    const r = routes.find((x) => x.id === 'petrin')!;
    const route = resolveRoute(city.graph, r);
    const nav = new Navigator(city.graph, routeGraphFromPb(city.graphPb, tuning.route.classCost), tuning.route, tuning.nav);
    const start = route.at(0), end = route.at(route.length);
    nav.follow({ id: `route:${r.id}`, name: r.legs[r.legs.length - 1]!.to.b, edge: route.edges[route.edges.length - 1]!,
      parkX: Math.round(end.x * 10), parkY: Math.round(end.y * 10) }, route.pts, start.x, start.y);
    expect(nav.hasRoute).toBe(true);
    expect(nav.remaining).toBeCloseTo(route.length, 0);
    expect(nav.update(start.x, start.y, start.dir, null, 1 / 60)).toBeNull();
    expect(nav.update(end.x, end.y, start.dir, null, 1 / 60)).toBe('arrived');
  });

  const runs: Run[] = [];
  it.each(routes.map((r) => [r.id, r] as const))('%s: the autopilot arrives with no rescue and no water fall', async (_, r) => {
    const route = resolveRoute(city.graph, r);
    const d = new DriveWorld(city, car, tuning);
    const cm = city.chunkM;
    const p = route.pts;
    let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
    for (let i = 0; i < p.length; i += 2) {
      x0 = Math.min(x0, p[i]!); x1 = Math.max(x1, p[i]!);
      y0 = Math.min(y0, p[i + 1]!); y1 = Math.max(y1, p[i + 1]!);
    }
    const nature = { chunkM: cm, version: city.manifest.natureVersion };
    for (const c of city.manifest.chunks) {
      if ((c.x + 1) * cm < x0 - cm || c.x * cm > x1 + cm || (c.y + 1) * cm < y0 - cm || c.y * cm > y1 + cm) continue;
      d.addChunk(await prepareChunk(await source.read(chunkPath(c.x, c.y)), nature));
    }
    let rescues = 0, waterFalls = 0;
    d.onRescue = () => rescues++;
    d.onWater = () => waterFalls++;
    const pilot = new Autopilot(route, tuning);
    pilot.start(d);
    d.beforeStep = (step) => pilot.step(d, d.input, step);
    const ex = city.manifest.exaggeration || 1;
    const dt = 1 / 60;
    let t = 0, minV = Infinity, maxV = 0, maxGrade = 0, airborne = 0, wasAir = false, rolling = false;
    const z0 = d.groundZ();
    let zMax = z0;
    while (!pilot.finished && t < 600) {
      d.update(dt);
      t += dt;
      const v = d.car.speed;
      if (pilot.s > 100) rolling = true;
      // Climb speed: past the first 100 m (the standing start) until the final approach.
      if (rolling && pilot.s < route.length - 2 * tuning.bench.arriveM) minV = Math.min(minV, v);
      maxV = Math.max(maxV, v);
      const g = d.grad.x * Math.cos(d.car.heading) + d.grad.y * Math.sin(d.car.heading);
      maxGrade = Math.max(maxGrade, Math.abs(g));
      const air = d.car.airborne || d.jumping;
      if (air && !wasAir) airborne++;
      wasAir = air;
      zMax = Math.max(zMax, d.groundZ());
    }
    const run: Run = {
      id: r.id,
      lengthM: Math.round(route.length),
      timeS: Math.round(t * 10) / 10,
      minMps: Math.round(minV * 10) / 10,
      maxMps: Math.round(maxV * 10) / 10,
      maxGradePct: Math.round(maxGrade * 1000) / 10,
      maxRealGradePct: Math.round((maxGrade / ex) * 1000) / 10,
      climbM: Math.round(((zMax - z0) / ex) * 10) / 10,
      airborne,
      rescues,
      respawns: pilot.respawns,
      waterFalls,
    };
    runs.push(run);
    if (report) writeFileSync(report, JSON.stringify(runs, null, 1));
    expect(pilot.finished, JSON.stringify(run)).toBe(true);
    expect(run.rescues, JSON.stringify(run)).toBe(0);
    expect(run.respawns, JSON.stringify(run)).toBe(0);
    expect(run.waterFalls, JSON.stringify(run)).toBe(0);
    expect(run.climbM, JSON.stringify(run)).toBeGreaterThan(20);
  }, 120_000);
});

describe('hill tuning panel (specs/bench.md v2 "Ladění kopců")', () => {
  it('names real tuning.yaml keys, sets them live and copies YAML with float literals', () => {
    const yaml = parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')) as Record<string, unknown>;
    const t = Tuning.fromJson(yaml);
    for (const k of HILL_KEYS) {
      const v = k.key.split('.').reduce<unknown>((o, p) => (o as Record<string, unknown>)[p], yaml);
      expect(v, k.key).toBe(k.get(t));
      expect(k.min).toBeLessThan(k.get(t));
      expect(k.max).toBeGreaterThan(k.get(t));
    }
    HILL_KEYS[0]!.set(t, 25);
    expect(t.slopePhysics.gravity).toBe(25);
    expect(hillYaml(t).split('\n')[0]).toBe('slope_physics.gravity: 25.0');
  });
});
