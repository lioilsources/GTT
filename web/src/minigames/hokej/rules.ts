import type { TuningMinigamesHokej } from '../../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../rules';
import { clamp, friction, isqrt, trunc } from '../physics';

/** specs/minigames/hokej.md, version 2 (arithmetic and friction: specs/minigames/fyzika.md v1). No rng. */
export interface HokejConfig {
  level: number;
  w: number;
  h: number;
  puckR: number;
  malletR: number;
  goalHalf: number;
  eWall: number;
  eMallet: number;
  dec: number;
  maxPuck: number;
  malletSpeed: number;
  aiSpeed: number[];
  aiReact: number[];
  aiDefY: number;
  homeY: number;
  serveY: number;
  goals: number;
  goalPause: number;
  starMargins: number[];
}

export interface Puck {
  x: number;
  y: number;
  vx: number;
  vy: number;
}

export interface Mallet {
  x: number;
  y: number;
  tx: number;
  ty: number;
}

export interface HokejState {
  tick: number;
  puck: Puck;
  me: Mallet;
  ai: Mallet;
  playerGoals: number;
  aiGoals: number;
  pause: number;
  aiClock: number;
  over: boolean;
}

export type HokejAction =
  | { by: 'player'; op: 'move'; x: number; y: number }
  | { by: 'player'; op: 'tick'; n: number }
  | { by: 'timeout' };

export interface HokejResult extends RulesResult {
  playerGoals: number;
  aiGoals: number;
}

export function hokejConfig(t: TuningMinigamesHokej, level: number): HokejConfig {
  return {
    level,
    w: t.w,
    h: t.h,
    puckR: t.puckR,
    malletR: t.malletR,
    goalHalf: t.goalHalf,
    eWall: t.eWall,
    eMallet: t.eMallet,
    dec: t.dec,
    maxPuck: t.maxPuck,
    malletSpeed: t.malletSpeed,
    aiSpeed: [...t.aiSpeed],
    aiReact: [...t.aiReact],
    aiDefY: t.aiDefY,
    homeY: t.homeY,
    serveY: t.serveY,
    goals: t.goals,
    goalPause: t.goalPause,
    starMargins: [...t.starMargins],
  };
}

/** Clips a target into a half: the player's (bottom) or the AI's (top). */
export function clipHalf(c: HokejConfig, x: number, y: number, top: boolean): { x: number; y: number } {
  const rm = c.malletR, mid = Math.floor(c.h / 2);
  return {
    x: clamp(x, rm, c.w - rm),
    y: top ? clamp(y, mid + rm, c.h - rm) : clamp(y, rm, mid - rm),
  };
}

/** Moves a mallet towards its target at most `speed`; returns the displacement. */
function drive(m: Mallet, speed: number): { dx: number; dy: number } {
  const dx = m.tx - m.x, dy = m.ty - m.y;
  const L = isqrt(dx * dx + dy * dy);
  const ox = m.x, oy = m.y;
  if (L <= speed) {
    m.x = m.tx;
    m.y = m.ty;
  } else {
    m.x += trunc(dx * speed, L);
    m.y += trunc(dy * speed, L);
  }
  return { dx: m.x - ox, dy: m.y - oy };
}

/** The automaton's new target from the puck and its mallet (specs "Soupeř"). */
export function aiTarget(c: HokejConfig, p: Puck, a: Mallet): { x: number; y: number } {
  const mid = Math.floor(c.w / 2);
  const G = c.puckR + c.malletR + 100;
  let t: { x: number; y: number };
  if (p.y >= Math.floor(c.h / 2)) {
    if (a.y > p.y + c.puckR) t = { x: p.x, y: p.y };
    else t = a.x <= p.x ? { x: p.x - G, y: p.y + G } : { x: p.x + G, y: p.y + G };
  } else t = { x: clamp(p.x, mid - c.goalHalf, mid + c.goalHalf), y: c.h - c.aiDefY };
  return clipHalf(c, t.x, t.y, true);
}

export class HokejRules implements Rules<HokejState, HokejAction, HokejResult, HokejConfig> {
  readonly id = 'hokej';
  readonly specVersion = 2;
  private cfg: HokejConfig | null = null;

  init(config: HokejConfig, _seed?: number): HokejState {
    this.cfg = config;
    return { tick: 0, ...this.faceoff(-1), playerGoals: 0, aiGoals: 0, pause: 0, aiClock: 0, over: false };
  }

  get config(): HokejConfig {
    if (!this.cfg) throw new Error('hokej: init first');
    return this.cfg;
  }

  /** Puck at rest `serveY` below (side −1) or above (+1) the centre, mallets and targets home. */
  private faceoff(side: number): { puck: Puck; me: Mallet; ai: Mallet } {
    const c = this.config;
    const x = Math.floor(c.w / 2);
    return {
      puck: { x, y: Math.floor(c.h / 2) + side * c.serveY, vx: 0, vy: 0 },
      me: { x, y: c.homeY, tx: x, ty: c.homeY },
      ai: { x, y: c.h - c.homeY, tx: x, ty: c.h - c.homeY },
    };
  }

  legalActions(): HokejAction[] {
    return [];
  }

  apply(s0: HokejState, a: HokejAction): HokejState {
    if (s0.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s0, over: true };
    if (a.by !== 'player') throw new IllegalAction(this.id, a);
    const c = this.config;
    if (a.op === 'move') {
      if (!Number.isInteger(a.x) || !Number.isInteger(a.y)) throw new IllegalAction(this.id, a);
      const t = clipHalf(c, a.x, a.y, false);
      return { ...s0, me: { ...s0.me, tx: t.x, ty: t.y } };
    }
    if (a.op !== 'tick' || !Number.isInteger(a.n) || a.n < 1) throw new IllegalAction(this.id, a);
    const s: HokejState = { ...s0, puck: { ...s0.puck }, me: { ...s0.me }, ai: { ...s0.ai } };
    for (let k = 0; k < a.n && !s.over; k++) this.tick(s);
    return s;
  }

  private tick(s: HokejState): void {
    const c = this.config;
    s.tick += 1;
    if (s.pause > 0) {
      s.pause -= 1;
      return;
    }
    const mv = drive(s.me, c.malletSpeed);
    s.aiClock += 1;
    if (s.aiClock >= c.aiReact[c.level - 1]!) {
      s.aiClock = 0;
      const t = aiTarget(c, s.puck, s.ai);
      s.ai.tx = t.x;
      s.ai.ty = t.y;
    }
    const ma = drive(s.ai, c.aiSpeed[c.level - 1]!);
    const p = s.puck;
    const x0 = p.x, y0 = p.y;
    p.x += p.vx;
    p.y += p.vy;
    const r = c.puckR, e = c.eWall, mid = Math.floor(c.w / 2);
    if (p.y < 0 || p.y > c.h) {
      const mine = p.y > c.h;
      // v2 step 5: x of the centre where it crosses the goal line, integer interpolation along the move.
      let xc = x0;
      if (!mine && y0 > 0) xc = x0 + trunc(p.vx * y0, y0 - p.y);
      if (mine && y0 < c.h) xc = x0 + trunc(p.vx * (c.h - y0), p.y - y0);
      if (Math.abs(xc - mid) > c.goalHalf) {
        // Crossed outside the mouth: bounce off the end wall, position mirrored over the line.
        p.y = mine ? 2 * c.h - p.y : 0 - p.y;
        p.vy = 0 - trunc(p.vy * e, 1000);
      }
    }
    if (p.y < 0 || p.y > c.h) {
      const mine = p.y > c.h;
      if (mine) s.playerGoals += 1;
      else s.aiGoals += 1;
      Object.assign(s, this.faceoff(mine ? 1 : -1));
      s.pause = c.goalPause;
      s.aiClock = 0;
      if (s.playerGoals >= c.goals || s.aiGoals >= c.goals) s.over = true;
      return;
    }
    if ((p.x - r < 0 && p.vx < 0) || (p.x + r > c.w && p.vx > 0)) p.vx = 0 - trunc(p.vx * e, 1000);
    if (((p.y - r < 0 && p.vy < 0) || (p.y + r > c.h && p.vy > 0)) && Math.abs(p.x - mid) > c.goalHalf) {
      p.vy = 0 - trunc(p.vy * e, 1000);
    }
    this.mallet(p, s.me, mv);
    this.mallet(p, s.ai, ma);
    const sp = isqrt(p.vx * p.vx + p.vy * p.vy);
    if (sp > c.maxPuck) {
      p.vx = trunc(p.vx * c.maxPuck, sp);
      p.vy = trunc(p.vy * c.maxPuck, sp);
    }
    friction(p, c.dec);
  }

  /** Step 7 for one mallet: bounce off it (relative velocity), then push the puck out to touching. */
  private mallet(p: Puck, m: Mallet, mv: { dx: number; dy: number }): void {
    const c = this.config;
    const R = c.puckR + c.malletR;
    const dx = p.x - m.x, dy = p.y - m.y;
    const d2 = dx * dx + dy * dy;
    if (d2 <= 0 || d2 >= R * R) return;
    const vn = (p.vx - mv.dx) * dx + (p.vy - mv.dy) * dy;
    if (vn < 0) {
      const k = trunc(vn * (1000 + c.eMallet) * 1000, d2);
      p.vx -= trunc(k * dx, 1000000);
      p.vy -= trunc(k * dy, 1000000);
    }
    const L = isqrt(d2);
    const r = c.puckR;
    p.x = clamp(m.x + trunc(dx * R, L), r, c.w - r);
    p.y = m.y + trunc(dy * R, L);
    if (Math.abs(p.x - Math.floor(c.w / 2)) > c.goalHalf) p.y = clamp(p.y, r, c.h - r);
  }

  aiAction(): HokejAction {
    return { by: 'player', op: 'tick', n: 1 };
  }

  result(s: HokejState): HokejResult | null {
    if (!s.over) return null;
    const d = s.playerGoals - s.aiGoals;
    const winner = d > 0 ? 'player' : d < 0 ? 'ai' : 'draw';
    const sm = this.config.starMargins;
    const stars = d <= 0 ? 0 : d >= sm[0]! ? 3 : d >= sm[1]! ? 2 : 1;
    return { winner, stars, score: s.playerGoals, playerGoals: s.playerGoals, aiGoals: s.aiGoals };
  }
}
