import { Prng } from '../../rules/prng';
import type { TuningMinigamesPiskvorky } from '../../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../rules';

/** specs/minigames/piskvorky.md, version 1. */
export interface PiskvorkyConfig {
  size: number;
  aiErrorPct: number[];
  defensePct: number[];
  fastMoves: number;
}

export type Side = 'player' | 'ai';

export interface PiskvorkyState {
  /** size² chars, row-major from the top: '.', 'x' (player), 'o' (AI). */
  board: string;
  turn: Side;
  moves: number;
  over: boolean;
  winner: '' | Side | 'draw';
  rng: number;
}

export type PiskvorkyAction = { by: Side; cell: number } | { by: 'timeout' };

export interface PiskvorkyResult extends RulesResult {
  moves: number;
}

export function piskvorkyConfig(t: TuningMinigamesPiskvorky): PiskvorkyConfig {
  return { size: t.size, aiErrorPct: [...t.aiErrorPct], defensePct: [...t.defensePct], fastMoves: t.fastMoves };
}

const mark = (s: Side): string => (s === 'player' ? 'x' : 'o');
const other = (s: Side): Side => (s === 'player' ? 'ai' : 'player');

/** The four line directions as (dr, dc): →, ↓, ↘, ↙. */
const DIRS: ReadonlyArray<readonly [number, number]> = [[0, 1], [1, 0], [1, 1], [1, -1]];

/** Length of the run of `m` through `cell` (counting `cell` as `m`) and its open ends, per direction. */
export function runAt(board: string, size: number, cell: number, m: string, d: number): { len: number; open: number } {
  const [dr, dc] = DIRS[d]!;
  const r0 = Math.floor(cell / size), c0 = cell % size;
  let len = 1, open = 0;
  for (const sg of [1, -1]) {
    let r = r0 + dr * sg, c = c0 + dc * sg;
    while (r >= 0 && r < size && c >= 0 && c < size && board[r * size + c] === m) {
      len++;
      r += dr * sg;
      c += dc * sg;
    }
    if (r >= 0 && r < size && c >= 0 && c < size && board[r * size + c] === '.') open++;
  }
  return { len, open };
}

/** The winning run through `cell` (cells ascending along the line), or [] (UI highlight). */
export function winningLine(board: string, size: number, cell: number): number[] {
  const m = board[cell];
  if (m !== 'x' && m !== 'o') return [];
  for (const [dr, dc] of DIRS) {
    const r0 = Math.floor(cell / size), c0 = cell % size;
    const line = [cell];
    for (const sg of [1, -1]) {
      let r = r0 + dr * sg, c = c0 + dc * sg;
      while (r >= 0 && r < size && c >= 0 && c < size && board[r * size + c] === m) {
        line.push(r * size + c);
        r += dr * sg;
        c += dc * sg;
      }
    }
    if (line.length >= 5) return line.sort((a, b) => a - b);
  }
  return [];
}

const VALUE: ReadonlyArray<readonly [number, number, number]> = [
  [0, 0, 0],
  [0, 1, 10], // L = 1: E = 0, 1, 2
  [0, 10, 100],
  [0, 100, 1000],
  [0, 1000, 10000],
];

/** útok(p, s): sum over the four directions of the line value a mark of `m` on `cell` would make. */
export function attack(board: string, size: number, cell: number, m: string): number {
  let v = 0;
  for (let d = 0; d < 4; d++) {
    const { len, open } = runAt(board, size, cell, m, d);
    v += len >= 5 ? 100000 : VALUE[len]![open]!;
  }
  return v;
}

/** AI candidates: empty cells within Chebyshev distance 2 of a mark, ascending; empty board → centre. */
export function candidates(board: string, size: number): number[] {
  const out: number[] = [];
  let any = false;
  for (let i = 0; i < board.length; i++) {
    if (board[i] !== '.') {
      any = true;
      continue;
    }
    const r = Math.floor(i / size), c = i % size;
    let near = false;
    for (let rr = Math.max(0, r - 2); rr <= Math.min(size - 1, r + 2) && !near; rr++) {
      for (let cc = Math.max(0, c - 2); cc <= Math.min(size - 1, c + 2); cc++) {
        if (board[rr * size + cc] !== '.') {
          near = true;
          break;
        }
      }
    }
    if (near) out.push(i);
  }
  if (!any) return [(size >> 1) * size + (size >> 1)];
  return out;
}

export class PiskvorkyRules implements Rules<PiskvorkyState, PiskvorkyAction, PiskvorkyResult, PiskvorkyConfig> {
  readonly id = 'piskvorky';
  readonly specVersion = 1;
  private cfg: PiskvorkyConfig | null = null;

  init(config: PiskvorkyConfig, seed: number): PiskvorkyState {
    this.cfg = config;
    return { board: '.'.repeat(config.size * config.size), turn: 'player', moves: 0, over: false, winner: '', rng: new Prng(seed).state };
  }

  private get c(): PiskvorkyConfig {
    if (!this.cfg) throw new Error('piskvorky: init first');
    return this.cfg;
  }

  legalActions(s: PiskvorkyState): PiskvorkyAction[] {
    if (s.over) return [];
    const out: PiskvorkyAction[] = [];
    for (let i = 0; i < s.board.length; i++) if (s.board[i] === '.') out.push({ by: s.turn, cell: i });
    return out;
  }

  apply(s: PiskvorkyState, a: PiskvorkyAction): PiskvorkyState {
    if (s.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s, over: true, winner: 'draw' };
    const cell = a.cell;
    if (a.by !== s.turn || !Number.isInteger(cell) || cell < 0 || cell >= s.board.length || s.board[cell] !== '.') {
      throw new IllegalAction(this.id, a);
    }
    const m = mark(s.turn);
    const board = s.board.slice(0, cell) + m + s.board.slice(cell + 1);
    const moves = s.turn === 'player' ? s.moves + 1 : s.moves;
    const size = this.c.size;
    for (let d = 0; d < 4; d++) {
      // The new mark is on the board, so run it as the same colour.
      if (runAt(board, size, cell, m, d).len >= 5) return { ...s, board, moves, over: true, winner: s.turn };
    }
    if (!board.includes('.')) return { ...s, board, moves, over: true, winner: 'draw' };
    return { ...s, board, moves, turn: other(s.turn) };
  }

  aiAction(s: PiskvorkyState, level: number, ai: Prng): PiskvorkyAction {
    if (s.over) throw new IllegalAction(this.id, { by: s.turn });
    const c = this.c;
    const lv = Math.min(Math.max(level, 1), c.aiErrorPct.length);
    const err = c.aiErrorPct[lv - 1] ?? 0;
    const def = c.defensePct[Math.min(lv, c.defensePct.length) - 1] ?? 100;
    const cand = candidates(s.board, c.size);
    const r = ai.nextInt(100);
    if (r < err) return { by: s.turn, cell: cand[ai.nextInt(cand.length)]! };
    const own = mark(s.turn), opp = mark(other(s.turn));
    let best = -1, bestCell = cand[0]!;
    for (const p of cand) {
      const v = attack(s.board, c.size, p, own) + Math.trunc((attack(s.board, c.size, p, opp) * def) / 100);
      if (v > best) {
        best = v;
        bestCell = p;
      }
    }
    return { by: s.turn, cell: bestCell };
  }

  result(s: PiskvorkyState): PiskvorkyResult | null {
    if (!s.over) return null;
    const winner = s.winner === '' ? 'draw' : s.winner;
    let marks = 0;
    for (const ch of s.board) if (ch !== '.') marks++;
    const win = winner === 'player';
    const stars = win ? (s.moves <= this.c.fastMoves ? 3 : 2) : 0;
    const score = win ? (s.board.length - marks) * 10 : 0;
    return { winner, stars, score, moves: s.moves };
  }
}
