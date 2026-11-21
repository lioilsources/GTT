import { describe, expect, it } from 'vitest';

import { flickAim, laneLayout } from '../src/minigames/koulena/game';
import { KoulenaRules, koulenaPoints, type KoulenaAction, type KoulenaConfig, type KoulenaState } from '../src/minigames/koulena/rules';
import { replay } from '../src/minigames/rules';
import { Prng } from '../src/rules/prng';

const cfg: KoulenaConfig = {
  series: 3,
  balls: 9,
  ringR: [80, 160, 240, 320, 400],
  ringPoints: [50, 40, 30, 20, 10],
  pockets: [-300, 360, 300, 360],
  pocketR: 50,
  pocketPoints: 100,
  scatter: [40, 55, 70, 85, 100],
  starScores: [700, 520, 360],
};

const centre = (level = 1): KoulenaAction => ({ by: 'player', x: 0, y: 0, level });

describe('koulena rules (specs/minigames/koulena.md)', () => {
  it('starts at series 1, ball 0 with an empty hit', () => {
    const r = new KoulenaRules();
    const s = r.init(cfg, 42);
    expect(s).toEqual({ series: 1, ball: 0, score: 0, seriesScores: [], lastHit: { x: 0, y: 0, points: 0 }, over: false, rng: new Prng(42).state });
    expect(r.legalActions()).toEqual([]);
    expect(r.result(s)).toBeNull();
  });

  it('ring boundaries: exactly on the radius counts for the inner ring', () => {
    expect(koulenaPoints(cfg, 0, 0)).toBe(50);
    expect(koulenaPoints(cfg, 80, 0)).toBe(50);
    expect(koulenaPoints(cfg, 81, 0)).toBe(40);
    expect(koulenaPoints(cfg, 0, -160)).toBe(40);
    expect(koulenaPoints(cfg, 96, 128)).toBe(40); // 3-4-5 triangle, distance 160
    expect(koulenaPoints(cfg, 240, 0)).toBe(30);
    expect(koulenaPoints(cfg, 0, 320)).toBe(20);
    expect(koulenaPoints(cfg, -400, 0)).toBe(10);
    expect(koulenaPoints(cfg, 401, 0)).toBe(0);
    expect(koulenaPoints(cfg, 300, -300)).toBe(0);
  });

  it('pockets win over rings and are checked before them', () => {
    expect(koulenaPoints(cfg, -300, 360)).toBe(100);
    expect(koulenaPoints(cfg, 300, 360)).toBe(100);
    expect(koulenaPoints(cfg, 350, 360)).toBe(100); // on the pocket edge
    expect(koulenaPoints(cfg, 351, 360)).toBe(0);
    // A pocket overlapping a ring still scores the pocket.
    const overlap = { ...cfg, pockets: [0, 0], pocketR: 10 };
    expect(koulenaPoints(overlap, 10, 0)).toBe(100);
    expect(koulenaPoints(overlap, 11, 0)).toBe(50);
  });

  it('scatter draws x then y from the state rng, deterministically', () => {
    const r = new KoulenaRules();
    const s0 = r.init(cfg, 7);
    const a = r.apply(s0, { by: 'player', x: 10, y: 20, level: 2 });
    const p = new Prng(7);
    const x = 10 + p.nextInt(111) - 55;
    const y = 20 + p.nextInt(111) - 55;
    expect(a.lastHit).toEqual({ x, y, points: koulenaPoints(cfg, x, y) });
    expect(a.rng).toBe(p.state);
    const r2 = new KoulenaRules();
    expect(r2.apply(r2.init(cfg, 7), { by: 'player', x: 10, y: 20, level: 2 })).toEqual(a);
    expect(Math.abs(a.lastHit.x - 10)).toBeLessThanOrEqual(55);
    expect(s0.ball).toBe(0); // apply is pure
  });

  it('rejects illegal actions', () => {
    const r = new KoulenaRules();
    const s = r.init(cfg, 1);
    expect(() => r.apply(s, { by: 'player', x: 0, y: 0, level: 0 })).toThrow();
    expect(() => r.apply(s, { by: 'player', x: 0, y: 0, level: 6 })).toThrow();
    expect(() => r.apply(s, { by: 'player', x: 0.5, y: 0, level: 1 })).toThrow();
    expect(() => r.apply(s, { by: 'ai', x: 0, y: 0, level: 1 } as unknown as KoulenaAction)).toThrow();
    expect(() => r.apply({ ...s, over: true }, centre())).toThrow();
  });

  it('closes a series after nine balls and the game after 27', () => {
    const r = new KoulenaRules();
    let s: KoulenaState = r.init(cfg, 3);
    for (let i = 0; i < 9; i++) s = r.apply(s, centre());
    expect(s).toMatchObject({ series: 2, ball: 0, over: false });
    expect(s.seriesScores).toEqual([s.score]);
    for (let i = 0; i < 17; i++) s = r.apply(s, centre());
    expect(s).toMatchObject({ series: 3, ball: 8, over: false });
    s = r.apply(s, centre());
    expect(s.over).toBe(true);
    expect(s.seriesScores).toHaveLength(3);
    expect(s.seriesScores.reduce((a, b) => a + b, 0)).toBe(s.score);
    expect(() => r.apply(s, centre())).toThrow();
    expect(r.result(s)).toEqual({ winner: s.score >= 360 ? 'player' : 'ai', stars: expect.any(Number), score: s.score, seriesScores: s.seriesScores });
  });

  it('stars follow the score thresholds', () => {
    const r = new KoulenaRules();
    const b = { ...r.init(cfg, 1), over: true };
    const res = (score: number) => r.result({ ...b, score })!;
    expect([700, 699, 520, 519, 360, 359, 0].map((v) => res(v).stars)).toEqual([3, 2, 2, 1, 1, 0, 0]);
    expect(res(360).winner).toBe('player');
    expect(res(359).winner).toBe('ai');
  });

  it('timeout ends the game with only finished series counted', () => {
    const r = new KoulenaRules();
    let s = r.init(cfg, 5);
    for (let i = 0; i < 11; i++) s = r.apply(s, centre(5));
    s = r.apply(s, { by: 'timeout' });
    expect(s.over).toBe(true);
    expect(s.series).toBe(2);
    expect(s.seriesScores).toHaveLength(1);
    expect(r.result(s)!.score).toBe(s.score);
    expect(() => r.apply(s, { by: 'timeout' })).toThrow();
  });

  it('aiAction aims at the centre with level 3', () => {
    expect(new KoulenaRules().aiAction()).toEqual({ by: 'player', x: 0, y: 0, level: 3 });
  });

  it('a seeded game replays to the same states', () => {
    const r = new KoulenaRules();
    const pol = new Prng(77);
    let s = r.init(cfg, 77);
    const steps: Array<{ action: Record<string, unknown> }> = [];
    while (!s.over) {
      const a: KoulenaAction = { by: 'player', x: pol.nextInt(801) - 400, y: pol.nextInt(801) - 400, level: 1 + pol.nextInt(5) };
      steps.push({ action: a as Record<string, unknown> });
      s = r.apply(s, a);
    }
    expect(steps).toHaveLength(27);
    const again = replay(new KoulenaRules() as never, { config: cfg as never, seed: 77, steps });
    expect(again.states.at(-1)).toEqual(s);
    expect(again.result).toEqual(r.result(s));
  });
});

describe('koulena flick mapping', () => {
  it('a straight swipe up aims along the centre line; length scales by mm per px', () => {
    const lay = laneLayout(cfg);
    expect(lay.aimOriginY).toBe(-400);
    expect(flickAim(lay, 0, -200, 2)).toEqual({ x: 0, y: 0 });
    expect(flickAim(lay, 150, -380, 2)).toEqual({ x: 300, y: 360 });
    const a = flickAim(lay, 10.3, -100.4, 2.2);
    expect(Number.isInteger(a.x) && Number.isInteger(a.y)).toBe(true);
  });
});
