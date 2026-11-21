import { Prng } from '../../rules/prng';
import type { TuningMinigamesSirky } from '../../gen/tuning';
import { IllegalAction, withRng, type Rules, type RulesResult } from '../rules';

/** specs/minigames/sirky.md, version 1. */
export interface SirkyConfig {
  start: number;
  minStart: number;
  maxStart: number;
  maxTake: number;
  roundsToWin: number;
  aiErrorPct: number[];
}

export type Side = 'player' | 'ai';

export interface SirkyState {
  left: number;
  turn: Side;
  starter: Side;
  round: number;
  player: number;
  ai: number;
  over: boolean;
  rng: number;
}

export type SirkyAction = { by: Side; take: number } | { by: 'timeout' };

export interface SirkyResult extends RulesResult {
  player: number;
  ai: number;
}

export function sirkyConfig(t: TuningMinigamesSirky): SirkyConfig {
  return {
    start: t.start,
    minStart: t.minStart,
    maxStart: t.maxStart,
    maxTake: t.maxTake,
    roundsToWin: t.roundsToWin,
    aiErrorPct: [...t.aiErrorPct],
  };
}

const other = (s: Side): Side => (s === 'player' ? 'ai' : 'player');

/** Each rules instance carries its config; init takes it again for vectors. */
export class SirkyRules implements Rules<SirkyState, SirkyAction, SirkyResult, SirkyConfig> {
  readonly id = 'sirky';
  readonly specVersion = 1;
  private cfg: SirkyConfig | null = null;

  init(config: SirkyConfig, seed: number): SirkyState {
    this.cfg = config;
    return { left: config.start, turn: 'player', starter: 'player', round: 1, player: 0, ai: 0, over: false, rng: new Prng(seed).state };
  }

  private get c(): SirkyConfig {
    if (!this.cfg) throw new Error('sirky: init first');
    return this.cfg;
  }

  legalActions(s: SirkyState): SirkyAction[] {
    if (s.over) return [];
    const m = Math.min(this.c.maxTake, s.left);
    return Array.from({ length: m }, (_, i) => ({ by: s.turn, take: i + 1 }));
  }

  apply(s: SirkyState, a: SirkyAction): SirkyState {
    if (s.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s, over: true };
    if (a.by !== s.turn || !Number.isInteger(a.take) || a.take < 1 || a.take > Math.min(this.c.maxTake, s.left)) {
      throw new IllegalAction(this.id, a);
    }
    const left = s.left - a.take;
    if (left > 0) return { ...s, left, turn: other(s.turn) };
    const winner = other(a.by);
    const n = { ...s, left: 0, [winner]: s[winner] + 1 };
    if (n[winner] >= this.c.roundsToWin) return { ...n, over: true };
    const starter = other(s.starter);
    const { value, rng } = withRng(s.rng, (r) => this.c.minStart + r.nextInt(this.c.maxStart - this.c.minStart + 1));
    return { ...n, round: s.round + 1, starter, turn: starter, left: value, rng };
  }

  aiAction(s: SirkyState, level: number, ai: Prng): SirkyAction {
    const c = this.c;
    const err = c.aiErrorPct[Math.min(Math.max(level, 1), c.aiErrorPct.length) - 1] ?? 0;
    const m = Math.min(c.maxTake, s.left);
    const r = ai.nextInt(100);
    if (r < err) return { by: s.turn, take: 1 + ai.nextInt(m) };
    const t = (s.left - 1) % (c.maxTake + 1);
    return { by: s.turn, take: t >= 1 ? t : 1 };
  }

  result(s: SirkyState): SirkyResult | null {
    if (!s.over) return null;
    const winner: Side = s.player > s.ai ? 'player' : 'ai';
    const stars = winner !== 'player' ? 0 : s.ai <= 2 ? 3 : s.ai === 3 ? 2 : 1;
    return { winner, stars, score: 100 * s.player, player: s.player, ai: s.ai };
  }
}
