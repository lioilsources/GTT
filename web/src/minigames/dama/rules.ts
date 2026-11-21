import { Prng } from '../../rules/prng';
import type { TuningMinigamesDama } from '../../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../rules';

/** specs/minigames/dama.md, version 1. */
export interface DamaConfig {
  aiDepth: number[];
  aiErrorPct: number[];
  quietLimit: number;
  fastPlies: number;
}

export type Side = 'player' | 'ai';

export interface DamaState {
  /** 32 dark squares, rows from the AI side: '.', 'w', 'W' (player), 'b', 'B' (AI). */
  board: string;
  turn: Side;
  plies: number;
  quiet: number;
  over: boolean;
  winner: '' | Side | 'draw';
  byMaterial: boolean;
  rng: number;
}

export type DamaAction = { by: Side; path: number[] } | { by: 'timeout' };

export interface DamaResult extends RulesResult {
  byMaterial: boolean;
  plies: number;
}

export function damaConfig(t: TuningMinigamesDama): DamaConfig {
  return { aiDepth: [...t.aiDepth], aiErrorPct: [...t.aiErrorPct], quietLimit: t.quietLimit, fastPlies: t.fastPlies };
}

// ---- Board geometry -------------------------------------------------------------------------

export const rowOf = (i: number): number => i >> 2;
export const colOf = (i: number): number => 2 * (i & 3) + (1 - (rowOf(i) & 1));
/** Square index of (r, c), or -1 for a light or off-board square. */
export function squareAt(r: number, c: number): number {
  if (r < 0 || r > 7 || c < 0 || c > 7 || ((r + c) & 1) === 0) return -1;
  return r * 4 + (c >> 1);
}

// Directions: 0 = up-left, 1 = up-right (player forward), 2 = down-left, 3 = down-right (AI forward).
const DR = [-1, -1, 1, 1];
const DC = [-1, 1, -1, 1];
/** NB[i * 4 + d] = neighbour of square i in direction d, or -1. */
const NB = new Int8Array(128);
for (let i = 0; i < 32; i++) for (let d = 0; d < 4; d++) NB[i * 4 + d] = squareAt(rowOf(i) + DR[d]!, colOf(i) + DC[d]!);

// Pieces in the search board: +1/+2 player man/king, -1/-2 AI man/king, 0 empty. Side sign: player +1.
const CODE: Record<string, number> = { '.': 0, w: 1, W: 2, b: -1, B: -2 };
const CHAR = ['B', 'b', '.', 'w', 'W'];

export function parseBoard(s: string): Int8Array {
  const b = new Int8Array(32);
  for (let i = 0; i < 32; i++) b[i] = CODE[s[i]!] ?? 0;
  return b;
}

export function boardString(b: Int8Array): string {
  let s = '';
  for (let i = 0; i < 32; i++) s += CHAR[b[i]! + 2];
  return s;
}

/** One move: the path of squares and the captured squares as a bit mask. */
export interface Move {
  path: number[];
  caps: number;
}

/** Appends every capture path of the piece on `from` (lifted from the board during the search). */
function capturesFrom(b: Int8Array, from: number, s: number, out: Move[]): void {
  const p = b[from]!;
  const king = p === 2 || p === -2;
  b[from] = 0;
  const path = [from];
  const d0 = s > 0 ? 0 : 2;
  const dfs = (cur: number, caps: number): void => {
    let found = false;
    if (king) {
      for (let d = 0; d < 4; d++) {
        let m = NB[cur * 4 + d]!;
        while (m >= 0 && b[m] === 0) m = NB[m * 4 + d]!;
        if (m < 0 || b[m]! * s >= 0 || (caps & (1 << m)) !== 0) continue;
        for (let l = NB[m * 4 + d]!; l >= 0 && b[l] === 0; l = NB[l * 4 + d]!) {
          found = true;
          path.push(l);
          dfs(l, caps | (1 << m));
          path.pop();
        }
      }
    } else {
      for (let d = d0; d < d0 + 2; d++) {
        const m = NB[cur * 4 + d]!;
        if (m < 0 || b[m]! * s >= 0 || (caps & (1 << m)) !== 0) continue;
        const l = NB[m * 4 + d]!;
        if (l < 0 || b[l] !== 0) continue;
        found = true;
        path.push(l);
        dfs(l, caps | (1 << m));
        path.pop();
      }
    }
    if (!found && path.length > 1) out.push({ path: [...path], caps });
  };
  dfs(from, 0);
  b[from] = p;
}

/** All legal moves of side `s` (+1 player, -1 AI) in generation order; captures are compulsory. */
export function generate(b: Int8Array, s: number): Move[] {
  const out: Move[] = [];
  for (let i = 0; i < 32; i++) if (b[i]! * s > 0) capturesFrom(b, i, s, out);
  if (out.length) return out;
  const d0 = s > 0 ? 0 : 2;
  for (let i = 0; i < 32; i++) {
    const p = b[i]! * s;
    if (p <= 0) continue;
    if (p === 2) {
      for (let d = 0; d < 4; d++) for (let l = NB[i * 4 + d]!; l >= 0 && b[l] === 0; l = NB[l * 4 + d]!) out.push({ path: [i, l], caps: 0 });
    } else {
      for (let d = d0; d < d0 + 2; d++) {
        const l = NB[i * 4 + d]!;
        if (l >= 0 && b[l] === 0) out.push({ path: [i, l], caps: 0 });
      }
    }
  }
  return out;
}

/** True when side `s` has at least one legal move (cheaper than generating them). */
export function hasMove(b: Int8Array, s: number): boolean {
  const d0 = s > 0 ? 0 : 2;
  for (let i = 0; i < 32; i++) {
    const p = b[i]! * s;
    if (p <= 0) continue;
    const lo = p === 2 ? 0 : d0, hi = p === 2 ? 4 : d0 + 2;
    for (let d = lo; d < hi; d++) {
      const m = NB[i * 4 + d]!;
      if (m < 0) continue;
      if (b[m] === 0) return true;
      if (b[m]! * s < 0) {
        const l = NB[m * 4 + d]!;
        if (l >= 0 && b[l] === 0) return true;
      }
    }
  }
  return false;
}

export function comparePaths(a: number[], b: number[]): number {
  const n = Math.min(a.length, b.length);
  for (let i = 0; i < n; i++) if (a[i] !== b[i]) return a[i]! - b[i]!;
  return a.length - b.length;
}

/** Legal moves in the canonical order of legalActions (paths lexicographically). */
export function sortedMoves(b: Int8Array, s: number): Move[] {
  return generate(b, s).sort((x, y) => comparePaths(x.path, y.path));
}

/** Plays `m` on `b` in place; returns true when the move resets the quiet counter. */
export function playMove(b: Int8Array, m: Move, s: number): boolean {
  const from = m.path[0]!, to = m.path[m.path.length - 1]!;
  let p = b[from]!;
  const man = p === s;
  b[from] = 0;
  for (let c = m.caps, i = 0; c !== 0; i++, c >>>= 1) if (c & 1) b[i] = 0;
  if (man && rowOf(to) === (s > 0 ? 0 : 7)) p = 2 * s;
  b[to] = p;
  return man || m.caps !== 0;
}

/** Static evaluation from the side to move: 100 per man, 300 per king. */
function evaluate(b: Int8Array, s: number): number {
  let v = 0;
  for (let i = 0; i < 32; i++) {
    const p = b[i]! * s;
    v += p === 1 ? 100 : p === -1 ? -100 : p === 2 ? 300 : p === -2 ? -300 : 0;
  }
  return v;
}

const LOSS = 100000;
const INF = 1 << 30;

/** Negamax with alpha-beta; boards per ply are preallocated in `stack`. */
function search(stack: Int8Array[], ply: number, s: number, quiet: number, depth: number, alpha: number, beta: number, limit: number): number {
  const b = stack[ply]!;
  if (depth === 0) {
    if (!hasMove(b, s)) return -LOSS;
    if (quiet >= limit) return 0;
    return evaluate(b, s);
  }
  const moves = generate(b, s);
  if (moves.length === 0) return -(LOSS + depth);
  if (quiet >= limit) return 0;
  const child = stack[ply + 1]!;
  let best = -INF;
  for (const m of moves) {
    child.set(b);
    const q = playMove(child, m, s) ? 0 : quiet + 1;
    const v = -search(stack, ply + 1, -s, q, depth - 1, -beta, -alpha, limit);
    if (v > best) best = v;
    if (v > alpha) alpha = v;
    if (alpha >= beta) break;
  }
  return best;
}

const other = (s: Side): Side => (s === 'player' ? 'ai' : 'player');
const sign = (s: Side): number => (s === 'player' ? 1 : -1);

function material(b: Int8Array, s: number): number {
  let v = 0;
  for (let i = 0; i < 32; i++) {
    const p = b[i]! * s;
    if (p > 0) v += p === 2 ? 3 : 1;
  }
  return v;
}

export function countPieces(board: string, side: Side): number {
  const [m, k] = side === 'player' ? ['w', 'W'] : ['b', 'B'];
  let n = 0;
  for (const ch of board) if (ch === m || ch === k) n++;
  return n;
}

/** True when the side to move must capture (UI hint). */
export function mustCapture(s: DamaState): boolean {
  if (s.over) return false;
  const m = generate(parseBoard(s.board), sign(s.turn));
  return m.length > 0 && m[0]!.caps !== 0;
}

export const START_BOARD = 'b'.repeat(12) + '.'.repeat(8) + 'w'.repeat(12);

/** Each rules instance carries its config; init takes it again for vectors. */
export class DamaRules implements Rules<DamaState, DamaAction, DamaResult, DamaConfig> {
  readonly id = 'dama';
  readonly specVersion = 1;
  private cfg: DamaConfig | null = null;

  init(config: DamaConfig, seed: number): DamaState {
    this.cfg = config;
    return { board: START_BOARD, turn: 'player', plies: 0, quiet: 0, over: false, winner: '', byMaterial: false, rng: new Prng(seed).state };
  }

  private get c(): DamaConfig {
    if (!this.cfg) throw new Error('dama: init first');
    return this.cfg;
  }

  legalActions(s: DamaState): DamaAction[] {
    if (s.over) return [];
    return sortedMoves(parseBoard(s.board), sign(s.turn)).map((m) => ({ by: s.turn, path: m.path }));
  }

  apply(s: DamaState, a: DamaAction): DamaState {
    if (s.over) throw new IllegalAction(this.id, a);
    const b = parseBoard(s.board);
    if (a.by === 'timeout') {
      const p = material(b, 1), q = material(b, -1);
      return { ...s, over: true, byMaterial: true, winner: p > q ? 'player' : q > p ? 'ai' : 'draw' };
    }
    if (a.by !== s.turn || !Array.isArray(a.path)) throw new IllegalAction(this.id, a);
    const sg = sign(s.turn);
    const m = generate(b, sg).find((x) => comparePaths(x.path, a.path) === 0);
    if (!m) throw new IllegalAction(this.id, a);
    const quiet = playMove(b, m, sg) ? 0 : s.quiet + 1;
    const turn = other(s.turn);
    const n: DamaState = { ...s, board: boardString(b), turn, plies: s.plies + 1, quiet };
    if (!hasMove(b, -sg)) return { ...n, over: true, winner: s.turn };
    if (quiet >= this.c.quietLimit) return { ...n, over: true, winner: 'draw' };
    return n;
  }

  aiAction(s: DamaState, level: number, ai: Prng): DamaAction {
    const c = this.c;
    const lv = Math.min(Math.max(level, 1), c.aiErrorPct.length);
    const err = c.aiErrorPct[lv - 1] ?? 0;
    const depth = Math.max(1, c.aiDepth[Math.min(lv, c.aiDepth.length) - 1] ?? 1);
    const b = parseBoard(s.board);
    const sg = sign(s.turn);
    const legal = sortedMoves(b, sg);
    if (legal.length === 0) throw new IllegalAction(this.id, { by: s.turn });
    const r = ai.nextInt(100);
    if (r < err) return { by: s.turn, path: legal[ai.nextInt(legal.length)]!.path };
    const stack = Array.from({ length: depth + 1 }, () => new Int8Array(32));
    let best = -INF, bestI = 0, alpha = -INF;
    for (let i = 0; i < legal.length; i++) {
      const child = stack[1]!;
      child.set(b);
      const q = playMove(child, legal[i]!, sg) ? 0 : s.quiet + 1;
      const v = -search(stack, 1, -sg, q, depth - 1, -INF, -alpha, c.quietLimit);
      if (v > best) {
        best = v;
        bestI = i;
      }
      if (v > alpha) alpha = v;
    }
    return { by: s.turn, path: legal[bestI]!.path };
  }

  result(s: DamaState): DamaResult | null {
    if (!s.over) return null;
    const winner = s.winner === '' ? 'draw' : s.winner;
    const stars = winner !== 'player' ? 0 : s.byMaterial ? 1 : s.plies <= this.c.fastPlies ? 3 : 2;
    const score = 100 * (12 - countPieces(s.board, 'ai'));
    return { winner, stars, score, byMaterial: s.byMaterial, plies: s.plies };
  }
}
