import { Prng } from '../../rules/prng';
import type { TuningMinigamesBowling } from '../../gen/tuning';
import { IllegalAction, withRng, type Rules, type RulesResult } from '../rules';
import { normalizedAim, off, rect, shotVelocity, simulate, trunc, type Body, type World } from '../physics';

/** specs/minigames/bowling.md, version 1 (physics: specs/minigames/fyzika.md v1). */
export interface BowlingConfig {
  level: number;
  laneW: number;
  headY: number;
  pinDx: number;
  pinDy: number;
  ballR: number;
  ballM: number;
  pinR: number;
  pinM: number;
  minSpeed: number;
  maxSpeed: number;
  pinDec: number;
  ePin: number;
  eWall: number;
  deckY0: number;
  deckY1: number;
  knock: number;
  maxSteps: number;
  scatter: number[];
  starScores: number[];
}

export interface BowlingState {
  frame: number;
  roll: number;
  standing: boolean[];
  rolls: number[];
  score: number;
  lastKnocked: number;
  over: boolean;
  rng: number;
}

export type BowlingAction =
  | { by: 'player'; op: 'roll'; x: number; aim: number; power: number }
  | { by: 'timeout' };

export interface BowlingResult extends RulesResult {
  rolls: number[];
}

export function bowlingConfig(t: TuningMinigamesBowling, level: number): BowlingConfig {
  return {
    level,
    laneW: t.laneW,
    headY: t.headY,
    pinDx: t.pinDx,
    pinDy: t.pinDy,
    ballR: t.ballR,
    ballM: t.ballM,
    pinR: t.pinR,
    pinM: t.pinM,
    minSpeed: t.minSpeed,
    maxSpeed: t.maxSpeed,
    pinDec: t.pinDec,
    ePin: t.ePin,
    eWall: t.eWall,
    deckY0: t.deckY0,
    deckY1: t.deckY1,
    knock: t.knock,
    maxSteps: t.maxSteps,
    scatter: [...t.scatter],
    starScores: [...t.starScores],
  };
}

/** Spot of pin i (0–9 = pins 1–10). */
export function pinSpot(c: BowlingConfig, i: number): { x: number; y: number } {
  const k = i < 1 ? 0 : i < 3 ? 1 : i < 6 ? 2 : 3;
  const j = i - (k * (k + 1)) / 2;
  return { x: Math.floor(c.laneW / 2) + (2 * j - k) * c.pinDx, y: c.headY + k * c.pinDy };
}

const ALL = (): boolean[] => Array.from({ length: 10 }, () => true);

/** Standard ten-pin score of the rolls so far (missing future rolls count 0). */
export function total(rolls: number[]): number {
  const r = (i: number): number => rolls[i] ?? 0;
  let sum = 0;
  let i = 0;
  for (let f = 0; f < 10 && i < rolls.length; f++) {
    if (r(i) === 10) {
      sum += 10 + r(i + 1) + r(i + 2);
      i += 1;
    } else if (r(i) + r(i + 1) === 10) {
      sum += 10 + r(i + 2);
      i += 2;
    } else {
      sum += r(i) + r(i + 1);
      i += 2;
    }
  }
  return sum;
}

/** Ball velocity of a roll: normalized aim, scatter from `rng` (ex, then ey), then the speed. */
export function rollVelocity(c: BowlingConfig, a: { x: number; aim: number; power: number }, rng: Prng): { vx: number; vy: number } {
  const n = normalizedAim(a.x, 0, a.aim, c.headY)!;
  const s = c.scatter[c.level - 1]!;
  const ex = rng.nextInt(2 * s + 1) - s;
  const ey = rng.nextInt(2 * s + 1) - s;
  const sp = c.minSpeed + trunc((c.maxSpeed - c.minSpeed) * a.power, 100);
  return shotVelocity(a.x, 0, n.x + ex, n.y + ey, sp)!;
}

/** Simulates one roll; returns which pins of `standing` fell. `onStep` (UI) sees the bodies after each step. */
export function simulateRoll(
  c: BowlingConfig,
  standing: boolean[],
  x: number,
  v: { vx: number; vy: number },
  onStep?: (bodies: Body[]) => void,
): boolean[] {
  const bodies: Body[] = [{ x, y: 0, vx: v.vx, vy: v.vy, r: c.ballR, m: c.ballM, on: true }];
  for (let i = 0; i < 10; i++) {
    const p = pinSpot(c, i);
    bodies.push({ x: p.x, y: p.y, vx: 0, vy: 0, r: c.pinR, m: c.pinM, on: standing[i]! });
  }
  const world: World = {
    bodies,
    statics: [
      rect(-50000, c.deckY0, 0, c.deckY1 + 50000, c.eWall),
      rect(c.laneW, c.deckY0, c.laneW + 50000, c.deckY1 + 50000, c.eWall),
    ],
    eBody: c.ePin,
    capture(w) {
      w.bodies.forEach((b, i) => {
        if (!b.on) return;
        if (b.y > c.deckY1) off(b);
        else if (i === 0 && b.y < c.deckY0 && (b.x < 0 || b.x > c.laneW)) off(b);
      });
      return false;
    },
    dec: (i) => (i === 0 ? 0 : c.pinDec),
  };
  simulate(world, c.maxSteps, onStep && ((w) => onStep(w.bodies)));
  const k2 = c.knock * c.knock;
  return standing.map((st, i) => {
    if (!st) return false;
    const b = bodies[i + 1]!, p = pinSpot(c, i);
    return !b.on || (b.x - p.x) ** 2 + (b.y - p.y) ** 2 > k2;
  });
}

export class BowlingRules implements Rules<BowlingState, BowlingAction, BowlingResult, BowlingConfig> {
  readonly id = 'bowling';
  readonly specVersion = 1;
  private cfg: BowlingConfig | null = null;

  init(config: BowlingConfig, seed: number): BowlingState {
    this.cfg = config;
    return { frame: 1, roll: 1, standing: ALL(), rolls: [], score: 0, lastKnocked: 0, over: false, rng: new Prng(seed).state };
  }

  get config(): BowlingConfig {
    if (!this.cfg) throw new Error('bowling: init first');
    return this.cfg;
  }

  legalActions(): BowlingAction[] {
    return [];
  }

  /** True when the action is a legal roll in state `s`. */
  legal(s: BowlingState, a: BowlingAction): boolean {
    const c = this.config;
    if (s.over || a.by !== 'player' || a.op !== 'roll') return false;
    return [a.x, a.aim, a.power].every(Number.isInteger) && a.x >= c.ballR && a.x <= c.laneW - c.ballR && a.power >= 1 && a.power <= 100;
  }

  /** The ball velocity this roll will get (draws the scatter from a copy of the state's rng). */
  velocity(s: BowlingState, a: { x: number; aim: number; power: number }): { vx: number; vy: number; rng: number } {
    const { value, rng } = withRng(s.rng, (r) => rollVelocity(this.config, a, r));
    return { ...value, rng };
  }

  apply(s: BowlingState, a: BowlingAction): BowlingState {
    if (s.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s, over: true };
    if (!this.legal(s, a)) throw new IllegalAction(this.id, a);
    const c = this.config;
    const v = this.velocity(s, a);
    const fell = simulateRoll(c, s.standing, a.x, v);
    const k = fell.filter(Boolean).length;
    let standing = s.standing.map((st, i) => st && !fell[i]);
    const rolls = [...s.rolls, k];
    let { frame, roll } = s;
    let over = false;
    if (frame < 10) {
      if ((roll === 1 && k === 10) || roll === 2) {
        frame += 1;
        roll = 1;
        standing = ALL();
      } else roll = 2;
    } else {
      if (standing.every((st) => !st)) standing = ALL();
      const f = rolls.slice(rolls.length - roll);
      if (roll === 1) roll = 2;
      else if (roll === 2 && (f[0] === 10 || f[0]! + f[1]! === 10)) roll = 3;
      else over = true;
    }
    return { frame, roll, standing, rolls, score: total(rolls), lastKnocked: k, over, rng: v.rng };
  }

  aiAction(): BowlingAction {
    const c = this.config;
    return { by: 'player', op: 'roll', x: Math.floor(c.laneW / 2), aim: Math.floor(c.laneW / 2), power: 80 };
  }

  result(s: BowlingState): BowlingResult | null {
    if (!s.over) return null;
    const ss = this.config.starScores;
    const stars = s.score >= ss[0]! ? 3 : s.score >= ss[1]! ? 2 : s.score >= ss[2]! ? 1 : 0;
    return { winner: stars >= 1 ? 'player' : 'ai', stars, score: s.score, rolls: [...s.rolls] };
  }
}
