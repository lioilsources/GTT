import { describe, expect, it } from 'vitest';

import { roundNote, yardAim, yardLayout } from '../src/minigames/kulicky/game';
import { KulickyRules, duelResult, type KulickyAction, type KulickyConfig, type KulickyState } from '../src/minigames/kulicky/rules';
import { aiPrng, replay } from '../src/minigames/rules';
import { Prng } from '../src/rules/prng';

const cfg: KulickyConfig = {
  rounds: 5,
  holeR: 25,
  holePoints: 3,
  closerPoints: 1,
  scatter: [30, 40, 50, 60, 70],
  aiScatter: [110, 90, 70, 55, 40],
  starMargins: [6, 3, 1],
};
/** No scatter: the marble lands where it was aimed (the rng is still drawn). */
const exact: KulickyConfig = { ...cfg, scatter: [0, 0, 0, 0, 0], aiScatter: [0, 0, 0, 0, 0] };

const p = (x: number, y: number, level = 1): KulickyAction => ({ by: 'player', x, y, level });
const a = (x: number, y: number, level = 1): KulickyAction => ({ by: 'ai', x, y, level });

function round(px: number, py: number, ax: number, ay: number): KulickyState {
  const r = new KulickyRules();
  const s = r.init(exact, 1);
  return r.apply(r.apply(s, p(px, py)), a(ax, ay));
}

describe('kulicky rules (specs/minigames/kulicky.md)', () => {
  it('starts in round 1 with the player to shoot and empty shots', () => {
    const r = new KulickyRules();
    const s = r.init(cfg, 42);
    expect(s).toEqual({
      round: 1, turn: 'player', playerPts: 0, aiPts: 0,
      playerShot: { x: 0, y: 0, inHole: false }, aiShot: { x: 0, y: 0, inHole: false },
      over: false, rng: new Prng(42).state,
    });
    expect(r.legalActions()).toEqual([]);
    expect(r.result(s)).toBeNull();
  });

  it('scatter draws x then y from the state rng with the side\'s table', () => {
    const r = new KulickyRules();
    const s1 = r.apply(r.init(cfg, 7), p(10, -20, 2));
    const g = new Prng(7);
    const x = 10 + g.nextInt(81) - 40, y = -20 + g.nextInt(81) - 40;
    expect(s1.playerShot).toEqual({ x, y, inHole: x * x + y * y <= 625 });
    expect(s1.rng).toBe(g.state);
    expect(s1.turn).toBe('ai');
    const s2 = r.apply(s1, a(0, 0, 4));
    const ax = g.nextInt(111) - 55, ay = g.nextInt(111) - 55;
    expect(s2.aiShot).toMatchObject({ x: ax, y: ay });
    expect(s2.rng).toBe(g.state);
  });

  it('hole boundary: exactly on the radius is in', () => {
    expect(round(25, 0, 200, 0).playerShot.inHole).toBe(true);
    expect(round(15, 20, 200, 0).playerShot.inHole).toBe(true); // 3-4-5, distance 25
    expect(round(26, 0, 200, 0).playerShot.inHole).toBe(false);
  });

  it('scores a round: holes, closer marble, ties', () => {
    expect(round(0, 0, 100, 0)).toMatchObject({ playerPts: 3, aiPts: 0 });
    expect(round(0, 0, 10, 10)).toMatchObject({ playerPts: 3, aiPts: 3 });
    expect(round(100, 0, 0, -5)).toMatchObject({ playerPts: 0, aiPts: 3 });
    expect(round(40, 0, 0, 50)).toMatchObject({ playerPts: 1, aiPts: 0 });
    expect(round(60, 0, 0, -50)).toMatchObject({ playerPts: 0, aiPts: 1 });
    expect(round(30, 40, -50, 0)).toMatchObject({ playerPts: 0, aiPts: 0 }); // equal distance
    const s = round(0, 0, 100, 0);
    expect(s).toMatchObject({ round: 2, turn: 'player', over: false });
  });

  it('rejects the side not on turn, bad fields and moves after the end', () => {
    const r = new KulickyRules();
    const s = r.init(cfg, 1);
    expect(() => r.apply(s, a(0, 0))).toThrow();
    expect(() => r.apply(s, p(0, 0, 0))).toThrow();
    expect(() => r.apply(s, p(0, 0, 6))).toThrow();
    expect(() => r.apply(s, p(0.5, 0))).toThrow();
    const s1 = r.apply(s, p(0, 0));
    expect(() => r.apply(s1, p(0, 0))).toThrow();
    expect(() => r.apply({ ...s, over: true }, p(0, 0))).toThrow();
    expect(() => r.apply({ ...s, over: true }, { by: 'timeout' })).toThrow();
  });

  it('ends after the last round with round = rounds + 1', () => {
    const r = new KulickyRules();
    let s = r.init(exact, 3);
    for (let i = 0; i < cfg.rounds; i++) s = r.apply(r.apply(s, p(0, 0)), a(200, 0));
    expect(s).toMatchObject({ round: 6, over: true, playerPts: 15, aiPts: 0 });
    expect(r.result(s)).toEqual({ winner: 'player', stars: 3, score: 15, playerPts: 15, aiPts: 0 });
    expect(() => r.apply(s, p(0, 0))).toThrow();
  });

  it('timeout ends the game; the open round does not count', () => {
    const r = new KulickyRules();
    let s = r.apply(r.init(exact, 3), p(0, 0));
    s = r.apply(s, { by: 'timeout' });
    expect(s).toMatchObject({ over: true, playerPts: 0, aiPts: 0, round: 1 });
    expect(r.result(s)).toMatchObject({ winner: 'draw', stars: 0, score: 0 });
  });

  it('stars follow the lead over the rival', () => {
    const res = (pp: number, ap: number) => duelResult(pp, ap, cfg.starMargins);
    expect([[6, 0], [8, 3], [3, 0], [5, 3], [1, 0], [0, 0], [0, 2]].map(([x, y]) => res(x!, y!).stars)).toEqual([3, 2, 2, 1, 1, 0, 0]);
    expect(res(2, 2).winner).toBe('draw');
    expect(res(1, 2)).toEqual({ winner: 'ai', stars: 0, score: 1, playerPts: 1, aiPts: 2 });
  });

  it('aiAction aims at the hole and leaves the ai stream alone', () => {
    const r = new KulickyRules();
    const s = r.init(cfg, 1);
    const ai = aiPrng(1);
    const before = ai.state;
    expect(r.aiAction(s, 4)).toEqual({ by: 'ai', x: 0, y: 0, level: 4 });
    expect(ai.state).toBe(before);
  });

  it('a seeded game replays to the same states', () => {
    const r = new KulickyRules();
    const pol = new Prng(77);
    let s = r.init(cfg, 77);
    const steps: Array<{ action: Record<string, unknown> }> = [];
    while (!s.over) {
      const act: KulickyAction = s.turn === 'player' ? p(pol.nextInt(201) - 100, pol.nextInt(201) - 100, 2) : { by: 'ai', x: 0, y: 0, level: 2 };
      steps.push({ action: (s.turn === 'player' ? act : { by: 'ai', level: 2 }) as Record<string, unknown> });
      s = r.apply(s, act);
    }
    expect(steps).toHaveLength(10);
    const again = replay(new KulickyRules() as never, { config: cfg as never, seed: 77, steps });
    expect(again.states.at(-1)).toEqual(s);
    expect(again.result).toEqual(r.result(s));
  });
});

describe('kulicky UI helpers', () => {
  it('a straight swipe up aims along the centre line from the yard edge', () => {
    const lay = yardLayout(cfg);
    expect(yardAim(lay, 0, lay.aimOriginY / 2, 2)).toEqual({ x: 0, y: 0 });
    const g = yardAim(lay, 10.3, -100.4, 1.6);
    expect(Number.isInteger(g.x) && Number.isInteger(g.y)).toBe(true);
  });

  it('round note compares the points each side gained', () => {
    expect(roundNote({ playerPts: 0, aiPts: 0 }, { playerPts: 3, aiPts: 0 })).toBe('roundWon');
    expect(roundNote({ playerPts: 0, aiPts: 0 }, { playerPts: 0, aiPts: 1 })).toBe('roundLost');
    expect(roundNote({ playerPts: 0, aiPts: 0 }, { playerPts: 3, aiPts: 3 })).toBe('draw');
  });
});
