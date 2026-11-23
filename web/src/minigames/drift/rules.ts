// Drift zone scoring (specs/minigames/drift.md, version 1): pure P0 rules over integer samples the
// world sends; no DOM, no Babylon, no randomness.
import type { TuningMinigamesDrift } from '../../gen/tuning';
import type { Prng } from '../../rules/prng';
import { IllegalAction, type Rules, type RulesResult } from '../rules';

export interface DriftConfig {
  level: number;
  minSlipMrad: number;
  maxSlipMrad: number;
  minSpeedCms: number;
  maxSpeedCms: number;
  ptsDiv: number;
  maxDtMs: number;
  graceMs: number;
  multStepMs: number;
  maxMult: number;
  /** Scores for 3, 2, 1 stars at difficulty 3. */
  starScores: number[];
  /** Star thresholds × % by difficulty 1–5. */
  levelPct: number[];
}

export interface DriftState {
  phase: 'run' | 'over';
  clockMs: number;
  lastDriftMs: number;
  score: number;
  chain: number;
  chainMs: number;
  mult: number;
  best: number;
  drifts: number;
  hits: number;
}

export type DriftAction =
  | { by: 'player'; op: 'sample'; atMs: number; slipMrad: number; speedCms: number; inZone: boolean }
  | { by: 'player'; op: 'hit'; atMs: number }
  | { by: 'timeout' };

export interface DriftResult extends RulesResult {
  best: number;
  drifts: number;
  hits: number;
}

const isInt = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v);
const idiv = (a: number, b: number): number => Math.floor(a / b);

export function driftConfig(t: TuningMinigamesDrift, level: number): DriftConfig {
  return {
    level,
    minSlipMrad: t.minSlipMrad,
    maxSlipMrad: t.maxSlipMrad,
    minSpeedCms: t.minSpeedCms,
    maxSpeedCms: t.maxSpeedCms,
    ptsDiv: t.ptsDiv,
    maxDtMs: t.maxDtMs,
    graceMs: t.graceMs,
    multStepMs: t.multStepMs,
    maxMult: t.maxMult,
    starScores: [...t.starScores],
    levelPct: [...t.levelPct],
  };
}

/** Star thresholds t[0..2] for the config's level. */
export function driftThresholds(c: DriftConfig): number[] {
  const pct = c.levelPct[c.level - 1]!;
  return c.starScores.map((s) => idiv(s * pct, 100));
}

/** Banks the open chain into the score (spec "Připsání"). */
function bank(s: DriftState): void {
  const b = s.chain * s.mult;
  s.score += b;
  s.best = Math.max(s.best, b);
  s.drifts += 1;
  s.chain = 0;
  s.chainMs = 0;
  s.mult = 1;
}

export class DriftRules implements Rules<DriftState, DriftAction, DriftResult, DriftConfig> {
  readonly id = 'drift';
  readonly specVersion = 1;
  private cfg: DriftConfig | null = null;

  get config(): DriftConfig {
    if (!this.cfg) throw new Error('drift: init first');
    return this.cfg;
  }

  init(config: DriftConfig): DriftState {
    this.cfg = config;
    return { phase: 'run', clockMs: 0, lastDriftMs: 0, score: 0, chain: 0, chainMs: 0, mult: 1, best: 0, drifts: 0, hits: 0 };
  }

  legalActions(s: DriftState): DriftAction[] {
    if (s.phase !== 'run') return [];
    return [{ by: 'player', op: 'sample', atMs: s.clockMs, slipMrad: 0, speedCms: 0, inZone: false }, { by: 'timeout' }];
  }

  apply(s0: DriftState, a: DriftAction): DriftState {
    if (s0.phase !== 'run') throw new IllegalAction(this.id, a);
    const s: DriftState = { ...s0 };
    if (a.by === 'timeout') {
      if (s.chain > 0) bank(s);
      s.phase = 'over';
      return s;
    }
    if (a.by !== 'player' || !isInt(a.atMs) || a.atMs < s.clockMs) throw new IllegalAction(this.id, a);
    const c = this.config;
    if (a.op === 'hit') {
      s.clockMs = a.atMs;
      s.hits += 1;
      s.chain = 0;
      s.chainMs = 0;
      s.mult = 1;
      return s;
    }
    if (a.op !== 'sample' || !isInt(a.slipMrad) || a.slipMrad < 0 || !isInt(a.speedCms) || a.speedCms < 0 || typeof a.inZone !== 'boolean') {
      throw new IllegalAction(this.id, a);
    }
    const dt = Math.min(a.atMs - s.clockMs, c.maxDtMs);
    s.clockMs = a.atMs;
    if (a.inZone && a.slipMrad >= c.minSlipMrad && a.speedCms >= c.minSpeedCms) {
      const ang = idiv(dt * Math.min(a.slipMrad, c.maxSlipMrad), 1000);
      const pts = idiv(ang * Math.min(a.speedCms, c.maxSpeedCms), c.ptsDiv);
      s.chain += pts;
      s.chainMs += dt;
      s.mult = Math.min(1 + idiv(s.chainMs, c.multStepMs), c.maxMult);
      s.lastDriftMs = a.atMs;
    } else if (s.chain > 0 && a.atMs - s.lastDriftMs > c.graceMs) {
      bank(s);
    }
    return s;
  }

  aiAction(_s: DriftState, _level: number, _ai: Prng): DriftAction {
    throw new Error('drift: no opponent');
  }

  result(s: DriftState): DriftResult | null {
    if (s.phase !== 'over') return null;
    const t = driftThresholds(this.config);
    const stars = s.score >= t[0]! ? 3 : s.score >= t[1]! ? 2 : s.score >= t[2]! ? 1 : 0;
    return { winner: stars >= 1 ? 'player' : 'draw', stars, score: s.score, best: s.best, drifts: s.drifts, hits: s.hits };
  }
}
