import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { JumpState, projectionScale, shadowScale, slopeAccel } from '../src/drive/slope';
import { Tuning } from '../src/gen/tuning';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const sp = tuning.slopePhysics;

/** The pure jump model over a ground profile at constant horizontal speed (no drag). */
function fly(v: number, g: (x: number) => number, x0 = -30, s = 4): { air: number; dist: number; landing: number | null; maxGap: number } {
  const dt = 1 / 60;
  const j = new JumpState();
  j.reset(g(x0));
  let x = x0, air = 0, landing: number | null = null, maxGap = 0;
  for (let i = 0; i < s * 60; i++) {
    x += v * dt;
    const l = j.step(g(x), dt, sp.gravity, sp.suspensionTravel);
    if (j.airborne) air += dt;
    maxGap = Math.max(maxGap, j.gap);
    if (l !== null && landing === null) landing = l;
  }
  return { air, dist: air * v, landing, maxGap };
}

const crest = (up: number, down: number) => (x: number): number => (x < 0 ? up * x : -down * x);
const near = (a: number, b: number, tol = 0.02): void => expect(Math.abs(a - b)).toBeLessThanOrEqual(Math.abs(b) * tol);

describe('jump model control table (specs/terrain.md "Kontrolní hodnoty", ±2 %)', () => {
  it('uses the table tuning (gravity 20, suspension 0.5)', () => {
    expect(sp.gravity).toBe(20);
    expect(sp.suspensionTravel).toBe(0.5);
  });

  it('30 m/s, 15 % up into 15 % down: 0.77 s, 23 m, landing 8.7 m/s', () => {
    const r = fly(30, crest(0.15, 0.15));
    near(r.air, 0.77);
    near(r.dist, 23);
    near(r.landing!, 8.7);
  });

  it('40 m/s, 20 % / 20 %: 1.53 s, 61 m, landing 15.7 m/s (hard)', () => {
    const r = fly(40, crest(0.2, 0.2));
    near(r.air, 1.53);
    near(r.dist, 61);
    near(r.landing!, 15.7);
    expect(r.landing!).toBeGreaterThan(sp.hardLanding);
  });

  it('15 m/s, 5 % / 5 %: no jump (gap 0.04 m)', () => {
    const r = fly(15, crest(0.05, 0.05));
    expect(r.air).toBe(0);
    expect(r.maxGap).toBeLessThan(0.06);
    expect(r.maxGap).toBeGreaterThan(0.03);
  });

  it('30 m/s, 5 cm step down: no jump', () => {
    expect(fly(30, (x) => (x < 0 ? 0 : -0.05)).air).toBe(0);
  });

  it('30 m/s, waves ±0.3 m with a 19 m period: no jump', () => {
    expect(fly(30, (x) => 0.3 * Math.sin((2 * Math.PI * x) / 19), 0, 6).air).toBe(0);
  });
});

describe('slope force and helpers (specs/terrain.md)', () => {
  it('a = −g · scale · grad · k, grip factor k', () => {
    const out = { x: 0, y: 0 };
    const k = slopeAccel(0.1, 0, sp, out);
    expect(k).toBeCloseTo(1 / Math.sqrt(1.01), 12);
    expect(out.x).toBeCloseTo(-20 * 0.6 * 0.1 * k, 12);
    expect(out.y).toBe(-0);
  });

  it('shadow scale and the F projection (hill 30 m up at 100 m moves 13.6 m, H 250)', () => {
    expect(shadowScale(0)).toBe(1);
    expect(shadowScale(4)).toBe(0.5);
    expect(100 * projectionScale(30, 250) - 100).toBeCloseTo(13.636, 2);
    expect(projectionScale(1000, 250)).toBeCloseTo(5, 9);
  });
});
