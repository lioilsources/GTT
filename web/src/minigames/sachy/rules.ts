import { Prng } from '../../rules/prng';
import type { TuningMinigamesSachy } from '../../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../rules';

/** specs/minigames/sachy.md, version 1: Gardner minichess 5×5. */
export interface SachyConfig {
  aiDepth: number[];
  aiErrorPct: number[];
  quietLimit: number;
  fastPlies: number;
}

export type Side = 'player' | 'ai';

export interface SachyState {
  /** 25 chars, row 0 on top: '.', upper case player (white), lower case AI (black). */
  board: string;
  turn: Side;
  plies: number;
  quiet: number;
  over: boolean;
  winner: '' | Side | 'draw';
  byCount: boolean;
  rng: number;
}

export type SachyAction = { by: Side; from: number; to: number } | { by: 'timeout' };

export interface SachyResult extends RulesResult {
  byCount: boolean;
  player: number;
  ai: number;
  plies: number;
}

export function sachyConfig(t: TuningMinigamesSachy): SachyConfig {
  return { aiDepth: [...t.aiDepth], aiErrorPct: [...t.aiErrorPct], quietLimit: t.quietLimit, fastPlies: t.fastPlies };
}

export const START_BOARD = 'rnbqkppppp.....PPPPPRNBQK';
const N = 5;
const VALUE: Record<string, number> = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 0 };
const ROOK = [[-1, 0], [1, 0], [0, -1], [0, 1]] as const;
const BISHOP = [[-1, -1], [-1, 1], [1, -1], [1, 1]] as const;
const KING = [...ROOK, ...BISHOP];
const KNIGHT = [[-2, -1], [-2, 1], [-1, -2], [-1, 2], [1, -2], [1, 2], [2, -1], [2, 1]] as const;
const INF = 1 << 30;

/** +1 player piece, −1 AI piece, 0 empty. */
const owner = (ch: string): number => (ch === '.' ? 0 : ch === ch.toUpperCase() ? 1 : -1);
const sideSign = (s: Side): number => (s === 'player' ? 1 : -1);

/** Pseudo-legal moves of side `sg` as [from, to] pairs, ascending by from, then to. */
function pseudo(b: string[], sg: number): Array<[number, number]> {
  const out: Array<[number, number]> = [];
  for (let i = 0; i < 25; i++) {
    const ch = b[i]!;
    if (owner(ch) !== sg) continue;
    const r0 = Math.floor(i / N), c0 = i % N;
    const t: number[] = [];
    const p = ch.toLowerCase();
    const at = (r: number, c: number): number => (r >= 0 && r < N && c >= 0 && c < N ? r * N + c : -1);
    if (p === 'p') {
      const r = r0 - sg;
      const f = at(r, c0);
      if (f >= 0 && b[f] === '.') t.push(f);
      for (const dc of [-1, 1]) {
        const x = at(r, c0 + dc);
        if (x >= 0 && owner(b[x]!) === -sg) t.push(x);
      }
    } else if (p === 'n' || p === 'k') {
      for (const [dr, dc] of p === 'n' ? KNIGHT : KING) {
        const x = at(r0 + dr, c0 + dc);
        if (x >= 0 && owner(b[x]!) !== sg) t.push(x);
      }
    } else {
      const dirs = p === 'r' ? ROOK : p === 'b' ? BISHOP : KING;
      for (const [dr, dc] of dirs) {
        let r = r0 + dr, c = c0 + dc;
        for (let x = at(r, c); x >= 0; r += dr, c += dc, x = at(r, c)) {
          const o = owner(b[x]!);
          if (o === sg) break;
          t.push(x);
          if (o !== 0) break;
        }
      }
    }
    t.sort((a, z) => a - z);
    for (const x of t) out.push([i, x]);
  }
  return out;
}

/** Board after moving from → to (promotion to a queen on the last row). */
function moved(b: string[], from: number, to: number): string[] {
  const n = [...b];
  let ch = n[from]!;
  const row = Math.floor(to / N);
  if (ch === 'P' && row === 0) ch = 'Q';
  else if (ch === 'p' && row === N - 1) ch = 'q';
  n[to] = ch;
  n[from] = '.';
  return n;
}

/** True when side `sg`'s king is attacked. */
function inCheck(b: string[], sg: number): boolean {
  const k = b.indexOf(sg === 1 ? 'K' : 'k');
  if (k < 0) return true;
  return pseudo(b, -sg).some(([, to]) => to === k);
}

function legalMoves(b: string[], sg: number): Array<[number, number]> {
  return pseudo(b, sg).filter(([f, t]) => !inCheck(moved(b, f, t), sg));
}

export function material(board: string, side: Side): number {
  const sg = sideSign(side);
  let m = 0;
  for (const ch of board) if (owner(ch) === sg) m += VALUE[ch.toLowerCase()]!;
  return m;
}

const kingsOnly = (b: string[]): boolean => b.every((ch) => ch === '.' || ch === 'k' || ch === 'K');

function evaluate(b: string[], sg: number): number {
  let v = 0;
  for (let i = 0; i < 25; i++) {
    const ch = b[i]!;
    const o = owner(ch);
    if (o === 0) continue;
    const p = ch.toLowerCase();
    const r = Math.floor(i / N);
    const adv = p === 'p' ? (o === 1 ? 4 - r : r) : 0;
    v += o * sg * (VALUE[p]! * 100 + adv * 10);
  }
  return v;
}

function search(b: string[], sg: number, quiet: number, d: number, quietLimit: number, alpha: number, beta: number): number {
  const ms = legalMoves(b, sg);
  if (ms.length === 0) return inCheck(b, sg) ? -(100000 + d) : 0;
  if (kingsOnly(b) || quiet >= quietLimit) return 0;
  if (d === 0) return evaluate(b, sg);
  let best = -INF;
  for (const [f, t] of ms) {
    const q = b[t] !== '.' || b[f]!.toLowerCase() === 'p' ? 0 : quiet + 1;
    const v = -search(moved(b, f, t), -sg, q, d - 1, quietLimit, -beta, -alpha);
    if (v > best) best = v;
    if (v > alpha) alpha = v;
    if (alpha >= beta) break;
  }
  return best;
}

const other = (s: Side): Side => (s === 'player' ? 'ai' : 'player');

export class SachyRules implements Rules<SachyState, SachyAction, SachyResult, SachyConfig> {
  readonly id = 'sachy';
  readonly specVersion = 1;
  private cfg: SachyConfig | null = null;

  private get c(): SachyConfig {
    if (!this.cfg) throw new Error('sachy: init first');
    return this.cfg;
  }

  init(config: SachyConfig, seed: number): SachyState {
    this.cfg = config;
    return { board: START_BOARD, turn: 'player', plies: 0, quiet: 0, over: false, winner: '', byCount: false, rng: new Prng(seed).state };
  }

  legalActions(s: SachyState): SachyAction[] {
    if (s.over) return [];
    return legalMoves(s.board.split(''), sideSign(s.turn)).map(([from, to]) => ({ by: s.turn, from, to }));
  }

  /** True when the side to move is in check. */
  check(s: SachyState): boolean {
    return inCheck(s.board.split(''), sideSign(s.turn));
  }

  apply(s: SachyState, a: SachyAction): SachyState {
    if (s.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') {
      const p = material(s.board, 'player'), q = material(s.board, 'ai');
      return { ...s, over: true, byCount: true, winner: p > q ? 'player' : q > p ? 'ai' : 'draw' };
    }
    if (a.by !== s.turn) throw new IllegalAction(this.id, a);
    const b = s.board.split('');
    const sg = sideSign(s.turn);
    if (!legalMoves(b, sg).some(([f, t]) => f === a.from && t === a.to)) throw new IllegalAction(this.id, a);
    const reset = b[a.to] !== '.' || b[a.from]!.toLowerCase() === 'p';
    const nb = moved(b, a.from, a.to);
    const n: SachyState = { ...s, board: nb.join(''), turn: other(s.turn), plies: s.plies + 1, quiet: reset ? 0 : s.quiet + 1 };
    if (legalMoves(nb, -sg).length === 0) return { ...n, over: true, winner: inCheck(nb, -sg) ? s.turn : 'draw' };
    if (kingsOnly(nb) || n.quiet >= this.c.quietLimit) return { ...n, over: true, winner: 'draw' };
    return n;
  }

  aiAction(s: SachyState, level: number, ai: Prng): SachyAction {
    if (s.over) throw new IllegalAction(this.id, { by: s.turn });
    const c = this.c;
    const lv = Math.min(Math.max(level, 1), 5);
    const err = c.aiErrorPct[lv - 1] ?? 0;
    const depth = Math.max(1, c.aiDepth[lv - 1] ?? 1);
    const b = s.board.split('');
    const sg = sideSign(s.turn);
    const legal = legalMoves(b, sg);
    const pick = (m: [number, number]): SachyAction => ({ by: s.turn, from: m[0], to: m[1] });
    if (ai.nextInt(100) < err) return pick(legal[ai.nextInt(legal.length)]!);
    let best = -INF, bestI = 0, alpha = -INF;
    for (let i = 0; i < legal.length; i++) {
      const [f, t] = legal[i]!;
      const q = b[t] !== '.' || b[f]!.toLowerCase() === 'p' ? 0 : s.quiet + 1;
      const v = -search(moved(b, f, t), -sg, q, depth - 1, c.quietLimit, -INF, -alpha);
      if (v > best) {
        best = v;
        bestI = i;
      }
      if (v > alpha) alpha = v;
    }
    return pick(legal[bestI]!);
  }

  result(s: SachyState): SachyResult | null {
    if (!s.over) return null;
    const winner = s.winner === '' ? 'draw' : s.winner;
    const player = material(s.board, 'player'), ai = material(s.board, 'ai');
    const stars = winner !== 'player' ? 0 : s.byCount ? 1 : s.plies <= this.c.fastPlies ? 3 : 2;
    return { winner, stars, score: player * 10, byCount: s.byCount, player, ai, plies: s.plies };
  }
}
