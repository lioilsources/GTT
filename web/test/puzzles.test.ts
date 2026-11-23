import { describe, expect, it } from 'vitest';

import { PosuvneRules, SOLVED, isSolved, neighbours } from '../src/minigames/posuvne/rules';
import { KvizRules, type KvizConfig } from '../src/minigames/kviz/rules';

const sm = [10, 20, 35, 60, 100];

describe('posuvne rules (specs/minigames/posuvne.md)', () => {
  it('neighbours are up, down, left, right', () => {
    expect(neighbours(5)).toEqual([1, 9, 4, 6]);
    expect(neighbours(15)).toEqual([11, 14]);
  });

  it('the shuffle is a permutation, never solved, par from the level', () => {
    const r = new PosuvneRules();
    for (let lv = 1; lv <= 5; lv++) {
      const s = r.init({ shuffleMoves: sm, level: lv }, 1234 + lv);
      expect([...s.tiles].sort((a, b) => a - b)).toEqual([...SOLVED].sort((a, b) => a - b));
      expect(isSolved(s.tiles)).toBe(false);
      expect(s.par === sm[lv - 1] || s.par === sm[lv - 1]! + 1).toBe(true);
    }
  });

  it('only tiles next to the gap move; solving ends the game', () => {
    const r = new PosuvneRules();
    const s = { ...r.init({ shuffleMoves: sm, level: 1 }, 1), tiles: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 0, 15], par: 1 };
    expect(r.legalActions(s)).toEqual([{ by: 'player', tile: 11 }, { by: 'player', tile: 14 }, { by: 'player', tile: 15 }]);
    expect(() => r.apply(s, { by: 'player', tile: 1 })).toThrow();
    const n = r.apply(s, { by: 'player', tile: 15 });
    expect(n).toMatchObject({ over: true, solved: true, moves: 1 });
    expect(r.result(n)).toEqual({ winner: 'player', stars: 3, score: 1000, moves: 1, par: 1 });
  });

  it('timeout leaves it unsolved', () => {
    const r = new PosuvneRules();
    const s = r.apply(r.init({ shuffleMoves: sm, level: 2 }, 9), { by: 'timeout' });
    expect(r.result(s)).toMatchObject({ winner: 'ai', stars: 0, score: 0 });
  });
});

const quiz: KvizConfig = { bank: [0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3], rounds: 10, starCorrect: [9, 7, 5] };

describe('kviz rules (specs/minigames/kviz.md)', () => {
  it('draws distinct questions and option permutations', () => {
    const r = new KvizRules();
    const s = r.init(quiz, 77);
    expect(s.order).toHaveLength(10);
    expect(new Set(s.order).size).toBe(10);
    for (const p of s.perms) expect([...p].sort()).toEqual([0, 1, 2, 3]);
  });

  it('counts right answers, -1 is wrong, stars by thresholds', () => {
    const r = new KvizRules();
    let s = r.init(quiz, 5);
    for (let k = 0; k < 10; k++) {
      const right = [0, 1, 2, 3].find((d) => r.isRight(s, d))!;
      s = r.apply(s, { by: 'player', answer: k < 7 ? right : -1 });
    }
    expect(s.over).toBe(true);
    expect(r.result(s)).toEqual({ winner: 'player', stars: 2, score: 700, correct: 7, rounds: 10 });
  });

  it('a short bank scales the thresholds', () => {
    const r = new KvizRules();
    let s = r.init({ ...quiz, bank: [0, 1, 2, 3, 0] }, 5);
    expect(s.order).toHaveLength(5);
    // thresholds 9*5/10 = 4, 7*5/10 = 3, 5*5/10 = 2
    for (let k = 0; k < 5; k++) {
      const right = [0, 1, 2, 3].find((d) => r.isRight(s, d))!;
      s = r.apply(s, { by: 'player', answer: k < 3 ? right : (right + 1) % 4 });
    }
    expect(r.result(s)).toMatchObject({ stars: 2, correct: 3, rounds: 5 });
  });
});
