import { Prng } from '../../rules/prng';
import type { TuningMinigamesLode } from '../../gen/tuning';
import { IllegalAction, withRng, type Rules, type RulesResult } from '../rules';

/** specs/minigames/lode.md, version 1. */
export interface LodeConfig {
  fleet: number[];
  shuffles: number;
  aiErrorPct: number[];
  fastShots: number;
  okShots: number;
}

export type Side = 'player' | 'ai';

export interface LodeState {
  /** Ships in fleet order; a ship is its cells ascending (i = y * 10 + x). */
  pShips: number[][];
  aShips: number[][];
  /** AI shots on the player's board / player shots on the AI board: '.', 'o' water, 'x' hit. */
  pShots: string;
  aShots: string;
  turn: Side;
  shots: number;
  shuffles: number;
  over: boolean;
  winner: '' | Side | 'draw';
  rng: number;
}

export type LodeAction =
  | { by: 'player'; op: 'shuffle' }
  | { by: Side; op: 'shot'; cell: number }
  | { by: 'timeout' };

export interface LodeResult extends RulesResult {
  shots: number;
}

export function lodeConfig(t: TuningMinigamesLode): LodeConfig {
  return { fleet: [...t.fleet], shuffles: t.shuffles, aiErrorPct: [...t.aiErrorPct], fastShots: t.fastShots, okShots: t.okShots };
}

/** Deals one fleet from `rng` (specs/minigames/lode.md "Pole a rozmístění"). */
export function placeFleet(fleet: readonly number[], rng: Prng): number[][] {
  const taken = new Uint8Array(100); // ship cells and their neighbours
  const ships: number[][] = [];
  for (const len of fleet) {
    for (;;) {
      const dir = rng.nextInt(2);
      const x = rng.nextInt(dir === 0 ? 11 - len : 10);
      const y = rng.nextInt(dir === 1 ? 11 - len : 10);
      const cells: number[] = [];
      for (let k = 0; k < len; k++) cells.push(dir === 0 ? y * 10 + x + k : (y + k) * 10 + x);
      if (cells.some((c) => taken[c])) continue;
      for (const c of cells) {
        const cx = c % 10, cy = Math.floor(c / 10);
        for (let yy = Math.max(0, cy - 1); yy <= Math.min(9, cy + 1); yy++) {
          for (let xx = Math.max(0, cx - 1); xx <= Math.min(9, cx + 1); xx++) taken[yy * 10 + xx] = 1;
        }
      }
      ships.push(cells);
      break;
    }
  }
  return ships;
}

export const sunk = (ship: readonly number[], shots: string): boolean => ship.every((c) => shots[c] === 'x');

const allSunk = (ships: number[][], shots: string): boolean => ships.every((s) => sunk(s, shots));

function hits(shots: string): number {
  let n = 0;
  for (const ch of shots) if (ch === 'x') n++;
  return n;
}

/** Cells next to (also diagonally) any sunk ship. */
function nearSunk(ships: number[][], shots: string): Set<number> {
  const out = new Set<number>();
  for (const s of ships) {
    if (!sunk(s, shots)) continue;
    for (const c of s) {
      const cx = c % 10, cy = Math.floor(c / 10);
      for (let yy = Math.max(0, cy - 1); yy <= Math.min(9, cy + 1); yy++) {
        for (let xx = Math.max(0, cx - 1); xx <= Math.min(9, cx + 1); xx++) out.add(yy * 10 + xx);
      }
    }
  }
  return out;
}

/** AI target candidates from hits on ships not yet sunk ([] = hunt). */
export function targetCandidates(ships: number[][], shots: string): number[] {
  const live = new Set<number>();
  for (const s of ships) if (!sunk(s, shots)) for (const c of s) if (shots[c] === 'x') live.add(c);
  if (live.size === 0) return [];
  const free = (x: number, y: number): boolean => x >= 0 && x < 10 && y >= 0 && y < 10 && shots[y * 10 + x] === '.';
  const out = new Set<number>();
  let lines = false;
  for (const c of live) {
    const x = c % 10, y = Math.floor(c / 10);
    for (const [dx, dy] of [[1, 0], [0, 1]] as const) {
      // Start of a run of at least two live hits in this direction.
      if (x - dx >= 0 && y - dy >= 0 && live.has((y - dy) * 10 + x - dx)) continue;
      let len = 1;
      while (x + dx * len < 10 && y + dy * len < 10 && live.has((y + dy * len) * 10 + x + dx * len)) len++;
      if (len < 2) continue;
      lines = true;
      if (free(x - dx, y - dy)) out.add((y - dy) * 10 + x - dx);
      if (free(x + dx * len, y + dy * len)) out.add((y + dy * len) * 10 + x + dx * len);
    }
  }
  if (!lines || out.size === 0) {
    for (const c of live) {
      const x = c % 10, y = Math.floor(c / 10);
      for (const [dx, dy] of [[0, -1], [-1, 0], [1, 0], [0, 1]] as const) if (free(x + dx, y + dy)) out.add((y + dy) * 10 + x + dx);
    }
  }
  return [...out].sort((a, b) => a - b);
}

export class LodeRules implements Rules<LodeState, LodeAction, LodeResult, LodeConfig> {
  readonly id = 'lode';
  readonly specVersion = 1;
  private cfg: LodeConfig | null = null;

  init(config: LodeConfig, seed: number): LodeState {
    this.cfg = config;
    const r = new Prng(seed);
    const pShips = placeFleet(config.fleet, r);
    const aShips = placeFleet(config.fleet, r);
    return {
      pShips, aShips, pShots: '.'.repeat(100), aShots: '.'.repeat(100), turn: 'player', shots: 0,
      shuffles: config.shuffles, over: false, winner: '', rng: r.state,
    };
  }

  private get c(): LodeConfig {
    if (!this.cfg) throw new Error('lode: init first');
    return this.cfg;
  }

  canShuffle(s: LodeState): boolean {
    return !s.over && s.turn === 'player' && s.shots === 0 && s.shuffles > 0;
  }

  legalActions(s: LodeState): LodeAction[] {
    if (s.over) return [];
    const out: LodeAction[] = [];
    if (s.turn === 'player' && this.canShuffle(s)) out.push({ by: 'player', op: 'shuffle' });
    const board = s.turn === 'player' ? s.aShots : s.pShots;
    for (let i = 0; i < 100; i++) if (board[i] === '.') out.push({ by: s.turn, op: 'shot', cell: i });
    return out;
  }

  apply(s: LodeState, a: LodeAction): LodeState {
    if (s.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') {
      const p = hits(s.aShots), q = hits(s.pShots);
      return { ...s, over: true, winner: p > q ? 'player' : q > p ? 'ai' : 'draw' };
    }
    if (a.by !== s.turn) throw new IllegalAction(this.id, a);
    if (a.op === 'shuffle') {
      if (!this.canShuffle(s)) throw new IllegalAction(this.id, a);
      const { value, rng } = withRng(s.rng, (r) => placeFleet(this.c.fleet, r));
      return { ...s, pShips: value, shuffles: s.shuffles - 1, rng };
    }
    if (a.op !== 'shot' || !Number.isInteger(a.cell) || a.cell < 0 || a.cell >= 100) throw new IllegalAction(this.id, a);
    const mine = s.turn === 'player';
    const board = mine ? s.aShots : s.pShots;
    if (board[a.cell] !== '.') throw new IllegalAction(this.id, a);
    const ships = mine ? s.aShips : s.pShips;
    const hit = ships.some((sh) => sh.includes(a.cell));
    const shots = board.slice(0, a.cell) + (hit ? 'x' : 'o') + board.slice(a.cell + 1);
    const n: LodeState = mine ? { ...s, aShots: shots, shots: s.shots + 1 } : { ...s, pShots: shots };
    if (hit && allSunk(ships, shots)) return { ...n, over: true, winner: s.turn };
    return hit ? n : { ...n, turn: mine ? 'ai' : 'player' };
  }

  aiAction(s: LodeState, level: number, ai: Prng): LodeAction {
    if (s.over) throw new IllegalAction(this.id, { by: s.turn });
    const c = this.c;
    const board = s.turn === 'ai' ? s.pShots : s.aShots;
    const ships = s.turn === 'ai' ? s.pShips : s.aShips;
    const free: number[] = [];
    for (let i = 0; i < 100; i++) if (board[i] === '.') free.push(i);
    const lv = Math.min(Math.max(level, 1), c.aiErrorPct.length);
    const err = c.aiErrorPct[lv - 1] ?? 0;
    const shot = (cell: number): LodeAction => ({ by: s.turn, op: 'shot', cell });
    const r = ai.nextInt(100);
    if (r < err) return shot(free[ai.nextInt(free.length)]!);
    const target = targetCandidates(ships, board);
    if (target.length) return shot(target[ai.nextInt(target.length)]!);
    let pool = free;
    if (lv >= 3) {
      const even = free.filter((i) => ((i % 10) + Math.floor(i / 10)) % 2 === 0);
      if (even.length) pool = even;
    }
    if (lv >= 4) {
      const near = nearSunk(ships, board);
      const rest = pool.filter((i) => !near.has(i));
      if (rest.length) pool = rest;
    }
    return shot(pool[ai.nextInt(pool.length)]!);
  }

  result(s: LodeState): LodeResult | null {
    if (!s.over) return null;
    const winner = s.winner === '' ? 'draw' : s.winner;
    const c = this.c;
    const win = winner === 'player';
    const stars = !win ? 0 : s.shots <= c.fastShots ? 3 : s.shots <= c.okShots ? 2 : 1;
    return { winner, stars, score: win ? Math.max(0, 1000 - 10 * s.shots) : 0, shots: s.shots };
  }
}
