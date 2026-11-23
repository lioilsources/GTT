import { Prng } from '../../rules/prng';
import type { TuningMinigamesKostky } from '../../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../rules';

/** specs/minigames/kostky.md, version 1. */
export interface KostkyConfig {
  bonusAt: number;
  bonus: number;
  aiErrorPct: number[];
  starMargins: number[];
}

export type Side = 'player' | 'ai';

export interface KostkyState {
  player: number[];
  ai: number[];
  turn: Side;
  round: number;
  dice: number[];
  rolls: number;
  over: boolean;
  rng: number;
}

export type KostkyAction =
  | { by: Side; op: 'roll'; keep: number[] }
  | { by: Side; op: 'score'; cat: number }
  | { by: 'timeout' };

export interface KostkyResult extends RulesResult {
  player: number;
  ai: number;
}

export function kostkyConfig(t: TuningMinigamesKostky): KostkyConfig {
  return { bonusAt: t.bonusAt, bonus: t.bonus, aiErrorPct: [...t.aiErrorPct], starMargins: [...t.starMargins] };
}

export const CATS = 13;
export const SMALL = 9;
export const LARGE = 10;
export const FULL = 8;
export const POKER = 11;
export const CHANCE = 12;
/** What an empty category is worth giving up (spec "AI", step 3). */
const POT = [5, 10, 15, 20, 25, 30, 30, 30, 25, 30, 40, 50, 30];

/** n[v] = dice showing v (index 0 unused). */
export function counts(dice: readonly number[]): number[] {
  const n = [0, 0, 0, 0, 0, 0, 0];
  for (const d of dice) n[d]!++;
  return n;
}

const hasRun = (n: number[], from: number, len: number): boolean => {
  for (let v = from; v < from + len; v++) if (n[v] === 0) return false;
  return true;
};

/** Value of category `cat` for five dice (spec "Kolonky"). */
export function catValue(cat: number, dice: readonly number[]): number {
  const n = counts(dice);
  const sum = dice.reduce((a, b) => a + b, 0);
  const max = Math.max(...n.slice(1));
  if (cat <= 5) return (cat + 1) * n[cat + 1]!;
  switch (cat) {
    case 6: return max >= 3 ? sum : 0;
    case 7: return max >= 4 ? sum : 0;
    case FULL: {
      const nz = n.slice(1).filter((x) => x > 0).sort();
      return nz.length === 2 && nz[0] === 2 && nz[1] === 3 ? 25 : 0;
    }
    case SMALL: return hasRun(n, 1, 4) || hasRun(n, 2, 4) || hasRun(n, 3, 4) ? 30 : 0;
    case LARGE: return hasRun(n, 1, 5) || hasRun(n, 2, 5) ? 40 : 0;
    case POKER: return max === 5 ? 50 : 0;
    default: return sum;
  }
}

/** Written categories plus the upper bonus. */
export function total(table: readonly number[], c: KostkyConfig): number {
  const v = table.map((x) => Math.max(0, x));
  const upper = v.slice(0, 6).reduce((a, b) => a + b, 0);
  return v.reduce((a, b) => a + b, 0) + (upper >= c.bonusAt ? c.bonus : 0);
}

export const upperSum = (table: readonly number[]): number => table.slice(0, 6).reduce((a, b) => a + Math.max(0, b), 0);

export class KostkyRules implements Rules<KostkyState, KostkyAction, KostkyResult, KostkyConfig> {
  readonly id = 'kostky';
  readonly specVersion = 1;
  private cfg: KostkyConfig | null = null;

  private get c(): KostkyConfig {
    if (!this.cfg) throw new Error('kostky: init first');
    return this.cfg;
  }

  init(config: KostkyConfig, seed: number): KostkyState {
    this.cfg = config;
    return {
      player: Array(CATS).fill(-1), ai: Array(CATS).fill(-1), turn: 'player', round: 1, dice: [], rolls: 0,
      over: false, rng: new Prng(seed).state,
    };
  }

  legalActions(s: KostkyState): KostkyAction[] {
    if (s.over) return [];
    const by = s.turn;
    if (s.rolls === 0) return [{ by, op: 'roll', keep: [] }];
    const out: KostkyAction[] = [];
    if (s.rolls < 3) {
      for (let m = 0; m < 31; m++) out.push({ by, op: 'roll', keep: [0, 1, 2, 3, 4].filter((i) => m & (1 << i)) });
    }
    s[by].forEach((v, cat) => v < 0 && out.push({ by, op: 'score', cat }));
    return out;
  }

  apply(s: KostkyState, a: KostkyAction): KostkyState {
    if (s.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s, over: true };
    if (a.by !== s.turn) throw new IllegalAction(this.id, a);
    if (a.op === 'roll') {
      const keep = a.keep;
      const ok = s.rolls === 0
        ? keep.length === 0
        : s.rolls < 3 && keep.length < 5 && keep.every((k, i) => Number.isInteger(k) && k >= 0 && k < 5 && (i === 0 || k > keep[i - 1]!));
      if (!ok) throw new IllegalAction(this.id, a);
      const r = new Prng(s.rng);
      const dice = [0, 1, 2, 3, 4].map((i) => (s.rolls > 0 && keep.includes(i) ? s.dice[i]! : 0));
      for (let i = 0; i < 5; i++) if (dice[i] === 0) dice[i] = r.nextInt(6) + 1;
      return { ...s, dice, rolls: s.rolls + 1, rng: r.state };
    }
    if (a.op !== 'score' || s.rolls === 0 || !(a.cat >= 0 && a.cat < CATS) || s[s.turn][a.cat] !== -1) throw new IllegalAction(this.id, a);
    const table = [...s[s.turn]];
    table[a.cat] = catValue(a.cat, s.dice);
    const n: KostkyState = { ...s, [s.turn]: table, dice: [], rolls: 0, turn: s.turn === 'player' ? 'ai' : 'player' };
    if (s.turn === 'ai') {
      n.round = s.round + 1;
      if (table.every((v) => v >= 0)) n.over = true;
    }
    return n;
  }

  /** Step 3: the free category with the highest val (ties → lower index). */
  private pick(s: KostkyState, level: number): number {
    const n = counts(s.dice);
    let best = -1;
    let bv = -Infinity;
    for (let i = 0; i < CATS; i++) {
      if (s.ai[i] !== -1) continue;
      const h = catValue(i, s.dice);
      let val: number;
      if (h > 0) {
        val = 10 * h;
        if (level >= 3 && i <= 5 && n[i + 1]! >= 3) val += 50;
        if (level >= 3 && i === CHANCE) val -= 50;
      } else val = -POT[i]!;
      if (val > bv) {
        bv = val;
        best = i;
      }
    }
    return best;
  }

  /** Dice to keep for the next roll (spec "AI", step 2), indices ascending. */
  aiKeep(dice: readonly number[], t: readonly number[], level: number): number[] {
    const n = counts(dice);
    let f = 6;
    for (let v = 5; v >= 1; v--) if (n[v]! > n[f]!) f = v;
    const c = n[f]!;
    const withF = (): number[] => dice.flatMap((d, i) => (d === f ? [i] : []));
    if (c >= 3) return withF();
    if (level >= 3 && (t[SMALL] === -1 || t[LARGE] === -1)) {
      let bestLen = 0, bestEnd = 0;
      for (let v = 1, len = 0; v <= 6; v++) {
        len = n[v]! > 0 ? len + 1 : 0;
        if (len >= bestLen && len > 0) {
          bestLen = len;
          bestEnd = v;
        }
      }
      if (bestLen >= 3) {
        const keep: number[] = [];
        for (let v = bestEnd - bestLen + 1; v <= bestEnd; v++) keep.push(dice.indexOf(v));
        return keep.sort((a, b) => a - b);
      }
    }
    if (c === 2) return withF();
    return [];
  }

  aiAction(s: KostkyState, level: number, ai: Prng): KostkyAction {
    const legal = this.legalActions(s);
    if (s.turn !== 'ai' || legal.length === 0) throw new IllegalAction(this.id, { by: 'ai' });
    const err = this.c.aiErrorPct[level - 1] ?? 0;
    if (ai.nextInt(100) < err) return legal[ai.nextInt(legal.length)]!;
    if (s.rolls === 0) return { by: 'ai', op: 'roll', keep: [] };
    const score = (): KostkyAction => ({ by: 'ai', op: 'score', cat: this.pick(s, level) });
    if (s.rolls === 3) return score();
    const t = s.ai;
    const n = counts(s.dice);
    if (
      (t[POKER] === -1 && n.includes(5)) ||
      (t[LARGE] === -1 && catValue(LARGE, s.dice) > 0) ||
      (t[FULL] === -1 && catValue(FULL, s.dice) > 0) ||
      (t[SMALL] === -1 && t[LARGE] !== -1 && catValue(SMALL, s.dice) > 0)
    ) return score();
    const keep = this.aiKeep(s.dice, t, level);
    return keep.length === 5 ? score() : { by: 'ai', op: 'roll', keep };
  }

  result(s: KostkyState): KostkyResult | null {
    if (!s.over) return null;
    const p = total(s.player, this.c), a = total(s.ai, this.c);
    const winner = p > a ? 'player' : p < a ? 'ai' : 'draw';
    const m = this.c.starMargins;
    const stars = winner !== 'player' ? 0 : p - a >= m[0]! ? 3 : p - a >= m[1]! ? 2 : 1;
    return { winner, stars, score: p, player: p, ai: a };
  }
}
