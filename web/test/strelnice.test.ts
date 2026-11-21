import { describe, expect, it } from 'vitest';

import { replay } from '../src/minigames/rules';
import { Prng } from '../src/rules/prng';
import {
  StrelniceRules,
  genTargets,
  onField,
  targetPos,
  type StrelniceAction,
  type StrelniceConfig,
  type StrelniceState,
  type Target,
} from '../src/minigames/strelnice/rules';

const cfg: StrelniceConfig = {
  rounds: 3,
  roundTicks: 2700,
  targets: 36,
  width: 1000,
  lanes: [250, 500, 750],
  kinds: [40, 9, 50, 60, 6, 20, 80, 4, 10],
  kindPct: [15, 55],
  magazine: 6,
  reloadTicks: 45,
  starScores: [1500, 1000, 600],
};

const tgt = (o: Partial<Target>): Target => ({ lane: 0, kind: 1, spawn: 0, dir: 1, hit: false, ...o });
const tick = (n: number): StrelniceAction => ({ by: 'player', op: 'tick', n });
const shoot = (x: number, y: number): StrelniceAction => ({ by: 'player', op: 'shoot', x, y });

describe('strelnice rules (specs/minigames/strelnice.md)', () => {
  it('generates round targets deterministically in lane → roll → spawn order', () => {
    const r = new StrelniceRules();
    const a = r.init(cfg, 42);
    const b = new StrelniceRules().init(cfg, 42);
    expect(a).toEqual(b);
    expect(a).toMatchObject({ round: 1, tick: 0, score: 0, shots: 0, hits: 0, ammo: 6, reload: 0, over: false });
    expect(a.targets).toHaveLength(36);

    const p = new Prng(42);
    const spacing = Math.floor((2700 * 9) / (10 * 36));
    for (let i = 0; i < 36; i++) {
      const lane = p.nextInt(3);
      const roll = p.nextInt(100);
      const spawn = i * spacing + p.nextInt(spacing);
      expect(a.targets[i]).toEqual({ lane, kind: roll < 15 ? 0 : roll < 55 ? 1 : 2, spawn, dir: lane % 2 === 0 ? 1 : -1, hit: false });
    }
    expect(a.rng).toBe(p.state);
    expect(genTargets(cfg, new Prng(42))).toEqual(a.targets);
  });

  it('positions and on-field edges', () => {
    const right = tgt({ lane: 0, kind: 1, spawn: 10, dir: 1 }); // r 60, speed 6
    expect(targetPos(right, 10, cfg)).toEqual({ x: -60, y: 250 });
    expect(targetPos(right, 20, cfg)).toEqual({ x: 0, y: 250 });
    expect(onField(right, 9, cfg)).toBe(false);
    expect(onField(right, 10, cfg)).toBe(true);
    const edge = tgt({ lane: 0, kind: 2, spawn: 0, dir: 1 }); // r 80, speed 4: x = -80 + 4t, width+r = 1080 at t = 290
    expect(onField(edge, 290, cfg)).toBe(true);
    expect(onField(edge, 291, cfg)).toBe(false);
    const left = tgt({ lane: 1, kind: 0, spawn: 0, dir: -1 }); // r 40, speed 9: x = 1040 - 9t
    expect(targetPos(left, 0, cfg)).toEqual({ x: 1040, y: 500 });
    expect(onField(left, 120, cfg)).toBe(true); // x = -40
    expect(onField(left, 121, cfg)).toBe(false);
    expect(onField({ ...right, hit: true }, 20, cfg)).toBe(false);
  });

  it('a hit on overlapping targets takes the lowest index', () => {
    const r = new StrelniceRules();
    const base = r.init(cfg, 1);
    const s: StrelniceState = {
      ...base,
      tick: 50,
      targets: [tgt({ kind: 2, spawn: 0 }), tgt({ kind: 0, spawn: 25 }), tgt({ kind: 1, spawn: 15 })],
    };
    // target 0: x = -80 + 4·50 = 120; target 1: x = -40 + 9·25 = 185; target 2: x = -60 + 6·35 = 150.
    const n = r.apply(s, shoot(150, 250));
    expect(n.targets.map((t) => t.hit)).toEqual([true, false, false]);
    expect(n).toMatchObject({ score: 10, hits: 1, shots: 1, ammo: 5 });
    const m = r.apply(n, shoot(150, 250));
    expect(m.targets.map((t) => t.hit)).toEqual([true, true, false]);
    expect(m.score).toBe(60);
    const miss = r.apply(m, shoot(500, 500));
    expect(miss).toMatchObject({ score: 60, hits: 2, shots: 3, ammo: 3 });
  });

  it('an empty magazine starts the reload, which refills; shooting while reloading changes nothing', () => {
    const r = new StrelniceRules();
    let s = r.init(cfg, 3);
    for (let i = 0; i < 6; i++) s = r.apply(s, shoot(0, 0));
    expect(s).toMatchObject({ ammo: 0, reload: 45, shots: 6 });
    expect(r.apply(s, shoot(0, 0))).toBe(s);
    s = r.apply(s, tick(44));
    expect(s).toMatchObject({ ammo: 0, reload: 1 });
    expect(r.apply(s, shoot(0, 0))).toBe(s);
    s = r.apply(s, tick(1));
    expect(s).toMatchObject({ ammo: 6, reload: 0, tick: 45 });
  });

  it('rejects illegal actions', () => {
    const r = new StrelniceRules();
    const s = r.init(cfg, 1);
    expect(() => r.apply(s, tick(0))).toThrow();
    expect(() => r.apply(s, { by: 'player', op: 'tick', n: 1.5 })).toThrow();
    expect(() => r.apply(s, { by: 'ai', op: 'tick', n: 1 } as unknown as StrelniceAction)).toThrow();
    expect(() => r.apply(s, shoot(1.5, 2))).toThrow();
    const over = r.apply(s, { by: 'timeout' });
    expect(over.over).toBe(true);
    expect(() => r.apply(over, tick(1))).toThrow();
    expect(() => r.apply(over, shoot(1, 1))).toThrow();
    expect(r.legalActions()).toEqual([]);
  });

  it('round rollover regenerates targets and resets the magazine; over after round 3', () => {
    const r = new StrelniceRules();
    let s = r.init(cfg, 9);
    s = r.apply(s, shoot(0, 0));
    s = r.apply(s, tick(2699));
    expect(s).toMatchObject({ round: 1, tick: 2699, ammo: 5 });
    const before = s;
    s = r.apply(s, tick(1));
    expect(s).toMatchObject({ round: 2, tick: 0, ammo: 6, reload: 0, over: false });
    expect(s.targets).toEqual(genTargets(cfg, new Prng(before.rng)));
    expect(s.targets).not.toEqual(before.targets);
    s = r.apply(s, tick(2700 + 5));
    expect(s).toMatchObject({ round: 3, tick: 5 });
    s = r.apply(s, tick(5000));
    expect(s).toMatchObject({ round: 3, tick: 2700, over: true });
    expect(r.result(s)).toEqual({ winner: 'ai', stars: 0, score: 0, shots: 1, hits: 0 });
  });

  it('stars follow starScores', () => {
    const r = new StrelniceRules();
    const b = { ...r.init(cfg, 1), over: true };
    const stars = (score: number) => r.result({ ...b, score })!;
    expect([0, 599, 600, 999, 1000, 1499, 1500, 4000].map((x) => stars(x).stars)).toEqual([0, 0, 1, 1, 2, 2, 3, 3]);
    expect(stars(600).winner).toBe('player');
    expect(stars(599).winner).toBe('ai');
    expect(r.result(r.init(cfg, 1))).toBeNull();
  });

  it('a played game replays to the same states', () => {
    const r = new StrelniceRules();
    const pol = new Prng(77);
    let s = r.init(cfg, 77);
    const steps: Array<{ action: Record<string, unknown> }> = [];
    const states: StrelniceState[] = [];
    while (!s.over) {
      const vis = s.targets.filter((t) => onField(t, s.tick, cfg));
      const a: StrelniceAction = vis.length && pol.nextInt(2) === 0
        ? (() => { const p = targetPos(vis[0]!, s.tick, cfg); return shoot(p.x, p.y); })()
        : tick(3 + pol.nextInt(8));
      steps.push({ action: a as unknown as Record<string, unknown> });
      s = r.apply(s, a);
      states.push(s);
    }
    expect(s.hits).toBeGreaterThan(0);
    const again = replay(new StrelniceRules() as never, { config: cfg as never, seed: 77, steps });
    expect(again.states).toEqual(states);
    expect(again.result).toEqual(r.result(s));
  });
});
