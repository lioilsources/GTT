/**
 * Integer minigame physics (specs/minigames/fyzika.md, version 1), shared by kulecnik, bowling,
 * minigolf (full world) and cihly, hokej (arithmetic and closest point). P0: integers only, every
 * formula rounds exactly as the spec says, so both clients move bodies bit for bit alike.
 */

/** Quotient rounded toward zero (`+ 0` turns −0 into 0 so JSON never sees it). */
export function trunc(a: number, b: number): number {
  return Math.trunc(a / b) + 0;
}

/** Largest s with s² ≤ n (n ≥ 0), exact. */
export function isqrt(n: number): number {
  if (n <= 0) return 0;
  let s = Math.floor(Math.sqrt(n));
  while (s * s > n) s--;
  while ((s + 1) * (s + 1) <= n) s++;
  return s;
}

export function clamp(v: number, lo: number, hi: number): number {
  return Math.min(Math.max(v, lo), hi);
}

/** A moving body: centre, velocity (u per step), radius, mass ≥ 1, `on` while in play. */
export interface Body {
  x: number;
  y: number;
  vx: number;
  vy: number;
  r: number;
  m: number;
  on: boolean;
}

export type Static =
  | { kind: 'rect'; x0: number; y0: number; x1: number; y1: number; e: number }
  | { kind: 'circle'; cx: number; cy: number; r: number; e: number };

export const rect = (x0: number, y0: number, x1: number, y1: number, e: number): Static => ({ kind: 'rect', x0, y0, x1, y1, e });
export const circle = (cx: number, cy: number, r: number, e: number): Static => ({ kind: 'circle', cx, cy, r, e });

/** A game's world: bodies, statics in the game's order and the game's hooks. */
export interface World {
  bodies: Body[];
  statics: Static[];
  /** Restitution of a body–body pair (per mille). */
  eBody: number;
  /** Step 2: may switch bodies off (pockets, goals, water); return true to end the simulation now. */
  capture?(w: World): boolean;
  /** Step 3: called for each pair whose velocities were resolved (vn < 0). */
  onHit?(i: number, j: number): void;
  /** Step 5: deceleration of body i (may depend on where it is). */
  dec(i: number, b: Body): number;
}

export function off(b: Body): void {
  b.on = false;
  b.vx = 0;
  b.vy = 0;
}

/** Body–body collision ("Srážka dvou těles"); true when the velocities were resolved (vn < 0). */
export function collideBodies(a: Body, b: Body, e: number): boolean {
  const dx = b.x - a.x, dy = b.y - a.y;
  const d2 = dx * dx + dy * dy;
  const R = a.r + b.r;
  if (d2 >= R * R || d2 === 0) return false;
  const vn = (b.vx - a.vx) * dx + (b.vy - a.vy) * dy;
  if (vn >= 0) return false;
  const k = trunc(vn * (1000 + e) * 1000, (a.m + b.m) * d2);
  a.vx += trunc(k * b.m * dx, 1000000);
  a.vy += trunc(k * b.m * dy, 1000000);
  b.vx -= trunc(k * a.m * dx, 1000000);
  b.vy -= trunc(k * a.m * dy, 1000000);
  return true;
}

/** Closest point of a static to (x, y). */
export function closest(s: Static, x: number, y: number): { qx: number; qy: number } {
  return s.kind === 'rect' ? { qx: clamp(x, s.x0, s.x1), qy: clamp(y, s.y0, s.y1) } : { qx: s.cx, qy: s.cy };
}

/** Body–static collision ("Srážka se statikou"). */
export function collideStatic(b: Body, s: Static): void {
  const { qx, qy } = closest(s, b.x, b.y);
  const dx = b.x - qx, dy = b.y - qy;
  const d2 = dx * dx + dy * dy;
  const reach = s.kind === 'rect' ? b.r : b.r + s.r;
  if (d2 <= 0 || d2 >= reach * reach) return;
  const vn = b.vx * dx + b.vy * dy;
  if (vn >= 0) return;
  const k = trunc(vn * (1000 + s.e) * 1000, d2);
  b.vx -= trunc(k * dx, 1000000);
  b.vy -= trunc(k * dy, 1000000);
}

/** Friction ("Tření") with deceleration `dec ≥ 0`. */
export function friction(b: { vx: number; vy: number }, dec: number): void {
  const s = isqrt(b.vx * b.vx + b.vy * b.vy);
  if (s <= dec) {
    b.vx = 0;
    b.vy = 0;
    return;
  }
  b.vx -= trunc(b.vx * dec, s);
  b.vy -= trunc(b.vy * dec, s);
}

/** One simulation step in the fixed order: move, capture, body–body, statics, friction. Returns true when capture ended it. */
export function step(w: World): boolean {
  const bs = w.bodies;
  for (const b of bs) {
    if (!b.on) continue;
    b.x += b.vx;
    b.y += b.vy;
  }
  if (w.capture?.(w)) return true;
  for (let i = 0; i < bs.length; i++) {
    for (let j = i + 1; j < bs.length; j++) {
      const a = bs[i]!, b = bs[j]!;
      if (!a.on || !b.on) continue;
      if (collideBodies(a, b, w.eBody)) w.onHit?.(i, j);
    }
  }
  for (const b of bs) {
    if (!b.on) continue;
    for (const s of w.statics) collideStatic(b, s);
  }
  for (let i = 0; i < bs.length; i++) {
    const b = bs[i]!;
    if (b.on) friction(b, w.dec(i, b));
  }
  return false;
}

export function moving(w: World): boolean {
  return w.bodies.some((b) => b.on && (b.vx !== 0 || b.vy !== 0));
}

/**
 * "Konec simulace úderu": steps while anything moves, at most `maxSteps`; leftover velocities are
 * zeroed. `onStep` (UI) sees the world after each whole step. Returns the steps taken and whether
 * capture ended the simulation.
 */
export function simulate(w: World, maxSteps: number, onStep?: (w: World) => void): { steps: number; captured: boolean } {
  let n = 0;
  let captured = false;
  while (n < maxSteps && moving(w)) {
    captured = step(w);
    n++;
    onStep?.(w);
    if (captured) break;
  }
  for (const b of w.bodies) {
    b.vx = 0;
    b.vy = 0;
  }
  return { steps: n, captured };
}

/** "Úder": velocity of speed `sp` from (x, y) towards (ax, ay); null when the aim is the centre (L = 0). */
export function shotVelocity(x: number, y: number, ax: number, ay: number, sp: number): { vx: number; vy: number } | null {
  const dx = ax - x, dy = ay - y;
  const L = isqrt(dx * dx + dy * dy);
  if (L === 0) return null;
  return { vx: trunc(sp * dx, L), vy: trunc(sp * dy, L) };
}

export const AIM_R = 100000;

/** "Normované míření": the aim point moved to AIM_R from (x, y); null when L = 0. */
export function normalizedAim(x: number, y: number, ax: number, ay: number): { x: number; y: number } | null {
  const dx = ax - x, dy = ay - y;
  const L = isqrt(dx * dx + dy * dy);
  if (L === 0) return null;
  return { x: x + trunc(dx * AIM_R, L), y: y + trunc(dy * AIM_R, L) };
}
