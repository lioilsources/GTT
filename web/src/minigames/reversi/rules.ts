import { Prng } from '../../rules/prng';
import type { TuningMinigamesReversi } from '../../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../rules';

/** specs/minigames/reversi.md, version 1. */
export interface ReversiConfig {
  aiDepth: number[];
  aiErrorPct: number[];
  star3Margin: number;
}

export type Side = 'player' | 'ai';

export interface ReversiState {
  /** 64 chars, row 0 on top: '.', 'x' (player), 'o' (AI). */
  board: string;
  turn: Side;
  plies: number;
  passes: number;
  over: boolean;
  winner: '' | Side | 'draw';
  byCount: boolean;
  rng: number;
}

/** cell -1 = pass. */
export type ReversiAction = { by: Side; cell: number } | { by: 'timeout' };

export interface ReversiResult extends RulesResult {
  byCount: boolean;
  player: number;
  ai: number;
}

export function reversiConfig(t: TuningMinigamesReversi): ReversiConfig {
  return { aiDepth: [...t.aiDepth], aiErrorPct: [...t.aiErrorPct], star3Margin: t.star3Margin };
}

const DIRS: ReadonlyArray<readonly [number, number]> = [[-1, -1], [-1, 0], [-1, 1], [0, -1], [0, 1], [1, -1], [1, 0], [1, 1]];

const HALF = [
  [100, -20, 10, 5, 5, 10, -20, 100],
  [-20, -50, -2, -2, -2, -2, -50, -20],
  [10, -2, -1, -1, -1, -1, -2, 10],
  [5, -2, -1, -1, -1, -1, -2, 5],
];
/** Square weights; rows 4-7 mirror rows 3-0. */
export const WEIGHTS: number[] = [...HALF, ...[...HALF].reverse()].flat();

export const START_BOARD = (() => {
  const b = '.'.repeat(64).split('');
  b[27] = 'o';
  b[36] = 'o';
  b[28] = 'x';
  b[35] = 'x';
  return b.join('');
})();

function parse(board: string): Int8Array {
  const b = new Int8Array(64);
  for (let i = 0; i < 64; i++) b[i] = board[i] === 'x' ? 1 : board[i] === 'o' ? -1 : 0;
  return b;
}

function boardString(b: Int8Array): string {
  let s = '';
  for (let i = 0; i < 64; i++) s += b[i] === 1 ? 'x' : b[i] === -1 ? 'o' : '.';
  return s;
}

/** Flips caused by `s` on empty `cell` (does not modify b), [] when illegal. */
function flipsOf(b: Int8Array, s: number, cell: number): number[] {
  if (b[cell] !== 0) return [];
  const out: number[] = [];
  const r0 = cell >> 3, c0 = cell & 7;
  for (const [dr, dc] of DIRS) {
    let r = r0 + dr, c = c0 + dc;
    const run: number[] = [];
    while (r >= 0 && r < 8 && c >= 0 && c < 8 && b[r * 8 + c] === -s) {
      run.push(r * 8 + c);
      r += dr;
      c += dc;
    }
    if (run.length && r >= 0 && r < 8 && c >= 0 && c < 8 && b[r * 8 + c] === s) out.push(...run);
  }
  return out;
}

/** Legal cells of `s` ascending; [-1] (pass) when there are none. */
function moves(b: Int8Array, s: number): number[] {
  const out: number[] = [];
  for (let i = 0; i < 64; i++) if (b[i] === 0 && flipsOf(b, s, i).length) out.push(i);
  return out.length ? out : [-1];
}

function count(b: Int8Array, s: number): number {
  let n = 0;
  for (let i = 0; i < 64; i++) if (b[i] === s) n++;
  return n;
}

/** End of game with `s` to move: full board, two passes, or `s` has no disc. */
function ended(b: Int8Array, s: number, passes: number): boolean {
  if (passes >= 2) return true;
  let empty = false;
  for (let i = 0; i < 64; i++) if (b[i] === 0) { empty = true; break; }
  return !empty || count(b, s) === 0;
}

const INF = 1 << 30;

function search(b: Int8Array, s: number, passes: number, depth: number, alpha: number, beta: number): number {
  if (ended(b, s, passes)) {
    const d = count(b, s) - count(b, -s);
    return 100000 * Math.sign(d) + d;
  }
  if (depth === 0) {
    let v = 0;
    for (let i = 0; i < 64; i++) v += WEIGHTS[i]! * b[i]! * s;
    return v;
  }
  let best = -INF;
  for (const cell of moves(b, s)) {
    const child = Int8Array.from(b);
    let p = 0;
    if (cell >= 0) {
      for (const f of flipsOf(child, s, cell)) child[f] = s;
      child[cell] = s;
    } else p = passes + 1;
    const v = -search(child, -s, p, depth - 1, -beta, -alpha);
    if (v > best) best = v;
    if (v > alpha) alpha = v;
    if (alpha >= beta) break;
  }
  return best;
}

const other = (s: Side): Side => (s === 'player' ? 'ai' : 'player');
const sign = (s: Side): number => (s === 'player' ? 1 : -1);

export function discs(board: string, side: Side): number {
  const ch = side === 'player' ? 'x' : 'o';
  let n = 0;
  for (const x of board) if (x === ch) n++;
  return n;
}

export class ReversiRules implements Rules<ReversiState, ReversiAction, ReversiResult, ReversiConfig> {
  readonly id = 'reversi';
  readonly specVersion = 1;
  private cfg: ReversiConfig | null = null;

  init(config: ReversiConfig, seed: number): ReversiState {
    this.cfg = config;
    return { board: START_BOARD, turn: 'player', plies: 0, passes: 0, over: false, winner: '', byCount: false, rng: new Prng(seed).state };
  }

  private get c(): ReversiConfig {
    if (!this.cfg) throw new Error('reversi: init first');
    return this.cfg;
  }

  legalActions(s: ReversiState): ReversiAction[] {
    if (s.over) return [];
    return moves(parse(s.board), sign(s.turn)).map((cell) => ({ by: s.turn, cell }));
  }

  apply(s: ReversiState, a: ReversiAction): ReversiState {
    if (s.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s, over: true, byCount: true, winner: this.leader(s.board) };
    if (a.by !== s.turn) throw new IllegalAction(this.id, a);
    const b = parse(s.board);
    const sg = sign(s.turn);
    if (!moves(b, sg).includes(a.cell)) throw new IllegalAction(this.id, a);
    let { plies, passes } = s;
    if (a.cell >= 0) {
      for (const f of flipsOf(b, sg, a.cell)) b[f] = sg;
      b[a.cell] = sg;
      plies++;
      passes = 0;
    } else passes++;
    const board = boardString(b);
    const n: ReversiState = { ...s, board, turn: other(s.turn), plies, passes };
    if (ended(b, -sg, passes)) return { ...n, over: true, winner: this.leader(board) };
    return n;
  }

  private leader(board: string): Side | 'draw' {
    const p = discs(board, 'player'), q = discs(board, 'ai');
    return p > q ? 'player' : q > p ? 'ai' : 'draw';
  }

  aiAction(s: ReversiState, level: number, ai: Prng): ReversiAction {
    if (s.over) throw new IllegalAction(this.id, { by: s.turn });
    const c = this.c;
    const b = parse(s.board);
    const sg = sign(s.turn);
    const legal = moves(b, sg);
    const lv = Math.min(Math.max(level, 1), c.aiErrorPct.length);
    const err = c.aiErrorPct[lv - 1] ?? 0;
    const depth = Math.max(1, c.aiDepth[Math.min(lv, c.aiDepth.length) - 1] ?? 1);
    const r = ai.nextInt(100);
    if (r < err) return { by: s.turn, cell: legal[ai.nextInt(legal.length)]! };
    let best = -INF, bestI = 0, alpha = -INF;
    for (let i = 0; i < legal.length; i++) {
      const cell = legal[i]!;
      const child = Int8Array.from(b);
      let p = 0;
      if (cell >= 0) {
        for (const f of flipsOf(child, sg, cell)) child[f] = sg;
        child[cell] = sg;
      } else p = s.passes + 1;
      const v = -search(child, -sg, p, depth - 1, -INF, -alpha);
      if (v > best) {
        best = v;
        bestI = i;
      }
      if (v > alpha) alpha = v;
    }
    return { by: s.turn, cell: legal[bestI]! };
  }

  result(s: ReversiState): ReversiResult | null {
    if (!s.over) return null;
    const winner = s.winner === '' ? 'draw' : s.winner;
    const player = discs(s.board, 'player'), ai = discs(s.board, 'ai');
    const stars = winner !== 'player' ? 0 : s.byCount ? 1 : player - ai >= this.c.star3Margin ? 3 : 2;
    return { winner, stars, score: player * 10, byCount: s.byCount, player, ai };
  }
}
