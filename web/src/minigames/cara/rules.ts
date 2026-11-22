import { Prng } from '../../rules/prng';
import type { TuningMinigamesCara } from '../../gen/tuning';
import { IllegalAction, withRng, type Rules } from '../rules';
import { duelResult, isInt, type DuelResult, type Side } from '../kulicky/rules';

/** specs/minigames/cara.md, version 1. */
export interface CaraConfig {
  rounds: number;
  linePoints: number;
  roundPoints: number;
  scatter: number[];
  aiScatter: number[];
  aiAim: number[];
  starMargins: number[];
}

export interface CaraCoin {
  /** Distance from the line in mm, negative short of it. */
  y: number;
  /** Over the line (y > 0). */
  burnt: boolean;
}

export interface CaraState {
  round: number;
  turn: Side;
  playerPts: number;
  aiPts: number;
  playerCoin: CaraCoin;
  aiCoin: CaraCoin;
  over: boolean;
  rng: number;
}

export type CaraAction = { by: Side; y: number; level: number } | { by: 'timeout' };

export function caraConfig(t: TuningMinigamesCara): CaraConfig {
  return {
    rounds: t.rounds,
    linePoints: t.linePoints,
    roundPoints: t.roundPoints,
    scatter: [...t.scatter],
    aiScatter: [...t.aiScatter],
    aiAim: [...t.aiAim],
    starMargins: [...t.starMargins],
  };
}

export class CaraRules implements Rules<CaraState, CaraAction, DuelResult, CaraConfig> {
  readonly id = 'cara';
  readonly specVersion = 1;
  private cfg: CaraConfig | null = null;

  init(config: CaraConfig, seed: number): CaraState {
    this.cfg = config;
    return {
      round: 1,
      turn: 'player',
      playerPts: 0,
      aiPts: 0,
      playerCoin: { y: 0, burnt: false },
      aiCoin: { y: 0, burnt: false },
      over: false,
      rng: new Prng(seed).state,
    };
  }

  get config(): CaraConfig {
    if (!this.cfg) throw new Error('cara: init first');
    return this.cfg;
  }

  /** Actions are continuous; apply checks them. */
  legalActions(): CaraAction[] {
    return [];
  }

  apply(s: CaraState, a: CaraAction): CaraState {
    if (s.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s, over: true };
    const c = this.config;
    const table = a.by === 'player' ? c.scatter : c.aiScatter;
    if (a.by !== s.turn || !isInt(a.y) || !isInt(a.level) || a.level < 1 || a.level > table.length) {
      throw new IllegalAction(this.id, a);
    }
    const sc = table[a.level - 1]!;
    const { value: y, rng } = withRng(s.rng, (r) => a.y + r.nextInt(2 * sc + 1) - sc);
    const coin: CaraCoin = { y, burnt: y > 0 };
    if (a.by === 'player') return { ...s, playerCoin: coin, turn: 'ai', rng };
    const pc = s.playerCoin;
    let playerPts = s.playerPts, aiPts = s.aiPts;
    if (pc.y === 0 || coin.y === 0) {
      // A coin right on the line scores linePoints; both may. No round point then.
      if (pc.y === 0) playerPts += c.linePoints;
      if (coin.y === 0) aiPts += c.linePoints;
    } else if (!pc.burnt && (coin.burnt || pc.y > coin.y)) {
      playerPts += c.roundPoints;
    } else if (!coin.burnt && (pc.burnt || coin.y > pc.y)) {
      aiPts += c.roundPoints;
    }
    const round = s.round + 1;
    return { ...s, aiCoin: coin, playerPts, aiPts, round, turn: 'player', over: round > c.rounds, rng };
  }

  /** The better the rival, the closer to the line it aims. Does not use the ai stream. */
  aiAction(_s: CaraState, level: number): CaraAction {
    return { by: 'ai', y: -this.config.aiAim[level - 1]!, level };
  }

  result(s: CaraState): DuelResult | null {
    if (!s.over) return null;
    return duelResult(s.playerPts, s.aiPts, this.config.starMargins);
  }
}
