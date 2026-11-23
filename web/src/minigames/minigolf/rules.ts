import { Prng } from '../../rules/prng';
import type { TuningMinigamesMinigolf } from '../../gen/tuning';
import { IllegalAction, withRng, type Rules, type RulesResult } from '../rules';
import { circle, normalizedAim, rect, shotVelocity, simulate, trunc, type Body, type Static, type World } from '../physics';

/** specs/minigames/minigolf.md, version 1 (physics: specs/minigames/fyzika.md v1). */
export interface MinigolfConfig {
  level: number;
  /** Six holes in the flat mm format of the spec. */
  holes: number[][];
  ballR: number;
  cupR: number;
  cupSpeed: number;
  maxSpeed: number;
  dec: number;
  sandDec: number;
  eWall: number;
  eBumper: number;
  maxSteps: number;
  maxStrokes: number;
  scatter: number[];
  starOver: number[];
}

export interface MinigolfState {
  hole: number;
  strokes: number;
  scores: number[];
  x: number;
  y: number;
  over: boolean;
  rng: number;
}

export type MinigolfAction =
  | { by: 'player'; op: 'putt'; x: number; y: number; power: number }
  | { by: 'timeout' };

export interface MinigolfResult extends RulesResult {
  scores: number[];
  par: number;
}

export function minigolfConfig(t: TuningMinigamesMinigolf, level: number): MinigolfConfig {
  return {
    level,
    holes: [t.h1, t.h2, t.h3, t.h4, t.h5, t.h6].map((h) => [...h]),
    ballR: t.ballR,
    cupR: t.cupR,
    cupSpeed: t.cupSpeed,
    maxSpeed: t.maxSpeed,
    dec: t.dec,
    sandDec: t.sandDec,
    eWall: t.eWall,
    eBumper: t.eBumper,
    maxSteps: t.maxSteps,
    maxStrokes: t.maxStrokes,
    scatter: [...t.scatter],
    starOver: [...t.starOver],
  };
}

export interface Box {
  x0: number;
  y0: number;
  x1: number;
  y1: number;
}

/** A hole in u (mm × 100). */
export interface Hole {
  w: number;
  h: number;
  par: number;
  sx: number;
  sy: number;
  cx: number;
  cy: number;
  walls: Box[];
  bumpers: Array<{ x: number; y: number; r: number }>;
  sand: Box[];
  water: Box[];
}

const U = 100;

/** Parses the flat mm list; a malformed list throws (a load error, the spec says). */
export function parseHole(a: number[]): Hole {
  let i = 0;
  const next = (): number => {
    const v = a[i++];
    if (v === undefined || !Number.isInteger(v)) throw new Error(`minigolf: malformed hole ${JSON.stringify(a)}`);
    return v;
  };
  const boxes = (): Box[] => Array.from({ length: next() }, () => ({ x0: next() * U, y0: next() * U, x1: next() * U, y1: next() * U }));
  const w = next() * U, h = next() * U, par = next();
  const sx = next() * U, sy = next() * U, cx = next() * U, cy = next() * U;
  const walls = boxes();
  const bumpers = Array.from({ length: next() }, () => ({ x: next() * U, y: next() * U, r: next() * U }));
  const sand = boxes();
  const water = boxes();
  if (i !== a.length) throw new Error(`minigolf: malformed hole ${JSON.stringify(a)}`);
  return { w, h, par, sx, sy, cx, cy, walls, bumpers, sand, water };
}

const inside = (b: Box, x: number, y: number): boolean => b.x0 <= x && x <= b.x1 && b.y0 <= y && y <= b.y1;

/** Statics in the spec's order: borders (200 mm thick), walls (eWall), bumpers (eBumper). */
export function holeStatics(c: MinigolfConfig, h: Hole): Static[] {
  const t = 200 * U, e = c.eWall;
  return [
    rect(-t, -t, 0, h.h + t, e),
    rect(h.w, -t, h.w + t, h.h + t, e),
    rect(0, -t, h.w, 0, e),
    rect(0, h.h, h.w, h.h + t, e),
    ...h.walls.map((b) => rect(b.x0, b.y0, b.x1, b.y1, e)),
    ...h.bumpers.map((b) => circle(b.x, b.y, b.r, c.eBumper)),
  ];
}

export type PuttEnd = 'rest' | 'water' | 'cup';

/** Simulates a putt from (x, y) with velocity v; `onStep` (UI) sees the ball after every step. */
export function simulatePutt(
  c: MinigolfConfig,
  h: Hole,
  x: number,
  y: number,
  v: { vx: number; vy: number },
  onStep?: (b: Body) => void,
): { end: PuttEnd; x: number; y: number } {
  const ball: Body = { x, y, vx: v.vx, vy: v.vy, r: c.ballR, m: 1, on: true };
  let end: PuttEnd = 'rest';
  const cup2 = c.cupR * c.cupR;
  const world: World = {
    bodies: [ball],
    statics: holeStatics(c, h),
    eBody: 1000,
    capture() {
      if (h.water.some((b) => inside(b, ball.x, ball.y))) {
        end = 'water';
        return true;
      }
      const dx = ball.x - h.cx, dy = ball.y - h.cy;
      if (dx * dx + dy * dy <= cup2 && ball.vx * ball.vx + ball.vy * ball.vy <= c.cupSpeed * c.cupSpeed) {
        end = 'cup';
        return true;
      }
      return false;
    },
    dec: (_, b) => (h.sand.some((s) => inside(s, b.x, b.y)) ? c.sandDec : c.dec),
  };
  simulate(world, c.maxSteps, onStep && (() => onStep(ball)));
  if (end === 'rest' && (ball.x - h.cx) ** 2 + (ball.y - h.cy) ** 2 <= cup2) end = 'cup';
  return { end, x: ball.x, y: ball.y };
}

export class MinigolfRules implements Rules<MinigolfState, MinigolfAction, MinigolfResult, MinigolfConfig> {
  readonly id = 'minigolf';
  readonly specVersion = 1;
  private cfg: MinigolfConfig | null = null;
  private parsed: Hole[] = [];

  init(config: MinigolfConfig, seed: number): MinigolfState {
    this.cfg = config;
    this.parsed = config.holes.map(parseHole);
    const h = this.parsed[0]!;
    return { hole: 1, strokes: 0, scores: [], x: h.sx, y: h.sy, over: false, rng: new Prng(seed).state };
  }

  get config(): MinigolfConfig {
    if (!this.cfg) throw new Error('minigolf: init first');
    return this.cfg;
  }

  /** Hole n (1–6) in u. */
  holeAt(n: number): Hole {
    return this.parsed[n - 1]!;
  }

  legalActions(): MinigolfAction[] {
    return [];
  }

  legal(s: MinigolfState, a: MinigolfAction): boolean {
    if (s.over || a.by !== 'player' || a.op !== 'putt') return false;
    return [a.x, a.y, a.power].every(Number.isInteger) && a.power >= 1 && a.power <= 100 && !(a.x === s.x && a.y === s.y);
  }

  /** The ball velocity of a putt and the rng after its scatter. */
  velocity(s: MinigolfState, a: { x: number; y: number; power: number }): { vx: number; vy: number; rng: number } {
    const c = this.config;
    const { value, rng } = withRng(s.rng, (r) => {
      const n = normalizedAim(s.x, s.y, a.x, a.y)!;
      const sc = c.scatter[c.level - 1]!;
      const ex = r.nextInt(2 * sc + 1) - sc;
      const ey = r.nextInt(2 * sc + 1) - sc;
      return shotVelocity(s.x, s.y, n.x + ex, n.y + ey, trunc(a.power * c.maxSpeed, 100))!;
    });
    return { ...value, rng };
  }

  apply(s: MinigolfState, a: MinigolfAction): MinigolfState {
    if (s.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s, over: true };
    if (!this.legal(s, a)) throw new IllegalAction(this.id, a);
    const c = this.config;
    const v = this.velocity(s, a);
    const out = simulatePutt(c, this.holeAt(s.hole), s.x, s.y, v);
    return this.settle({ ...s, strokes: s.strokes + 1, rng: v.rng }, s, out);
  }

  /** Rules after the simulation: splash, holed, stroke cap, next hole. */
  settle(n: MinigolfState, before: MinigolfState, out: { end: PuttEnd; x: number; y: number }): MinigolfState {
    const c = this.config;
    let s: MinigolfState = { ...n, x: out.x, y: out.y };
    if (out.end === 'water') s = { ...s, strokes: s.strokes + 1, x: before.x, y: before.y };
    if (out.end === 'cup') return this.nextHole(s, s.strokes);
    if (s.strokes >= c.maxStrokes) return this.nextHole(s, c.maxStrokes + 1);
    return s;
  }

  private nextHole(s: MinigolfState, score: number): MinigolfState {
    const scores = [...s.scores, score];
    if (s.hole >= 6) return { ...s, scores, hole: 7, strokes: 0, over: true };
    const h = this.holeAt(s.hole + 1);
    return { ...s, scores, hole: s.hole + 1, strokes: 0, x: h.sx, y: h.sy };
  }

  aiAction(s: MinigolfState): MinigolfAction {
    const h = this.holeAt(Math.min(s.hole, 6));
    return { by: 'player', op: 'putt', x: h.cx, y: h.cy, power: 50 };
  }

  result(s: MinigolfState): MinigolfResult | null {
    if (!s.over) return null;
    const score = s.scores.reduce((a, b) => a + b, 0);
    const par = s.scores.reduce((a, _, i) => a + this.holeAt(i + 1).par, 0);
    const so = this.config.starOver;
    const over = score - par;
    const stars = s.scores.length < 6 ? 0 : over <= so[0]! ? 3 : over <= so[1]! ? 2 : over <= so[2]! ? 1 : 0;
    return { winner: stars >= 1 ? 'player' : 'ai', stars, score, scores: [...s.scores], par };
  }
}
