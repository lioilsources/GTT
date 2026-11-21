import { Prng } from '../../rules/prng';
import type { TuningMinigamesStrelnice } from '../../gen/tuning';
import { IllegalAction, withRng, type Rules, type RulesResult } from '../rules';

/** specs/minigames/strelnice.md, version 1. `tick_hz` is UI-only and not part of the config. */
export interface StrelniceConfig {
  rounds: number;
  roundTicks: number;
  targets: number;
  width: number;
  lanes: number[];
  /** Triples (radius, speed per tick, points): small, medium, large. */
  kinds: number[];
  kindPct: number[];
  magazine: number;
  reloadTicks: number;
  starScores: number[];
}

export interface Target {
  lane: number;
  kind: number;
  spawn: number;
  dir: number;
  hit: boolean;
}

export interface StrelniceState {
  round: number;
  tick: number;
  score: number;
  shots: number;
  hits: number;
  ammo: number;
  reload: number;
  targets: Target[];
  over: boolean;
  rng: number;
}

export type StrelniceAction =
  | { by: 'player'; op: 'tick'; n: number }
  | { by: 'player'; op: 'shoot'; x: number; y: number }
  | { by: 'timeout' };

export interface StrelniceResult extends RulesResult {
  shots: number;
  hits: number;
}

export function strelniceConfig(t: TuningMinigamesStrelnice): StrelniceConfig {
  return {
    rounds: t.rounds,
    roundTicks: t.roundTicks,
    targets: t.targets,
    width: t.width,
    lanes: [...t.lanes],
    kinds: [...t.kinds],
    kindPct: [...t.kindPct],
    magazine: t.magazine,
    reloadTicks: t.reloadTicks,
    starScores: [...t.starScores],
  };
}

export const kindRadius = (cfg: StrelniceConfig, kind: number): number => cfg.kinds[3 * kind]!;
export const kindSpeed = (cfg: StrelniceConfig, kind: number): number => cfg.kinds[3 * kind + 1]!;
export const kindPoints = (cfg: StrelniceConfig, kind: number): number => cfg.kinds[3 * kind + 2]!;

/** Targets of one round, drawn from `r` in the order lane → roll → spawn jitter per target. */
export function genTargets(cfg: StrelniceConfig, r: Prng): Target[] {
  const spacing = Math.floor((cfg.roundTicks * 9) / (10 * cfg.targets));
  const out: Target[] = [];
  for (let i = 0; i < cfg.targets; i++) {
    const lane = r.nextInt(cfg.lanes.length);
    const roll = r.nextInt(100);
    const kind = roll < cfg.kindPct[0]! ? 0 : roll < cfg.kindPct[1]! ? 1 : 2;
    const spawn = i * spacing + r.nextInt(spacing);
    out.push({ lane, kind, spawn, dir: lane % 2 === 0 ? 1 : -1, hit: false });
  }
  return out;
}

/** Target position at tick `tick` (meaningful for tick ≥ spawn). */
export function targetPos(t: Target, tick: number, cfg: StrelniceConfig): { x: number; y: number } {
  const r = kindRadius(cfg, t.kind);
  const x0 = t.dir === 1 ? -r : cfg.width + r;
  return { x: x0 + t.dir * kindSpeed(cfg, t.kind) * (tick - t.spawn), y: cfg.lanes[t.lane]! };
}

/** On the field: spawned, not hit and −r ≤ x ≤ width + r. */
export function onField(t: Target, tick: number, cfg: StrelniceConfig): boolean {
  if (tick < t.spawn || t.hit) return false;
  const r = kindRadius(cfg, t.kind);
  const { x } = targetPos(t, tick, cfg);
  return x >= -r && x <= cfg.width + r;
}

export class StrelniceRules implements Rules<StrelniceState, StrelniceAction, StrelniceResult, StrelniceConfig> {
  readonly id = 'strelnice';
  readonly specVersion = 1;
  private cfg: StrelniceConfig | null = null;

  init(config: StrelniceConfig, seed: number): StrelniceState {
    this.cfg = config;
    const { value, rng } = withRng(new Prng(seed).state, (r) => genTargets(config, r));
    return { round: 1, tick: 0, score: 0, shots: 0, hits: 0, ammo: config.magazine, reload: 0, targets: value, over: false, rng };
  }

  get config(): StrelniceConfig {
    if (!this.cfg) throw new Error('strelnice: init first');
    return this.cfg;
  }

  legalActions(): StrelniceAction[] {
    return [];
  }

  apply(s: StrelniceState, a: StrelniceAction): StrelniceState {
    if (s.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s, over: true };
    if (a.by !== 'player') throw new IllegalAction(this.id, a);
    if (a.op === 'tick') {
      if (!Number.isInteger(a.n) || a.n < 1) throw new IllegalAction(this.id, a);
      return this.advance(s, a.n);
    }
    if (a.op === 'shoot') {
      if (!Number.isInteger(a.x) || !Number.isInteger(a.y)) throw new IllegalAction(this.id, a);
      return this.shoot(s, a.x, a.y);
    }
    throw new IllegalAction(this.id, a);
  }

  private advance(s0: StrelniceState, n: number): StrelniceState {
    const c = this.config;
    const s = { ...s0 };
    for (let k = 0; k < n; k++) {
      s.tick += 1;
      if (s.reload > 0) {
        s.reload -= 1;
        if (s.reload === 0) s.ammo = c.magazine;
      }
      if (s.tick >= c.roundTicks) {
        if (s.round >= c.rounds) {
          s.over = true;
          break;
        }
        const { value, rng } = withRng(s.rng, (r) => genTargets(c, r));
        s.round += 1;
        s.tick = 0;
        s.ammo = c.magazine;
        s.reload = 0;
        s.targets = value;
        s.rng = rng;
      }
    }
    return s;
  }

  private shoot(s: StrelniceState, x: number, y: number): StrelniceState {
    const c = this.config;
    if (s.ammo <= 0 || s.reload > 0) return s;
    const n = { ...s, ammo: s.ammo - 1, shots: s.shots + 1 };
    const i = s.targets.findIndex((t) => {
      if (!onField(t, s.tick, c)) return false;
      const p = targetPos(t, s.tick, c);
      const r = kindRadius(c, t.kind);
      return (x - p.x) ** 2 + (y - p.y) ** 2 <= r * r;
    });
    if (i >= 0) {
      const t = s.targets[i]!;
      n.targets = s.targets.map((u, j) => (j === i ? { ...u, hit: true } : u));
      n.score += kindPoints(c, t.kind);
      n.hits += 1;
    }
    if (n.ammo === 0) n.reload = c.reloadTicks;
    return n;
  }

  aiAction(): StrelniceAction {
    return { by: 'player', op: 'tick', n: 1 };
  }

  result(s: StrelniceState): StrelniceResult | null {
    if (!s.over) return null;
    const ss = this.config.starScores;
    const stars = s.score >= ss[0]! ? 3 : s.score >= ss[1]! ? 2 : s.score >= ss[2]! ? 1 : 0;
    return { winner: stars >= 1 ? 'player' : 'ai', stars, score: s.score, shots: s.shots, hits: s.hits };
  }
}
