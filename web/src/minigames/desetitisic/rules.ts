import { Prng } from '../../rules/prng';
import type { TuningMinigamesDesetitisic } from '../../gen/tuning';
import { IllegalAction, withRng, type Rules, type RulesResult } from '../rules';

/** specs/minigames/desetitisic.md, version 1. */
export interface DesetitisicConfig {
  target: number;
  maxRounds: number;
  aiBankAt: number[];
  aiErrorPct: number[];
  starMargins: number[];
}

export type Side = 'player' | 'ai';
export type Phase = 'roll' | 'keep' | 'decide' | 'over';

export interface DesetitisicState {
  player: number;
  ai: number;
  turn: Side;
  phase: Phase;
  /** Values of the last roll; empty until the side on turn rolls. */
  roll: number[];
  /** How many dice the next roll throws (1–6). */
  dice: number;
  turnScore: number;
  round: number;
  lastBust: boolean;
  over: boolean;
  rng: number;
}

export type DesetitisicAction =
  | { by: Side; op: 'roll' }
  | { by: Side; op: 'keep'; dice: number[] }
  | { by: Side; op: 'bank' }
  | { by: 'timeout' };

export interface DesetitisicResult extends RulesResult {
  player: number;
  ai: number;
}

export function desetitisicConfig(t: TuningMinigamesDesetitisic): DesetitisicConfig {
  return {
    target: t.target,
    maxRounds: t.maxRounds,
    aiBankAt: [...t.aiBankAt],
    aiErrorPct: [...t.aiErrorPct],
    starMargins: [...t.starMargins],
  };
}

/**
 * Value of a selection (multiset of die values) by its best decomposition into a 1–6 straight
 * (1500), triples (100 × v, three 1s = 1000) and single 1s (100) and 5s (50); null when some die
 * fits no combination or the selection is empty.
 */
export function scoreSelection(values: readonly number[]): number | null {
  if (values.length === 0) return null;
  const c = [0, 0, 0, 0, 0, 0, 0];
  for (const v of values) {
    if (!Number.isInteger(v) || v < 1 || v > 6) return null;
    c[v]!++;
  }
  // Six different values: only the straight uses 2, 3, 4 and 6 as singles-free dice.
  if (values.length === 6 && c.slice(1).every((n) => n === 1)) return 1500;
  let total = 0;
  for (let v = 1; v <= 6; v++) {
    const n = c[v]!;
    const triples = Math.floor(n / 3);
    const rest = n - 3 * triples;
    // A triple always beats three singles (1000 > 300, 500 > 150), so take as many as fit.
    if (v === 1) total += triples * 1000 + rest * 100;
    else if (v === 5) total += triples * 500 + rest * 50;
    else if (rest !== 0) return null;
    else total += triples * 100 * v;
  }
  return total;
}

/** The roll rule: one nextInt(6) + 1 per die, in order. Exported so UIs can show a busted roll. */
export function rollDice(rng: number, n: number): { values: number[]; rng: number } {
  const { value, rng: next } = withRng(rng, (r) => Array.from({ length: n }, () => r.nextInt(6) + 1));
  return { values: value, rng: next };
}

/** Legal selections of a roll: ascending index lists ordered by bitmask (Σ 2^i) ascending. */
export function selections(roll: readonly number[]): number[][] {
  const out: number[][] = [];
  for (let m = 1; m < 1 << roll.length; m++) {
    const idx: number[] = [];
    for (let i = 0; i < roll.length; i++) if (m & (1 << i)) idx.push(i);
    if (scoreSelection(idx.map((i) => roll[i]!)) !== null) out.push(idx);
  }
  return out;
}

const other = (s: Side): Side => (s === 'player' ? 'ai' : 'player');

export class DesetitisicRules
  implements Rules<DesetitisicState, DesetitisicAction, DesetitisicResult, DesetitisicConfig> {
  readonly id = 'desetitisic';
  readonly specVersion = 1;
  private cfg: DesetitisicConfig | null = null;

  init(config: DesetitisicConfig, seed: number): DesetitisicState {
    this.cfg = config;
    return {
      player: 0,
      ai: 0,
      turn: 'player',
      phase: 'roll',
      roll: [],
      dice: 6,
      turnScore: 0,
      round: 1,
      lastBust: false,
      over: false,
      rng: new Prng(seed).state,
    };
  }

  private get c(): DesetitisicConfig {
    if (!this.cfg) throw new Error('desetitisic: init first');
    return this.cfg;
  }

  legalActions(s: DesetitisicState): DesetitisicAction[] {
    switch (s.phase) {
      case 'roll':
        return [{ by: s.turn, op: 'roll' }];
      case 'keep':
        return selections(s.roll).map((dice) => ({ by: s.turn, op: 'keep', dice }));
      case 'decide':
        return [{ by: s.turn, op: 'roll' }, { by: s.turn, op: 'bank' }];
      default:
        return [];
    }
  }

  apply(s: DesetitisicState, a: DesetitisicAction): DesetitisicState {
    if (s.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s, over: true, phase: 'over' };
    if (a.by !== s.turn) throw new IllegalAction(this.id, a);
    switch (a.op) {
      case 'roll': {
        if (s.phase !== 'roll' && s.phase !== 'decide') throw new IllegalAction(this.id, a);
        const { values, rng } = rollDice(s.rng, s.dice);
        if (selections(values).length === 0) return this.endTurn({ ...s, rng, turnScore: 0, lastBust: true }, false);
        return { ...s, rng, roll: values, phase: 'keep', lastBust: false };
      }
      case 'keep': {
        if (s.phase !== 'keep') throw new IllegalAction(this.id, a);
        const idx = a.dice;
        const ok = Array.isArray(idx) && idx.length > 0 &&
          idx.every((i, k) => Number.isInteger(i) && i >= 0 && i < s.roll.length && (k === 0 || i > idx[k - 1]!));
        const value = ok ? scoreSelection(idx.map((i) => s.roll[i]!)) : null;
        if (value === null) throw new IllegalAction(this.id, a);
        const dice = s.dice - idx.length;
        return { ...s, turnScore: s.turnScore + value, dice: dice === 0 ? 6 : dice, phase: 'decide' };
      }
      case 'bank': {
        if (s.phase !== 'decide') throw new IllegalAction(this.id, a);
        const total = s[s.turn] + s.turnScore;
        return this.endTurn({ ...s, [s.turn]: total }, total >= this.c.target);
      }
      default:
        throw new IllegalAction(this.id, a);
    }
  }

  /** End of turn: reset the turn, pass it, count the round after the AI, then check game end. */
  private endTurn(s: DesetitisicState, reachedTarget: boolean): DesetitisicState {
    const round = s.turn === 'ai' ? s.round + 1 : s.round;
    const over = reachedTarget || (s.turn === 'ai' && round > this.c.maxRounds);
    return {
      ...s,
      turnScore: 0,
      dice: 6,
      roll: [],
      phase: over ? 'over' : 'roll',
      turn: other(s.turn),
      round,
      over,
    };
  }

  aiAction(s: DesetitisicState, level: number, ai: Prng): DesetitisicAction {
    const c = this.c;
    const lv = Math.min(Math.max(level, 1), 5);
    const by = s.turn;
    if (s.phase === 'keep') {
      const legal = selections(s.roll);
      const err = c.aiErrorPct[Math.min(lv, c.aiErrorPct.length) - 1] ?? 0;
      const r = ai.nextInt(100);
      if (r < err) return { by, op: 'keep', dice: legal[ai.nextInt(legal.length)]! };
      let best = legal[0]!;
      let bestV = scoreSelection(best.map((i) => s.roll[i]!))!;
      for (const sel of legal.slice(1)) {
        const v = scoreSelection(sel.map((i) => s.roll[i]!))!;
        if (v > bestV || (v === bestV && sel.length < best.length)) {
          best = sel;
          bestV = v;
        }
      }
      return { by, op: 'keep', dice: best };
    }
    if (s.phase === 'decide') {
      const bankAt = c.aiBankAt[Math.min(lv, c.aiBankAt.length) - 1] ?? 0;
      if (s[by] + s.turnScore >= c.target) return { by, op: 'bank' };
      if (s.dice === 6) return { by, op: 'roll' };
      if (s.turnScore >= bankAt || (s.dice <= 2 && s.turnScore >= 200)) return { by, op: 'bank' };
      return { by, op: 'roll' };
    }
    return { by, op: 'roll' };
  }

  result(s: DesetitisicState): DesetitisicResult | null {
    if (!s.over) return null;
    const winner = s.player > s.ai ? 'player' : s.player < s.ai ? 'ai' : 'draw';
    const lead = s.player - s.ai;
    const [m3 = 0, m2 = 0] = this.c.starMargins;
    const stars = winner !== 'player' ? 0 : lead >= m3 ? 3 : lead >= m2 ? 2 : 1;
    return { winner, stars, score: s.player, player: s.player, ai: s.ai };
  }
}
