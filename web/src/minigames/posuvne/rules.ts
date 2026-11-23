import { Prng } from '../../rules/prng';
import type { TuningMinigamesPosuvne } from '../../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../rules';

/** specs/minigames/posuvne.md, version 1. `level` is MinigameContext.difficulty. */
export interface PosuvneConfig {
  shuffleMoves: number[];
  level: number;
}

export interface PosuvneState {
  /** 16 numbers row by row from the top, 0 = the gap. */
  tiles: number[];
  moves: number;
  par: number;
  over: boolean;
  solved: boolean;
  rng: number;
}

export type PosuvneAction = { by: 'player'; tile: number } | { by: 'timeout' };

export interface PosuvneResult extends RulesResult {
  moves: number;
  par: number;
}

export function posuvneConfig(t: TuningMinigamesPosuvne, level: number): PosuvneConfig {
  return { shuffleMoves: [...t.shuffleMoves], level };
}

export const SOLVED: readonly number[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 0];

export const isSolved = (t: readonly number[]): boolean => t.every((v, i) => v === SOLVED[i]);

/** Positions next to `p` in the order up, down, left, right. */
export function neighbours(p: number): number[] {
  const r = p >> 2, c = p & 3;
  const out: number[] = [];
  if (r > 0) out.push(p - 4);
  if (r < 3) out.push(p + 4);
  if (c > 0) out.push(p - 1);
  if (c < 3) out.push(p + 1);
  return out;
}

export class PosuvneRules implements Rules<PosuvneState, PosuvneAction, PosuvneResult, PosuvneConfig> {
  readonly id = 'posuvne';
  readonly specVersion = 1;

  init(config: PosuvneConfig, seed: number): PosuvneState {
    const rng = new Prng(seed);
    const lv = Math.min(Math.max(config.level, 1), config.shuffleMoves.length);
    let par = config.shuffleMoves[lv - 1] ?? 0;
    const tiles = [...SOLVED];
    let gap = 15, last = -1;
    const step = (): void => {
      const nb = neighbours(gap).filter((p) => p !== last);
      const p = nb[rng.nextInt(nb.length)]!;
      tiles[gap] = tiles[p]!;
      tiles[p] = 0;
      last = gap;
      gap = p;
    };
    for (let k = 0; k < par; k++) step();
    if (isSolved(tiles)) {
      step();
      par += 1;
    }
    return { tiles, moves: 0, par, over: false, solved: false, rng: rng.state };
  }

  legalActions(s: PosuvneState): PosuvneAction[] {
    if (s.over) return [];
    const gap = s.tiles.indexOf(0);
    return neighbours(gap).map((p) => s.tiles[p]!).sort((a, b) => a - b).map((tile) => ({ by: 'player', tile }));
  }

  apply(s: PosuvneState, a: PosuvneAction): PosuvneState {
    if (s.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s, over: true, solved: false };
    if (a.by !== 'player' || !Number.isInteger(a.tile)) throw new IllegalAction(this.id, a);
    const gap = s.tiles.indexOf(0);
    const p = s.tiles.indexOf(a.tile);
    if (a.tile === 0 || p < 0 || !neighbours(gap).includes(p)) throw new IllegalAction(this.id, a);
    const tiles = [...s.tiles];
    tiles[gap] = a.tile;
    tiles[p] = 0;
    const solved = isSolved(tiles);
    return { ...s, tiles, moves: s.moves + 1, over: solved, solved };
  }

  aiAction(): PosuvneAction {
    throw new Error('posuvne: no opponent');
  }

  result(s: PosuvneState): PosuvneResult | null {
    if (!s.over) return null;
    if (!s.solved) return { winner: 'ai', stars: 0, score: 0, moves: s.moves, par: s.par };
    const stars = s.moves <= s.par ? 3 : s.moves <= 2 * s.par ? 2 : 1;
    return { winner: 'player', stars, score: Math.max(100, 1000 - 10 * Math.max(0, s.moves - s.par)), moves: s.moves, par: s.par };
  }
}
