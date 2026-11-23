import { Prng } from '../../rules/prng';
import type { TuningMinigamesHad } from '../../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../rules';

/** specs/minigames/had.md, version 1. */
export interface HadConfig {
  level: number;
  w: number;
  h: number;
  startInterval: number[];
  minInterval: number[];
  speedupEvery: number;
  foodPoints: number;
  starScores: number[];
}

export type Cell = [number, number];

export interface HadState {
  body: Cell[];
  dir: number;
  next: number;
  food: Cell;
  t: number;
  interval: number;
  score: number;
  eaten: number;
  over: boolean;
  rng: number;
}

export type HadAction =
  | { by: 'player'; op: 'tick'; n: number }
  | { by: 'player'; op: 'turn'; dir: number }
  | { by: 'timeout' };

export interface HadResult extends RulesResult {
  length: number;
}

export function hadConfig(t: TuningMinigamesHad, level: number): HadConfig {
  return {
    level,
    w: t.w,
    h: t.h,
    startInterval: [...t.startInterval],
    minInterval: [...t.minInterval],
    speedupEvery: t.speedupEvery,
    foodPoints: t.foodPoints,
    starScores: [...t.starScores],
  };
}

/** Direction d → (dx, dy): 0 up (+y), 1 right, 2 down, 3 left. */
export const DIRS: ReadonlyArray<Cell> = [[0, 1], [1, 0], [0, -1], [-1, 0]];

export class HadRules implements Rules<HadState, HadAction, HadResult, HadConfig> {
  readonly id = 'had';
  readonly specVersion = 1;
  private cfg: HadConfig | null = null;

  init(config: HadConfig, seed: number): HadState {
    this.cfg = config;
    const cx = Math.floor(config.w / 2), cy = Math.floor(config.h / 2);
    const s: HadState = {
      body: [[cx, cy], [cx, cy - 1], [cx, cy - 2]],
      dir: 0,
      next: 0,
      food: [0, 0],
      t: 0,
      interval: config.startInterval[config.level - 1]!,
      score: 0,
      eaten: 0,
      over: false,
      rng: new Prng(seed).state,
    };
    this.placeFood(s);
    return s;
  }

  get config(): HadConfig {
    if (!this.cfg) throw new Error('had: init first');
    return this.cfg;
  }

  /** Food on a free cell (rows from y = 0, x from 0 in a row); none free → over (food stays). */
  private placeFood(s: HadState): void {
    const c = this.config;
    const taken = new Set(s.body.map(([x, y]) => y * c.w + x));
    const free: Cell[] = [];
    for (let y = 0; y < c.h; y++) for (let x = 0; x < c.w; x++) if (!taken.has(y * c.w + x)) free.push([x, y]);
    if (free.length === 0) {
      s.over = true;
      return;
    }
    const r = new Prng(s.rng);
    s.food = free[r.nextInt(free.length)]!;
    s.rng = r.state;
  }

  legalActions(): HadAction[] {
    return [];
  }

  apply(s0: HadState, a: HadAction): HadState {
    if (s0.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s0, over: true };
    if (a.by !== 'player') throw new IllegalAction(this.id, a);
    if (a.op === 'turn') {
      if (!Number.isInteger(a.dir) || a.dir < 0 || a.dir > 3) throw new IllegalAction(this.id, a);
      return a.dir === (s0.dir + 2) % 4 ? s0 : { ...s0, next: a.dir };
    }
    if (a.op !== 'tick' || !Number.isInteger(a.n) || a.n < 1) throw new IllegalAction(this.id, a);
    const s: HadState = { ...s0, body: s0.body.map(([x, y]) => [x, y] as Cell), food: [...s0.food] as Cell };
    for (let k = 0; k < a.n && !s.over; k++) {
      s.t += 1;
      if (s.t >= s.interval) {
        s.t = 0;
        this.move(s);
      }
    }
    return s;
  }

  private move(s: HadState): void {
    const c = this.config;
    s.dir = s.next;
    const [hx, hy] = s.body[0]!;
    const [dx, dy] = DIRS[s.dir]!;
    const nx = hx + dx, ny = hy + dy;
    if (nx < 0 || ny < 0 || nx >= c.w || ny >= c.h) {
      s.over = true;
      return;
    }
    const eats = nx === s.food[0] && ny === s.food[1];
    const check = eats ? s.body : s.body.slice(0, -1);
    if (check.some(([x, y]) => x === nx && y === ny)) {
      s.over = true;
      return;
    }
    s.body.unshift([nx, ny]);
    if (!eats) {
      s.body.pop();
      return;
    }
    s.score += c.foodPoints;
    s.eaten += 1;
    if (s.eaten % c.speedupEvery === 0) s.interval = Math.max(s.interval - 1, c.minInterval[c.level - 1]!);
    this.placeFood(s);
  }

  aiAction(): HadAction {
    return { by: 'player', op: 'tick', n: 1 };
  }

  result(s: HadState): HadResult | null {
    if (!s.over) return null;
    const ss = this.config.starScores;
    const stars = s.score >= ss[0]! ? 3 : s.score >= ss[1]! ? 2 : s.score >= ss[2]! ? 1 : 0;
    return { winner: stars >= 1 ? 'player' : 'ai', stars, score: s.score, length: s.body.length };
  }
}
