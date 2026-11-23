// Sprint A→B bookkeeping (specs/minigames/sprint.md, version 1): destination pick, checkpoint order,
// time and stars. Pure P0 rules, no DOM, no Babylon: the world says where the car is.
import type { TuningMinigamesSprint } from '../../gen/tuning';
import { Prng } from '../../rules/prng';
import { IllegalAction, withRng, type Rules, type RulesResult } from '../rules';

export interface SprintConfig {
  /** Destination ids in pack order (the Taxi definition). */
  dests: string[];
  level: number;
  parBaseMs: number;
  /** Par average speed (dm/s) by difficulty 1–5. */
  parDmPerS: number[];
  hitPenaltyMs: number;
  /** Time in % of par for 3, 2, 1 stars. */
  starPct: number[];
}

export type SprintPhase = 'pick' | 'ready' | 'run' | 'over';

export interface SprintState {
  rng: number;
  phase: SprintPhase;
  dest: string;
  distDm: number;
  cps: number;
  parMs: number;
  goMs: number;
  clockMs: number;
  passed: number;
  splits: number[];
  hits: number;
  finished: boolean;
  timeMs: number;
}

export type SprintAction =
  | { by: 'player'; op: 'pick'; allow: string[] }
  | { by: 'player'; op: 'go'; atMs: number; distDm: number; cps: number }
  | { by: 'player'; op: 'cp'; atMs: number; index: number }
  | { by: 'player'; op: 'hit'; atMs: number }
  | { by: 'player'; op: 'finish'; atMs: number }
  | { by: 'timeout' };

export interface SprintResult extends RulesResult {
  timeMs: number;
  parMs: number;
  dest: string;
  hits: number;
}

const isInt = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v);
const idiv = (a: number, b: number): number => Math.floor(a / b);

export function sprintConfig(t: TuningMinigamesSprint, dests: readonly string[], level: number): SprintConfig {
  return {
    dests: [...dests],
    level,
    parBaseMs: t.parBaseMs,
    parDmPerS: [...t.parDmPerS],
    hitPenaltyMs: t.hitPenaltyMs,
    starPct: [...t.starPct],
  };
}

/** Par for a route of distDm at the config's level. */
export function sprintPar(c: SprintConfig, distDm: number): number {
  return c.parBaseMs + idiv(distDm * 1000, c.parDmPerS[c.level - 1]!);
}

/** Stars for a finished time against par. */
export function sprintStars(c: SprintConfig, timeMs: number, parMs: number): number {
  for (let i = 0; i < 3; i++) if (timeMs * 100 <= parMs * c.starPct[i]!) return 3 - i;
  return 0;
}

export class SprintRules implements Rules<SprintState, SprintAction, SprintResult, SprintConfig> {
  readonly id = 'sprint';
  readonly specVersion = 1;
  private cfg: SprintConfig | null = null;

  get config(): SprintConfig {
    if (!this.cfg) throw new Error('sprint: init first');
    return this.cfg;
  }

  init(config: SprintConfig, seed: number): SprintState {
    this.cfg = config;
    return {
      rng: new Prng(seed).state, phase: 'pick', dest: '', distDm: 0, cps: 0, parMs: 0, goMs: 0, clockMs: 0, passed: 0,
      splits: [], hits: 0, finished: false, timeMs: 0,
    };
  }

  legalActions(s: SprintState): SprintAction[] {
    switch (s.phase) {
      case 'pick':
        return [{ by: 'player', op: 'pick', allow: [] }, { by: 'timeout' }];
      case 'ready':
        return [{ by: 'player', op: 'go', atMs: s.clockMs, distDm: 0, cps: 0 }, { by: 'timeout' }];
      case 'run': {
        const out: SprintAction[] = [];
        if (s.passed < s.cps) out.push({ by: 'player', op: 'cp', atMs: s.clockMs, index: s.passed });
        out.push({ by: 'player', op: 'hit', atMs: s.clockMs });
        if (s.passed === s.cps) out.push({ by: 'player', op: 'finish', atMs: s.clockMs });
        out.push({ by: 'timeout' });
        return out;
      }
      default:
        return [];
    }
  }

  apply(s: SprintState, a: SprintAction): SprintState {
    if (s.phase === 'over') throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s, phase: 'over' };
    if (a.by !== 'player') throw new IllegalAction(this.id, a);
    const c = this.config;
    if (a.op === 'pick') {
      if (s.phase !== 'pick' || !Array.isArray(a.allow) || a.allow.some((d) => typeof d !== 'string' || !c.dests.includes(d))) throw new IllegalAction(this.id, a);
      const pool = a.allow.length === 0 ? [...c.dests] : c.dests.filter((d) => a.allow.includes(d));
      if (pool.length === 0) return { ...s, phase: 'over', finished: false };
      const { value, rng } = withRng(s.rng, (r) => pool[r.nextInt(pool.length)]!);
      return { ...s, rng, dest: value, phase: 'ready' };
    }
    if (!isInt(a.atMs) || a.atMs < s.clockMs) throw new IllegalAction(this.id, a);
    switch (a.op) {
      case 'go':
        if (s.phase !== 'ready' || !isInt(a.distDm) || a.distDm < 0 || !isInt(a.cps) || a.cps < 0) throw new IllegalAction(this.id, a);
        return { ...s, goMs: a.atMs, clockMs: a.atMs, distDm: a.distDm, cps: a.cps, parMs: sprintPar(c, a.distDm), phase: 'run' };
      case 'cp':
        if (s.phase !== 'run' || a.index !== s.passed || s.passed >= s.cps) throw new IllegalAction(this.id, a);
        return { ...s, clockMs: a.atMs, passed: s.passed + 1, splits: [...s.splits, a.atMs - s.goMs] };
      case 'hit':
        if (s.phase !== 'run') throw new IllegalAction(this.id, a);
        return { ...s, clockMs: a.atMs, hits: s.hits + 1 };
      case 'finish':
        if (s.phase !== 'run' || s.passed !== s.cps) throw new IllegalAction(this.id, a);
        return { ...s, clockMs: a.atMs, timeMs: a.atMs - s.goMs + s.hits * c.hitPenaltyMs, finished: true, phase: 'over' };
      default:
        throw new IllegalAction(this.id, a);
    }
  }

  aiAction(_s: SprintState, _level: number, _ai: Prng): SprintAction {
    throw new Error('sprint: no opponent');
  }

  result(s: SprintState): SprintResult | null {
    if (s.phase !== 'over') return null;
    const c = this.config;
    const stars = s.finished ? sprintStars(c, s.timeMs, s.parMs) : 0;
    const score = s.finished ? idiv(Math.max(0, 2 * s.parMs - s.timeMs), 100) : 0;
    return { winner: stars >= 1 ? 'player' : 'draw', stars, score, timeMs: s.timeMs, parMs: s.parMs, dest: s.dest, hits: s.hits };
  }
}
