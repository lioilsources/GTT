import { Prng } from '../../rules/prng';
import type { TuningMinigamesKviz } from '../../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../rules';

/** specs/minigames/kviz.md, version 1. `bank` = correct option indices in bank order. */
export interface KvizConfig {
  bank: number[];
  rounds: number;
  starCorrect: number[];
}

export interface KvizState {
  order: number[];
  perms: number[][];
  cur: number;
  correct: number;
  answers: number[];
  over: boolean;
  rng: number;
}

/** answer = shown option index 0-3, -1 = the question timer ran out. */
export type KvizAction = { by: 'player'; answer: number } | { by: 'timeout' };

export interface KvizResult extends RulesResult {
  correct: number;
  rounds: number;
}

export function kvizConfig(t: TuningMinigamesKviz, bank: number[]): KvizConfig {
  return { bank: [...bank], rounds: t.rounds, starCorrect: [...t.starCorrect] };
}

/** One question of content/quiz/<city>.json (written by `metro sync`). */
export interface QuizQuestion {
  id: string;
  q: { en: string; cs: string };
  options: { en: string[]; cs: string[] };
  answer: number;
}

export interface QuizBank {
  questions: QuizQuestion[];
}

export class KvizRules implements Rules<KvizState, KvizAction, KvizResult, KvizConfig> {
  readonly id = 'kviz';
  readonly specVersion = 1;
  private cfg: KvizConfig | null = null;

  init(config: KvizConfig, seed: number): KvizState {
    this.cfg = config;
    const rng = new Prng(seed);
    const n = config.bank.length;
    const R = Math.min(config.rounds, n);
    const idx = Array.from({ length: n }, (_, i) => i);
    for (let i = 0; i < R; i++) {
      const j = i + rng.nextInt(n - i);
      const t = idx[i]!;
      idx[i] = idx[j]!;
      idx[j] = t;
    }
    const order = idx.slice(0, R);
    const perms = order.map(() => {
      const p = [0, 1, 2, 3];
      for (let i = 3; i >= 1; i--) {
        const j = rng.nextInt(i + 1);
        const t = p[i]!;
        p[i] = p[j]!;
        p[j] = t;
      }
      return p;
    });
    return { order, perms, cur: 0, correct: 0, answers: [], over: R === 0, rng: rng.state };
  }

  private get c(): KvizConfig {
    if (!this.cfg) throw new Error('kviz: init first');
    return this.cfg;
  }

  legalActions(s: KvizState): KvizAction[] {
    if (s.over) return [];
    return [0, 1, 2, 3, -1].map((answer) => ({ by: 'player', answer }));
  }

  /** True when shown option `d` of the current question is the right one. */
  isRight(s: KvizState, d: number): boolean {
    return d >= 0 && s.perms[s.cur]![d] === this.c.bank[s.order[s.cur]!];
  }

  apply(s: KvizState, a: KvizAction): KvizState {
    if (s.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s, over: true };
    if (a.by !== 'player' || !Number.isInteger(a.answer) || a.answer < -1 || a.answer > 3) throw new IllegalAction(this.id, a);
    const correct = this.isRight(s, a.answer) ? s.correct + 1 : s.correct;
    const cur = s.cur + 1;
    return { ...s, cur, correct, answers: [...s.answers, a.answer], over: cur >= s.order.length };
  }

  aiAction(): KvizAction {
    throw new Error('kviz: no opponent');
  }

  result(s: KvizState): KvizResult | null {
    if (!s.over) return null;
    const c = this.c;
    const R = s.order.length;
    const need = c.starCorrect.map((t) => (R < c.rounds ? Math.trunc((t * R) / c.rounds) : t));
    let stars = 0;
    for (let k = 0; k < need.length; k++) {
      if (s.correct >= need[k]!) {
        stars = need.length - k;
        break;
      }
    }
    return { winner: stars >= 1 ? 'player' : 'ai', stars, score: s.correct * 100, correct: s.correct, rounds: R };
  }
}
