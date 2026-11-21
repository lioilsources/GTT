import { Prng } from '../../rules/prng';
import type { TuningMinigamesSipky } from '../../gen/tuning';
import { IllegalAction, withRng, type Rules, type RulesResult } from '../rules';

/** specs/minigames/sipky.md, version 1. Integer arithmetic only (all products stay far below 2^53). */
export interface SipkyConfig {
  start: number;
  maxRounds: number;
  playerScatter: number;
  aiScatter: number[];
  starDarts: number[];
}

export type Side = 'player' | 'ai';

export interface Hit {
  x: number;
  y: number;
  points: number;
  mult: number;
}

export interface SipkyState {
  player: number;
  ai: number;
  turn: Side;
  dart: number;
  turnStart: number;
  playerDarts: number;
  round: number;
  lastHit: Hit;
  over: boolean;
  rng: number;
}

export type SipkyAction =
  | { by: 'player'; x: number; y: number }
  | { by: 'ai'; x: number; y: number; level: number }
  | { by: 'timeout' };

export interface SipkyResult extends RulesResult {
  player: number;
  ai: number;
  playerDarts: number;
}

export function sipkyConfig(t: TuningMinigamesSipky): SipkyConfig {
  return {
    start: t.start,
    maxRounds: t.maxRounds,
    playerScatter: t.playerScatter,
    aiScatter: [...t.aiScatter],
    starDarts: [...t.starDarts],
  };
}

/** Sector values from the top, clockwise. */
export const SECTORS = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5];

/** Sector boundaries B[j]: direction 9° + 18°·j clockwise from +y, ×10⁶. */
const B: ReadonlyArray<readonly [number, number]> = [
  [156434, 987688], [453990, 891007], [707107, 707107], [891007, 453990], [987688, 156434],
  [987688, -156434], [891007, -453990], [707107, -707107], [453990, -891007], [156434, -987688],
  [-156434, -987688], [-453990, -891007], [-707107, -707107], [-891007, -453990], [-987688, -156434],
  [-987688, 156434], [-891007, 453990], [-707107, 707107], [-453990, 891007], [-156434, 987688],
];

/** Sector centres C[k]: direction 18°·k clockwise from +y, ×10⁶. */
const C: ReadonlyArray<readonly [number, number]> = [
  [0, 1000000], [309017, 951057], [587785, 809017], [809017, 587785], [951057, 309017],
  [1000000, 0], [951057, -309017], [809017, -587785], [587785, -809017], [309017, -951057],
  [0, -1000000], [-309017, -951057], [-587785, -809017], [-809017, -587785], [-951057, -309017],
  [-1000000, 0], [-951057, 309017], [-809017, 587785], [-587785, 809017], [-309017, 951057],
];

/** Board radii in 0.1 mm. */
export const RING = { bull: 64, outerBull: 159, tripleIn: 990, tripleOut: 1070, doubleIn: 1620, doubleOut: 1700 };

/** Radii the AI aims at: inner single, triple, double. */
export const AIM = { single: 574, triple: 1030, double: 1660 };

const cross = (a: readonly [number, number], x: number, y: number): number => a[0] * y - a[1] * x;

/** Sector index of a point: first k with cross(B[k−1], p) ≤ 0 and cross(B[k], p) > 0. */
export function sectorAt(x: number, y: number): number {
  for (let k = 0; k < 20; k++) {
    if (cross(B[(k + 19) % 20]!, x, y) <= 0 && cross(B[k]!, x, y) > 0) return k;
  }
  return 0;
}

/** Points and multiplier of a landing point (board units, y up). */
export function scoreAt(x: number, y: number): { points: number; mult: number } {
  const r2 = x * x + y * y;
  const sq = (r: number): number => r * r;
  if (r2 <= sq(RING.bull)) return { points: 50, mult: 2 };
  if (r2 <= sq(RING.outerBull)) return { points: 25, mult: 1 };
  if (r2 >= sq(RING.doubleOut)) return { points: 0, mult: 0 };
  const v = SECTORS[sectorAt(x, y)]!;
  if (r2 >= sq(RING.tripleIn) && r2 < sq(RING.tripleOut)) return { points: 3 * v, mult: 3 };
  if (r2 >= sq(RING.doubleIn)) return { points: 2 * v, mult: 2 };
  return { points: v, mult: 1 };
}

/** rnd(q) = trunc((q + sign(q)·500000) / 10⁶). */
function rnd(q: number): number {
  return Math.trunc((q + Math.sign(q) * 500000) / 1000000);
}

/** The point on the centre line of sector value [value] at radius [r]. */
export function pointOn(value: number, r: number): { x: number; y: number } {
  const c = C[SECTORS.indexOf(value)]!;
  return { x: rnd(c[0] * r) + 0, y: rnd(c[1] * r) + 0 };
}

/** AI target for remaining score z (spec "AI", no randomness). */
export function aiTarget(z: number): { x: number; y: number } {
  if (z === 50) return { x: 0, y: 0 };
  if (z <= 20) return pointOn(z, AIM.single);
  if (z <= 40 && z % 2 === 0) return pointOn(z / 2, AIM.double);
  if (z <= 60 && z % 3 === 0) return pointOn(z / 3, AIM.triple);
  if (z <= 60 && z - 20 >= 1 && z - 20 <= 20) return pointOn(z - 20, AIM.single);
  return pointOn(20, AIM.triple);
}

const other = (s: Side): Side => (s === 'player' ? 'ai' : 'player');

export class SipkyRules implements Rules<SipkyState, SipkyAction, SipkyResult, SipkyConfig> {
  readonly id = 'sipky';
  readonly specVersion = 1;
  private cfg: SipkyConfig | null = null;

  init(config: SipkyConfig, seed: number): SipkyState {
    this.cfg = config;
    return {
      player: config.start,
      ai: config.start,
      turn: 'player',
      dart: 0,
      turnStart: config.start,
      playerDarts: 0,
      round: 1,
      lastHit: { x: 0, y: 0, points: 0, mult: 0 },
      over: false,
      rng: new Prng(seed).state,
    };
  }

  private get c(): SipkyConfig {
    if (!this.cfg) throw new Error('sipky: init first');
    return this.cfg;
  }

  /** Actions are continuous; apply checks them. */
  legalActions(_s: SipkyState): SipkyAction[] {
    return [];
  }

  private scatter(a: SipkyAction): number {
    if (a.by === 'player') return this.c.playerScatter;
    if (a.by !== 'ai' || !Number.isInteger(a.level)) throw new IllegalAction(this.id, a);
    const n = this.c.aiScatter.length;
    return this.c.aiScatter[Math.min(Math.max(a.level, 1), n) - 1]!;
  }

  apply(s: SipkyState, a: SipkyAction): SipkyState {
    if (s.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s, over: true };
    if (a.by !== s.turn || !Number.isInteger(a.x) || !Number.isInteger(a.y)) throw new IllegalAction(this.id, a);
    const sc = this.scatter(a);
    const { value: [x, y], rng } = withRng(s.rng, (r) => {
      const dx = r.nextInt(2 * sc + 1) - sc;
      const dy = r.nextInt(2 * sc + 1) - sc;
      return [a.x + dx, a.y + dy] as const;
    });
    const { points, mult } = scoreAt(x, y);
    const side = s.turn;
    const n: SipkyState = {
      ...s,
      rng,
      lastHit: { x, y, points, mult },
      playerDarts: side === 'player' ? s.playerDarts + 1 : s.playerDarts,
    };
    const left = s[side] - points;
    if (left < 0) return this.endTurn({ ...n, [side]: s.turnStart });
    if (left === 0) return { ...n, [side]: 0, over: true };
    if (s.dart >= 2) return this.endTurn({ ...n, [side]: left });
    return { ...n, [side]: left, dart: s.dart + 1 };
  }

  private endTurn(s: SipkyState): SipkyState {
    const turn = other(s.turn);
    const n: SipkyState = { ...s, dart: 0, turn, turnStart: s[turn] };
    if (s.turn !== 'ai') return n;
    const round = s.round + 1;
    return { ...n, round, over: round > this.c.maxRounds };
  }

  aiAction(s: SipkyState, level: number, _ai: Prng): SipkyAction {
    const { x, y } = aiTarget(s.ai);
    return { by: 'ai', x, y, level };
  }

  result(s: SipkyState): SipkyResult | null {
    if (!s.over) return null;
    const winner = s.player < s.ai ? 'player' : s.ai < s.player ? 'ai' : 'draw';
    const [d3, d2] = this.c.starDarts;
    const stars = winner !== 'player' ? 0 : s.playerDarts <= d3! ? 3 : s.playerDarts <= d2! ? 2 : 1;
    return { winner, stars, score: this.c.start - s.player, player: s.player, ai: s.ai, playerDarts: s.playerDarts };
  }
}
