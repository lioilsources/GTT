import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { Tuning } from '../src/gen/tuning';
import { beats, DurakRules, durakConfig, type DurakState } from '../src/minigames/durak/rules';
import { figure, GorodkiRules, gorodkiConfig } from '../src/minigames/gorodki/rules';
import { aiPrng } from '../src/minigames/rules';
import { SachyRules, sachyConfig, START_BOARD, type SachyState } from '../src/minigames/sachy/rules';

const root = join(__dirname, '..', '..');
const tm = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8'))).minigames;

describe('sachy rules (specs/minigames/sachy.md)', () => {
  const r = new SachyRules();
  const s0 = r.init(sachyConfig(tm.sachy), 1);
  const at = (board: string, turn: SachyState['turn'] = 'player'): SachyState => ({ ...s0, board, turn });
  const moves = (s: SachyState): string[] => r.legalActions(s).map((a) => ('from' in a ? `${a.from}-${a.to}` : ''));

  it('starts with pawn steps and knight jumps only, white first', () => {
    expect(s0.board).toBe(START_BOARD);
    // Pawns 15–19 step to 10–14, knight 21 jumps to 10 and 12.
    expect(moves(s0)).toEqual(['15-10', '16-11', '17-12', '18-13', '19-14', '21-10', '21-12']);
  });

  it('a pinned piece cannot move; a pawn on the last row becomes a queen', () => {
    // Black rook on 0 pins the white bishop on 10 against the king on 20.
    const pin = at('r...k' + '.....' + 'B....' + '.....' + 'K....');
    expect(moves(pin).filter((m) => m.startsWith('10-'))).toEqual([]);
    const promo = r.apply(at('....k' + 'P....' + '.....' + '.....' + 'K....'), { by: 'player', from: 5, to: 0 });
    expect(promo.board[0]).toBe('Q');
    expect(promo.quiet).toBe(0);
  });

  it('mate wins at once, stalemate and bare kings draw, timeout counts material', () => {
    // Queen up to 0 mates the king on 4; the king on 14 guards 8 and 9.
    const mate = r.apply(at('....k' + '.....' + 'Q...K' + '.....' + '.....'), { by: 'player', from: 10, to: 0 });
    expect(mate.over && mate.winner).toBe('player');
    expect(r.result(mate)!.stars).toBe(3);
    const stale = r.apply(at('....k' + '.....' + '..Q.K' + '.....' + '.....'), { by: 'player', from: 12, to: 13 });
    expect(stale.over && stale.winner).toBe('draw');
    const bare = r.apply(at('....k' + '..p..' + '...K.' + '.....' + '.....'), { by: 'player', from: 13, to: 7 });
    expect(bare.over && bare.winner).toBe('draw');
    const t = r.apply(s0, { by: 'timeout' });
    expect(r.result(t)).toMatchObject({ winner: 'draw', stars: 0, byCount: true });
  });

  it('the AI finds a mate in one and illegal moves throw', () => {
    // Queen 23 → 3 mates the king on 0 (the black king on 10 covers 5 and 6); 23 → 5 too, 3 comes first.
    const s = at('K....' + '.....' + 'k....' + '.....' + '...q.', 'ai');
    expect(r.aiAction(s, 5, aiPrng(1))).toEqual({ by: 'ai', from: 23, to: 3 });
    expect(() => r.apply(s0, { by: 'player', from: 20, to: 15 })).toThrow();
    expect(() => r.apply(s0, { by: 'ai', from: 5, to: 10 })).toThrow();
  });
});

describe('gorodki rules (specs/minigames/gorodki.md)', () => {
  const cfg = gorodkiConfig(tm.gorodki, 1);
  const mid = cfg.gorodW / 2;

  it('lays figure 1 from the middle of the front line and starts from the kon', () => {
    const r = new GorodkiRules();
    const s = r.init(cfg, 1);
    expect(s).toMatchObject({ fig: 1, bats: cfg.bats[0], polukon: false });
    expect(s.px[0]).toBe(mid + cfg.figures[0]![0]!);
    expect(s.py[0]).toBe(cfg.gorodY0 + cfg.figures[0]![1]!);
    expect(figure(cfg, 3).up).toEqual([true, true, true, true, true]);
  });

  it('a straight hard throw knocks pieces out and moves to the polukon; a miss does not', () => {
    const r = new GorodkiRules();
    const s = r.init(cfg, 1);
    const hit = r.apply(s, { by: 'player', op: 'throw', x: mid, aim: mid, power: 100 });
    expect(hit.lastOut).toBeGreaterThan(0);
    expect(hit.polukon).toBe(true);
    expect(hit.bats).toBe(s.bats - 1);
    const miss = r.apply(s, { by: 'player', op: 'throw', x: 0, aim: -200000, power: 100 });
    expect(miss).toMatchObject({ lastOut: 0, polukon: false, throws: 1 });
    expect(() => r.apply(s, { by: 'player', op: 'throw', x: -1, aim: mid, power: 50 })).toThrow();
  });

  it('clearing a figure lays the next one; the last bat ends the game', () => {
    const r = new GorodkiRules();
    const s = r.init(cfg, 1);
    const one = { ...s, up: [true, false, false, false, false], px: [mid, 0, 0, 0, 0], py: [cfg.gorodY0 + 10000, 0, 0, 0, 0] };
    const n = r.apply(one, { by: 'player', op: 'throw', x: mid, aim: mid, power: 100 });
    expect(n).toMatchObject({ fig: 2, cleared: 1, polukon: false, up: [true, true, true, true, true] });
    const last = r.apply({ ...s, bats: 1 }, { by: 'player', op: 'throw', x: 0, aim: -200000, power: 10 });
    expect(last.over).toBe(true);
    expect(r.result(last)).toMatchObject({ winner: 'ai', stars: 0 });
  });
});

describe('durak rules (specs/minigames/durak.md)', () => {
  it('deals six each, trump from the bottom card, the lowest trump attacks', () => {
    const r = new DurakRules();
    const s = r.init(durakConfig(tm.durak, 5), 3);
    expect(s.n).toBe(4);
    expect(s.hands.every((h) => h.length === 6)).toBe(true);
    expect(s.stock.length).toBe(12);
    expect(Math.floor(s.trumpCard / 9)).toBe(s.trump);
    const lows = s.hands.map((h) => Math.min(99, ...h.filter((c) => Math.floor(c / 9) === s.trump).map((c) => c % 9)));
    expect(lows[s.attacker]).toBe(Math.min(...lows));
  });

  it('beats by a higher card of the suit or a trump', () => {
    expect(beats(5, 3, 2)).toBe(true);
    expect(beats(3, 5, 2)).toBe(false);
    expect(beats(18, 8, 2)).toBe(true);
    expect(beats(8, 18, 2)).toBe(false);
    expect(beats(10, 3, 2)).toBe(false);
  });

  it('take hands the table to the defender, the next seat attacks; pass after a beat is bito', () => {
    const r = new DurakRules();
    const base = r.init(durakConfig(tm.durak, 1), 1);
    const s: DurakState = { ...base, hands: [[0, 9, 10], [1, 2, 27]], stock: [], trump: 3, attacker: 0, defender: 1, thrower: 0 };
    const a = r.apply(s, { by: 'player', op: 'play', card: 0 });
    expect(a.limit).toBe(3);
    expect(r.legalActions(a).map((l) => ('op' in l ? l.op + ('card' in l ? l.card : '') : ''))).toEqual(['beat1', 'beat2', 'beat27', 'take']);
    const took = r.apply(a, { by: 'ai', op: 'take' });
    expect(took.hands[1]).toEqual([0, 1, 2, 27]);
    expect(took.attacker).toBe(0);
    const b = r.apply(a, { by: 'ai', op: 'beat', card: 1 });
    expect(r.legalActions(b).map((l) => ('op' in l ? l.op : ''))).toEqual(['play', 'play', 'pass']);
    const bito = r.apply(b, { by: 'player', op: 'pass' });
    expect(bito).toMatchObject({ table: [], attacker: 1, defender: 0 });
  });

  it('the last one holding cards is the durak; first out gets three stars', () => {
    const r = new DurakRules();
    const base = r.init(durakConfig(tm.durak, 1), 1);
    const s: DurakState = { ...base, hands: [[0], [1, 2]], stock: [], trump: 3, attacker: 0, defender: 1, thrower: 0 };
    const b = r.apply(r.apply(s, { by: 'player', op: 'play', card: 0 }), { by: 'ai', op: 'beat', card: 1 });
    const end = r.apply(b, { by: 'player', op: 'pass' });
    expect(end).toMatchObject({ over: true, durak: 1, finished: [0] });
    expect(r.result(end)).toMatchObject({ winner: 'player', stars: 3, place: 1 });
  });
});
