import { Prng } from '../../rules/prng';
import type { TuningMinigamesPrase } from '../../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../rules';

/** specs/minigames/prase.md, version 1. */
export interface PraseConfig {
  target: number;
  maxRounds: number;
  aiHoldAt: number[];
  aiErrorPct: number[];
  starMargins: number[];
}

export type Side = 'player' | 'ai';

export interface PraseState {
  player: number;
  ai: number;
  turn: Side;
  turnScore: number;
  die: number;
  bust: boolean;
  round: number;
  over: boolean;
  rng: number;
}

export type PraseAction = { by: Side; op: 'roll' | 'hold' } | { by: 'timeout' };

export interface PraseResult extends RulesResult {
  player: number;
  ai: number;
}

export function praseConfig(t: TuningMinigamesPrase): PraseConfig {
  return {
    target: t.target,
    maxRounds: t.maxRounds,
    aiHoldAt: [...t.aiHoldAt],
    aiErrorPct: [...t.aiErrorPct],
    starMargins: [...t.starMargins],
  };
}

export class PraseRules implements Rules<PraseState, PraseAction, PraseResult, PraseConfig> {
  readonly id = 'prase';
  readonly specVersion = 1;
  private cfg: PraseConfig | null = null;

  private get c(): PraseConfig {
    if (!this.cfg) throw new Error('prase: init first');
    return this.cfg;
  }

  init(config: PraseConfig, seed: number): PraseState {
    this.cfg = config;
    return { player: 0, ai: 0, turn: 'player', turnScore: 0, die: 0, bust: false, round: 1, over: false, rng: new Prng(seed).state };
  }

  legalActions(s: PraseState): PraseAction[] {
    if (s.over) return [];
    const by = s.turn;
    return s.turnScore === 0 ? [{ by, op: 'roll' }] : [{ by, op: 'roll' }, { by, op: 'hold' }];
  }

  /** Turn passes; after the AI's turn the round advances and may end the game. */
  private endTurn(s: PraseState): PraseState {
    const n: PraseState = { ...s, turnScore: 0, turn: s.turn === 'player' ? 'ai' : 'player' };
    if (s.turn === 'ai') {
      n.round = s.round + 1;
      if (n.round > this.c.maxRounds) n.over = true;
    }
    return n;
  }

  apply(s: PraseState, a: PraseAction): PraseState {
    if (s.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s, over: true };
    if (a.by !== s.turn) throw new IllegalAction(this.id, a);
    if (a.op === 'roll') {
      const r = new Prng(s.rng);
      const die = r.nextInt(6) + 1;
      const n = { ...s, die, rng: r.state };
      if (die === 1) return this.endTurn({ ...n, turnScore: 0, bust: true });
      return { ...n, turnScore: s.turnScore + die, bust: false };
    }
    if (a.op !== 'hold' || s.turnScore === 0) throw new IllegalAction(this.id, a);
    const banked = s[s.turn] + s.turnScore;
    const n = { ...s, [s.turn]: banked };
    if (banked >= this.c.target) return { ...n, turnScore: 0, over: true };
    return this.endTurn(n);
  }

  aiAction(s: PraseState, level: number, ai: Prng): PraseAction {
    const legal = this.legalActions(s);
    if (s.turn !== 'ai' || legal.length === 0) throw new IllegalAction(this.id, { by: 'ai' });
    const err = this.c.aiErrorPct[level - 1] ?? 0;
    if (ai.nextInt(100) < err) return legal[ai.nextInt(legal.length)]!;
    const roll: PraseAction = { by: 'ai', op: 'roll' };
    const hold: PraseAction = { by: 'ai', op: 'hold' };
    const t = s.turnScore;
    if (t === 0) return roll;
    if (s.ai + t >= this.c.target) return hold;
    if (level >= 3 && s.round === this.c.maxRounds) return s.ai + t > s.player ? hold : roll;
    if (level >= 4 && s.player >= this.c.target - 20) return roll;
    return t >= (this.c.aiHoldAt[level - 1] ?? 20) ? hold : roll;
  }

  result(s: PraseState): PraseResult | null {
    if (!s.over) return null;
    const { player: p, ai: a } = s;
    const winner = p > a ? 'player' : p < a ? 'ai' : 'draw';
    const m = this.c.starMargins;
    const stars = winner !== 'player' ? 0 : p - a >= m[0]! ? 3 : p - a >= m[1]! ? 2 : 1;
    return { winner, stars, score: p, player: p, ai: a };
  }
}
