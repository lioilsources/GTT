// Stickball (specs/minigames/stickball.md, version 1): pitch, swing or take, bases and outs.
// Pure P0 rules; the pitcher is aiAction, the timing error comes from the UI.
import type { TuningMinigamesStickball } from '../../gen/tuning';
import { Prng } from '../../rules/prng';
import { IllegalAction, withRng, type Rules, type RulesResult } from '../rules';

export interface StickballConfig {
  level: number;
  maxOuts: number;
  strikesOut: number;
  ballsWalk: number;
  zonePct: number[];
  flightMin: number[];
  flightVar: number[];
  perfectMs: number;
  goodMs: number;
  okMs: number;
  foulMs: number;
  catchPct: number[];
  starRuns: number[];
}

export type StickballLast = '' | 'ball' | 'strike' | 'foul' | 'single' | 'double' | 'homer' | 'catch' | 'walk' | 'strikeout';

export interface StickballPitch {
  zone: boolean;
  lane: number;
  flightMs: number;
}

export interface StickballState {
  phase: 'pitch' | 'bat' | 'over';
  outs: number;
  strikes: number;
  balls: number;
  /** Bit 0 first, bit 1 second, bit 2 third base. */
  bases: number;
  runs: number;
  hits: number;
  homers: number;
  pitch: StickballPitch;
  last: StickballLast;
  rng: number;
}

export type StickballAction =
  | { by: 'ai'; op: 'pitch'; zone: boolean; lane: number; flightMs: number }
  | { by: 'player'; op: 'swing'; lane: number; errMs: number }
  | { by: 'player'; op: 'take' }
  | { by: 'timeout' };

export interface StickballResult extends RulesResult {
  hits: number;
  homers: number;
}

const isInt = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v);
const isLane = (v: unknown): v is number => isInt(v) && v >= 0 && v <= 2;

export function stickballConfig(t: TuningMinigamesStickball, level: number): StickballConfig {
  return {
    level,
    maxOuts: t.maxOuts,
    strikesOut: t.strikesOut,
    ballsWalk: t.ballsWalk,
    zonePct: [...t.zonePct],
    flightMin: [...t.flightMin],
    flightVar: [...t.flightVar],
    perfectMs: t.perfectMs,
    goodMs: t.goodMs,
    okMs: t.okMs,
    foulMs: t.foulMs,
    catchPct: [...t.catchPct],
    starRuns: [...t.starRuns],
  };
}

/** Timing grade of a swing before lane and zone: 3 perfect … 0 foul, −1 miss. */
export function swingGrade(c: StickballConfig, errMs: number): number {
  const e = Math.abs(errMs);
  return e <= c.perfectMs ? 3 : e <= c.goodMs ? 2 : e <= c.okMs ? 1 : e <= c.foulMs ? 0 : -1;
}

export class StickballRules implements Rules<StickballState, StickballAction, StickballResult, StickballConfig> {
  readonly id = 'stickball';
  readonly specVersion = 1;
  private cfg: StickballConfig | null = null;

  get config(): StickballConfig {
    if (!this.cfg) throw new Error('stickball: init first');
    return this.cfg;
  }

  init(config: StickballConfig, seed: number): StickballState {
    this.cfg = config;
    return {
      phase: 'pitch', outs: 0, strikes: 0, balls: 0, bases: 0, runs: 0, hits: 0, homers: 0,
      pitch: { zone: false, lane: 0, flightMs: 0 }, last: '', rng: new Prng(seed).state,
    };
  }

  legalActions(s: StickballState): StickballAction[] {
    if (s.phase !== 'bat') return [];
    return [
      { by: 'player', op: 'take' },
      { by: 'player', op: 'swing', lane: 0, errMs: 0 },
      { by: 'player', op: 'swing', lane: 1, errMs: 0 },
      { by: 'player', op: 'swing', lane: 2, errMs: 0 },
    ];
  }

  apply(s0: StickballState, a: StickballAction): StickballState {
    if (s0.phase === 'over') throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s0, phase: 'over' };
    const c = this.config;
    const s: StickballState = { ...s0, pitch: { ...s0.pitch } };
    if (a.by === 'ai') {
      if (s.phase !== 'pitch' || a.op !== 'pitch' || typeof a.zone !== 'boolean' || !isLane(a.lane) || !isInt(a.flightMs) || a.flightMs < 1) {
        throw new IllegalAction(this.id, a);
      }
      s.pitch = { zone: a.zone, lane: a.lane, flightMs: a.flightMs };
      s.phase = 'bat';
      s.last = '';
      return s;
    }
    if (a.by !== 'player' || s.phase !== 'bat') throw new IllegalAction(this.id, a);
    if (a.op === 'take') {
      if (s.pitch.zone) this.strike(s);
      else {
        s.balls += 1;
        if (s.balls === c.ballsWalk) this.walk(s);
        else this.next(s, 'ball');
      }
      return s;
    }
    if (a.op !== 'swing' || !isLane(a.lane) || !isInt(a.errMs)) throw new IllegalAction(this.id, a);
    let g = swingGrade(c, a.errMs);
    if (g >= 0) {
      g -= Math.abs(a.lane - s.pitch.lane);
      if (!s.pitch.zone) g -= 1;
    }
    if (g === 3) this.hit(s, 4);
    else if (g === 2) this.hit(s, 2);
    else if (g === 1) {
      const { value, rng } = withRng(s.rng, (r) => r.nextInt(100));
      s.rng = rng;
      if (value < c.catchPct[c.level - 1]!) this.out(s, 'catch');
      else this.hit(s, 1);
    } else if (g === 0) {
      if (s.strikes < c.strikesOut - 1) s.strikes += 1;
      this.next(s, 'foul');
    } else this.strike(s);
    return s;
  }

  /** Ball, strike or foul without ending the at-bat. */
  private next(s: StickballState, last: StickballLast): void {
    s.last = last;
    s.phase = 'pitch';
  }

  /** At-bat over: count reset, game over at maxOuts. */
  private atBatOver(s: StickballState, last: StickballLast): void {
    s.strikes = 0;
    s.balls = 0;
    s.last = last;
    s.phase = s.outs === this.config.maxOuts ? 'over' : 'pitch';
  }

  private strike(s: StickballState): void {
    s.strikes += 1;
    if (s.strikes === this.config.strikesOut) this.out(s, 'strikeout');
    else this.next(s, 'strike');
  }

  private out(s: StickballState, last: StickballLast): void {
    s.outs += 1;
    this.atBatOver(s, last);
  }

  private hit(s: StickballState, k: number): void {
    s.hits += 1;
    if (k === 4) s.homers += 1;
    let bases = 0;
    for (let p = 1; p <= 3; p++) {
      if (!(s.bases & (1 << (p - 1)))) continue;
      const q = p + k;
      if (q >= 4) s.runs += 1;
      else bases |= 1 << (q - 1);
    }
    if (k >= 4) s.runs += 1;
    else bases |= 1 << (k - 1);
    s.bases = bases;
    this.atBatOver(s, k === 4 ? 'homer' : k === 2 ? 'double' : 'single');
  }

  private walk(s: StickballState): void {
    const b = s.bases;
    if ((b & 7) === 7) s.runs += 1;
    let n = b | 1;
    if (b & 1) {
      n |= 2;
      if (b & 2) n |= 4;
    }
    s.bases = n & 7;
    this.atBatOver(s, 'walk');
  }

  aiAction(s: StickballState, level: number, ai: Prng): StickballAction {
    if (s.phase !== 'pitch') throw new Error('stickball: not pitching');
    const c = this.config;
    const zone = ai.nextInt(100) < c.zonePct[level - 1]!;
    const lane = ai.nextInt(3);
    const flightMs = c.flightMin[level - 1]! + ai.nextInt(c.flightVar[level - 1]! + 1);
    return { by: 'ai', op: 'pitch', zone, lane, flightMs };
  }

  result(s: StickballState): StickballResult | null {
    if (s.phase !== 'over') return null;
    const r = this.config.starRuns;
    const stars = s.runs >= r[0]! ? 3 : s.runs >= r[1]! ? 2 : s.runs >= r[2]! ? 1 : 0;
    return { winner: stars >= 1 ? 'player' : 'ai', stars, score: s.runs, hits: s.hits, homers: s.homers };
  }
}
