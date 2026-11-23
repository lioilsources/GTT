// Double Dutch (specs/minigames/doubledutch.md, version 1), the first engine `rhythm` game: the chart
// is drawn at init, each beat is judged by the timing error the UI measures. Pure P0 rules.
import type { TuningMinigamesDoubledutch } from '../../gen/tuning';
import { Prng } from '../../rules/prng';
import { IllegalAction, type Rules, type RulesResult } from '../rules';

export interface DoubledutchConfig {
  level: number;
  beats: number;
  introBeats: number;
  startGapMs: number[];
  minGapMs: number[];
  speedupEvery: number;
  speedupMs: number;
  trickPct: number[];
  perfectMs: number;
  goodMs: number;
  okMs: number;
  maxTrips: number;
  perfectPts: number;
  goodPts: number;
  okPts: number;
  trickMult: number;
  comboStep: number;
  maxMult: number;
  starPct: number[];
}

export interface DoubledutchState {
  /** 0 jump (tap), 1 trick (swipe up) per beat. */
  kinds: number[];
  next: number;
  score: number;
  combo: number;
  bestCombo: number;
  trips: number;
  perfect: number;
  good: number;
  ok: number;
  misses: number;
  over: boolean;
  rng: number;
}

export type DoubledutchAction =
  | { by: 'player'; op: 'hit'; input: number; errMs: number }
  | { by: 'player'; op: 'miss' }
  | { by: 'timeout' };

export interface DoubledutchResult extends RulesResult {
  pct: number;
  bestCombo: number;
  misses: number;
}

const isInt = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v);
const idiv = (a: number, b: number): number => Math.floor(a / b);

export function doubledutchConfig(t: TuningMinigamesDoubledutch, level: number): DoubledutchConfig {
  return {
    level,
    beats: t.beats,
    introBeats: t.introBeats,
    startGapMs: [...t.startGapMs],
    minGapMs: [...t.minGapMs],
    speedupEvery: t.speedupEvery,
    speedupMs: t.speedupMs,
    trickPct: [...t.trickPct],
    perfectMs: t.perfectMs,
    goodMs: t.goodMs,
    okMs: t.okMs,
    maxTrips: t.maxTrips,
    perfectPts: t.perfectPts,
    goodPts: t.goodPts,
    okPts: t.okPts,
    trickMult: t.trickMult,
    comboStep: t.comboStep,
    maxMult: t.maxMult,
    starPct: [...t.starPct],
  };
}

/** Gap (ms) from beat i − 1 to beat i ≥ 1 (spec "Rozestupy úderů"). */
export function beatGap(c: DoubledutchConfig, i: number): number {
  const l = c.level - 1;
  return Math.max(c.minGapMs[l]!, c.startGapMs[l]! - idiv(i, c.speedupEvery) * c.speedupMs);
}

/** Beat times (ms from the start) with the first beat at leadInMs. */
export function beatTimes(c: DoubledutchConfig, leadInMs: number): number[] {
  const out: number[] = [];
  for (let i = 0; i < c.beats; i++) out.push(i === 0 ? leadInMs : out[i - 1]! + beatGap(c, i));
  return out;
}

/** Combo multiplier for a combo count. */
const multOf = (c: DoubledutchConfig, combo: number): number => 1 + Math.min(idiv(combo, c.comboStep), c.maxMult - 1);

/** All perfect with an unbroken combo. */
export function doubledutchMax(c: DoubledutchConfig, kinds: readonly number[]): number {
  let m = 0;
  for (let i = 0; i < c.beats; i++) m += c.perfectPts * (kinds[i] === 1 ? c.trickMult : 1) * multOf(c, i + 1);
  return m;
}

export class DoubledutchRules implements Rules<DoubledutchState, DoubledutchAction, DoubledutchResult, DoubledutchConfig> {
  readonly id = 'doubledutch';
  readonly specVersion = 1;
  private cfg: DoubledutchConfig | null = null;

  get config(): DoubledutchConfig {
    if (!this.cfg) throw new Error('doubledutch: init first');
    return this.cfg;
  }

  init(config: DoubledutchConfig, seed: number): DoubledutchState {
    this.cfg = config;
    const r = new Prng(seed);
    const pct = config.trickPct[config.level - 1]!;
    const kinds: number[] = [];
    for (let i = 0; i < config.beats; i++) kinds.push(i < config.introBeats ? 0 : r.nextInt(100) < pct ? 1 : 0);
    return { kinds, next: 0, score: 0, combo: 0, bestCombo: 0, trips: 0, perfect: 0, good: 0, ok: 0, misses: 0, over: false, rng: r.state };
  }

  legalActions(s: DoubledutchState): DoubledutchAction[] {
    if (s.over) return [];
    return [{ by: 'player', op: 'hit', input: s.kinds[s.next]!, errMs: 0 }, { by: 'player', op: 'miss' }];
  }

  apply(s0: DoubledutchState, a: DoubledutchAction): DoubledutchState {
    if (s0.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s0, over: true };
    if (a.by !== 'player') throw new IllegalAction(this.id, a);
    const c = this.config;
    const s: DoubledutchState = { ...s0 };
    const kind = s.kinds[s.next]!;
    let missed: boolean;
    if (a.op === 'miss') missed = true;
    else if (a.op === 'hit') {
      if ((a.input !== 0 && a.input !== 1) || !isInt(a.errMs)) throw new IllegalAction(this.id, a);
      const e = Math.abs(a.errMs);
      missed = a.input !== kind || e > c.okMs;
      if (!missed) {
        s.combo += 1;
        s.bestCombo = Math.max(s.bestCombo, s.combo);
        const mult = multOf(c, s.combo);
        let base: number;
        if (e <= c.perfectMs) {
          base = c.perfectPts;
          s.perfect += 1;
        } else if (e <= c.goodMs) {
          base = c.goodPts;
          s.good += 1;
        } else {
          base = c.okPts;
          s.ok += 1;
        }
        s.score += base * (kind === 1 ? c.trickMult : 1) * mult;
      }
    } else throw new IllegalAction(this.id, a);
    if (missed) {
      s.misses += 1;
      s.trips += 1;
      s.combo = 0;
    }
    s.next += 1;
    if (s.next === c.beats || s.trips === c.maxTrips) s.over = true;
    return s;
  }

  aiAction(_s: DoubledutchState, _level: number, _ai: Prng): DoubledutchAction {
    throw new Error('doubledutch: no opponent');
  }

  result(s: DoubledutchState): DoubledutchResult | null {
    if (!s.over) return null;
    const c = this.config;
    const max = doubledutchMax(c, s.kinds);
    const pct = max > 0 ? idiv(s.score * 100, max) : 0;
    const stars = pct >= c.starPct[0]! ? 3 : pct >= c.starPct[1]! ? 2 : pct >= c.starPct[2]! ? 1 : 0;
    return { winner: stars >= 1 ? 'player' : 'ai', stars, score: s.score, pct, bestCombo: s.bestCombo, misses: s.misses };
  }
}
