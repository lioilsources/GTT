import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { beforeAll, describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { Tuning } from '../src/gen/tuning';
import { dodge, overlapsBox, Pedestrian, PedestrianWorld, settle, stepAvoid, type CarPose, type PedStats } from '../src/peds/pedestrians';
import { Prng } from '../src/rules/prng';
import type { PackSource } from '../src/world/citypack';
import { City } from '../src/world/model';

// Same cases as packages/drive_core/test/pedestrians_test.dart (specs/pedestrians.md "Testy").
const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const t = tuning.pedestrians;
const r = t.radiusM * tuning.carScale;
const car = (x: number, y: number, heading: number, vx: number, vy: number): CarPose => ({
  x, y, heading, halfLength: 5.5, halfWidth: 2.4, vx, vy,
});

describe('dodge', () => {
  it('ignores a pedestrian outside the band', () => {
    expect(dodge(0, 12, r, car(0, 0, 0, 20, 0), t)).toBeNull();
    expect(dodge(-20, 0, r, car(0, 0, 0, 20, 0), t)).toBeNull(); // behind
    expect(dodge(60, 0, r, car(0, 0, 0, 20, 0), t)).toBeNull(); // beyond the horizon
  });

  it('ignores a standing car', () => {
    expect(dodge(8, 0, r, car(0, 0, 0, 0, 0), t)).toBeNull();
  });

  it('leaps a pedestrian ahead out of the band, away from the axis', () => {
    const d = dodge(20, 1, r, car(0, 0, 0, 20, 0), t)!;
    expect(d).not.toBeNull();
    expect(d.dx).toBeCloseTo(0, 9);
    expect(d.dy).toBeGreaterThan(0); // left of the path stays left
    expect(1 + d.dy).toBeGreaterThanOrEqual(2.4 + r + t.dodgeMarginM);
    expect(d.tc).toBeCloseTo((20 - 5.5 - r - t.dodgeMarginM) / 20, 9);
    expect(d.dur).toBeLessThanOrEqual(d.tc * t.leapFraction + 1e-12);
    const right = dodge(20, -1, r, car(0, 0, 0, 20, 0), t)!;
    expect(right.dy).toBeLessThan(0);
    const centre = dodge(20, 0, r, car(0, 0, 0, 20, 0), t)!;
    expect(centre.dy).toBeGreaterThan(0); // perp = 0 → +1
  });

  it('uses the velocity, not the heading (reversing)', () => {
    expect(dodge(10, 0, r, car(0, 0, 0, -8, 0), t)).toBeNull();
    const d = dodge(-10, 0.5, r, car(0, 0, 0, -8, 0), t)!;
    expect(d).not.toBeNull();
    expect(d.dy).toBeGreaterThan(0); // n = (0, −1), perp = −0.5: the leap goes further to +y
  });

  it('jumps at once when contact is imminent', () => {
    const d = dodge(6, 0, r, car(0, 0, 0, 30, 0), t)!;
    expect(d.tc).toBe(0);
    expect(d.dur).toBe(0);
  });
});

/** Point (px, py) vs the box swept from pose c over [0, T] at constant velocity (sampled). */
function hitsSwept(px: number, py: number, c: CarPose, T: number, dt: number): boolean {
  for (let s = 0; s <= T + 1e-9; s += dt) {
    if (overlapsBox(px, py, r, { ...c, x: c.x + c.vx * s, y: c.y + c.vy * s })) return true;
  }
  return false;
}

describe('the guarantee (R7)', () => {
  it('no approach in limits ever touches a pedestrian', () => {
    const rnd = new Prng(1);
    const u = (): number => rnd.nextU32() / 4294967296;
    const dt = 1 / 60;
    let tested = 0, dodged = 0;
    for (let n = 0; n < 400; n++) {
      const h = u() * 2 * Math.PI;
      const speed = t.dodgeMinMps + u() * (45 - t.dodgeMinMps);
      const slip = (u() * 2 - 1) * 0.6;
      const back = u() < 0.15 ? -1 : 1;
      const vx = Math.cos(h + slip) * speed * back, vy = Math.sin(h + slip) * speed * back;
      const c0 = car(0, 0, h, vx, vy);
      // Pedestrian near the car's path: up to 50 m along the velocity, ±6 m across.
      const ux = vx / speed, uy = vy / speed;
      const al = -6 + u() * 56, pe = (u() * 2 - 1) * 6;
      const p = new Pedestrian(n + 1);
      p.bx = p.x = ux * al - uy * pe;
      p.by = p.y = uy * al + ux * pe;
      if (overlapsBox(p.x, p.y, r, c0)) continue;
      tested++;
      const stats: PedStats = { clamps: 0, dodges: 0 };
      const T = 2.5;
      let c = c0;
      for (let s = 0; s < T; s += dt) {
        c = { ...c, x: c.x + vx * dt, y: c.y + vy * dt };
        const was = p.mode;
        stepAvoid(p, [c], r, dt, t, stats);
        settle(p, [c], r, t, stats);
        expect(overlapsBox(p.x, p.y, r, c)).toBe(false);
        // Where a leap ends is outside the box the car sweeps over the rest of the pass.
        if (was !== 'stun' && p.mode === 'stun') expect(hitsSwept(p.x, p.y, c, T - s, dt / 4)).toBe(false);
      }
      expect(stats.clamps).toBe(0);
      if (stats.dodges > 0) dodged++;
    }
    expect(tested).toBeGreaterThan(300);
    expect(dodged).toBeGreaterThan(100);
  });
});

const pack = join(root, 'build', 'packs', 'nyc');
const source: PackSource = { read: async (p) => new Uint8Array(readFileSync(join(pack, p))) };

describe.skipIf(!existsSync(pack))('pedestrian world on NYC', () => {
  let city: City;
  beforeAll(async () => {
    city = await City.load(source);
  });

  const player = (): CarPose => ({ x: city.startX, y: city.startY, heading: city.startHeading, halfLength: 5.5, halfWidth: 2.4, vx: 0, vy: 0 });

  function onSidewalk(w: PedestrianWorld, x: number, y: number): boolean {
    const hit = city.graph.nearest(x, y, 40, (e) => w.walkable(e));
    if (!hit) return false;
    return Math.abs(hit.dist - w.offset(hit.edge)) < 1.5 || hit.dist < hit.edge.width / 2 + 1.5;
  }

  it('fills the area with walkers on sidewalks, under the cap', () => {
    const w = new PedestrianWorld(city, tuning);
    w.update(1 / 60, [player()], 60, false);
    expect(w.peds.length).toBeGreaterThan(5);
    expect(w.peds.length).toBeLessThanOrEqual(t.maxCount);
    for (const p of w.peds) {
      expect(Math.hypot(p.x - city.startX, p.y - city.startY)).toBeGreaterThanOrEqual(t.fillClearM);
      expect(onSidewalk(w, p.x, p.y)).toBe(true);
    }
    expect(new Set(w.peds.map((p) => p.id)).size).toBe(w.peds.length);
  });

  it('keeps them on the sidewalks while walking', () => {
    const w = new PedestrianWorld(city, tuning);
    for (let i = 0; i < 60 * 30; i++) w.update(1 / 60, [player()], 60, false);
    expect(w.peds.length).toBeGreaterThan(5);
    for (const p of w.peds) if (p.mode === 'walk') expect(onSidewalk(w, p.x, p.y)).toBe(true);
    expect(w.stats.clamps).toBe(0);
  });

  it('night lowers the cap; disabled means empty', () => {
    const w = new PedestrianWorld(city, tuning);
    for (let i = 0; i < 60 * 5; i++) w.update(1 / 60, [player()], 60, true);
    expect(w.peds.length).toBeLessThanOrEqual(Math.round(t.maxCount * t.nightFactor));
    const off = Tuning.fromJson({ ...tuning.toJson(), pedestrians: { ...t.toJson(), enabled: false } });
    const w2 = new PedestrianWorld(city, off);
    w2.update(1 / 60, [player()], 60, false);
    expect(w2.peds.length).toBe(0);
  });

  it('nearest and byId', () => {
    const w = new PedestrianWorld(city, tuning);
    w.update(1 / 60, [player()], 60, false);
    const p = w.peds[0]!;
    expect(w.nearest(p.x + 0.1, p.y)).toBe(p);
    expect(w.byId(p.id)).toBe(p);
    expect(w.nearest(p.x, p.y, -1)).toBeNull();
  });
});
