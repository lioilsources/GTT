import { describe, expect, it } from 'vitest';

import {
  DesetitisicRules,
  scoreSelection,
  selections,
  type DesetitisicConfig,
  type DesetitisicState,
} from '../src/minigames/desetitisic/rules';
import { aiPrng, replay } from '../src/minigames/rules';

const cfg: DesetitisicConfig = {
  target: 5000,
  maxRounds: 10,
  aiBankAt: [250, 300, 350, 400, 450],
  aiErrorPct: [40, 25, 10, 5, 0],
  starMargins: [1500, 500],
};

/** Finds a seed whose first roll of `n` dice satisfies `pred` (rolls come from the state's rng). */
function stateWithRoll(r: DesetitisicRules, pred: (s: DesetitisicState) => boolean, base: Partial<DesetitisicState> = {}) {
  for (let seed = 1; seed < 100000; seed++) {
    const s0 = { ...r.init(cfg, seed), ...base };
    const s = r.apply(s0, { by: s0.turn, op: 'roll' });
    if (pred(s)) return { s0, s };
  }
  throw new Error('no seed found');
}

describe('desetitisic scoring (specs/minigames/desetitisic.md)', () => {
  it('scores singles, triples and the straight', () => {
    expect(scoreSelection([1])).toBe(100);
    expect(scoreSelection([5])).toBe(50);
    expect(scoreSelection([1, 5])).toBe(150);
    expect(scoreSelection([2, 2, 2])).toBe(200);
    expect(scoreSelection([1, 1, 1])).toBe(1000);
    expect(scoreSelection([5, 5, 5, 5])).toBe(550);
    expect(scoreSelection([1, 2, 3, 4, 5, 6])).toBe(1500);
    expect(scoreSelection([6, 5, 4, 3, 2, 1])).toBe(1500);
  });

  it('uses the best decomposition (spec edge cases)', () => {
    expect(scoreSelection([1, 1, 1, 1])).toBe(1100);
    expect(scoreSelection([2, 2, 2, 2, 2, 2])).toBe(400);
    expect(scoreSelection([1, 1, 1, 1, 1, 1])).toBe(2000);
    expect(scoreSelection([3, 3, 3, 4, 4, 4])).toBe(700);
  });

  it('rejects selections with a die outside every combination', () => {
    expect(scoreSelection([])).toBeNull();
    expect(scoreSelection([2])).toBeNull();
    expect(scoreSelection([1, 2])).toBeNull();
    expect(scoreSelection([2, 2, 2, 2])).toBeNull();
    expect(scoreSelection([1, 2, 3, 4, 5])).toBeNull();
    expect(scoreSelection([2, 3, 4, 6, 6])).toBeNull();
  });

  it('a roll of 2-3-4-6-6 has no legal selection, ordered by bitmask otherwise', () => {
    expect(selections([2, 3, 4, 6, 6])).toEqual([]);
    expect(selections([1, 2, 5])).toEqual([[0], [2], [0, 2]]);
  });
});

describe('desetitisic rules', () => {
  it('starts with the player rolling six dice', () => {
    const r = new DesetitisicRules();
    const s = r.init(cfg, 42);
    expect(s).toMatchObject({ player: 0, ai: 0, turn: 'player', phase: 'roll', roll: [], dice: 6, turnScore: 0, round: 1, lastBust: false, over: false });
    expect(r.legalActions(s)).toEqual([{ by: 'player', op: 'roll' }]);
  });

  it('rejects illegal moves', () => {
    const r = new DesetitisicRules();
    const s = r.init(cfg, 1);
    expect(() => r.apply(s, { by: 'ai', op: 'roll' })).toThrow();
    expect(() => r.apply(s, { by: 'player', op: 'bank' })).toThrow();
    expect(() => r.apply(s, { by: 'player', op: 'keep', dice: [0] })).toThrow();
    const k = { ...s, phase: 'keep' as const, roll: [1, 2, 3, 3, 5, 6] };
    expect(() => r.apply(k, { by: 'player', op: 'keep', dice: [1] })).toThrow();
    expect(() => r.apply(k, { by: 'player', op: 'keep', dice: [4, 0] })).toThrow();
    expect(() => r.apply(k, { by: 'player', op: 'keep', dice: [0, 0] })).toThrow();
    expect(() => r.apply(k, { by: 'player', op: 'keep', dice: [] })).toThrow();
    expect(() => r.apply(k, { by: 'player', op: 'roll' })).toThrow();
  });

  it('keep adds the value and decides; a bust loses the turn', () => {
    const r = new DesetitisicRules();
    let s: DesetitisicState = { ...r.init(cfg, 1), phase: 'keep', roll: [1, 2, 3, 3, 5, 6], turnScore: 300 };
    s = r.apply(s, { by: 'player', op: 'keep', dice: [0, 4] });
    expect(s).toMatchObject({ turnScore: 450, dice: 4, phase: 'decide' });
    expect(r.legalActions(s)).toEqual([{ by: 'player', op: 'roll' }, { by: 'player', op: 'bank' }]);

    const { s: b } = stateWithRoll(r, (x) => x.lastBust, { dice: 2, phase: 'decide', turnScore: 800, player: 100 });
    expect(b).toMatchObject({ turn: 'ai', phase: 'roll', turnScore: 0, dice: 6, roll: [], lastBust: true, player: 100, round: 1 });
  });

  it('hot dice: keeping every die resets to six', () => {
    const r = new DesetitisicRules();
    const s = r.apply({ ...r.init(cfg, 1), phase: 'keep', roll: [1, 5], dice: 2 }, { by: 'player', op: 'keep', dice: [0, 1] });
    expect(s).toMatchObject({ dice: 6, turnScore: 150, phase: 'decide' });
    const st = r.apply({ ...r.init(cfg, 1), phase: 'keep', roll: [4, 2, 6, 1, 3, 5] }, { by: 'player', op: 'keep', dice: [0, 1, 2, 3, 4, 5] });
    expect(st).toMatchObject({ dice: 6, turnScore: 1500 });
  });

  it('bank adds the turn score and passes the turn; the round counts after the AI', () => {
    const r = new DesetitisicRules();
    let s: DesetitisicState = { ...r.init(cfg, 1), phase: 'decide', turnScore: 450, dice: 3, roll: [2, 3, 4] };
    s = r.apply(s, { by: 'player', op: 'bank' });
    expect(s).toMatchObject({ player: 450, turn: 'ai', phase: 'roll', turnScore: 0, dice: 6, roll: [], round: 1, over: false });
    s = r.apply({ ...s, phase: 'decide', turnScore: 300 }, { by: 'ai', op: 'bank' });
    expect(s).toMatchObject({ ai: 300, turn: 'player', round: 2, over: false });
  });

  it('reaching the target ends the game at once', () => {
    const r = new DesetitisicRules();
    const s = r.apply({ ...r.init(cfg, 1), player: 4800, phase: 'decide', turnScore: 200 }, { by: 'player', op: 'bank' });
    expect(s).toMatchObject({ player: 5000, over: true, phase: 'over' });
    expect(r.legalActions(s)).toEqual([]);
    expect(r.result(s)).toEqual({ winner: 'player', stars: 3, score: 5000, player: 5000, ai: 0 });
  });

  it('the game ends after the AI turn of the last round', () => {
    const r = new DesetitisicRules();
    const last = { ...r.init(cfg, 1), round: 10, turn: 'ai' as const, phase: 'decide' as const, turnScore: 100, player: 900, ai: 700 };
    const s = r.apply(last, { by: 'ai', op: 'bank' });
    expect(s).toMatchObject({ round: 11, over: true, phase: 'over', ai: 800 });
    expect(r.result(s)).toMatchObject({ winner: 'player', stars: 1, score: 900 });
    const p = r.apply({ ...last, turn: 'player' }, { by: 'player', op: 'bank' });
    expect(p.over).toBe(false);
  });

  it('stars follow the lead; equal totals draw', () => {
    const r = new DesetitisicRules();
    const b = { ...r.init(cfg, 1), over: true, phase: 'over' as const };
    const stars = (player: number, ai: number) => r.result({ ...b, player, ai })!.stars;
    expect([stars(3000, 1500), stars(3000, 1501), stars(3000, 2500), stars(3000, 2550), stars(2000, 2500)]).toEqual([3, 2, 2, 1, 0]);
    expect(r.result({ ...b, player: 1000, ai: 1000 })!.winner).toBe('draw');
  });

  it('timeout ends the game', () => {
    const r = new DesetitisicRules();
    const s = r.apply({ ...r.init(cfg, 1), player: 300 }, { by: 'timeout' });
    expect(s).toMatchObject({ over: true, phase: 'over' });
    expect(r.result(s)!.winner).toBe('player');
  });

  it('AI bank rule', () => {
    const r = new DesetitisicRules();
    const ai = aiPrng(1);
    const d = (x: Partial<DesetitisicState>) =>
      (r.aiAction({ ...r.init(cfg, 1), turn: 'ai', phase: 'decide', ...x }, 3, ai) as { op: string }).op;
    expect(d({ turnScore: 350, dice: 3 })).toBe('bank');
    expect(d({ turnScore: 300, dice: 3 })).toBe('roll');
    expect(d({ turnScore: 200, dice: 2 })).toBe('bank');
    expect(d({ turnScore: 150, dice: 1 })).toBe('roll');
    expect(d({ turnScore: 1500, dice: 6 })).toBe('roll');
    expect(d({ turnScore: 1500, dice: 6, ai: 3600 })).toBe('bank');
    expect(d({ turnScore: 50, dice: 5, ai: 4950 })).toBe('bank');
  });

  it('perfect AI (level 5) keeps the best value with the fewest dice', () => {
    const r = new DesetitisicRules();
    const ai = aiPrng(9);
    const k = (roll: number[]) => r.aiAction({ ...r.init(cfg, 1), turn: 'ai', phase: 'keep', roll, dice: roll.length }, 5, ai);
    expect(k([1, 1, 1, 1, 2, 3])).toEqual({ by: 'ai', op: 'keep', dice: [0, 1, 2, 3] });
    expect(k([3, 4, 1, 2, 6, 5])).toEqual({ by: 'ai', op: 'keep', dice: [0, 1, 2, 3, 4, 5] });
    expect(k([5, 5, 5, 5, 2, 2])).toEqual({ by: 'ai', op: 'keep', dice: [0, 1, 2, 3] });
  });

  it('a whole game replays to the same states', () => {
    const r = new DesetitisicRules();
    const steps = [];
    let s = r.init(cfg, 99);
    const ai = aiPrng(99);
    while (!s.over && steps.length < 2000) {
      const a = s.turn === 'player'
        ? s.phase === 'decide' && s.turnScore >= 300 ? r.legalActions(s)[1]! : r.legalActions(s).at(-1)!
        : r.aiAction(s, 3, ai);
      steps.push({ action: s.turn === 'ai' ? { by: 'ai', level: 3 } : (a as Record<string, unknown>) });
      s = r.apply(s, a);
    }
    expect(s.over).toBe(true);
    const again = replay(new DesetitisicRules() as never, { config: cfg as never, seed: 99, steps });
    expect(again.states.at(-1)).toEqual(s);
  });
});
