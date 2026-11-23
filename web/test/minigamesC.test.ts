import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { Tuning } from '../src/gen/tuning';
import { aiPrng } from '../src/minigames/rules';
import { KulecnikRules, footSpot, headSpot, kulecnikConfig, type KulecnikState } from '../src/minigames/kulecnik/rules';
import { BowlingRules, bowlingConfig, pinSpot, total } from '../src/minigames/bowling/rules';
import { MinigolfRules, minigolfConfig, parseHole } from '../src/minigames/minigolf/rules';
import { HadRules, hadConfig } from '../src/minigames/had/rules';
import { CihlyRules, brickRect, cihlyConfig } from '../src/minigames/cihly/rules';
import { KrtekRules, krtekConfig } from '../src/minigames/krtek/rules';
import { HokejRules, hokejConfig } from '../src/minigames/hokej/rules';

const tuning = Tuning.fromJson(parse(readFileSync(join(__dirname, '..', '..', 'content', 'tuning.yaml'), 'utf8')));
const tm = tuning.minigames;

describe('kulecnik', () => {
  const cfg = kulecnikConfig(tm.kulecnik);
  const fresh = (): { r: KulecnikRules; s: KulecnikState } => {
    const r = new KulecnikRules();
    return { r, s: r.init(cfg, 1) };
  };
  const place = (s: KulecnikState, at: Record<number, [number, number] | null>): KulecnikState => ({
    ...s,
    balls: s.balls.map((b, i) => (i in at ? (at[i] ? { x: at[i]![0], y: at[i]![1], on: true } : { ...b, on: false }) : b)),
  });

  it('racks the cue on the head spot and rack[0] on the foot spot', () => {
    const { s } = fresh();
    expect(s.balls[0]).toEqual({ ...headSpot(cfg), on: true });
    expect(s.balls[cfg.rack[0]!]).toEqual({ ...footSpot(cfg), on: true });
    expect(s.balls.every((b) => b.on)).toBe(true);
  });

  it('rejects shots out of turn, out of range or at the cue centre', () => {
    const { r, s } = fresh();
    const c = s.balls[0]!;
    expect(() => r.apply(s, { by: 'ai', op: 'shot', x: c.x, y: c.y + 10, power: 50 })).toThrow();
    expect(() => r.apply(s, { by: 'player', op: 'shot', x: c.x, y: c.y + 10, power: 0 })).toThrow();
    expect(() => r.apply(s, { by: 'player', op: 'shot', x: c.x, y: c.y, power: 50 })).toThrow();
  });

  it('a straight break hits rack[0] first, counts the shot and never assigns groups', () => {
    const { r, s } = fresh();
    const t = s.balls[cfg.rack[0]!]!;
    const n = r.apply(s, { by: 'player', op: 'shot', x: t.x, y: t.y, power: 100 });
    expect(n.shots).toBe(1);
    expect(n.last.firstHit).toBe(cfg.rack[0]);
    expect(n.last.foul).toBe(n.last.pots.includes(0));
    expect(n.playerGroup).toBe('');
  });

  it('a scratch is a foul, the cue goes back to the first free spot below the head spot', () => {
    const { r, s } = fresh();
    const hs = headSpot(cfg);
    const t0 = place({ ...s, shots: 3 }, { 0: [9000, 9000], 1: [hs.x, hs.y] });
    const n = r.apply(t0, { by: 'player', op: 'shot', x: 0, y: 0, power: 30 });
    expect(n.last.pots).toEqual([0]);
    expect(n.last.foul).toBe(true);
    expect(n.turn).toBe('ai');
    expect(n.balls[0]).toEqual({ x: hs.x, y: hs.y - cfg.rackDx, on: true });
  });

  it('the eight before the group is cleared loses', () => {
    const { r, s } = fresh();
    const t0 = place({ ...s, shots: 3, playerGroup: 'solid' }, { 0: [12000, 12000], 8: [7000, 7000] });
    const n = r.apply(t0, { by: 'player', op: 'shot', x: 7000, y: 7000, power: 30 });
    expect(n.last.pots).toContain(8);
    expect(n.over).toBe(true);
    expect(r.result(n)).toMatchObject({ winner: 'ai', stars: 0 });
  });

  it('the AI decides deterministically and draws exactly two scatter values', () => {
    const { r, s } = fresh();
    const t = s.balls[cfg.rack[0]!]!;
    const after = r.apply(s, { by: 'player', op: 'shot', x: t.x + 4000, y: t.y, power: 5 });
    const ai = { ...after, turn: 'ai' as const };
    const a1 = r.aiAction(ai, 3, aiPrng(9)), a2 = r.aiAction(ai, 3, aiPrng(9));
    expect(a1).toEqual(a2);
    const p = aiPrng(9);
    r.aiAction(ai, 1, p);
    const q = aiPrng(9);
    q.nextU32();
    q.nextU32();
    expect(p.state).toBe(q.state);
  });

  it('timeout: fewer own balls wins, open table is a draw', () => {
    const { r, s } = fresh();
    expect(r.result(r.apply(s, { by: 'timeout' }))).toMatchObject({ winner: 'draw', playerLeft: 7, aiLeft: 7 });
    const t0 = place({ ...s, playerGroup: 'stripe' }, { 9: null });
    expect(r.result(r.apply(t0, { by: 'timeout' }))).toMatchObject({ winner: 'player', stars: 3, score: 1 });
  });
});

describe('bowling', () => {
  it('scores strikes, spares and open frames', () => {
    expect(total(Array(12).fill(10))).toBe(300);
    expect(total(Array(21).fill(5))).toBe(150);
    expect(total([3, 4, 10, 2])).toBe(7 + 12 + 2);
    expect(total([9, 1])).toBe(10);
  });

  it('places pins 1–10 in four rows', () => {
    const cfg = bowlingConfig(tm.bowling, 1);
    const mid = Math.floor(cfg.laneW / 2);
    expect(pinSpot(cfg, 0)).toEqual({ x: mid, y: cfg.headY });
    expect(pinSpot(cfg, 6)).toEqual({ x: mid - 3 * cfg.pinDx, y: cfg.headY + 3 * cfg.pinDy });
    expect(pinSpot(cfg, 9)).toEqual({ x: mid + 3 * cfg.pinDx, y: cfg.headY + 3 * cfg.pinDy });
  });

  it('a gutter ball knocks nothing and moves to the second roll', () => {
    const r = new BowlingRules();
    const s = r.init(bowlingConfig(tm.bowling, 1), 3);
    const n = r.apply(s, { by: 'player', op: 'roll', x: r.config.ballR, aim: -400000, power: 50 });
    expect(n).toMatchObject({ frame: 1, roll: 2, lastKnocked: 0, rolls: [0] });
    expect(() => r.apply(s, { by: 'player', op: 'roll', x: 0, aim: 0, power: 50 })).toThrow();
  });
});

describe('minigolf', () => {
  it('parses holes in mm into u and rejects malformed lists', () => {
    const h = parseHole(tm.minigolf.h6);
    expect(h).toMatchObject({ w: 120000, h: 340000, par: 3, cx: 60000, cy: 300000 });
    expect(h.walls).toHaveLength(2);
    expect(h.water).toHaveLength(2);
    expect(() => parseHole([1000, 3000, 2, 500, 300, 500, 2600, 1, 0, 0])).toThrow();
  });

  it('water costs a penalty stroke and returns the ball', () => {
    const r = new MinigolfRules();
    let s = r.init(minigolfConfig(tm.minigolf, 1), 5);
    s = { ...s, hole: 6, x: 20000, y: 120000 };
    const n = r.apply(s, { by: 'player', op: 'putt', x: 20000, y: 170000, power: 60 });
    expect(n).toMatchObject({ hole: 6, strokes: 2, x: 20000, y: 120000 });
  });
});

describe('had', () => {
  it('ignores a reversal and moves on the interval', () => {
    const r = new HadRules();
    const cfg = hadConfig(tm.had, 1);
    let s = r.init(cfg, 2);
    s = r.apply(s, { by: 'player', op: 'turn', dir: 2 });
    expect(s.next).toBe(0);
    s = r.apply(s, { by: 'player', op: 'tick', n: cfg.startInterval[0]! });
    expect(s.body[0]).toEqual([7, 11]);
    expect(s.t).toBe(0);
  });
});

describe('cihly', () => {
  it('clamps the paddle and serves after serveTicks', () => {
    const r = new CihlyRules();
    const cfg = cihlyConfig(tm.cihly, 2);
    let s = r.init(cfg, 4);
    s = r.apply(s, { by: 'player', op: 'move', x: -50 });
    expect(s.paddle).toBe(cfg.paddleW[1]);
    s = r.apply(s, { by: 'player', op: 'tick', n: cfg.serveTicks });
    expect(s.serve).toBe(0);
    expect(s.ball.vx ** 2 + s.ball.vy ** 2).toBeLessThanOrEqual(cfg.speed[1]! ** 2);
    expect(s.ball.vy).toBeGreaterThan(0);
    expect(brickRect(cfg, 0)).toEqual({ x0: 80, x1: 1230, y0: 14050, y1: 14500 });
  });
});

describe('krtek', () => {
  it('spawns on schedule; a full board draws nothing', () => {
    const r = new KrtekRules();
    const cfg = krtekConfig(tm.krtek, 1);
    let s = r.init(cfg, 8);
    s = r.apply(s, { by: 'player', op: 'tick', n: cfg.firstSpawn });
    expect(s.holes.filter((h) => h.kind !== '')).toHaveLength(1);
    const full = { ...s, nextSpawn: 1, holes: s.holes.map(() => ({ kind: 'mole' as const, left: 50 })) };
    const n = r.apply(full, { by: 'player', op: 'tick', n: 1 });
    expect(n.rng).toBe(full.rng);
    const i = s.holes.findIndex((h) => h.kind !== '');
    const hit = r.apply(s, { by: 'player', op: 'hit', hole: i });
    expect(hit.holes[i]).toEqual({ kind: '', left: 0 });
    expect(r.apply(hit, { by: 'player', op: 'hit', hole: i })).toEqual(hit);
  });
});

describe('hokej', () => {
  it('starts at the faceoff and clips the player target into the lower half', () => {
    const r = new HokejRules();
    const cfg = hokejConfig(tm.hokej, 3);
    const s = r.init(cfg, 0);
    expect(s.puck).toEqual({ x: 3000, y: 3500, vx: 0, vy: 0 });
    expect(s.me).toEqual({ x: 3000, y: 1200, tx: 3000, ty: 1200 });
    const m = r.apply(s, { by: 'player', op: 'move', x: 99999, y: 99999 });
    expect(m.me).toMatchObject({ tx: cfg.w - cfg.malletR, ty: cfg.h / 2 - cfg.malletR });
  });
});
