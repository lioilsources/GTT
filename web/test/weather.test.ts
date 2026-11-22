import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { Tuning } from '../src/gen/tuning';
import { rulesModules } from '../src/rules/vectors';
import { rainCells } from '../src/render/weatherView';
import { isWeatherKind, weatherActive, weatherConfig, WeatherRules, type WeatherAction, type WeatherConfig } from '../src/weather/rules';
import { fogAlpha, weatherToastKey, WeatherWorld, wetFactor } from '../src/weather/weather';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const P = { by: 'player' } as const;
const tick: WeatherAction = { ...P, op: 'tick' };

const run = (cfg: WeatherConfig, seed: number, acts: WeatherAction[]) => {
  const r = new WeatherRules();
  let s = r.init(cfg, seed);
  const out = [s];
  for (const a of acts) out.push((s = r.apply(s, a)));
  return out;
};

describe('weather rules (specs/weather.md P0)', () => {
  it('is registered for vector replay', () => {
    expect(rulesModules['weather']!().specVersion).toBe(1);
  });

  it('starts clear with a gap in min..max and no changes', () => {
    for (let seed = 0; seed < 50; seed++) {
      const s = new WeatherRules().init({ weights: [5, 3, 2], minS: 3, maxS: 7 }, seed);
      expect(s.kind).toBe('clear');
      expect(s.changes).toBe(0);
      expect(s.left).toBeGreaterThanOrEqual(3);
      expect(s.left).toBeLessThanOrEqual(7);
    }
  });

  it('never repeats the kind on a tick change', () => {
    const states = run({ weights: [5, 3, 2], minS: 1, maxS: 1 }, 42, Array(60).fill(tick));
    for (let i = 1; i < states.length; i++) expect(states[i]!.kind).not.toBe(states[i - 1]!.kind);
    expect(states.at(-1)!.changes).toBe(60);
  });

  it('keeps the kind and the PRNG draw for the gap only when the other weights are zero', () => {
    const [, a] = run({ weights: [4, 0, 0], minS: 2, maxS: 2 }, 9, [tick, tick]).slice(1);
    expect(a!.kind).toBe('clear');
    expect(a!.changes).toBe(1);
    expect(a!.left).toBe(2);
  });

  it('set: any kind, same kind renews the gap, unknown kind is illegal', () => {
    const r = new WeatherRules();
    const s0 = r.init(weatherConfig(tuning.weather), 5);
    const s1 = r.apply(s0, { ...P, op: 'set', kind: 'clear' });
    expect(s1.kind).toBe('clear');
    expect(s1.changes).toBe(1);
    expect(s1.rng).not.toBe(s0.rng);
    expect(() => r.apply(s1, { ...P, op: 'set', kind: 'snow' as never })).toThrow();
    expect(() => r.apply(s1, { by: 'ai', op: 'tick' } as never)).toThrow();
    expect(() => r.apply(s1, { ...P, op: 'wind' } as never)).toThrow();
    expect(r.legalActions(s1).map((a) => (a.op === 'set' ? a.kind : a.op))).toEqual(['tick', 'clear', 'rain', 'fog']);
    expect(r.result(s1)).toBeNull();
  });

  it('kind guard and city switch', () => {
    expect(isWeatherKind('fog')).toBe(true);
    expect(isWeatherKind('snow')).toBe(false);
    expect(weatherActive(tuning.weather, 'nyc')).toBe(tuning.weather.enabled && tuning.weather.cities.nyc);
    expect(weatherActive(tuning.weather, 'atlantis')).toBe(false);
    expect(weatherActive(tuning.weather, 'constructor')).toBe(false);
  });
});

describe('weather in the world (P1)', () => {
  const wt = tuning.weather;

  it('ticks once per whole game second and stops while paused', () => {
    const w = new WeatherWorld(wt, 1);
    const left = w.state.left;
    w.update(0.4);
    w.update(0.4);
    expect(w.state.left).toBe(left);
    w.update(0.4);
    expect(w.state.left).toBe(left - 1);
    for (let i = 0; i < 100; i++) w.update(0); // paused: the clock stands
    expect(w.state.left).toBe(left - 1);
  });

  it('grip switches at once, the look blends linearly over blend_s', () => {
    const w = new WeatherWorld(wt, 3);
    const changes: string[] = [];
    w.onChange.push((k) => changes.push(k));
    expect(w.grip).toBe(1);
    w.set('rain');
    expect(changes).toEqual(['rain']);
    expect(w.grip).toBe(wt.rainGrip);
    w.fade(wt.blendS / 4);
    expect(w.blend.rain).toBeCloseTo(0.25);
    expect(w.blend.clear).toBeCloseTo(0.75);
    w.fade(wt.blendS);
    expect(w.blend).toEqual({ clear: 0, rain: 1, fog: 0 });
    w.set('fog');
    expect(w.grip).toBe(1);
    w.fade(wt.blendS / 2);
    expect(w.blend.rain).toBeCloseTo(0.5);
    expect(w.blend.fog).toBeCloseTo(0.5);
    w.set('fog'); // same kind: no change, no toast
    expect(changes).toEqual(['rain', 'fog']);
  });

  it('fog alpha: centre, smooth ramp from fog_inner, edge', () => {
    expect(fogAlpha(wt, 0)).toBeCloseTo(wt.fogCenterAlpha);
    expect(fogAlpha(wt, wt.fogInner)).toBeCloseTo(wt.fogCenterAlpha);
    expect(fogAlpha(wt, 1)).toBeCloseTo(wt.fogEdgeAlpha);
    const mid = fogAlpha(wt, (wt.fogInner + 1) / 2);
    expect(mid).toBeCloseTo((wt.fogCenterAlpha + wt.fogEdgeAlpha) / 2);
  });

  it('wet roads darken to 1 − wet_darken', () => {
    expect(wetFactor(wt, 0)).toBe(1);
    expect(wetFactor(wt, 1)).toBeCloseTo(1 - wt.wetDarken);
  });

  it('rain cells hold about rain_drops streaks, each longer than a streak', () => {
    const w = 1170, h = 2532, len = wt.rainLenPx * 3;
    const { cw, ch } = rainCells(w, h, wt.rainDrops, len);
    expect((w * h) / (cw * ch)).toBeCloseTo(wt.rainDrops, 0);
    expect(ch).toBeGreaterThan(len);
  });

  it('toast keys', () => {
    expect(weatherToastKey('clear')).toBe('weatherClear');
    expect(weatherToastKey('rain')).toBe('weatherRain');
    expect(weatherToastKey('fog')).toBe('weatherFog');
  });
});
