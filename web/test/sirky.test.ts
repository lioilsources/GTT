import { describe, expect, it } from 'vitest';

import { aiPrng, replay } from '../src/minigames/rules';
import { SirkyRules, type SirkyConfig } from '../src/minigames/sirky/rules';

const cfg: SirkyConfig = { start: 15, minStart: 12, maxStart: 25, maxTake: 3, roundsToWin: 5, aiErrorPct: [60, 45, 30, 15, 0] };

describe('sirky rules (specs/minigames/sirky.md)', () => {
  it('starts with the player and 15 matches', () => {
    const r = new SirkyRules();
    const s = r.init(cfg, 42);
    expect(s).toMatchObject({ left: 15, turn: 'player', starter: 'player', round: 1, player: 0, ai: 0, over: false });
    expect(r.legalActions(s).map((a) => ('take' in a ? a.take : 0))).toEqual([1, 2, 3]);
  });

  it('rejects illegal moves', () => {
    const r = new SirkyRules();
    const s = r.init(cfg, 1);
    expect(() => r.apply(s, { by: 'ai', take: 1 })).toThrow();
    expect(() => r.apply(s, { by: 'player', take: 4 })).toThrow();
    expect(() => r.apply(s, { by: 'player', take: 0 })).toThrow();
  });

  it('taking the last match loses the round and the starter alternates', () => {
    const r = new SirkyRules();
    let s = { ...r.init(cfg, 7), left: 2 };
    s = r.apply(s, { by: 'player', take: 1 });
    s = r.apply(s, { by: 'ai', take: 1 });
    expect(s.player).toBe(1);
    expect(s.round).toBe(2);
    expect(s.starter).toBe('ai');
    expect(s.turn).toBe('ai');
    expect(s.left).toBeGreaterThanOrEqual(12);
    expect(s.left).toBeLessThanOrEqual(25);
  });

  it('perfect AI (level 5) never loses a winnable position', () => {
    const r = new SirkyRules();
    const ai = aiPrng(3);
    for (let left = 2; left <= 25; left++) {
      if ((left - 1) % 4 === 0) continue;
      const s = { ...r.init(cfg, 3), left, turn: 'ai' as const };
      const a = r.aiAction(s, 5, ai);
      expect('take' in a && (left - a.take - 1) % 4).toBe(0);
    }
  });

  it('stars follow the opponent round count', () => {
    const r = new SirkyRules();
    const base = r.init(cfg, 1);
    const res = (ai: number, player = 5) => r.result({ ...base, over: true, player, ai })!;
    expect([res(0).stars, res(2).stars, res(3).stars, res(4).stars, res(5, 2).stars]).toEqual([3, 3, 2, 1, 0]);
    expect(res(2).score).toBe(500);
  });

  it('a whole game against itself ends within bounds', () => {
    const r = new SirkyRules();
    const steps = [];
    let s = r.init(cfg, 99);
    const ai = aiPrng(99);
    while (!s.over && steps.length < 500) {
      const a = s.turn === 'player' ? r.legalActions(s)[0]! : r.aiAction(s, 3, ai);
      steps.push({ action: s.turn === 'ai' ? { by: 'ai', level: 3 } : (a as Record<string, unknown>) });
      s = r.apply(s, a);
    }
    expect(s.over).toBe(true);
    const again = replay(new SirkyRules() as never, { config: cfg as never, seed: 99, steps });
    expect(again.states.at(-1)).toEqual(s);
  });
});
