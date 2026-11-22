import { Prng } from '../../rules/prng';
import type { TuningMinigamesKulicky } from '../../gen/tuning';
import { IllegalAction, withRng, type Rules, type RulesResult } from '../rules';

/** specs/minigames/kulicky.md, version 1. */
export interface KulickyConfig {
  rounds: number;
  holeR: number;
  holePoints: number;
  closerPoints: number;
  scatter: number[];
  aiScatter: number[];
  starMargins: number[];
}

export type Side = 'player' | 'ai';

export interface KulickyShot {
  x: number;
  y: number;
  inHole: boolean;
}

export interface KulickyState {
  round: number;
  turn: Side;
  playerPts: number;
  aiPts: number;
  playerShot: KulickyShot;
  aiShot: KulickyShot;
  over: boolean;
  rng: number;
}

export type KulickyAction = { by: Side; x: number; y: number; level: number } | { by: 'timeout' };

export interface DuelResult extends RulesResult {
  playerPts: number;
  aiPts: number;
}

export function kulickyConfig(t: TuningMinigamesKulicky): KulickyConfig {
  return {
    rounds: t.rounds,
    holeR: t.holeR,
    holePoints: t.holePoints,
    closerPoints: t.closerPoints,
    scatter: [...t.scatter],
    aiScatter: [...t.aiScatter],
    starMargins: [...t.starMargins],
  };
}

export const isInt = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v);

/** Result shared by the two-sided point games (Kuličky, Čára, Nohejbal): stars by the lead. */
export function duelResult(playerPts: number, aiPts: number, starMargins: number[]): DuelResult {
  const margin = playerPts - aiPts;
  const winner = margin > 0 ? 'player' : margin < 0 ? 'ai' : 'draw';
  let stars = 0;
  for (let i = 0; i < starMargins.length && i < 3; i++) {
    if (margin >= starMargins[i]!) {
      stars = 3 - i;
      break;
    }
  }
  return { winner, stars, score: playerPts, playerPts, aiPts };
}

/** Landing point: x then y scatter from the state rng (spec "Cvrnk"). */
export function scatterShot(r: Prng, x: number, y: number, s: number): { x: number; y: number } {
  const lx = x + r.nextInt(2 * s + 1) - s;
  const ly = y + r.nextInt(2 * s + 1) - s;
  return { x: lx, y: ly };
}

export class KulickyRules implements Rules<KulickyState, KulickyAction, DuelResult, KulickyConfig> {
  readonly id = 'kulicky';
  readonly specVersion = 1;
  private cfg: KulickyConfig | null = null;

  init(config: KulickyConfig, seed: number): KulickyState {
    this.cfg = config;
    const empty = { x: 0, y: 0, inHole: false };
    return { round: 1, turn: 'player', playerPts: 0, aiPts: 0, playerShot: { ...empty }, aiShot: { ...empty }, over: false, rng: new Prng(seed).state };
  }

  get config(): KulickyConfig {
    if (!this.cfg) throw new Error('kulicky: init first');
    return this.cfg;
  }

  /** Actions are continuous; apply checks them. */
  legalActions(): KulickyAction[] {
    return [];
  }

  apply(s: KulickyState, a: KulickyAction): KulickyState {
    if (s.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s, over: true };
    const c = this.config;
    const table = a.by === 'player' ? c.scatter : c.aiScatter;
    if (a.by !== s.turn || !isInt(a.x) || !isInt(a.y) || !isInt(a.level) || a.level < 1 || a.level > table.length) {
      throw new IllegalAction(this.id, a);
    }
    const sc = table[a.level - 1]!;
    const { value: p, rng } = withRng(s.rng, (r) => scatterShot(r, a.x, a.y, sc));
    const shot: KulickyShot = { x: p.x, y: p.y, inHole: p.x * p.x + p.y * p.y <= c.holeR * c.holeR };
    if (a.by === 'player') return { ...s, playerShot: shot, turn: 'ai', rng };
    const ps = s.playerShot;
    let playerPts = s.playerPts, aiPts = s.aiPts;
    if (ps.inHole) playerPts += c.holePoints;
    if (shot.inHole) aiPts += c.holePoints;
    if (!ps.inHole && !shot.inHole) {
      const dp = ps.x * ps.x + ps.y * ps.y, da = shot.x * shot.x + shot.y * shot.y;
      if (dp < da) playerPts += c.closerPoints;
      else if (da < dp) aiPts += c.closerPoints;
    }
    const round = s.round + 1;
    return { ...s, aiShot: shot, playerPts, aiPts, round, turn: 'player', over: round > c.rounds, rng };
  }

  /** Aims straight at the hole; accuracy comes from aiScatter. Does not use the ai stream. */
  aiAction(_s: KulickyState, level: number): KulickyAction {
    return { by: 'ai', x: 0, y: 0, level };
  }

  result(s: KulickyState): DuelResult | null {
    if (!s.over) return null;
    return duelResult(s.playerPts, s.aiPts, this.config.starMargins);
  }
}
