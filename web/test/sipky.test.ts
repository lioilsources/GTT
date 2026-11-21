import { describe, expect, it } from 'vitest';

import { Prng } from '../src/rules/prng';
import { aiPrng, replay } from '../src/minigames/rules';
import { aiTarget, scoreAt, SipkyRules, type SipkyConfig } from '../src/minigames/sipky/rules';

const cfg: SipkyConfig = { start: 301, maxRounds: 15, playerScatter: 60, aiScatter: [420, 300, 210, 150, 100], starDarts: [18, 27] };
const exact: SipkyConfig = { ...cfg, playerScatter: 0, aiScatter: [0, 0, 0, 0, 0] };

describe('sipky board (specs/minigames/sipky.md "Terč")', () => {
  it('scores bull, outer bull, trebles, doubles, singles and misses', () => {
    expect(scoreAt(0, 0)).toEqual({ points: 50, mult: 2 });
    expect(scoreAt(64, 0)).toEqual({ points: 50, mult: 2 });
    expect(scoreAt(65, 0)).toEqual({ points: 25, mult: 1 });
    expect(scoreAt(0, -159)).toEqual({ points: 25, mult: 1 });
    expect(scoreAt(160, 0)).toEqual({ points: 6, mult: 1 });
    expect(scoreAt(0, 574)).toEqual({ points: 20, mult: 1 });
    expect(scoreAt(0, 989)).toEqual({ points: 20, mult: 1 });
    expect(scoreAt(0, 990)).toEqual({ points: 60, mult: 3 });
    expect(scoreAt(0, 1030)).toEqual({ points: 60, mult: 3 });
    expect(scoreAt(0, 1069)).toEqual({ points: 60, mult: 3 });
    expect(scoreAt(0, 1070)).toEqual({ points: 20, mult: 1 });
    expect(scoreAt(0, 1619)).toEqual({ points: 20, mult: 1 });
    expect(scoreAt(0, 1620)).toEqual({ points: 40, mult: 2 });
    expect(scoreAt(0, 1660)).toEqual({ points: 40, mult: 2 });
    expect(scoreAt(0, 1699)).toEqual({ points: 40, mult: 2 });
    expect(scoreAt(0, 1700)).toEqual({ points: 0, mult: 0 });
    expect(scoreAt(2000, 0)).toEqual({ points: 0, mult: 0 });
  });

  it('sector boundaries go to the clockwise sector', () => {
    // (±500, ±500) lie exactly on B[2], B[7], B[12], B[17].
    expect(scoreAt(500, 500).points).toBe(4);
    expect(scoreAt(500, -500).points).toBe(2);
    expect(scoreAt(-500, -500).points).toBe(16);
    expect(scoreAt(-500, 500).points).toBe(12);
    // Just either side of B[0] (9° from +y): tan 9° ≈ 0.1584.
    expect(scoreAt(95, 600).points).toBe(20);
    expect(scoreAt(96, 600).points).toBe(1);
    expect(scoreAt(-95, 600).points).toBe(20);
    expect(scoreAt(-96, 600).points).toBe(5);
    expect(scoreAt(600, 0).points).toBe(6);
    expect(scoreAt(-600, 0).points).toBe(11);
    expect(scoreAt(0, -600).points).toBe(3);
  });
});

describe('sipky rules (specs/minigames/sipky.md)', () => {
  it('starts at 301 with the player', () => {
    const r = new SipkyRules();
    const s = r.init(cfg, 42);
    expect(s).toMatchObject({ player: 301, ai: 301, turn: 'player', dart: 0, turnStart: 301, playerDarts: 0, round: 1, over: false });
    expect(s.lastHit).toEqual({ x: 0, y: 0, points: 0, mult: 0 });
    expect(r.legalActions(s)).toEqual([]);
  });

  it('rejects illegal actions', () => {
    const r = new SipkyRules();
    const s = r.init(cfg, 1);
    expect(() => r.apply(s, { by: 'ai', x: 0, y: 0, level: 3 })).toThrow();
    expect(() => r.apply(s, { by: 'player', x: 0.5, y: 0 })).toThrow();
    expect(() => r.apply(r.apply(s, { by: 'timeout' }), { by: 'player', x: 0, y: 0 })).toThrow();
  });

  it('scatter draws x then y from the state rng', () => {
    const r = new SipkyRules();
    const s = r.init(cfg, 77);
    const p = new Prng(s.rng);
    const dx = p.nextInt(121) - 60, dy = p.nextInt(121) - 60;
    const n = r.apply(s, { by: 'player', x: 0, y: 1030 });
    expect(n.lastHit).toMatchObject({ x: dx, y: 1030 + dy, ...scoreAt(dx, 1030 + dy) });
    expect(n.rng).toBe(p.state);
    expect(n.playerDarts).toBe(1);
    expect(n.dart).toBe(1);
  });

  it('three darts end the turn; the AI turn ends the round', () => {
    const r = new SipkyRules();
    let s = r.init(exact, 1);
    for (let i = 0; i < 3; i++) s = r.apply(s, { by: 'player', x: 0, y: 1030 });
    expect(s).toMatchObject({ player: 121, turn: 'ai', dart: 0, turnStart: 301, playerDarts: 3, round: 1 });
    for (let i = 0; i < 3; i++) s = r.apply(s, { by: 'ai', x: 0, y: 574, level: 2 });
    expect(s).toMatchObject({ ai: 241, turn: 'player', dart: 0, turnStart: 121, round: 2 });
  });

  it('a bust restores the turn start and ends the turn', () => {
    const r = new SipkyRules();
    let s = { ...r.init(exact, 3), player: 70, turnStart: 70 };
    s = r.apply(s, { by: 'player', x: 0, y: 574 });
    expect(s).toMatchObject({ player: 50, dart: 1 });
    s = r.apply(s, { by: 'player', x: 0, y: 1030 });
    expect(s).toMatchObject({ player: 70, turn: 'ai', dart: 0, turnStart: 301, playerDarts: 2 });
    expect(s.lastHit).toEqual({ x: 0, y: 1030, points: 60, mult: 3 });
  });

  it('an exact finish wins at once', () => {
    const r = new SipkyRules();
    const s = r.apply({ ...r.init(exact, 3), player: 40, turnStart: 40, playerDarts: 17, dart: 2 }, { by: 'player', x: 0, y: 1660 });
    expect(s).toMatchObject({ player: 0, over: true, playerDarts: 18 });
    expect(r.result(s)).toEqual({ winner: 'player', stars: 3, score: 301, player: 0, ai: 301, playerDarts: 18 });
    expect(r.result({ ...s, playerDarts: 19 })!.stars).toBe(2);
    expect(r.result({ ...s, playerDarts: 28 })!.stars).toBe(1);
  });

  it('AI targets by remaining score', () => {
    expect(aiTarget(50)).toEqual({ x: 0, y: 0 });
    expect(aiTarget(20)).toEqual({ x: 0, y: 574 });
    expect(aiTarget(40)).toEqual({ x: 0, y: 1660 });
    expect(aiTarget(57)).toEqual({ x: -318, y: -980 });
    expect(aiTarget(60)).toEqual({ x: 0, y: 1030 });
    expect(aiTarget(61)).toEqual({ x: 0, y: 1030 });
    expect(aiTarget(301)).toEqual({ x: 0, y: 1030 });
    expect(aiTarget(25)).toEqual({ x: -177, y: 546 });
    expect(scoreAt(aiTarget(57).x, aiTarget(57).y)).toEqual({ points: 57, mult: 3 });
    for (let z = 1; z <= 60; z++) {
      const { x, y } = aiTarget(z);
      const p = scoreAt(x, y).points;
      if (z <= 20 || (z <= 40 && z % 2 === 0) || z % 3 === 0 || z === 50) expect(p).toBe(z);
      else expect(p).toBe(z - 20 >= 1 && z - 20 <= 20 ? z - 20 : 60);
    }
    const r = new SipkyRules();
    const s = { ...r.init(cfg, 1), ai: 57, turn: 'ai' as const };
    expect(r.aiAction(s, 4, aiPrng(1))).toEqual({ by: 'ai', x: -318, y: -980, level: 4 });
  });

  it('max rounds and timeout end the game on the lower score', () => {
    const r = new SipkyRules();
    let s = r.init({ ...exact, maxRounds: 1 }, 5);
    for (let i = 0; i < 3; i++) s = r.apply(s, { by: 'player', x: 3000, y: 0 });
    for (let i = 0; i < 3; i++) s = r.apply(s, { by: 'ai', x: 0, y: 1030, level: 5 });
    expect(s).toMatchObject({ round: 2, over: true });
    expect(r.result(s)).toEqual({ winner: 'ai', stars: 0, score: 0, player: 301, ai: 121, playerDarts: 3 });
    const t = r.apply(r.init(cfg, 5), { by: 'timeout' });
    expect(r.result(t)).toMatchObject({ winner: 'draw', stars: 0, score: 0 });
    expect(r.result(r.init(cfg, 5))).toBeNull();
  });

  it('a whole game replays to the same state', () => {
    const r = new SipkyRules();
    const steps = [];
    let s = r.init(cfg, 99);
    const ai = aiPrng(99);
    while (!s.over && steps.length < 500) {
      if (s.turn === 'ai') {
        steps.push({ action: { by: 'ai', level: 3 } as Record<string, unknown> });
        s = r.apply(s, r.aiAction(s, 3, ai));
      } else {
        const a = { by: 'player' as const, ...aiTarget(s.player) };
        steps.push({ action: a as Record<string, unknown> });
        s = r.apply(s, a);
      }
    }
    expect(s.over).toBe(true);
    const again = replay(new SipkyRules() as never, { config: cfg as never, seed: 99, steps });
    expect(again.states.at(-1)).toEqual(s);
  });
});
