import { describe, expect, it } from 'vitest';

import { pavementLayout, tossAim } from '../src/minigames/cara/game';
import { CaraRules, type CaraAction, type CaraConfig, type CaraState } from '../src/minigames/cara/rules';
import { aiPrng, replay } from '../src/minigames/rules';
import { Prng } from '../src/rules/prng';

const cfg: CaraConfig = {
  rounds: 7,
  linePoints: 3,
  roundPoints: 1,
  scatter: [20, 28, 36, 44, 52],
  aiScatter: [90, 70, 55, 40, 28],
  aiAim: [90, 70, 55, 40, 28],
  starMargins: [5, 3, 1],
};
const exact: CaraConfig = { ...cfg, scatter: [0, 0, 0, 0, 0], aiScatter: [0, 0, 0, 0, 0] };

const p = (y: number, level = 1): CaraAction => ({ by: 'player', y, level });
const a = (y: number, level = 1): CaraAction => ({ by: 'ai', y, level });

function round(py: number, ay: number): CaraState {
  const r = new CaraRules();
  return r.apply(r.apply(r.init(exact, 1), p(py)), a(ay));
}

describe('cara rules (specs/minigames/cara.md)', () => {
  it('starts in round 1 with the player to toss', () => {
    const r = new CaraRules();
    const s = r.init(cfg, 42);
    expect(s).toEqual({
      round: 1, turn: 'player', playerPts: 0, aiPts: 0,
      playerCoin: { y: 0, burnt: false }, aiCoin: { y: 0, burnt: false },
      over: false, rng: new Prng(42).state,
    });
    expect(r.legalActions()).toEqual([]);
    expect(r.result(s)).toBeNull();
  });

  it('scatter is one draw from the state rng', () => {
    const r = new CaraRules();
    const s1 = r.apply(r.init(cfg, 9), p(-30, 3));
    const g = new Prng(9);
    const y = -30 + g.nextInt(73) - 36;
    expect(s1.playerCoin).toEqual({ y, burnt: y > 0 });
    expect(s1.rng).toBe(g.state);
  });

  it('scores a round: line, closer unburnt coin, burns and ties', () => {
    expect(round(0, -10)).toMatchObject({ playerPts: 3, aiPts: 0 });
    expect(round(0, 0)).toMatchObject({ playerPts: 3, aiPts: 3 });
    expect(round(-10, 0)).toMatchObject({ playerPts: 0, aiPts: 3 });
    expect(round(-5, -20)).toMatchObject({ playerPts: 1, aiPts: 0 });
    expect(round(-30, -2)).toMatchObject({ playerPts: 0, aiPts: 1 });
    expect(round(3, -80)).toMatchObject({ playerPts: 0, aiPts: 1 }); // player burnt
    expect(round(-80, 1)).toMatchObject({ playerPts: 1, aiPts: 0 }); // rival burnt
    expect(round(5, 2)).toMatchObject({ playerPts: 0, aiPts: 0 }); // both burnt
    expect(round(-15, -15)).toMatchObject({ playerPts: 0, aiPts: 0 }); // tie
    expect(round(1, 0).playerCoin.burnt).toBe(true);
    expect(round(0, 1).playerCoin.burnt).toBe(false);
    expect(round(-5, -20)).toMatchObject({ round: 2, turn: 'player', over: false });
  });

  it('rejects the side not on turn, bad fields and moves after the end', () => {
    const r = new CaraRules();
    const s = r.init(cfg, 1);
    expect(() => r.apply(s, a(0))).toThrow();
    expect(() => r.apply(s, p(0, 0))).toThrow();
    expect(() => r.apply(s, p(0, 6))).toThrow();
    expect(() => r.apply(s, p(1.5))).toThrow();
    expect(() => r.apply(r.apply(s, p(0)), p(0))).toThrow();
    expect(() => r.apply({ ...s, over: true }, p(0))).toThrow();
  });

  it('ends after seven rounds; stars by the lead', () => {
    const r = new CaraRules();
    let s = r.init(exact, 3);
    for (let i = 0; i < cfg.rounds; i++) s = r.apply(r.apply(s, p(-5)), a(-40));
    expect(s).toMatchObject({ round: 8, over: true, playerPts: 7, aiPts: 0 });
    expect(r.result(s)).toEqual({ winner: 'player', stars: 3, score: 7, playerPts: 7, aiPts: 0 });
    const res = (pp: number, ap: number) => r.result({ ...s, playerPts: pp, aiPts: ap })!;
    expect([[5, 0], [4, 0], [3, 0], [2, 0], [1, 0], [0, 0], [0, 1]].map(([x, y]) => res(x!, y!).stars)).toEqual([3, 2, 2, 1, 1, 0, 0]);
    expect(res(2, 2).winner).toBe('draw');
    expect(res(0, 1).winner).toBe('ai');
  });

  it('timeout ends the game', () => {
    const r = new CaraRules();
    const s = r.apply(r.apply(r.init(exact, 3), p(0)), { by: 'timeout' });
    expect(s).toMatchObject({ over: true, playerPts: 0 });
    expect(() => r.apply(s, { by: 'timeout' })).toThrow();
  });

  it('aiAction aims aiAim short of the line without the ai stream', () => {
    const r = new CaraRules();
    const s = r.init(cfg, 1);
    const ai = aiPrng(1);
    const before = ai.state;
    expect(r.aiAction(s, 1)).toEqual({ by: 'ai', y: -90, level: 1 });
    expect(r.aiAction(s, 5)).toEqual({ by: 'ai', y: -28, level: 5 });
    expect(ai.state).toBe(before);
  });

  it('a seeded game replays to the same states', () => {
    const r = new CaraRules();
    const pol = new Prng(5);
    let s = r.init(cfg, 5);
    const steps: Array<{ action: Record<string, unknown> }> = [];
    while (!s.over) {
      if (s.turn === 'player') {
        const act = p(-pol.nextInt(60), 1 + pol.nextInt(5));
        steps.push({ action: act as Record<string, unknown> });
        s = r.apply(s, act);
      } else {
        steps.push({ action: { by: 'ai', level: 3 } });
        s = r.apply(s, r.aiAction(s, 3));
      }
    }
    const again = replay(new CaraRules() as never, { config: cfg as never, seed: 5, steps });
    expect(again.states.at(-1)).toEqual(s);
    expect(again.result).toEqual(r.result(s));
  });
});

describe('cara UI helpers', () => {
  it('a longer swipe up aims further; a swipe to the line aims at 0', () => {
    const lay = pavementLayout(cfg);
    expect(tossAim(lay, lay.aimOriginY / 2, 2)).toBe(0);
    expect(tossAim(lay, -10, 1.4)).toBeLessThan(tossAim(lay, -100, 1.4));
    expect(Number.isInteger(tossAim(lay, -33.3, 1.4))).toBe(true);
  });
});
