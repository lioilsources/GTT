import { Prng } from '../../rules/prng';
import type { TuningMinigamesMlyn } from '../../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../rules';

/** specs/minigames/mlyn.md, version 1. */
export interface MlynConfig {
  aiDepth: number[];
  aiErrorPct: number[];
  quietLimit: number;
  flying: boolean;
  star3Pieces: number;
}

export type Side = 'player' | 'ai';

export interface MlynState {
  /** 24 points: '.', 'w' (player), 'b' (AI). */
  board: string;
  hand: { player: number; ai: number };
  turn: Side;
  plies: number;
  quiet: number;
  over: boolean;
  winner: '' | Side | 'draw';
  byPieces: boolean;
  rng: number;
}

export type MlynAction = { by: Side; from: number; to: number; remove: number } | { by: 'timeout' };

export interface MlynResult extends RulesResult {
  byPieces: boolean;
  plies: number;
}

export function mlynConfig(t: TuningMinigamesMlyn): MlynConfig {
  return { aiDepth: [...t.aiDepth], aiErrorPct: [...t.aiErrorPct], quietLimit: t.quietLimit, flying: t.flying, star3Pieces: t.star3Pieces };
}

/** The 16 mills in spec order. */
export const MILLS: ReadonlyArray<readonly [number, number, number]> = [
  [0, 1, 2], [3, 4, 5], [6, 7, 8], [9, 10, 11], [12, 13, 14], [15, 16, 17], [18, 19, 20], [21, 22, 23],
  [0, 9, 21], [3, 10, 18], [6, 11, 15], [1, 4, 7], [16, 19, 22], [8, 12, 17], [5, 13, 20], [2, 14, 23],
];

/** ADJ[p] = neighbours of point p, ascending. */
export const ADJ: number[][] = (() => {
  const a: number[][] = Array.from({ length: 24 }, () => []);
  for (const [x, y, z] of MILLS) {
    a[x]!.push(y);
    a[y]!.push(x, z);
    a[z]!.push(y);
  }
  return a.map((n) => [...new Set(n)].sort((p, q) => p - q));
})();

/** MILLS_OF[p] = indices of the mills through point p. */
const MILLS_OF: number[][] = (() => {
  const m: number[][] = Array.from({ length: 24 }, () => []);
  MILLS.forEach((ml, k) => ml.forEach((p) => m[p]!.push(k)));
  return m;
})();

// ---- Search position (mutable, cheap) ------------------------------------------------------

/** Board as +1 player / -1 AI / 0 empty; hands indexed by side sign (0 = player, 1 = AI). */
interface Pos {
  b: Int8Array;
  hand: [number, number];
}

const hi = (s: number): 0 | 1 => (s > 0 ? 0 : 1);

function inMill(b: Int8Array, p: number): boolean {
  const s = b[p]!;
  if (s === 0) return false;
  for (const k of MILLS_OF[p]!) {
    const [x, y, z] = MILLS[k]!;
    if (b[x] === s && b[y] === s && b[z] === s) return true;
  }
  return false;
}

function count(b: Int8Array, s: number): number {
  let n = 0;
  for (let i = 0; i < 24; i++) if (b[i] === s) n++;
  return n;
}

function closedMills(b: Int8Array, s: number): number {
  let n = 0;
  for (const [x, y, z] of MILLS) if (b[x] === s && b[y] === s && b[z] === s) n++;
  return n;
}

/** Points of the opponent of `s` that a mill may take, ascending (none on board → [-1]). */
function removable(b: Int8Array, s: number): number[] {
  const out: number[] = [];
  const all: number[] = [];
  for (let i = 0; i < 24; i++) {
    if (b[i] !== -s) continue;
    all.push(i);
    if (!inMill(b, i)) out.push(i);
  }
  if (out.length) return out;
  return all.length ? all : [-1];
}

/** (from, to) pairs of side `s` ignoring removals, in (from, to) order. */
function steps(pos: Pos, s: number, flying: boolean): Array<[number, number]> {
  const { b } = pos;
  const out: Array<[number, number]> = [];
  if (pos.hand[hi(s)]! > 0) {
    for (let t = 0; t < 24; t++) if (b[t] === 0) out.push([-1, t]);
    return out;
  }
  const fly = flying && count(b, s) === 3;
  for (let f = 0; f < 24; f++) {
    if (b[f] !== s) continue;
    if (fly) {
      for (let t = 0; t < 24; t++) if (b[t] === 0) out.push([f, t]);
    } else {
      for (const t of ADJ[f]!) if (b[t] === 0) out.push([f, t]);
    }
  }
  return out;
}

interface Move {
  from: number;
  to: number;
  remove: number;
}

/** Every legal move of `s` in (from, to, remove) order. */
function generate(pos: Pos, s: number, flying: boolean): Move[] {
  const out: Move[] = [];
  const { b } = pos;
  for (const [f, t] of steps(pos, s, flying)) {
    if (f >= 0) b[f] = 0;
    b[t] = s;
    if (inMill(b, t)) for (const r of removable(b, s)) out.push({ from: f, to: t, remove: r });
    else out.push({ from: f, to: t, remove: -1 });
    b[t] = 0;
    if (f >= 0) b[f] = s;
  }
  return out;
}

/** Plays `m` in place; returns true when it closed a mill. */
function play(pos: Pos, m: Move, s: number): boolean {
  const { b } = pos;
  if (m.from >= 0) b[m.from] = 0;
  else pos.hand[hi(s)]!--;
  b[m.to] = s;
  const mill = inMill(b, m.to);
  if (mill && m.remove >= 0) b[m.remove] = 0;
  return mill;
}

/** True when side `s` to move has lost: placing done and under 3 stones, or no legal move. */
function lost(pos: Pos, s: number, flying: boolean): boolean {
  if (pos.hand[hi(s)] === 0 && count(pos.b, s) < 3) return true;
  return steps(pos, s, flying).length === 0;
}

function evaluate(pos: Pos, s: number, flying: boolean): number {
  const { b } = pos;
  const own = count(b, s) + pos.hand[hi(s)]!, opp = count(b, -s) + pos.hand[hi(-s)]!;
  let v = 100 * (own - opp) + 10 * (closedMills(b, s) - closedMills(b, -s));
  if (pos.hand[0] === 0 && pos.hand[1] === 0) v += steps(pos, s, flying).length - steps(pos, -s, flying).length;
  return v;
}

const LOSS = 100000;
const INF = 1 << 30;

function clone(p: Pos): Pos {
  return { b: Int8Array.from(p.b), hand: [p.hand[0], p.hand[1]] };
}

function search(pos: Pos, s: number, quiet: number, depth: number, alpha: number, beta: number, c: MlynConfig): number {
  if (lost(pos, s, c.flying)) return -(LOSS + depth);
  if (quiet >= c.quietLimit) return 0;
  if (depth === 0) return evaluate(pos, s, c.flying);
  let best = -INF;
  for (const m of generate(pos, s, c.flying)) {
    const child = clone(pos);
    const mill = play(child, m, s);
    const q = mill ? 0 : m.from >= 0 ? quiet + 1 : quiet;
    const v = -search(child, -s, q, depth - 1, -beta, -alpha, c);
    if (v > best) best = v;
    if (v > alpha) alpha = v;
    if (alpha >= beta) break;
  }
  return best;
}

const other = (s: Side): Side => (s === 'player' ? 'ai' : 'player');
const sign = (s: Side): number => (s === 'player' ? 1 : -1);

function toPos(s: MlynState): Pos {
  const b = new Int8Array(24);
  for (let i = 0; i < 24; i++) b[i] = s.board[i] === 'w' ? 1 : s.board[i] === 'b' ? -1 : 0;
  return { b, hand: [s.hand.player, s.hand.ai] };
}

function boardString(b: Int8Array): string {
  let out = '';
  for (let i = 0; i < 24; i++) out += b[i] === 1 ? 'w' : b[i] === -1 ? 'b' : '.';
  return out;
}

/** Stones of a side on the board. */
export function stones(board: string, side: Side): number {
  const ch = side === 'player' ? 'w' : 'b';
  let n = 0;
  for (const x of board) if (x === ch) n++;
  return n;
}

export class MlynRules implements Rules<MlynState, MlynAction, MlynResult, MlynConfig> {
  readonly id = 'mlyn';
  readonly specVersion = 1;
  private cfg: MlynConfig | null = null;

  init(config: MlynConfig, seed: number): MlynState {
    this.cfg = config;
    return {
      board: '.'.repeat(24), hand: { player: 9, ai: 9 }, turn: 'player', plies: 0, quiet: 0,
      over: false, winner: '', byPieces: false, rng: new Prng(seed).state,
    };
  }

  private get c(): MlynConfig {
    if (!this.cfg) throw new Error('mlyn: init first');
    return this.cfg;
  }

  legalActions(s: MlynState): MlynAction[] {
    if (s.over) return [];
    return generate(toPos(s), sign(s.turn), this.c.flying).map((m) => ({ by: s.turn, ...m }));
  }

  apply(s: MlynState, a: MlynAction): MlynState {
    if (s.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') {
      const p = stones(s.board, 'player') + s.hand.player, q = stones(s.board, 'ai') + s.hand.ai;
      return { ...s, over: true, byPieces: true, winner: p > q ? 'player' : q > p ? 'ai' : 'draw' };
    }
    if (a.by !== s.turn) throw new IllegalAction(this.id, a);
    const pos = toPos(s);
    const sg = sign(s.turn);
    const m = generate(pos, sg, this.c.flying).find((x) => x.from === a.from && x.to === a.to && x.remove === a.remove);
    if (!m) throw new IllegalAction(this.id, a);
    const mill = play(pos, m, sg);
    const quiet = mill ? 0 : m.from >= 0 ? s.quiet + 1 : s.quiet;
    const n: MlynState = {
      ...s, board: boardString(pos.b), hand: { player: pos.hand[0], ai: pos.hand[1] }, turn: other(s.turn), plies: s.plies + 1, quiet,
    };
    if (lost(pos, -sg, this.c.flying)) return { ...n, over: true, winner: s.turn };
    if (quiet >= this.c.quietLimit) return { ...n, over: true, winner: 'draw' };
    return n;
  }

  aiAction(s: MlynState, level: number, ai: Prng): MlynAction {
    const c = this.c;
    const pos = toPos(s);
    const sg = sign(s.turn);
    const legal = generate(pos, sg, c.flying);
    if (s.over || legal.length === 0) throw new IllegalAction(this.id, { by: s.turn });
    const lv = Math.min(Math.max(level, 1), c.aiErrorPct.length);
    const err = c.aiErrorPct[lv - 1] ?? 0;
    const depth = Math.max(1, c.aiDepth[Math.min(lv, c.aiDepth.length) - 1] ?? 1);
    const r = ai.nextInt(100);
    if (r < err) return { by: s.turn, ...legal[ai.nextInt(legal.length)]! };
    let best = -INF, bestI = 0, alpha = -INF;
    for (let i = 0; i < legal.length; i++) {
      const m = legal[i]!;
      const child = clone(pos);
      const mill = play(child, m, sg);
      const q = mill ? 0 : m.from >= 0 ? s.quiet + 1 : s.quiet;
      const v = -search(child, -sg, q, depth - 1, -INF, -alpha, c);
      if (v > best) {
        best = v;
        bestI = i;
      }
      if (v > alpha) alpha = v;
    }
    return { by: s.turn, ...legal[bestI]! };
  }

  result(s: MlynState): MlynResult | null {
    if (!s.over) return null;
    const winner = s.winner === '' ? 'draw' : s.winner;
    const stars = winner !== 'player' ? 0 : s.byPieces ? 1 : stones(s.board, 'player') >= this.c.star3Pieces ? 3 : 2;
    const score = 100 * (9 - stones(s.board, 'ai') - s.hand.ai);
    return { winner, stars, score, byPieces: s.byPieces, plies: s.plies };
  }
}
