import { Prng } from '../../rules/prng';
import type { TuningMinigamesKoulena } from '../../gen/tuning';
import { IllegalAction, withRng, type Rules, type RulesResult } from '../rules';

/** specs/minigames/koulena.md, version 1. */
export interface KoulenaConfig {
  series: number;
  balls: number;
  ringR: number[];
  ringPoints: number[];
  /** Pocket centres as x, y pairs. */
  pockets: number[];
  pocketR: number;
  pocketPoints: number;
  scatter: number[];
  starScores: number[];
}

export interface KoulenaHit {
  x: number;
  y: number;
  points: number;
}

export interface KoulenaState {
  series: number;
  ball: number;
  score: number;
  seriesScores: number[];
  lastHit: KoulenaHit;
  over: boolean;
  rng: number;
}

export type KoulenaAction = { by: 'player'; x: number; y: number; level: number } | { by: 'timeout' };

export interface KoulenaResult extends RulesResult {
  seriesScores: number[];
}

export function koulenaConfig(t: TuningMinigamesKoulena): KoulenaConfig {
  return {
    series: t.series,
    balls: t.balls,
    ringR: [...t.ringR],
    ringPoints: [...t.ringPoints],
    pockets: [...t.pockets],
    pocketR: t.pocketR,
    pocketPoints: t.pocketPoints,
    scatter: [...t.scatter],
    starScores: [...t.starScores],
  };
}

/** Points for a landing point: pockets first (config order), then the first ring that holds it. */
export function koulenaPoints(c: KoulenaConfig, x: number, y: number): number {
  for (let i = 0; i + 1 < c.pockets.length; i += 2) {
    const dx = x - c.pockets[i]!, dy = y - c.pockets[i + 1]!;
    if (dx * dx + dy * dy <= c.pocketR * c.pocketR) return c.pocketPoints;
  }
  const d2 = x * x + y * y;
  for (let i = 0; i < c.ringR.length; i++) {
    if (d2 <= c.ringR[i]! * c.ringR[i]!) return c.ringPoints[i] ?? 0;
  }
  return 0;
}

const isInt = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v);

export class KoulenaRules implements Rules<KoulenaState, KoulenaAction, KoulenaResult, KoulenaConfig> {
  readonly id = 'koulena';
  readonly specVersion = 1;
  private cfg: KoulenaConfig | null = null;

  init(config: KoulenaConfig, seed: number): KoulenaState {
    this.cfg = config;
    return { series: 1, ball: 0, score: 0, seriesScores: [], lastHit: { x: 0, y: 0, points: 0 }, over: false, rng: new Prng(seed).state };
  }

  get config(): KoulenaConfig {
    if (!this.cfg) throw new Error('koulena: init first');
    return this.cfg;
  }

  /** Actions are continuous; apply checks them. */
  legalActions(): KoulenaAction[] {
    return [];
  }

  apply(s: KoulenaState, a: KoulenaAction): KoulenaState {
    if (s.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s, over: true };
    const c = this.config;
    if (a.by !== 'player' || !isInt(a.x) || !isInt(a.y) || !isInt(a.level) || a.level < 1 || a.level > c.scatter.length) {
      throw new IllegalAction(this.id, a);
    }
    const sc = c.scatter[a.level - 1]!;
    const { value: hit, rng } = withRng(s.rng, (r) => {
      const x = a.x + r.nextInt(2 * sc + 1) - sc;
      const y = a.y + r.nextInt(2 * sc + 1) - sc;
      return { x, y, points: koulenaPoints(c, x, y) };
    });
    const score = s.score + hit.points;
    const n: KoulenaState = { ...s, score, lastHit: hit, ball: s.ball + 1, rng };
    if (n.ball < c.balls) return n;
    const closed = s.seriesScores.reduce((a2, b) => a2 + b, 0);
    const seriesScores = [...s.seriesScores, score - closed];
    return { ...n, seriesScores, series: s.series + 1, ball: 0, over: s.series >= c.series };
  }

  /** No opponent: the contract still wants one, it aims at the centre with level 3. */
  aiAction(): KoulenaAction {
    return { by: 'player', x: 0, y: 0, level: 3 };
  }

  result(s: KoulenaState): KoulenaResult | null {
    if (!s.over) return null;
    const t = this.config.starScores;
    const stars = s.score >= t[0]! ? 3 : s.score >= t[1]! ? 2 : s.score >= t[2]! ? 1 : 0;
    return { winner: stars >= 1 ? 'player' : 'ai', stars, score: s.score, seriesScores: [...s.seriesScores] };
  }
}
