import { Prng } from '../../rules/prng';
import type { TuningMinigamesCtyri } from '../../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../rules';

/** specs/minigames/ctyri.md, version 1. */
export interface CtyriConfig {
  aiDepth: number[];
  aiErrorPct: number[];
  fastMoves: number;
}

export type Side = 'player' | 'ai';

export interface CtyriState {
  /** 42 chars, row 0 on top: '.', 'x' (player), 'o' (AI). */
  board: string;
  turn: Side;
  moves: number;
  over: boolean;
  winner: '' | Side | 'draw';
  rng: number;
}

export type CtyriAction = { by: Side; col: number } | { by: 'timeout' };

export interface CtyriResult extends RulesResult {
  moves: number;
}

export function ctyriConfig(t: TuningMinigamesCtyri): CtyriConfig {
  return { aiDepth: [...t.aiDepth], aiErrorPct: [...t.aiErrorPct], fastMoves: t.fastMoves };
}

export const COLS = 7;
export const ROWS = 6;
const N = COLS * ROWS;

/** The 69 windows of four cells (horizontal, vertical, both diagonals). */
export const WINDOWS: number[][] = (() => {
  const w: number[][] = [];
  const dirs = [[0, 1], [1, 0], [1, 1], [1, -1]];
  for (const [dr, dc] of dirs) {
    for (let r = 0; r < ROWS; r++) {
      for (let c = 0; c < COLS; c++) {
        const er = r + 3 * dr!, ec = c + 3 * dc!;
        if (er < 0 || er >= ROWS || ec < 0 || ec >= COLS) continue;
        w.push([0, 1, 2, 3].map((k) => (r + k * dr!) * COLS + c + k * dc!));
      }
    }
  }
  return w;
})();

// Search board: +1 player, -1 AI, 0 empty.
function parse(board: string): Int8Array {
  const b = new Int8Array(N);
  for (let i = 0; i < N; i++) b[i] = board[i] === 'x' ? 1 : board[i] === 'o' ? -1 : 0;
  return b;
}

/** Row a token dropped into `col` lands on, or -1 when the column is full. */
function landing(b: Int8Array, col: number): number {
  for (let r = ROWS - 1; r >= 0; r--) if (b[r * COLS + col] === 0) return r;
  return -1;
}

/** True when the piece on `cell` is part of four or more in a row. */
function wins(b: Int8Array, cell: number): boolean {
  return winLine(b, cell).length > 0;
}

function winLine(b: Int8Array, cell: number): number[] {
  const s = b[cell]!;
  if (s === 0) return [];
  const r0 = Math.floor(cell / COLS), c0 = cell % COLS;
  for (const [dr, dc] of [[0, 1], [1, 0], [1, 1], [1, -1]] as const) {
    const line = [cell];
    for (const sg of [1, -1]) {
      let r = r0 + dr * sg, c = c0 + dc * sg;
      while (r >= 0 && r < ROWS && c >= 0 && c < COLS && b[r * COLS + c] === s) {
        line.push(r * COLS + c);
        r += dr * sg;
        c += dc * sg;
      }
    }
    if (line.length >= 4) return line.sort((a, z) => a - z);
  }
  return [];
}

/** The winning four through `cell` (UI highlight). */
export function winningLine(board: string, cell: number): number[] {
  return winLine(parse(board), cell);
}

/** Leaf evaluation from the side `s` to move. */
function evaluate(b: Int8Array, s: number): number {
  let v = 0;
  for (const w of WINDOWS) {
    let own = 0, opp = 0;
    for (const i of w) {
      const p = b[i]! * s;
      if (p > 0) own++;
      else if (p < 0) opp++;
    }
    if (opp === 0) v += own === 3 ? 50 : own === 2 ? 5 : 0;
    else if (own === 0) v -= opp === 3 ? 60 : opp === 2 ? 5 : 0;
  }
  for (let r = 0; r < ROWS; r++) v += 3 * b[r * COLS + 3]! * s;
  return v;
}

const LOSS = 100000;
const INF = 1 << 30;

/** Negamax with alpha-beta; `last` is the cell the opponent just played (-1 at the root). */
function search(b: Int8Array, s: number, last: number, filled: number, depth: number, alpha: number, beta: number): number {
  if (last >= 0 && wins(b, last)) return -(LOSS + depth);
  if (filled === N) return 0;
  if (depth === 0) return evaluate(b, s);
  let best = -INF;
  for (let c = 0; c < COLS; c++) {
    const r = landing(b, c);
    if (r < 0) continue;
    const i = r * COLS + c;
    b[i] = s;
    const v = -search(b, -s, i, filled + 1, depth - 1, -beta, -alpha);
    b[i] = 0;
    if (v > best) best = v;
    if (v > alpha) alpha = v;
    if (alpha >= beta) break;
  }
  return best;
}

const other = (s: Side): Side => (s === 'player' ? 'ai' : 'player');
const sign = (s: Side): number => (s === 'player' ? 1 : -1);

export class CtyriRules implements Rules<CtyriState, CtyriAction, CtyriResult, CtyriConfig> {
  readonly id = 'ctyri';
  readonly specVersion = 1;
  private cfg: CtyriConfig | null = null;

  init(config: CtyriConfig, seed: number): CtyriState {
    this.cfg = config;
    return { board: '.'.repeat(N), turn: 'player', moves: 0, over: false, winner: '', rng: new Prng(seed).state };
  }

  private get c(): CtyriConfig {
    if (!this.cfg) throw new Error('ctyri: init first');
    return this.cfg;
  }

  legalActions(s: CtyriState): CtyriAction[] {
    if (s.over) return [];
    const out: CtyriAction[] = [];
    for (let c = 0; c < COLS; c++) if (s.board[c] === '.') out.push({ by: s.turn, col: c });
    return out;
  }

  /** The cell a token dropped into `col` lands on, or -1 (UI). */
  landingCell(s: CtyriState, col: number): number {
    const r = landing(parse(s.board), col);
    return r < 0 ? -1 : r * COLS + col;
  }

  apply(s: CtyriState, a: CtyriAction): CtyriState {
    if (s.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s, over: true, winner: 'draw' };
    const b = parse(s.board);
    if (a.by !== s.turn || !Number.isInteger(a.col) || a.col < 0 || a.col >= COLS) throw new IllegalAction(this.id, a);
    const r = landing(b, a.col);
    if (r < 0) throw new IllegalAction(this.id, a);
    const cell = r * COLS + a.col;
    b[cell] = sign(s.turn);
    const board = s.board.slice(0, cell) + (s.turn === 'player' ? 'x' : 'o') + s.board.slice(cell + 1);
    const moves = s.turn === 'player' ? s.moves + 1 : s.moves;
    if (wins(b, cell)) return { ...s, board, moves, over: true, winner: s.turn };
    if (!board.includes('.')) return { ...s, board, moves, over: true, winner: 'draw' };
    return { ...s, board, moves, turn: other(s.turn) };
  }

  aiAction(s: CtyriState, level: number, ai: Prng): CtyriAction {
    const legal = this.legalActions(s) as Array<{ by: Side; col: number }>;
    if (legal.length === 0) throw new IllegalAction(this.id, { by: s.turn });
    const c = this.c;
    const lv = Math.min(Math.max(level, 1), c.aiErrorPct.length);
    const err = c.aiErrorPct[lv - 1] ?? 0;
    const depth = Math.max(1, c.aiDepth[Math.min(lv, c.aiDepth.length) - 1] ?? 1);
    const r = ai.nextInt(100);
    if (r < err) return legal[ai.nextInt(legal.length)]!;
    const b = parse(s.board);
    const sg = sign(s.turn);
    let filled = 0;
    for (let i = 0; i < N; i++) if (b[i] !== 0) filled++;
    let best = -INF, bestI = 0, alpha = -INF;
    for (let k = 0; k < legal.length; k++) {
      const col = legal[k]!.col;
      const i = landing(b, col) * COLS + col;
      b[i] = sg;
      const v = -search(b, -sg, i, filled + 1, depth - 1, -INF, -alpha);
      b[i] = 0;
      if (v > best) {
        best = v;
        bestI = k;
      }
      if (v > alpha) alpha = v;
    }
    return legal[bestI]!;
  }

  result(s: CtyriState): CtyriResult | null {
    if (!s.over) return null;
    const winner = s.winner === '' ? 'draw' : s.winner;
    let tokens = 0;
    for (const ch of s.board) if (ch !== '.') tokens++;
    const win = winner === 'player';
    return { winner, stars: win ? (s.moves <= this.c.fastMoves ? 3 : 2) : 0, score: win ? (N - tokens) * 20 : 0, moves: s.moves };
  }
}
