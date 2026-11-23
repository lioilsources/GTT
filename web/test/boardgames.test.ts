import { describe, expect, it } from 'vitest';

import { Prng } from '../src/rules/prng';
import { aiPrng } from '../src/minigames/rules';
import { PiskvorkyRules, attack, candidates, type PiskvorkyConfig } from '../src/minigames/piskvorky/rules';
import { CtyriRules, WINDOWS, type CtyriConfig } from '../src/minigames/ctyri/rules';
import { ADJ, MlynRules, type MlynConfig, type MlynState } from '../src/minigames/mlyn/rules';
import { ReversiRules, WEIGHTS, START_BOARD, type ReversiConfig } from '../src/minigames/reversi/rules';
import { LodeRules, placeFleet, targetCandidates, type LodeConfig } from '../src/minigames/lode/rules';

const pisk: PiskvorkyConfig = { size: 15, aiErrorPct: [40, 25, 12, 5, 0], defensePct: [50, 70, 90, 100, 110], fastMoves: 15 };

function boardWith(n: number, marks: Record<number, string>): string {
  return Array.from({ length: n }, (_, i) => marks[i] ?? '.').join('');
}

describe('piskvorky rules (specs/minigames/piskvorky.md)', () => {
  it('empty board: the AI candidate is the centre', () => {
    expect(candidates('.'.repeat(225), 15)).toEqual([7 * 15 + 7]);
  });

  it('candidates are within Chebyshev distance 2 of a mark', () => {
    const c = candidates(boardWith(225, { 0: 'x' }), 15);
    expect(c).toEqual([1, 2, 15, 16, 17, 30, 31, 32]);
  });

  it('five in a row wins, six too', () => {
    const r = new PiskvorkyRules();
    let s = r.init(pisk, 1);
    s = { ...s, board: boardWith(225, { 0: 'x', 1: 'x', 2: 'x', 3: 'x', 5: 'x' }) };
    const n = r.apply(s, { by: 'player', cell: 4 });
    expect(n).toMatchObject({ over: true, winner: 'player', moves: 1 });
    expect(r.result(n)).toEqual({ winner: 'player', stars: 3, score: (225 - 6) * 10, moves: 1 });
  });

  it('attack scores open and closed runs by the table', () => {
    // x x _ on an empty row, both ends open: L = 3, E = 2 horizontally; 1 / 0 runs elsewhere.
    const b = boardWith(225, { 100: 'x', 101: 'x' });
    expect(attack(b, 15, 102, 'x')).toBe(1000 + 10 + 10 + 10);
    // At the edge the run has one open end.
    const e = boardWith(225, { 0: 'x', 1: 'x' });
    expect(attack(e, 15, 2, 'x')).toBe(100 + 1 + 1 + 1);
  });

  it('defence weight decides between winning and blocking (spec formula as written)', () => {
    const r = new PiskvorkyRules();
    let s = r.init({ ...pisk, aiErrorPct: [0, 0, 0, 0, 0] }, 1);
    s = { ...s, turn: 'ai', board: boardWith(225, { 30: 'o', 31: 'o', 32: 'o', 33: 'o', 60: 'x', 61: 'x', 62: 'x', 63: 'x' }) };
    // def 90 %: completing the own five (cell 34) scores highest.
    expect(r.aiAction(s, 3, aiPrng(1))).toEqual({ by: 'ai', cell: 34 });
    // def 110 %: blocking the player's five (cell 64) outweighs it.
    expect(r.aiAction(s, 5, aiPrng(1))).toEqual({ by: 'ai', cell: 64 });
  });

  it('timeout is a draw with no stars', () => {
    const r = new PiskvorkyRules();
    const s = r.apply(r.init(pisk, 1), { by: 'timeout' });
    expect(r.result(s)).toEqual({ winner: 'draw', stars: 0, score: 0, moves: 0 });
  });
});

const c4: CtyriConfig = { aiDepth: [1, 2, 3, 5, 7], aiErrorPct: [35, 20, 10, 5, 0], fastMoves: 12 };

describe('ctyri rules (specs/minigames/ctyri.md)', () => {
  it('has 69 windows', () => expect(WINDOWS.length).toBe(69));

  it('tokens fall to the lowest empty cell; full columns are not legal', () => {
    const r = new CtyriRules();
    let s = r.init(c4, 1);
    s = r.apply(s, { by: 'player', col: 3 });
    expect(s.board[38]).toBe('x');
    expect(s.turn).toBe('ai');
    s = r.apply(s, { by: 'ai', col: 3 });
    expect(s.board[31]).toBe('o');
    const full = { ...s, board: 'x' + '.'.repeat(41) };
    expect(r.legalActions(full).map((a) => ('col' in a ? a.col : -1))).toEqual([1, 2, 3, 4, 5, 6]);
  });

  it('a vertical four wins', () => {
    const r = new CtyriRules();
    let s = r.init(c4, 1);
    for (let k = 0; k < 3; k++) {
      s = r.apply(s, { by: 'player', col: 0 });
      s = r.apply(s, { by: 'ai', col: 1 });
    }
    s = r.apply(s, { by: 'player', col: 0 });
    expect(s).toMatchObject({ over: true, winner: 'player', moves: 4 });
    expect(r.result(s)).toEqual({ winner: 'player', stars: 3, score: (42 - 7) * 20, moves: 4 });
  });

  it('the AI blocks an immediate threat at depth 2 and wins at depth 1', () => {
    const r = new CtyriRules();
    let s = r.init(c4, 1);
    s = r.apply(s, { by: 'player', col: 0 });
    s = r.apply(s, { by: 'ai', col: 6 });
    s = r.apply(s, { by: 'player', col: 1 });
    s = r.apply(s, { by: 'ai', col: 6 });
    s = r.apply(s, { by: 'player', col: 2 });
    // The player threatens column 3 (x x x on the bottom row).
    expect(r.aiAction(s, 5, aiPrng(1))).toEqual({ by: 'ai', col: 3 });
  });
});

const mill: MlynConfig = { aiDepth: [1, 2, 2, 3, 4], aiErrorPct: [35, 20, 10, 5, 0], quietLimit: 50, flying: true, star3Pieces: 6 };

describe('mlyn rules (specs/minigames/mlyn.md)', () => {
  it('adjacency follows the mills', () => {
    expect(ADJ[0]).toEqual([1, 9]);
    expect(ADJ[4]).toEqual([1, 3, 5, 7]);
    expect(ADJ[10]).toEqual([3, 9, 11, 18]);
  });

  it('placing starts with 24 placements and closing a mill requires a removal', () => {
    const r = new MlynRules();
    let s = r.init(mill, 1);
    expect(r.legalActions(s)).toHaveLength(24);
    s = { ...s, board: 'ww.' + '.'.repeat(6) + 'b' + '.'.repeat(14), hand: { player: 7, ai: 8 } };
    const closing = r.legalActions(s).filter((a) => 'to' in a && a.to === 2);
    expect(closing).toEqual([{ by: 'player', from: -1, to: 2, remove: 9 }]);
    expect(() => r.apply(s, { by: 'player', from: -1, to: 2, remove: -1 })).toThrow();
    const n = r.apply(s, closing[0]!);
    expect(n.board.slice(0, 3)).toBe('www');
    expect(n.board[9]).toBe('.');
    expect(n.hand.player).toBe(6);
  });

  it('only stones outside mills can be taken unless all are in mills', () => {
    const r = new MlynRules();
    const base = r.init(mill, 1);
    // AI mill 21-22-23 and a loose stone on 12; player closes 0-1-2.
    const s: MlynState = { ...base, board: 'ww' + '.'.repeat(10) + 'b' + '.'.repeat(8) + 'bbb', hand: { player: 5, ai: 5 } };
    expect(r.legalActions(s).filter((a) => 'to' in a && a.to === 2).map((a) => ('remove' in a ? a.remove : 0))).toEqual([12]);
    const all: MlynState = { ...s, board: 'ww' + '.'.repeat(19) + 'bbb' };
    expect(r.legalActions(all).filter((a) => 'to' in a && a.to === 2).map((a) => ('remove' in a ? a.remove : 0))).toEqual([21, 22, 23]);
  });

  it('three stones fly, under three loses', () => {
    const r = new MlynRules();
    const base = r.init(mill, 1);
    const s: MlynState = { ...base, board: 'w.w' + '.'.repeat(6) + 'w' + '.'.repeat(11) + 'bbb', hand: { player: 0, ai: 0 }, turn: 'ai' };
    const flights = r.legalActions(s).filter((a) => 'from' in a && a.from === 21);
    expect(flights.length).toBeGreaterThan(2);
    const noFly = new MlynRules();
    noFly.init({ ...mill, flying: false }, 1);
    expect(noFly.legalActions(s).filter((a) => 'from' in a && a.from === 21).map((a) => ('to' in a ? a.to : 0))).toEqual([]);
    // Player closes 0-1-2 by moving 9 -> ... not adjacent; instead fly: the player has 3 stones too.
    const n = r.apply({ ...s, turn: 'player' }, { by: 'player', from: 9, to: 1, remove: 21 });
    expect(n).toMatchObject({ over: true, winner: 'player' });
    expect(r.result(n)).toMatchObject({ winner: 'player', stars: 2, byPieces: false });
  });

  it('timeout counts board and hand', () => {
    const r = new MlynRules();
    const s = r.apply({ ...r.init(mill, 1), board: 'w' + '.'.repeat(23), hand: { player: 8, ai: 9 } }, { by: 'timeout' });
    expect(r.result(s)).toEqual({ winner: 'draw', stars: 0, score: 0, byPieces: true, plies: 0 });
  });
});

const rev: ReversiConfig = { aiDepth: [1, 2, 3, 4, 5], aiErrorPct: [35, 20, 10, 5, 0], star3Margin: 20 };

describe('reversi rules (specs/minigames/reversi.md)', () => {
  it('weights are symmetric', () => {
    for (let r = 0; r < 8; r++) for (let c = 0; c < 8; c++) {
      expect(WEIGHTS[r * 8 + c]).toBe(WEIGHTS[(7 - r) * 8 + c]);
      expect(WEIGHTS[r * 8 + c]).toBe(WEIGHTS[r * 8 + 7 - c]);
    }
  });

  it('starts with four legal moves for the player and flips', () => {
    const r = new ReversiRules();
    const s = r.init(rev, 1);
    expect(s.board).toBe(START_BOARD);
    expect(r.legalActions(s).map((a) => ('cell' in a ? a.cell : 0))).toEqual([19, 26, 37, 44]);
    const n = r.apply(s, { by: 'player', cell: 19 });
    expect(n.board[27]).toBe('x');
    expect(n).toMatchObject({ turn: 'ai', plies: 1, passes: 0 });
  });

  it('a side without a move may only pass; two passes end the game', () => {
    const r = new ReversiRules();
    const base = r.init(rev, 1);
    // x o . : player plays 2, then the AI has no disc and the game ends.
    const s = { ...base, board: 'xo' + '.'.repeat(62) };
    const n = r.apply(s, { by: 'player', cell: 2 });
    expect(n).toMatchObject({ over: true, winner: 'player' });
    // No legal move for the player: only pass.
    const p = { ...base, board: 'o.x' + '.'.repeat(61) };
    expect(r.legalActions(p)).toEqual([{ by: 'player', cell: -1 }]);
    const q = r.apply(p, { by: 'player', cell: -1 });
    expect(q).toMatchObject({ passes: 1, turn: 'ai', over: false });
  });
});

const fleet: LodeConfig = { fleet: [5, 4, 3, 3, 2], shuffles: 3, aiErrorPct: [50, 30, 15, 5, 0], fastShots: 45, okShots: 70 };

describe('lode rules (specs/minigames/lode.md)', () => {
  it('fleets never touch, even diagonally', () => {
    for (let seed = 1; seed < 40; seed++) {
      const ships = placeFleet(fleet.fleet, new Prng(seed));
      expect(ships.map((s) => s.length)).toEqual(fleet.fleet);
      const owner = new Map<number, number>();
      ships.forEach((s, k) => s.forEach((c) => owner.set(c, k)));
      for (const [c, k] of owner) {
        const x = c % 10, y = Math.floor(c / 10);
        for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
          const nx = x + dx, ny = y + dy;
          if (nx < 0 || nx > 9 || ny < 0 || ny > 9) continue;
          const o = owner.get(ny * 10 + nx);
          if (o !== undefined) expect(o).toBe(k);
        }
      }
    }
  });

  it('shuffle only before the first shot; a hit shoots again', () => {
    const r = new LodeRules();
    let s = r.init(fleet, 3);
    expect(r.legalActions(s)[0]).toEqual({ by: 'player', op: 'shuffle' });
    const re = r.apply(s, { by: 'player', op: 'shuffle' });
    expect(re.shuffles).toBe(2);
    expect(re.aShips).toEqual(s.aShips);
    const target = s.aShips[0]![0]!;
    s = r.apply(s, { by: 'player', op: 'shot', cell: target });
    expect(s).toMatchObject({ turn: 'player', shots: 1 });
    expect(r.canShuffle(s)).toBe(false);
  });

  it('targets extend a line of hits, otherwise orthogonal neighbours', () => {
    const ships = [[22, 23, 24, 25]];
    const shots1 = '.'.repeat(23) + 'x' + '.'.repeat(76);
    expect(targetCandidates(ships, shots1)).toEqual([13, 22, 24, 33]);
    const shots2 = '.'.repeat(23) + 'xx' + '.'.repeat(75);
    expect(targetCandidates(ships, shots2)).toEqual([22, 25]);
  });
});
