import { describe, expect, it } from 'vitest';

import { INTRO_KEY, rememberIntro, shouldShowIntro, type IntroStore } from '../src/firstrun/intro';
import { LoadProgress, ProgressSource } from '../src/firstrun/progress';
import { pausingOverlays } from '../src/pause';

const memStore = (): IntroStore & { m: Map<string, string> } => {
  const m = new Map<string, string>();
  return { m, getItem: (k) => m.get(k) ?? null, setItem: (k, v) => void m.set(k, v) };
};
const throwing: IntroStore = {
  getItem: () => {
    throw new Error('blocked');
  },
  setItem: () => {
    throw new Error('blocked');
  },
};

describe('first run intro (specs/firstrun.md)', () => {
  it('shows once, then remembers', () => {
    const s = memStore();
    expect(shouldShowIntro(new URLSearchParams(''), s)).toBe(true);
    rememberIntro(s);
    expect(s.m.get(INTRO_KEY)).toBe('1');
    expect(shouldShowIntro(new URLSearchParams(''), s)).toBe(false);
  });
  it('skips automated runs and deep links', () => {
    for (const q of ['bench', 'demo=roadster', 'gallery', 'mg=oko', 'skits', 'cars', 'nointro']) {
      expect(shouldShowIntro(new URLSearchParams(q), memStore())).toBe(false);
    }
    expect(shouldShowIntro(new URLSearchParams('city=prague'), memStore())).toBe(true);
  });
  it('blocked storage: shows every time and never throws', () => {
    expect(shouldShowIntro(new URLSearchParams(''), throwing)).toBe(true);
    expect(() => rememberIntro(throwing)).not.toThrow();
    expect(shouldShowIntro(new URLSearchParams(''), null)).toBe(true);
  });
  it('pauses the game', () => {
    expect(pausingOverlays).toContain('intro');
  });
});

describe('download progress (specs/firstrun.md)', () => {
  it('is 0 without a total, monotonic and capped at 99', () => {
    const seen: number[] = [];
    const p = new LoadProgress((x) => seen.push(x));
    p.received(100);
    expect(p.percent).toBe(0);
    p.started('graph.pb', 1000);
    expect(p.percent).toBe(9);
    p.announce('chunks/0_0.pb', 1000); // total grows: the percent must not drop
    expect(p.percent).toBe(9);
    p.started('chunks/0_0.pb', 1000); // announced already: not counted twice
    p.received(1900);
    expect(p.percent).toBe(99);
    expect(seen).toEqual([...seen].sort((a, b) => a - b));
  });
  it('responses without Content-Length only add to the loaded bytes', () => {
    const p = new LoadProgress();
    p.started('a', null);
    p.started('b', 200);
    p.received(100);
    expect(p.percent).toBe(49);
  });
  it('stop() freezes the percent for later streaming', () => {
    const seen: number[] = [];
    const p = new LoadProgress((x) => seen.push(x));
    p.started('a', 100);
    p.received(10);
    p.stop();
    p.received(80);
    expect(seen).toEqual([9]);
  });
  it('ProgressSource streams bytes through the progress', async () => {
    const body = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]);
    const fake = (async () => new Response(body, { headers: { 'content-length': '8' } })) as unknown as typeof fetch;
    const p = new LoadProgress();
    const src = new ProgressSource('x/', p, fake);
    expect(await src.read('graph.pb')).toEqual(body);
    expect(p.percent).toBe(99);
  });
});
