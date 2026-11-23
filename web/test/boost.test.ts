import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { parse } from 'yaml';
import { describe, expect, it } from 'vitest';

import { BOOST_HINT_KEY, BoostHint, boostHintKey, readBoostHint, writeBoostHint } from '../src/drive/boostHint';
import { ControlInput, createScheme, SchemeB, SchemeC, type ControlScheme } from '../src/drive/controls';
import { Tuning } from '../src/gen/tuning';

// specs/controls.md v2: Boost in schemes B and C, the boost hint.
const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const t = tuning.controls;
const W = 400, H = 860;
const centre = (r: { left: number; top: number; width: number; height: number }): { x: number; y: number } =>
  ({ x: r.left + r.width / 2, y: r.top + r.height / 2 });
const read = (s: ControlScheme): ControlInput => {
  const out = new ControlInput();
  s.update(out);
  return out;
};

describe('scheme B boost', () => {
  it('the Boost button boosts and steers nothing; a second thumb still steers', () => {
    const b = createScheme('b', t);
    b.down(1, centre(SchemeB.boostButton(W, H)), W, H);
    let o = read(b);
    expect(o.boost).toBe(true);
    expect(o.steer).toBe(0);
    expect(o.brake).toBe(0);
    b.down(2, { x: W * 0.9, y: H * 0.5 }, W, H);
    o = read(b);
    expect(o.boost).toBe(true);
    expect(o.steer).toBe(1);
    b.up(1);
    o = read(b);
    expect(o.boost).toBe(false);
    expect(o.steer).toBe(1);
  });
  it('a steering finger sliding over the button keeps steering', () => {
    const b = createScheme('b', t);
    b.down(1, { x: W * 0.1, y: H * 0.8 }, W, H);
    b.move(1, centre(SchemeB.boostButton(W, H)), W, H);
    const o = read(b);
    expect(o.boost).toBe(false);
    expect(o.steer).toBe(-1);
  });
});

describe('scheme C boost', () => {
  it('the Boost button above the pedal boosts, the wheel still steers', () => {
    const c = createScheme('c', t) as SchemeC;
    c.down(1, centre(SchemeC.boostButton(W, H)), W, H);
    expect(c.boostHeld).toBe(true);
    let o = read(c);
    expect(o.boost).toBe(true);
    expect(o.brake).toBe(0);
    const ctr = SchemeC.wheelCentre(W, H), r = SchemeC.wheelRadius(W);
    c.down(2, { x: ctr.x, y: ctr.y - r }, W, H);
    c.move(2, { x: ctr.x + r, y: ctr.y }, W, H);
    o = read(c);
    expect(o.boost).toBe(true);
    expect(o.steer).toBeGreaterThan(0.5);
    c.up(1);
    expect(read(c).boost).toBe(false);
  });
  it('the brake pedal is not boost', () => {
    const c = createScheme('c', t);
    c.down(1, centre(SchemeC.pedal(W, H)), W, H);
    const o = read(c);
    expect(o.brake).toBe(1);
    expect(o.boost).toBe(false);
  });
});

describe('boost hint', () => {
  it('shows on the first drive, again after cruise without boost, at most max times', () => {
    const h = new BoostHint(t, 0);
    expect(h.step(0, 0, false)).toBeNull(); // paused
    expect(h.step(1 / 60, 0, false)).toBe('show');
    expect(h.shown).toBe(1);
    // Slow driving does not count.
    for (let i = 0; i < 100; i++) expect(h.step(1, t.boostHintMinSpeedMps - 1, false)).toBeNull();
    let shows = 1;
    for (let i = 0; i < 1000; i++) if (h.step(1, 14, false) === 'show') shows++;
    expect(shows).toBe(t.boostHintMax);
    expect(h.shown).toBe(t.boostHintMax);
  });
  it('the second show waits boost_hint_after_s of cruise', () => {
    const h = new BoostHint(t, 1);
    const n = Math.ceil(t.boostHintAfterS);
    for (let i = 0; i < n - 1; i++) expect(h.step(1, 14, false)).toBeNull();
    expect(h.step(1, 14, false)).toBe('show');
  });
  it('using boost stops the hint for good', () => {
    const h = new BoostHint(t, 0);
    expect(h.step(1 / 60, 0, true)).toBe('used');
    expect(h.shown).toBe(t.boostHintMax);
    expect(h.step(1 / 60, 30, true)).toBeNull();
    for (let i = 0; i < 1000; i++) expect(h.step(1, 14, false)).toBeNull();
  });
  it('is persisted: once shown it does not show again on the next start before the cruise wait', () => {
    const mem = new Map<string, string>();
    const store = { getItem: (k: string) => mem.get(k) ?? null, setItem: (k: string, v: string) => void mem.set(k, v) };
    expect(readBoostHint(store)).toBe(0);
    const first = new BoostHint(t, readBoostHint(store));
    expect(first.step(1 / 60, 0, false)).toBe('show');
    writeBoostHint(store, first.shown);
    expect(mem.get(BOOST_HINT_KEY)).toBe('1');
    const next = new BoostHint(t, readBoostHint(store));
    expect(next.step(1 / 60, 0, false)).toBeNull();
    // Blocked storage: no throw, counts from 0.
    const bad = {
      getItem: (): string | null => {
        throw new Error('blocked');
      },
      setItem: (): void => {
        throw new Error('blocked');
      },
    };
    expect(readBoostHint(bad)).toBe(0);
    expect(() => writeBoostHint(bad, 2)).not.toThrow();
  });
  it('text follows the scheme, keyboard wins', () => {
    expect(boostHintKey('a', false)).toBe('boostHintA');
    expect(boostHintKey('b', false)).toBe('boostHintB');
    expect(boostHintKey('c', false)).toBe('boostHintC');
    expect(boostHintKey('b', true)).toBe('boostHintKeys');
  });
});
