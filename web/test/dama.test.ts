import { describe, expect, it } from 'vitest';

import { DamaRules, type DamaConfig, type DamaState } from '../src/minigames/dama/rules';
import { aiPrng, replay } from '../src/minigames/rules';

const cfg: DamaConfig = { aiDepth: [1, 2, 3, 4, 5], aiErrorPct: [35, 20, 10, 5, 0], quietLimit: 50, fastPlies: 80 };

/** Board string with only the given pieces. */
function board(pieces: Record<number, string>): string {
  return Array.from({ length: 32 }, (_, i) => pieces[i] ?? '.').join('');
}

function setup(pieces: Record<number, string>, turn: 'player' | 'ai' = 'player', c: DamaConfig = cfg): { r: DamaRules; s: DamaState } {
  const r = new DamaRules();
  const s = { ...r.init(c, 1), board: board(pieces), turn };
  return { r, s };
}

const paths = (r: DamaRules, s: DamaState): number[][] => r.legalActions(s).map((a) => ('path' in a ? a.path : []));

describe('dama rules (specs/minigames/dama.md)', () => {
  it('starts with the player and 7 legal moves in path order', () => {
    const r = new DamaRules();
    const s = r.init(cfg, 42);
    expect(s).toMatchObject({ turn: 'player', plies: 0, quiet: 0, over: false, winner: '', byMaterial: false });
    expect(s.board).toBe('bbbbbbbbbbbb........wwwwwwwwwwww');
    expect(paths(r, s)).toEqual([[20, 16], [21, 16], [21, 17], [22, 17], [22, 18], [23, 18], [23, 19]]);
  });

  it('capturing is compulsory', () => {
    const { r, s } = setup({ 21: 'w', 28: 'w', 17: 'b', 0: 'b' });
    expect(paths(r, s)).toEqual([[21, 14]]);
    expect(() => r.apply(s, { by: 'player', path: [28, 24] })).toThrow();
    const n = r.apply(s, { by: 'player', path: [21, 14] });
    expect(n.board[17]).toBe('.');
    expect(n.board[14]).toBe('w');
    expect(n).toMatchObject({ turn: 'ai', plies: 1, quiet: 0 });
  });

  it('rejects moves out of turn', () => {
    const r = new DamaRules();
    const s = r.init(cfg, 1);
    expect(() => r.apply(s, { by: 'ai', path: [8, 12] })).toThrow();
    expect(() => r.apply(s, { by: 'player', path: [20, 12] })).toThrow();
  });

  it('a man cannot capture backwards', () => {
    const { r, s } = setup({ 13: 'w', 17: 'b', 0: 'b' });
    expect(paths(r, s)).toEqual([[13, 8], [13, 9]]);
  });

  it('a king captures from a distance and must continue, landing choice is free', () => {
    const { r, s } = setup({ 28: 'W', 21: 'b', 9: 'b', 31: 'b' });
    const ps = paths(r, s);
    expect(ps).toContainEqual([28, 14, 0]);
    expect(ps).toContainEqual([28, 14, 5]);
    expect(ps).toContainEqual([28, 17]);
    expect(ps).not.toContainEqual([28, 14]);
    const n = r.apply(s, { by: 'player', path: [28, 14, 5] });
    expect(n.board).toBe(board({ 5: 'W', 31: 'b' }));
    expect(n.quiet).toBe(0);
  });

  it('jumped pieces block until the move ends', () => {
    // King on 28 jumps 21 to 14, then 9 to 5 or 0; from there the jumped 21 cannot be jumped again.
    const { r, s } = setup({ 28: 'W', 21: 'b', 9: 'b', 31: 'b' });
    for (const p of paths(r, s)) expect(new Set(p).size).toBe(p.length);
  });

  it('a man promotes only at the end of its move and keeps capturing as a man', () => {
    // Man on 10 jumps 6 to row 0 (square 1); a king could go on over 5, a man cannot.
    const { r, s } = setup({ 10: 'w', 6: 'b', 5: 'b', 31: 'b' });
    expect(paths(r, s)).toEqual([[10, 1]]);
    const n = r.apply(s, { by: 'player', path: [10, 1] });
    expect(n.board[1]).toBe('W');
    expect(n.board[5]).toBe('b');
  });

  it('the AI man promotes on row 7', () => {
    const { r, s } = setup({ 24: 'b', 0: 'w' }, 'ai');
    const n = r.apply(s, { by: 'ai', path: [24, 28] });
    expect(n.board[28]).toBe('B');
  });

  it('a side without a move loses', () => {
    const { r, s } = setup({ 4: 'w', 0: 'b', 3: 'b' }, 'ai');
    const n = r.apply(s, { by: 'ai', path: [3, 7] });
    expect(n).toMatchObject({ over: true, winner: 'ai', turn: 'player' });
    expect(r.legalActions(n)).toEqual([]);
    expect(r.result(n)).toMatchObject({ winner: 'ai', stars: 0, byMaterial: false, plies: 1 });
  });

  it('a fast win gives 3 stars, a slow one 2', () => {
    const { r, s } = setup({ 9: 'w', 5: 'b' });
    const n = r.apply(s, { by: 'player', path: [9, 0] });
    expect(n).toMatchObject({ over: true, winner: 'player' });
    expect(r.result(n)).toMatchObject({ stars: 3, score: 1200 });
    expect(r.result({ ...n, plies: 81 })!.stars).toBe(2);
  });

  it('quiet moves of kings reach the draw limit', () => {
    const c = { ...cfg, quietLimit: 2 };
    const { r, s } = setup({ 31: 'W', 0: 'B' }, 'player', c);
    let n = r.apply(s, { by: 'player', path: [31, 27] });
    expect(n).toMatchObject({ quiet: 1, over: false });
    n = r.apply(n, { by: 'ai', path: [0, 4] });
    expect(n).toMatchObject({ quiet: 2, over: true, winner: 'draw' });
    expect(r.result(n)).toMatchObject({ winner: 'draw', stars: 0 });
  });

  it('a man move resets the quiet counter', () => {
    const { r, s } = setup({ 31: 'W', 21: 'w', 0: 'B' });
    const n = r.apply({ ...s, quiet: 7 }, { by: 'player', path: [21, 16] });
    expect(n.quiet).toBe(0);
  });

  it('timeout decides by material (man 1, king 3)', () => {
    const r = new DamaRules();
    const s = r.init(cfg, 3);
    expect(r.apply(s, { by: 'timeout' })).toMatchObject({ over: true, winner: 'draw', byMaterial: true });
    const k = setup({ 31: 'W', 0: 'b', 1: 'b' });
    const n = k.r.apply(k.s, { by: 'timeout' });
    expect(k.r.result(n)).toMatchObject({ winner: 'player', stars: 1, byMaterial: true, score: 1000 });
    const l = setup({ 31: 'w', 0: 'b', 1: 'b' });
    expect(l.r.apply(l.s, { by: 'timeout' }).winner).toBe('ai');
  });

  it('the AI at every level returns a legal move, depth 5 quickly', () => {
    const r = new DamaRules();
    let s = r.init(cfg, 11);
    s = r.apply(s, { by: 'player', path: [22, 17] });
    const legal = paths(r, s);
    for (let level = 1; level <= 5; level++) {
      const a = r.aiAction(s, level, aiPrng(level));
      expect(legal).toContainEqual('path' in a ? a.path : []);
    }
    const t0 = performance.now();
    r.aiAction(s, 5, aiPrng(1));
    expect(performance.now() - t0).toBeLessThan(500);
  });

  it('the AI takes a winning capture', () => {
    const { r, s } = setup({ 5: 'b', 9: 'w', 31: 'w' }, 'ai');
    expect(r.aiAction(s, 5, aiPrng(1))).toEqual({ by: 'ai', path: [5, 14] });
  });

  it('a whole game replays to the same states', () => {
    const r = new DamaRules();
    const steps = [];
    let s = r.init(cfg, 99);
    const ai = aiPrng(99);
    while (!s.over && steps.length < 400) {
      const a = s.turn === 'player' ? r.legalActions(s)[0]! : r.aiAction(s, 3, ai);
      steps.push({ action: s.turn === 'ai' ? { by: 'ai', level: 3 } : (a as Record<string, unknown>) });
      s = r.apply(s, a);
    }
    if (!s.over) {
      steps.push({ action: { by: 'timeout' } });
      s = r.apply(s, { by: 'timeout' });
    }
    const again = replay(new DamaRules() as never, { config: cfg as never, seed: 99, steps });
    expect(again.states.at(-1)).toEqual(s);
    expect(again.result).toEqual(r.result(s));
  });
});
