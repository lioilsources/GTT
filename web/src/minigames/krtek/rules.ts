import { Prng } from '../../rules/prng';
import type { TuningMinigamesKrtek } from '../../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../rules';

/** specs/minigames/krtek.md, version 1. */
export interface KrtekConfig {
  level: number;
  holes: number;
  gameTicks: number;
  firstSpawn: number;
  spawnEvery: number[];
  upTicks: number[];
  goldPct: number;
  bombPct: number[];
  points: number;
  goldPoints: number;
  bombPenalty: number;
  starScores: number[];
}

export type MoleKind = '' | 'mole' | 'gold' | 'bomb';

export interface MoleHole {
  kind: MoleKind;
  left: number;
}

export interface KrtekState {
  tick: number;
  holes: MoleHole[];
  nextSpawn: number;
  score: number;
  hits: number;
  misses: number;
  over: boolean;
  rng: number;
}

export type KrtekAction =
  | { by: 'player'; op: 'tick'; n: number }
  | { by: 'player'; op: 'hit'; hole: number }
  | { by: 'timeout' };

export interface KrtekResult extends RulesResult {
  hits: number;
  misses: number;
}

export function krtekConfig(t: TuningMinigamesKrtek, level: number): KrtekConfig {
  return {
    level,
    holes: t.holes,
    gameTicks: t.gameTicks,
    firstSpawn: t.firstSpawn,
    spawnEvery: [...t.spawnEvery],
    upTicks: [...t.upTicks],
    goldPct: t.goldPct,
    bombPct: [...t.bombPct],
    points: t.points,
    goldPoints: t.goldPoints,
    bombPenalty: t.bombPenalty,
    starScores: [...t.starScores],
  };
}

export class KrtekRules implements Rules<KrtekState, KrtekAction, KrtekResult, KrtekConfig> {
  readonly id = 'krtek';
  readonly specVersion = 1;
  private cfg: KrtekConfig | null = null;

  init(config: KrtekConfig, seed: number): KrtekState {
    this.cfg = config;
    return {
      tick: 0,
      holes: Array.from({ length: config.holes }, () => ({ kind: '' as MoleKind, left: 0 })),
      nextSpawn: config.firstSpawn,
      score: 0,
      hits: 0,
      misses: 0,
      over: false,
      rng: new Prng(seed).state,
    };
  }

  get config(): KrtekConfig {
    if (!this.cfg) throw new Error('krtek: init first');
    return this.cfg;
  }

  legalActions(): KrtekAction[] {
    return [];
  }

  apply(s0: KrtekState, a: KrtekAction): KrtekState {
    if (s0.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s0, over: true };
    if (a.by !== 'player') throw new IllegalAction(this.id, a);
    const c = this.config;
    const s: KrtekState = { ...s0, holes: s0.holes.map((h) => ({ ...h })) };
    if (a.op === 'hit') {
      if (!Number.isInteger(a.hole) || a.hole < 0 || a.hole >= c.holes) throw new IllegalAction(this.id, a);
      const h = s.holes[a.hole]!;
      if (h.kind === 'mole' || h.kind === 'gold') {
        s.score += h.kind === 'gold' ? c.goldPoints : c.points;
        s.hits += 1;
      } else if (h.kind === 'bomb') s.score = Math.max(0, s.score - c.bombPenalty);
      h.kind = '';
      h.left = 0;
      return s;
    }
    if (a.op !== 'tick' || !Number.isInteger(a.n) || a.n < 1) throw new IllegalAction(this.id, a);
    for (let k = 0; k < a.n && !s.over; k++) this.tick(s);
    return s;
  }

  private tick(s: KrtekState): void {
    const c = this.config;
    s.tick += 1;
    for (const h of s.holes) {
      if (h.left <= 0) continue;
      h.left -= 1;
      if (h.left === 0) {
        if (h.kind === 'mole' || h.kind === 'gold') s.misses += 1;
        h.kind = '';
      }
    }
    s.nextSpawn -= 1;
    if (s.nextSpawn === 0) {
      s.nextSpawn = c.spawnEvery[c.level - 1]!;
      const empty = s.holes.map((h, i) => (h.kind === '' ? i : -1)).filter((i) => i >= 0);
      if (empty.length > 0) {
        const r = new Prng(s.rng);
        const h = s.holes[empty[r.nextInt(empty.length)]!]!;
        const roll = r.nextInt(100);
        s.rng = r.state;
        const bomb = c.bombPct[c.level - 1]!;
        h.kind = roll < bomb ? 'bomb' : roll < bomb + c.goldPct ? 'gold' : 'mole';
        h.left = c.upTicks[c.level - 1]!;
      }
    }
    if (s.tick >= c.gameTicks) s.over = true;
  }

  aiAction(): KrtekAction {
    return { by: 'player', op: 'tick', n: 1 };
  }

  result(s: KrtekState): KrtekResult | null {
    if (!s.over) return null;
    const ss = this.config.starScores;
    const stars = s.score >= ss[0]! ? 3 : s.score >= ss[1]! ? 2 : s.score >= ss[2]! ? 1 : 0;
    return { winner: stars >= 1 ? 'player' : 'ai', stars, score: s.score, hits: s.hits, misses: s.misses };
  }
}
