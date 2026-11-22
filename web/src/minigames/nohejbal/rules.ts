import { Prng } from '../../rules/prng';
import type { TuningMinigamesNohejbal } from '../../gen/tuning';
import { IllegalAction, withRng, type Rules } from '../rules';
import { duelResult, isInt, scatterShot, type DuelResult, type Side } from '../kulicky/rules';

/** specs/minigames/nohejbal.md, version 1. */
export interface NohejbalConfig {
  halfWidth: number;
  depth: number;
  winPoints: number;
  winBy: number;
  maxPoints: number;
  scatter: number[];
  aiScatter: number[];
  aiReach: number[];
  aiMargin: number[];
  starMargins: number[];
}

export interface NohejbalShot {
  /** Who hit it; "" before the first shot. */
  by: Side | '';
  /** Landing point in the receiver's half (mm, y back from the net). */
  x: number;
  y: number;
  in: boolean;
  /** The receiver got to it (the player always does for a ball in the court). */
  reached: boolean;
}

export interface NohejbalState {
  playerPts: number;
  aiPts: number;
  turn: Side;
  server: Side;
  rally: number;
  lastShot: NohejbalShot;
  over: boolean;
  rng: number;
}

export type NohejbalAction = { by: Side; x: number; y: number; level: number } | { by: 'timeout' };

export function nohejbalConfig(t: TuningMinigamesNohejbal): NohejbalConfig {
  return {
    halfWidth: t.halfWidth,
    depth: t.depth,
    winPoints: t.winPoints,
    winBy: t.winBy,
    maxPoints: t.maxPoints,
    scatter: [...t.scatter],
    aiScatter: [...t.aiScatter],
    aiReach: [...t.aiReach],
    aiMargin: [...t.aiMargin],
    starMargins: [...t.starMargins],
  };
}

/** True once a side has won: winPoints with a winBy lead, or maxPoints outright. */
export function nohejbalOver(c: NohejbalConfig, p: number, a: number): boolean {
  const won = (x: number, y: number): boolean => (x >= c.winPoints && x - y >= c.winBy) || x >= c.maxPoints;
  return won(p, a) || won(a, p);
}

export class NohejbalRules implements Rules<NohejbalState, NohejbalAction, DuelResult, NohejbalConfig> {
  readonly id = 'nohejbal';
  readonly specVersion = 1;
  private cfg: NohejbalConfig | null = null;

  init(config: NohejbalConfig, seed: number): NohejbalState {
    this.cfg = config;
    return {
      playerPts: 0,
      aiPts: 0,
      turn: 'player',
      server: 'player',
      rally: 0,
      lastShot: { by: '', x: 0, y: 0, in: false, reached: false },
      over: false,
      rng: new Prng(seed).state,
    };
  }

  get config(): NohejbalConfig {
    if (!this.cfg) throw new Error('nohejbal: init first');
    return this.cfg;
  }

  /** Actions are continuous; apply checks them. */
  legalActions(): NohejbalAction[] {
    return [];
  }

  apply(s: NohejbalState, a: NohejbalAction): NohejbalState {
    if (s.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s, over: true };
    const c = this.config;
    const table = a.by === 'player' ? c.scatter : c.aiScatter;
    if (
      a.by !== s.turn || !isInt(a.x) || !isInt(a.y) || !isInt(a.level) ||
      a.level < 1 || a.level > table.length || (a.by === 'player' && a.level > c.aiReach.length)
    ) {
      throw new IllegalAction(this.id, a);
    }
    const sc = table[a.level - 1]!;
    const { value: p, rng } = withRng(s.rng, (r) => scatterShot(r, a.x, a.y, sc));
    const inCourt = Math.abs(p.x) <= c.halfWidth && p.y >= 0 && p.y <= c.depth;
    let reached = false;
    if (inCourt) {
      if (a.by === 'player') {
        const reach = c.aiReach[a.level - 1]!;
        const dy = p.y - Math.trunc(c.depth / 2);
        reached = p.x * p.x + dy * dy <= reach * reach;
      } else {
        reached = true;
      }
    }
    const lastShot: NohejbalShot = { by: a.by, x: p.x, y: p.y, in: inCourt, reached };
    const other: Side = a.by === 'player' ? 'ai' : 'player';
    if (reached) return { ...s, lastShot, turn: other, rally: s.rally + 1, rng };
    // Out: point to the receiver; in but out of reach: point to the hitter.
    const winner: Side = inCourt ? a.by : other;
    const playerPts = s.playerPts + (winner === 'player' ? 1 : 0);
    const aiPts = s.aiPts + (winner === 'ai' ? 1 : 0);
    return {
      ...s,
      playerPts,
      aiPts,
      lastShot,
      server: winner,
      turn: winner,
      rally: 0,
      over: nohejbalOver(c, playerPts, aiPts),
      rng,
    };
  }

  /** Aims at one of the four corners of the player's half, kept aiMargin inside the lines. */
  aiAction(_s: NohejbalState, level: number, ai: Prng): NohejbalAction {
    const c = this.config;
    const m = c.aiMargin[level - 1]!;
    const k = ai.nextInt(4);
    const x = (k % 2 === 0 ? -1 : 1) * (c.halfWidth - m);
    const y = k < 2 ? m : c.depth - m;
    return { by: 'ai', x, y, level };
  }

  result(s: NohejbalState): DuelResult | null {
    if (!s.over) return null;
    return duelResult(s.playerPts, s.aiPts, this.config.starMargins);
  }
}
