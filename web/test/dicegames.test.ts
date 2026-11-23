import { describe, expect, it } from 'vitest';

import { KostkyRules, catValue, total, type KostkyConfig, type KostkyState } from '../src/minigames/kostky/rules';
import { PraseRules, type PraseConfig, type PraseState } from '../src/minigames/prase/rules';
import { aiPrng } from '../src/minigames/rules';
import { Prng } from '../src/rules/prng';

const kCfg: KostkyConfig = { bonusAt: 63, bonus: 35, aiErrorPct: [40, 25, 12, 5, 0], starMargins: [60, 20] };
const pCfg: PraseConfig = { target: 100, maxRounds: 15, aiHoldAt: [10, 15, 18, 20, 20], aiErrorPct: [35, 20, 10, 5, 0], starMargins: [40, 15] };

const free = (): number[] => Array(13).fill(-1);

describe('kostky categories (specs/minigames/kostky.md)', () => {
  it('values the table', () => {
    expect(catValue(2, [3, 3, 1, 3, 6])).toBe(9);
    expect(catValue(6, [3, 3, 1, 3, 6])).toBe(16);
    expect(catValue(7, [3, 3, 1, 3, 6])).toBe(0);
    expect(catValue(8, [2, 2, 5, 5, 5])).toBe(25);
    expect(catValue(8, [5, 5, 5, 5, 5])).toBe(0);
    expect(catValue(9, [1, 3, 4, 2, 6])).toBe(30);
    expect(catValue(10, [1, 3, 4, 2, 6])).toBe(0);
    expect(catValue(10, [6, 3, 4, 2, 5])).toBe(40);
    expect(catValue(11, [4, 4, 4, 4, 4])).toBe(50);
    expect(catValue(7, [4, 4, 4, 4, 4])).toBe(20);
    expect(catValue(12, [1, 2, 3, 4, 6])).toBe(16);
  });

  it('adds the upper bonus', () => {
    const t = [3, 6, 9, 12, 15, 18, -1, -1, -1, -1, -1, -1, -1];
    expect(total(t, kCfg)).toBe(63 + 35);
    expect(total([...t.slice(0, 5), 12, ...t.slice(6)], kCfg)).toBe(57);
  });
});

describe('kostky rules', () => {
  it('rolls keep the held dice and allow three rolls', () => {
    const r = new KostkyRules();
    let s = r.init(kCfg, 4);
    expect(r.legalActions(s)).toEqual([{ by: 'player', op: 'roll', keep: [] }]);
    s = r.apply(s, { by: 'player', op: 'roll', keep: [] });
    const first = s.dice;
    expect(r.legalActions(s)).toHaveLength(31 + 13);
    s = r.apply(s, { by: 'player', op: 'roll', keep: [0, 2] });
    expect([s.dice[0], s.dice[2]]).toEqual([first[0], first[2]]);
    s = r.apply(s, { by: 'player', op: 'roll', keep: [1] });
    expect(r.legalActions(s).every((a) => a.by !== 'timeout' && a.op === 'score')).toBe(true);
    s = r.apply(s, { by: 'player', op: 'score', cat: 11 });
    expect([s.turn, s.rolls, s.dice, s.round]).toEqual(['ai', 0, [], 1]);
  });

  it('AI keeps a straight run at level 3 and pairs below', () => {
    const r = new KostkyRules();
    expect(r.aiKeep([2, 3, 4, 4, 6], free(), 3)).toEqual([0, 1, 2]);
    expect(r.aiKeep([2, 3, 4, 4, 6], free(), 2)).toEqual([2, 3]);
    expect(r.aiKeep([5, 5, 1, 5, 2], free(), 5)).toEqual([0, 1, 3]);
    expect(r.aiKeep([1, 6, 3, 2, 5], free(), 1)).toEqual([]);
  });

  it('AI scores five of a kind at once and draws r first', () => {
    const r = new KostkyRules();
    const s: KostkyState = { ...r.init(kCfg, 1), turn: 'ai', dice: [6, 6, 6, 6, 6], rolls: 1 };
    const ai = aiPrng(8), ref = aiPrng(8);
    expect(r.aiAction(s, 5, ai)).toEqual({ by: 'ai', op: 'score', cat: 11 });
    ref.nextInt(100);
    expect(ai.state).toBe(ref.state);
    // Poker written: holding all five → score the best free row.
    const t = free();
    t[11] = 50;
    expect(r.aiAction({ ...s, ai: t }, 5, aiPrng(8))).toEqual({ by: 'ai', op: 'score', cat: 5 });
  });

  it('ends after the AI fills its 13th row', () => {
    const r = new KostkyRules();
    let s = r.init(kCfg, 21);
    const ai = aiPrng(21), p = new Prng(2);
    while (!r.result(s)) {
      if (s.turn === 'ai') s = r.apply(s, r.aiAction(s, 4, ai));
      else {
        const l = r.legalActions(s);
        s = r.apply(s, l[p.nextInt(l.length)]!);
      }
    }
    expect(s.round).toBe(14);
    expect(s.ai.every((v) => v >= 0) && s.player.every((v) => v >= 0)).toBe(true);
  });
});

describe('prase rules (specs/minigames/prase.md)', () => {
  const base = (r: PraseRules, o: Partial<PraseState>): PraseState => ({ ...r.init(pCfg, 1), ...o });

  it('a one loses the turn; hold is legal only with points', () => {
    const r = new PraseRules();
    let s = r.init(pCfg, 1);
    expect(r.legalActions(s)).toEqual([{ by: 'player', op: 'roll' }]);
    for (let i = 0; i < 50 && s.turn === 'player'; i++) s = r.apply(s, { by: 'player', op: 'roll' });
    expect([s.die, s.bust, s.turnScore, s.turn]).toEqual([1, true, 0, 'ai']);
  });

  it('banking to target ends the game without passing the turn', () => {
    const r = new PraseRules();
    const s = r.apply(base(r, { player: 95, turnScore: 7 }), { by: 'player', op: 'hold' });
    expect([s.over, s.turn, s.player, s.turnScore]).toEqual([true, 'player', 102, 0]);
    expect(r.result(s)).toEqual({ winner: 'player', stars: 3, score: 102, player: 102, ai: 0 });
  });

  it('the round limit ends the game after the AI turn', () => {
    const r = new PraseRules();
    const s = r.apply(base(r, { turn: 'ai', round: 15, turnScore: 4 }), { by: 'ai', op: 'hold' });
    expect([s.over, s.round]).toEqual([true, 16]);
  });

  it('AI rules: last-turn chase (level ≥ 3), chase near target (level ≥ 4)', () => {
    const r = new PraseRules();
    const last = base(r, { turn: 'ai', round: 15, player: 50, ai: 20, turnScore: 25 });
    expect(r.aiAction(last, 5, aiPrng(0))).toEqual({ by: 'ai', op: 'roll' });
    expect(r.aiAction({ ...last, turnScore: 31 }, 5, aiPrng(0))).toEqual({ by: 'ai', op: 'hold' });
    const near = base(r, { turn: 'ai', round: 5, player: 85, ai: 30, turnScore: 25 });
    expect(r.aiAction(near, 5, aiPrng(0))).toEqual({ by: 'ai', op: 'roll' });
    expect(r.aiAction({ ...near, player: 79 }, 5, aiPrng(0))).toEqual({ by: 'ai', op: 'hold' });
  });
});
