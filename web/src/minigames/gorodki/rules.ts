import { Prng } from '../../rules/prng';
import type { TuningMinigamesGorodki } from '../../gen/tuning';
import { IllegalAction, withRng, type Rules, type RulesResult } from '../rules';
import { normalizedAim, off, shotVelocity, simulate, trunc, type Body, type World } from '../physics';

/** specs/minigames/gorodki.md, version 1 (physics: specs/minigames/fyzika.md v1). */
export interface GorodkiConfig {
  level: number;
  gorodW: number;
  gorodY0: number;
  gorodY1: number;
  polukonY: number;
  batR: number;
  batM: number;
  batDec: number;
  pieceR: number;
  pieceM: number;
  pieceDec: number;
  minSpeed: number;
  maxSpeed: number;
  eBody: number;
  fieldPad: number;
  maxSteps: number;
  bats: number[];
  scatter: number[];
  starFigs: number[];
  /** Five figures, each [dx, dy] × 5 from the middle of the front line. */
  figures: number[][];
}

export interface GorodkiState {
  fig: number;
  px: number[];
  py: number[];
  up: boolean[];
  bats: number;
  throws: number;
  cleared: number;
  knocked: number;
  polukon: boolean;
  lastOut: number;
  over: boolean;
  rng: number;
}

export type GorodkiAction =
  | { by: 'player'; op: 'throw'; x: number; aim: number; power: number }
  | { by: 'timeout' };

export interface GorodkiResult extends RulesResult {
  cleared: number;
  knocked: number;
  throws: number;
}

export function gorodkiConfig(t: TuningMinigamesGorodki, level: number): GorodkiConfig {
  return {
    level,
    gorodW: t.gorodW,
    gorodY0: t.gorodY0,
    gorodY1: t.gorodY1,
    polukonY: t.polukonY,
    batR: t.batR,
    batM: t.batM,
    batDec: t.batDec,
    pieceR: t.pieceR,
    pieceM: t.pieceM,
    pieceDec: t.pieceDec,
    minSpeed: t.minSpeed,
    maxSpeed: t.maxSpeed,
    eBody: t.eBody,
    fieldPad: t.fieldPad,
    maxSteps: t.maxSteps,
    bats: [...t.bats],
    scatter: [...t.scatter],
    starFigs: [...t.starFigs],
    figures: [t.fig1, t.fig2, t.fig3, t.fig4, t.fig5].map((f) => [...f]),
  };
}

/** Pieces of figure `fig` (1–5) at their start spots. */
export function figure(c: GorodkiConfig, fig: number): { px: number[]; py: number[]; up: boolean[] } {
  const f = c.figures[fig - 1]!;
  const mid = Math.floor(c.gorodW / 2);
  return {
    px: [0, 1, 2, 3, 4].map((k) => mid + f[2 * k]!),
    py: [0, 1, 2, 3, 4].map((k) => c.gorodY0 + f[2 * k + 1]!),
    up: [true, true, true, true, true],
  };
}

export const throwLine = (c: GorodkiConfig, s: GorodkiState): number => (s.polukon ? c.polukonY : 0);

/** Bat velocity of a throw: normalized aim, scatter from `rng` (ex, then ey), then the speed. */
export function throwVelocity(c: GorodkiConfig, ly: number, a: { x: number; aim: number; power: number }, rng: Prng): { vx: number; vy: number } {
  const n = normalizedAim(a.x, ly, a.aim, c.gorodY0)!;
  const s = c.scatter[c.level - 1]!;
  const ex = rng.nextInt(2 * s + 1) - s;
  const ey = rng.nextInt(2 * s + 1) - s;
  const sp = c.minSpeed + trunc((c.maxSpeed - c.minSpeed) * a.power, 100);
  return shotVelocity(a.x, ly, n.x + ex, n.y + ey, sp)!;
}

/** Simulates one throw; returns the bodies after it (0 = bat, 1–5 = pieces). `onStep` (UI) sees each step. */
export function simulateThrow(
  c: GorodkiConfig,
  s: GorodkiState,
  x: number,
  v: { vx: number; vy: number },
  onStep?: (bodies: Body[]) => void,
): Body[] {
  const bodies: Body[] = [{ x, y: throwLine(c, s), vx: v.vx, vy: v.vy, r: c.batR, m: c.batM, on: true }];
  for (let k = 0; k < 5; k++) bodies.push({ x: s.px[k]!, y: s.py[k]!, vx: 0, vy: 0, r: c.pieceR, m: c.pieceM, on: s.up[k]! });
  const world: World = {
    bodies,
    statics: [],
    eBody: c.eBody,
    capture(w) {
      for (const b of w.bodies) {
        if (b.on && (b.x < -c.fieldPad || b.x > c.gorodW + c.fieldPad || b.y > c.gorodY1 + c.fieldPad)) off(b);
      }
      return false;
    },
    dec: (i) => (i === 0 ? c.batDec : c.pieceDec),
  };
  simulate(world, c.maxSteps, onStep && ((w) => onStep(w.bodies)));
  return bodies;
}

export const inGorod = (c: GorodkiConfig, b: Body): boolean =>
  b.on && b.x >= 0 && b.x <= c.gorodW && b.y >= c.gorodY0 && b.y <= c.gorodY1;

export class GorodkiRules implements Rules<GorodkiState, GorodkiAction, GorodkiResult, GorodkiConfig> {
  readonly id = 'gorodki';
  readonly specVersion = 1;
  private cfg: GorodkiConfig | null = null;

  init(config: GorodkiConfig, seed: number): GorodkiState {
    this.cfg = config;
    return {
      fig: 1, ...figure(config, 1), bats: config.bats[config.level - 1]!, throws: 0, cleared: 0, knocked: 0,
      polukon: false, lastOut: 0, over: false, rng: new Prng(seed).state,
    };
  }

  get config(): GorodkiConfig {
    if (!this.cfg) throw new Error('gorodki: init first');
    return this.cfg;
  }

  legalActions(): GorodkiAction[] {
    return [];
  }

  legal(s: GorodkiState, a: GorodkiAction): boolean {
    const c = this.config;
    if (s.over || a.by !== 'player' || a.op !== 'throw') return false;
    return [a.x, a.aim, a.power].every(Number.isInteger) && a.x >= 0 && a.x <= c.gorodW && a.power >= 1 && a.power <= 100;
  }

  /** The bat velocity this throw will get (draws the scatter from a copy of the state's rng). */
  velocity(s: GorodkiState, a: { x: number; aim: number; power: number }): { vx: number; vy: number; rng: number } {
    const { value, rng } = withRng(s.rng, (r) => throwVelocity(this.config, throwLine(this.config, s), a, r));
    return { ...value, rng };
  }

  apply(s: GorodkiState, a: GorodkiAction): GorodkiState {
    if (s.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s, over: true };
    if (!this.legal(s, a)) throw new IllegalAction(this.id, a);
    const c = this.config;
    const v = this.velocity(s, a);
    const bodies = simulateThrow(c, s, a.x, v);
    const px = [...s.px], py = [...s.py], up = [...s.up];
    let out = 0;
    for (let k = 0; k < 5; k++) {
      if (!up[k]) continue;
      const b = bodies[k + 1]!;
      if (inGorod(c, b)) {
        px[k] = b.x;
        py[k] = b.y;
      } else {
        up[k] = false;
        out++;
      }
    }
    let n: GorodkiState = {
      ...s, px, py, up, bats: s.bats - 1, throws: s.throws + 1, knocked: s.knocked + out, lastOut: out,
      polukon: s.polukon || out > 0, rng: v.rng,
    };
    if (up.every((u) => !u)) {
      n = { ...n, cleared: n.cleared + 1 };
      if (s.fig === 5) return { ...n, over: true };
      n = { ...n, fig: s.fig + 1, ...figure(c, s.fig + 1), polukon: false };
    }
    if (n.bats === 0) n = { ...n, over: true };
    return n;
  }

  aiAction(): GorodkiAction {
    const m = Math.floor(this.config.gorodW / 2);
    return { by: 'player', op: 'throw', x: m, aim: m, power: 60 };
  }

  result(s: GorodkiState): GorodkiResult | null {
    if (!s.over) return null;
    const sf = this.config.starFigs;
    const stars = s.cleared >= sf[0]! ? 3 : s.cleared >= sf[1]! ? 2 : s.cleared >= sf[2]! ? 1 : 0;
    const score = s.knocked * 10 + s.cleared * 50 + (s.cleared === 5 ? s.bats * 20 : 0);
    return { winner: stars >= 1 ? 'player' : 'ai', stars, score, cleared: s.cleared, knocked: s.knocked, throws: s.throws };
  }
}
