import { describe, expect, it } from 'vitest';

import {
  circle,
  collideBodies,
  collideStatic,
  friction,
  isqrt,
  normalizedAim,
  rect,
  shotVelocity,
  simulate,
  step,
  trunc,
  type Body,
  type World,
} from '../src/minigames/physics';

const body = (o: Partial<Body>): Body => ({ x: 0, y: 0, vx: 0, vy: 0, r: 10, m: 1, on: true, ...o });

describe('integer physics (specs/minigames/fyzika.md)', () => {
  it('trunc rounds toward zero and never yields -0', () => {
    expect(trunc(7, 2)).toBe(3);
    expect(trunc(-7, 2)).toBe(-3);
    expect(Object.is(trunc(-1, 2), 0)).toBe(true);
  });

  it('isqrt is exact around perfect squares and large values', () => {
    for (const n of [0, 1, 2, 3, 4, 15, 16, 17, 99, 100, 101]) expect(isqrt(n)).toBe(Math.floor(Math.sqrt(n)));
    const big = 94906265 ** 2;
    expect(isqrt(big)).toBe(94906265);
    expect(isqrt(big - 1)).toBe(94906264);
    expect(isqrt(-5)).toBe(0);
  });

  it('head-on equal masses swap velocities (e = 1000)', () => {
    const a = body({ x: 0, vx: 5 }), b = body({ x: 10, vx: 0 });
    expect(collideBodies(a, b, 1000)).toBe(true);
    expect([a.vx, b.vx]).toEqual([0, 5]);
  });

  it('separating or coincident bodies do not collide', () => {
    expect(collideBodies(body({ vx: -5 }), body({ x: 15 }), 1000)).toBe(false);
    expect(collideBodies(body({}), body({}), 1000)).toBe(false);
  });

  it('flat wall reflects only the normal component; corner and circle along the contact line', () => {
    const b = body({ x: 5, y: 50, vx: -4, vy: 3 });
    collideStatic(b, rect(-100, 0, 0, 100, 1000));
    expect([b.vx, b.vy]).toEqual([4, 3]);
    const c = body({ x: 6, y: 8, vx: -3, vy: -4 });
    collideStatic(c, circle(0, 0, 5, 1000));
    expect([c.vx, c.vy]).toEqual([3, 4]);
    const inside = body({ x: 50, y: 50, vx: -4 });
    collideStatic(inside, rect(0, 0, 100, 100, 1000));
    expect(inside.vx).toBe(-4);
  });

  it('friction slows along the velocity and stops at s ≤ dec', () => {
    const v = { vx: 30, vy: 40 };
    friction(v, 5);
    expect(v).toEqual({ vx: 27, vy: 36 });
    const w = { vx: 3, vy: 4 };
    friction(w, 5);
    expect(w).toEqual({ vx: 0, vy: 0 });
  });

  it('shot and normalized aim', () => {
    expect(shotVelocity(0, 0, 0, 0, 10)).toBeNull();
    expect(shotVelocity(0, 0, 3, 4, 100)).toEqual({ vx: 60, vy: 80 });
    expect(normalizedAim(10, 10, 13, 14)).toEqual({ x: 60010, y: 80010 });
  });

  it('step order: move, capture, pairs, statics, friction; simulate zeroes leftovers', () => {
    const order: string[] = [];
    const w: World = {
      bodies: [body({ x: 0, vx: 100 }), body({ x: 115 })],
      statics: [],
      eBody: 1000,
      capture: () => (order.push('capture'), false),
      onHit: (i, j) => order.push(`hit ${i},${j}`),
      dec: () => (order.push('dec'), 1),
    };
    step(w);
    expect(order).toEqual(['capture', 'hit 0,1', 'dec', 'dec']);
    const out = simulate(w, 3);
    expect(out.steps).toBe(3);
    expect(w.bodies.every((b) => b.vx === 0 && b.vy === 0)).toBe(true);
  });
});
