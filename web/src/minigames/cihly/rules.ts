import { Prng } from '../../rules/prng';
import type { TuningMinigamesCihly } from '../../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../rules';
import { clamp, isqrt, trunc } from '../physics';

/** specs/minigames/cihly.md, version 1 (arithmetic and closest point: specs/minigames/fyzika.md v1). */
export interface CihlyConfig {
  level: number;
  w: number;
  h: number;
  ballR: number;
  paddleY: number;
  paddleH: number;
  paddleW: number[];
  speed: number[];
  maxVxPct: number;
  serveTicks: number;
  lives: number;
  rows: number;
  cols: number;
  brickX0: number;
  brickTop: number;
  brickW: number;
  brickH: number;
  brickGap: number;
  rowPoints: number[];
  livesBonus: number;
  starScores: number[];
}

export interface CihlyBall {
  x: number;
  y: number;
  vx: number;
  vy: number;
}

export interface CihlyState {
  ball: CihlyBall;
  paddle: number;
  serve: number;
  bricks: boolean[];
  score: number;
  lives: number;
  over: boolean;
  rng: number;
}

export type CihlyAction =
  | { by: 'player'; op: 'move'; x: number }
  | { by: 'player'; op: 'tick'; n: number }
  | { by: 'timeout' };

export interface CihlyResult extends RulesResult {
  lives: number;
  cleared: boolean;
}

export function cihlyConfig(t: TuningMinigamesCihly, level: number): CihlyConfig {
  return {
    level,
    w: t.w,
    h: t.h,
    ballR: t.ballR,
    paddleY: t.paddleY,
    paddleH: t.paddleH,
    paddleW: [...t.paddleW],
    speed: [...t.speed],
    maxVxPct: t.maxVxPct,
    serveTicks: t.serveTicks,
    lives: t.lives,
    rows: t.rows,
    cols: t.cols,
    brickX0: t.brickX0,
    brickTop: t.brickTop,
    brickW: t.brickW,
    brickH: t.brickH,
    brickGap: t.brickGap,
    rowPoints: [...t.rowPoints],
    livesBonus: t.livesBonus,
    starScores: [...t.starScores],
  };
}

/** Brick i = row × cols + col (row 0 at the top). */
export function brickRect(c: CihlyConfig, i: number): { x0: number; y0: number; x1: number; y1: number } {
  const row = Math.floor(i / c.cols), col = i % c.cols;
  const x0 = c.brickX0 + col * (c.brickW + c.brickGap);
  const y1 = c.brickTop - row * (c.brickH + c.brickGap);
  return { x0, x1: x0 + c.brickW, y0: y1 - c.brickH, y1 };
}

export const halfWidth = (c: CihlyConfig): number => c.paddleW[c.level - 1]!;

export class CihlyRules implements Rules<CihlyState, CihlyAction, CihlyResult, CihlyConfig> {
  readonly id = 'cihly';
  readonly specVersion = 1;
  private cfg: CihlyConfig | null = null;

  init(config: CihlyConfig, seed: number): CihlyState {
    this.cfg = config;
    const paddle = Math.floor(config.w / 2);
    return {
      ball: this.onPaddle(paddle),
      paddle,
      serve: config.serveTicks,
      bricks: Array.from({ length: config.rows * config.cols }, () => true),
      score: 0,
      lives: config.lives,
      over: false,
      rng: new Prng(seed).state,
    };
  }

  get config(): CihlyConfig {
    if (!this.cfg) throw new Error('cihly: init first');
    return this.cfg;
  }

  private onPaddle(paddle: number): CihlyBall {
    const c = this.config;
    return { x: paddle, y: c.paddleY + c.paddleH + c.ballR, vx: 0, vy: 0 };
  }

  legalActions(): CihlyAction[] {
    return [];
  }

  apply(s0: CihlyState, a: CihlyAction): CihlyState {
    if (s0.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s0, over: true };
    if (a.by !== 'player') throw new IllegalAction(this.id, a);
    const c = this.config;
    if (a.op === 'move') {
      if (!Number.isInteger(a.x)) throw new IllegalAction(this.id, a);
      const hw = halfWidth(c);
      return { ...s0, paddle: clamp(a.x, hw, c.w - hw) };
    }
    if (a.op !== 'tick' || !Number.isInteger(a.n) || a.n < 1) throw new IllegalAction(this.id, a);
    const s: CihlyState = { ...s0, ball: { ...s0.ball }, bricks: [...s0.bricks] };
    for (let k = 0; k < a.n && !s.over; k++) this.tick(s);
    return s;
  }

  private tick(s: CihlyState): void {
    const c = this.config;
    const sp = c.speed[c.level - 1]!, hw = halfWidth(c), r = c.ballR;
    if (s.serve > 0) {
      s.serve -= 1;
      s.ball = this.onPaddle(s.paddle);
      if (s.serve === 0) {
        const sv = Math.floor(sp / 2);
        const g = new Prng(s.rng);
        s.ball.vx = g.nextInt(2 * sv + 1) - sv;
        s.rng = g.state;
        s.ball.vy = isqrt(sp * sp - s.ball.vx * s.ball.vx);
      }
      return;
    }
    const b = s.ball;
    b.x += b.vx;
    b.y += b.vy;
    if ((b.x - r < 0 && b.vx < 0) || (b.x + r > c.w && b.vx > 0)) b.vx = 0 - b.vx;
    if (b.y + r > c.h && b.vy > 0) b.vy = 0 - b.vy;
    for (let i = 0; i < s.bricks.length; i++) {
      if (!s.bricks[i]) continue;
      const q = brickRect(c, i);
      const dx = b.x - clamp(b.x, q.x0, q.x1), dy = b.y - clamp(b.y, q.y0, q.y1);
      const d2 = dx * dx + dy * dy;
      if (d2 >= r * r) continue;
      if (d2 === 0) b.vy = 0 - b.vy;
      else if (b.vx * dx + b.vy * dy >= 0) continue;
      else if (Math.abs(dx) > Math.abs(dy)) b.vx = 0 - b.vx;
      else if (Math.abs(dy) > Math.abs(dx)) b.vy = 0 - b.vy;
      else {
        b.vx = 0 - b.vx;
        b.vy = 0 - b.vy;
      }
      s.bricks[i] = false;
      s.score += c.rowPoints[Math.floor(i / c.cols)]!;
      break;
    }
    if (b.vy < 0 && b.y >= c.paddleY) {
      const dx = b.x - clamp(b.x, s.paddle - hw, s.paddle + hw);
      const dy = b.y - clamp(b.y, c.paddleY - c.paddleH, c.paddleY + c.paddleH);
      if (dx * dx + dy * dy < r * r) {
        const mx = trunc(sp * c.maxVxPct, 100);
        b.vx = clamp(trunc(mx * (b.x - s.paddle), hw), -mx, mx);
        b.vy = isqrt(sp * sp - b.vx * b.vx);
      }
    }
    if (b.y + r < 0) {
      s.lives -= 1;
      if (s.lives === 0) s.over = true;
      else {
        s.serve = c.serveTicks;
        s.ball = this.onPaddle(s.paddle);
      }
    }
    if (s.bricks.every((x) => !x)) {
      s.score += s.lives * c.livesBonus;
      s.over = true;
    }
  }

  aiAction(): CihlyAction {
    return { by: 'player', op: 'tick', n: 1 };
  }

  result(s: CihlyState): CihlyResult | null {
    if (!s.over) return null;
    const ss = this.config.starScores;
    const stars = s.score >= ss[0]! ? 3 : s.score >= ss[1]! ? 2 : s.score >= ss[2]! ? 1 : 0;
    return { winner: stars >= 1 ? 'player' : 'ai', stars, score: s.score, lives: s.lives, cleared: s.bricks.every((x) => !x) };
  }
}
