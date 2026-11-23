import type { TuningCameraChase } from '../gen/tuning';

/**
 * Oblique chase camera of client W (specs/terrain.md "Šikmý pohled", "Upřesnění T2"; P2). Pure
 * part: the pose behind the car, the field of view, the occluder test, the camera-mode setting
 * and the two-finger double tap. worldView.ts renders it, farRing.ts draws the lod ring.
 */

export type CameraMode = 'topdown' | 'chase';

/** Far ring radius, fog start and end (m, specs/terrain.md; the fog ramps in squared). */
export const RING_M = 1500;
export const FOG_START_M = 500;
export const FOG_END_M = 1500;
/** Chase view: the driven car is a box this tall, its top drawing on the roof (hop roll in 3D). */
export const CHASE_BODY_M = 1.2;
/** Chase view: traffic, pedestrians and roads are kept this far around the car (m). */
export const CHASE_NEAR_M = 300;
/** Occluding buildings (specs/terrain.md): within 6 m of the camera–car segment, drawn at 0.3 coverage. */
export const FADE_RADIUS_M = 6;
export const FADE_COVERAGE = 0.3;
/** Two-finger double tap: the second tap within 0.35 s (specs/terrain.md). */
export const DOUBLE_TAP_S = 0.35;
/** The eye stays at least this high over the ground under it (a hill behind the car). */
export const EYE_CLEARANCE_M = 4;

/** Fog of the chase view at distance d: ((d − start) / (end − start))², clamped to 0..1 (mirrors the shaders). */
export function fogFactor(d: number): number {
  const k = Math.min(1, Math.max(0, (d - FOG_START_M) / (FOG_END_M - FOG_START_M)));
  return k * k;
}

/** World point: x east, y north, z up (metres). */
export interface P3 { x: number; y: number; z: number }

export interface ChasePose { eye: P3; target: P3 }

/**
 * Camera `distance_m` behind the car along [heading] at `zRef + height_m`, aiming `look_ahead_m`
 * ahead at zRef. [zoom] (the edge / landing zoom-out) scales distance and height; [groundAt] lifts
 * the eye over a hill behind the car.
 */
export function chasePose(
  x: number, y: number, zRef: number, heading: number, c: TuningCameraChase, zoom = 1,
  groundAt: ((x: number, y: number) => number | null) | null = null,
): ChasePose {
  const dx = Math.cos(heading), dy = Math.sin(heading);
  const d = c.distanceM * zoom;
  const ex = x - dx * d, ey = y - dy * d;
  let ez = zRef + c.heightM * zoom;
  const g = groundAt?.(ex, ey);
  if (g !== null && g !== undefined) ez = Math.max(ez, g + EYE_CLEARANCE_M);
  return { eye: { x: ex, y: ey, z: ez }, target: { x: x + dx * c.lookAheadM, y: y + dy * c.lookAheadM, z: zRef } };
}

/** Pitch below the horizon (radians) of the default pose: atan(height / (distance + look ahead)). */
export function chasePitch(c: TuningCameraChase): number {
  return Math.atan2(c.heightM, c.distanceM + c.lookAheadM);
}

/** `fov_deg` holds for the shorter screen side: horizontal in portrait, vertical in landscape. */
export function chaseFov(c: TuningCameraChase, w: number, h: number): { fov: number; horizontal: boolean } {
  return { fov: (c.fovDeg * Math.PI) / 180, horizontal: w <= h };
}

/**
 * Occluder test of the fade (mirrors the shader): point p is nearer the camera than the car, at
 * most FADE_RADIUS_M from the eye–car segment and above half the car ([car] is 1 m over its base).
 */
export function occludes(eye: P3, car: P3, p: P3): boolean {
  const vx = car.x - eye.x, vy = car.y - eye.y, vz = car.z - eye.z;
  const l2 = vx * vx + vy * vy + vz * vz;
  if (l2 < 1e-6) return false;
  const t = ((p.x - eye.x) * vx + (p.y - eye.y) * vy + (p.z - eye.z) * vz) / l2;
  if (t <= 0 || t >= 1 || p.z <= car.z - 0.5) return false;
  const qx = eye.x + vx * t - p.x, qy = eye.y + vy * t - p.y, qz = eye.z + vz * t - p.z;
  return qx * qx + qy * qy + qz * qz <= FADE_RADIUS_M * FADE_RADIUS_M;
}

/** localStorage key of the camera choice (W only; the P0 save does not carry it). */
export const CAMERA_KEY = 'metro:camera';

/** The slice of Storage the setting uses (localStorage in the browser, a fake in tests). */
export interface ModeStore {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
}

function defaultStore(): ModeStore | null {
  try {
    return typeof localStorage === 'undefined' ? null : localStorage;
  } catch {
    return null;
  }
}

/** Start mode: `?camera=` (debug), else the remembered choice, else top-down (K1 = A). */
export function readCameraMode(param: string | null, store: ModeStore | null = defaultStore()): CameraMode {
  if (param === 'chase' || param === 'topdown') return param;
  try {
    return store?.getItem(CAMERA_KEY) === 'chase' ? 'chase' : 'topdown';
  } catch {
    return 'topdown';
  }
}

export function writeCameraMode(mode: CameraMode, store: ModeStore | null = defaultStore()): void {
  try {
    store?.setItem(CAMERA_KEY, mode);
  } catch {
    // Private mode or blocked storage: the choice lasts for this session only.
  }
}

/**
 * Two-finger double tap: a tap = two pointers down together and both up again without moving far;
 * a second such tap within DOUBLE_TAP_S fires. Times in seconds, positions in CSS pixels.
 */
export class TwoFingerTap {
  private readonly down = new Map<number, { x: number; y: number; t: number }>();
  /** Two fingers were down at once since the last release of all pointers. */
  private pair = false;
  private moved = false;
  private pairAt = 0;
  private lastTap = -Infinity;

  constructor(readonly maxMovePx = 24, readonly maxHoldS = 0.3) {}

  pointerDown(id: number, x: number, y: number, t: number): void {
    this.down.set(id, { x, y, t });
    if (this.down.size === 2 && !this.pair) {
      this.pair = true;
      this.moved = false;
      this.pairAt = t;
    } else if (this.down.size > 2) {
      this.moved = true;
    }
  }

  pointerMove(id: number, x: number, y: number): void {
    const p = this.down.get(id);
    if (p && Math.hypot(x - p.x, y - p.y) > this.maxMovePx) this.moved = true;
  }

  /** Returns true when this release completes a double tap. */
  pointerUp(id: number, t: number): boolean {
    if (!this.down.delete(id) || this.down.size > 0) return false;
    if (!this.pair) return false;
    this.pair = false;
    if (this.moved || t - this.pairAt > this.maxHoldS) {
      this.lastTap = -Infinity;
      return false;
    }
    if (t - this.lastTap <= DOUBLE_TAP_S) {
      this.lastTap = -Infinity;
      return true;
    }
    this.lastTap = t;
    return false;
  }

  cancel(id: number): void {
    this.down.delete(id);
    if (this.down.size === 0) this.pair = false;
  }
}
