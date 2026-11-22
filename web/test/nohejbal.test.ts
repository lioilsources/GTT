import { describe, expect, it } from 'vitest';

import { courtAim } from '../src/minigames/nohejbal/game';
import { NohejbalRules, nohejbalOver, type NohejbalAction, type NohejbalConfig, type NohejbalState } from '../src/minigames/nohejbal/rules';
import { aiPrng, replay } from '../src/minigames/rules';
import { Prng } from '../src/rules/prng';

const cfg: NohejbalConfig = {
  halfWidth: 450,
  depth: 900,
  winPoints: 10,
  winBy: 2,
  maxPoints: 15,
  scatter: [40, 55, 70, 85, 100],
  aiScatter: [160, 130, 100, 80, 60],
  aiReach: [250, 300, 350, 400, 450],
  playerReach: 380,
  aiMargin: [220, 180, 140, 110, 80],
  starMargins: [6, 3, 1],
};
const exact: NohejbalConfig = { ...cfg, scatter: [0, 0, 0, 0, 0], aiScatter: [0, 0, 0, 0, 0] };

const p = (x: number, y: number, level = 1): NohejbalAction => ({ by: 'player', x, y, level });
const a = (x: number, y: number, level = 1): NohejbalAction => ({ by: 'ai', x, y, level });

function start(): { r: NohejbalRules; s: NohejbalState } {
  const r = new NohejbalRules();
  return { r, s: r.init(exact, 1) };
}

describe('nohejbal rules (specs/minigames/nohejbal.md)', () => {
  it('starts 0:0 with the player serving', () => {
    const r = new NohejbalRules();
    const s = r.init(cfg, 42);
    expect(s).toEqual({
      playerPts: 0, aiPts: 0, turn: 'player', server: 'player', rally: 0,
      lastShot: { by: '', x: 0, y: 0, in: false, reached: false }, over: false, rng: new Prng(42).state,
    });
    expect(r.legalActions()).toEqual([]);
    expect(r.result(s)).toBeNull();
  });

  it('scatter draws x then y from the state rng', () => {
    const r = new NohejbalRules();
    const s1 = r.apply(r.init(cfg, 7), p(100, 400, 2));
    const g = new Prng(7);
    const x = 100 + g.nextInt(111) - 55, y = 400 + g.nextInt(111) - 55;
    expect(s1.lastShot).toMatchObject({ by: 'player', x, y });
    expect(s1.rng).toBe(g.state);
  });

  it('court bounds: lines are in, beyond them is out (point to the receiver)', () => {
    const { r, s } = start();
    expect(r.apply(s, p(450, 900)).lastShot.in).toBe(true);
    expect(r.apply(s, p(-450, 0)).lastShot.in).toBe(true);
    const out = r.apply(s, p(451, 450));
    expect(out).toMatchObject({ aiPts: 1, playerPts: 0, server: 'ai', turn: 'ai', rally: 0 });
    expect(out.lastShot).toEqual({ by: 'player', x: 451, y: 450, in: false, reached: false });
    expect(r.apply(s, p(0, -1)).aiPts).toBe(1);
    expect(r.apply(s, p(0, 901)).aiPts).toBe(1);
  });

  it('the rival returns balls within aiReach of its centre, otherwise the player scores', () => {
    const { r, s } = start();
    const ret = r.apply(s, p(150, 650)); // 150² + 200² = 250²: on the edge at level 1
    expect(ret).toMatchObject({ turn: 'ai', rally: 1, playerPts: 0, aiPts: 0 });
    expect(ret.lastShot).toMatchObject({ in: true, reached: true });
    const win = r.apply(s, p(151, 650));
    expect(win).toMatchObject({ playerPts: 1, server: 'player', turn: 'player', rally: 0 });
    expect(win.lastShot).toMatchObject({ in: true, reached: false });
    expect(r.apply(s, p(151, 650, 2)).turn).toBe('ai'); // level 2 reaches 300
  });

  it('the player returns balls within playerReach of its centre, otherwise the rival scores', () => {
    const { r, s } = start();
    const s1 = r.apply(s, p(0, 450));
    const s2 = r.apply(s1, a(228, 754)); // 228² + 304² = 380²: on the edge
    expect(s2).toMatchObject({ turn: 'player', rally: 2 });
    expect(s2.lastShot).toMatchObject({ by: 'ai', in: true, reached: true });
    const s3 = r.apply(s1, a(229, 754));
    expect(s3).toMatchObject({ aiPts: 1, playerPts: 0, server: 'ai', turn: 'ai', rally: 0 });
    expect(s3.lastShot).toMatchObject({ by: 'ai', in: true, reached: false });
    const s4 = r.apply(s1, a(0, 950)); // out: point to the player
    expect(s4).toMatchObject({ playerPts: 1, server: 'player', turn: 'player', rally: 0 });
    expect(s4.lastShot).toMatchObject({ in: false, reached: false });
  });

  it('end: win_points with a two-point lead, deuce goes on, max_points ends it', () => {
    expect(nohejbalOver(cfg, 10, 8)).toBe(true);
    expect(nohejbalOver(cfg, 10, 9)).toBe(false);
    expect(nohejbalOver(cfg, 9, 0)).toBe(false);
    expect(nohejbalOver(cfg, 12, 10)).toBe(true);
    expect(nohejbalOver(cfg, 13, 12)).toBe(false);
    expect(nohejbalOver(cfg, 15, 14)).toBe(true);
    expect(nohejbalOver(cfg, 14, 15)).toBe(true);
    const { r, s } = start();
    const won = r.apply({ ...s, playerPts: 9, aiPts: 3 }, p(400, 100));
    expect(won).toMatchObject({ playerPts: 10, over: true });
    expect(r.result(won)).toEqual({ winner: 'player', stars: 3, score: 10, playerPts: 10, aiPts: 3 });
    expect(() => r.apply(won, p(0, 0))).toThrow();
    const lost = r.apply({ ...s, playerPts: 14, aiPts: 14 }, p(0, -50));
    expect(lost).toMatchObject({ aiPts: 15, over: true });
    expect(r.result(lost)).toMatchObject({ winner: 'ai', stars: 0, score: 14 });
  });

  it('stars by the lead; draw only on a timeout tie', () => {
    const { r, s } = start();
    const res = (pp: number, ap: number) => r.result({ ...s, playerPts: pp, aiPts: ap, over: true })!;
    expect([[10, 4], [10, 5], [10, 7], [10, 8], [11, 9], [3, 3], [8, 10]].map(([x, y]) => res(x!, y!).stars)).toEqual([3, 2, 2, 1, 1, 0, 0]);
    const t = r.apply(s, { by: 'timeout' });
    expect(t.over).toBe(true);
    expect(r.result(t)).toMatchObject({ winner: 'draw', stars: 0 });
  });

  it('rejects the side not on turn, bad fields and moves after the end', () => {
    const { r, s } = start();
    expect(() => r.apply(s, a(0, 0))).toThrow();
    expect(() => r.apply(s, p(0, 0, 0))).toThrow();
    expect(() => r.apply(s, p(0, 0, 6))).toThrow();
    expect(() => r.apply(s, p(0, 0.5))).toThrow();
    expect(() => r.apply(r.apply(s, p(0, 450)), p(0, 450))).toThrow();
    expect(() => r.apply({ ...s, over: true }, { by: 'timeout' })).toThrow();
  });

  it('aiAction picks a corner with one ai draw', () => {
    const { r, s } = start();
    const ai = aiPrng(3);
    const g = aiPrng(3);
    for (let i = 0; i < 8; i++) {
      const k = g.nextInt(4);
      const m = cfg.aiMargin[1]!;
      expect(r.aiAction(s, 2, ai)).toEqual({ by: 'ai', x: (k % 2 === 0 ? -1 : 1) * (450 - m), y: k < 2 ? m : 900 - m, level: 2 });
      expect(ai.state).toBe(g.state);
    }
  });

  it('a seeded game replays to the same states', () => {
    const r = new NohejbalRules();
    const ai = aiPrng(11);
    const pol = new Prng(1234);
    let s = r.init(cfg, 11);
    const steps: Array<{ action: Record<string, unknown> }> = [];
    while (!s.over) {
      if (s.turn === 'player') {
        const act = p(pol.nextInt(901) - 450, pol.nextInt(901), 3);
        steps.push({ action: act as Record<string, unknown> });
        s = r.apply(s, act);
      } else {
        steps.push({ action: { by: 'ai', level: 3 } });
        s = r.apply(s, r.aiAction(s, 3, ai));
      }
    }
    const again = replay(new NohejbalRules() as never, { config: cfg as never, seed: 11, steps });
    expect(again.states.at(-1)).toEqual(s);
    expect(again.result).toEqual(r.result(s));
  });
});

describe('nohejbal UI helpers', () => {
  it('a swipe up aims past the net, sideways moves x', () => {
    expect(courtAim(0, -225, 2)).toEqual({ x: 0, y: 450 });
    expect(courtAim(-100, -300, 2)).toEqual({ x: -200, y: 600 });
    const g = courtAim(10.3, -100.4, 2);
    expect(Number.isInteger(g.x) && Number.isInteger(g.y)).toBe(true);
  });
});
