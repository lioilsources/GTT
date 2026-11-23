import type { TuningControls } from '../gen/tuning';

/** What the driver asks for this frame (specs/controls.md). steer > 0 turns right. */
export class ControlInput {
  steer = 0;
  /** 0..1; without it the car accelerates by itself up to cruise speed. */
  throttle = 0;
  /** 0..1; held while slow or stopped it reverses. */
  brake = 0;
  handbrake = false;
  /** Asks for top speed instead of cruise. */
  boost = false;
  /**
   * Engine off: no automatic throttle and no engine braking (scenario input "coast",
   * specs/terrain.md "Scénáře"; the game itself never sets it).
   */
  coast = false;

  reset(): void {
    this.coast = false;
    this.steer = 0;
    this.throttle = 0;
    this.brake = 0;
    this.handbrake = false;
    this.boost = false;
  }
}

export interface ScreenPt {
  x: number;
  y: number;
}
export interface ScreenRect {
  left: number;
  top: number;
  width: number;
  height: number;
}

const inRect = (r: ScreenRect, p: ScreenPt, pad: number): boolean =>
  p.x >= r.left - pad && p.x <= r.left + r.width + pad && p.y >= r.top - pad && p.y <= r.top + r.height + pad;

const clamp = (v: number, lo: number, hi: number): number => Math.min(hi, Math.max(lo, v));

export type ControlSchemeId = 'a' | 'b' | 'c';

/** A touch layout: pointer events in, ControlInput out. Pure logic (port of drive_core controls.dart). */
export interface ControlScheme {
  readonly id: ControlSchemeId;
  down(pointer: number, p: ScreenPt, w: number, h: number): void;
  move(pointer: number, p: ScreenPt, w: number, h: number): void;
  up(pointer: number): void;
  update(out: ControlInput): void;
}

export function createScheme(id: ControlSchemeId, t: TuningControls): ControlScheme {
  return id === 'a' ? new SchemeA(t) : id === 'b' ? new SchemeB() : new SchemeC(t);
}

/** A (default): drag sideways steers, down brakes/reverses, up boosts; a second finger is the handbrake. */
export class SchemeA implements ControlScheme {
  readonly id = 'a' as const;
  private main: number | null = null;
  origin: ScreenPt = { x: 0, y: 0 };
  pos: ScreenPt = { x: 0, y: 0 };
  private w = 1;
  private h = 1;
  private readonly extra = new Set<number>();

  constructor(readonly t: TuningControls) {}

  get active(): boolean {
    return this.main !== null;
  }

  down(pointer: number, p: ScreenPt, w: number, h: number): void {
    this.w = Math.max(w, 1);
    this.h = Math.max(h, 1);
    if (this.main === null) {
      this.main = pointer;
      this.origin = { ...p };
      this.pos = { ...p };
    } else {
      this.extra.add(pointer);
    }
  }

  move(pointer: number, p: ScreenPt): void {
    if (pointer === this.main) this.pos = { ...p };
  }

  up(pointer: number): void {
    if (pointer === this.main) {
      this.main = null;
      // A remaining finger becomes the steering thumb.
      const next = this.extra.values().next();
      if (!next.done) {
        this.main = next.value;
        this.extra.delete(next.value);
        this.origin = { ...this.pos };
      }
    } else {
      this.extra.delete(pointer);
    }
  }

  update(out: ControlInput): void {
    if (this.main === null) return;
    const t = this.t;
    out.steer = clamp((this.pos.x - this.origin.x) / (t.aFullSteerWidth * this.w), -1, 1);
    const v = (this.pos.y - this.origin.y) / this.h;
    if (v > t.aDeadZoneHeight) out.brake = clamp((v - t.aDeadZoneHeight) / t.aFullBrakeHeight, 0, 1);
    if (v < -t.aDeadZoneHeight) out.boost = true;
    if (this.extra.size > 0) out.handbrake = true;
  }
}

/**
 * B: hold the left or right half to steer; both halves brake (and reverse). v2: a finger that
 * starts on the Boost button bottom centre boosts until lifted and steers nothing.
 */
export class SchemeB implements ControlScheme {
  readonly id = 'b' as const;
  private readonly right = new Map<number, boolean>();
  private readonly boost = new Set<number>();

  get leftHeld(): boolean {
    for (const v of this.right.values()) if (!v) return true;
    return false;
  }
  get rightHeld(): boolean {
    for (const v of this.right.values()) if (v) return true;
    return false;
  }
  get boostHeld(): boolean {
    return this.boost.size > 0;
  }

  // Layout in screen-width units (presentation, specs/controls.md v2).
  static boostButton(w: number, h: number): ScreenRect {
    return { left: w * 0.38, top: h - w * 0.28, width: w * 0.24, height: w * 0.2 };
  }

  down(pointer: number, p: ScreenPt, w: number, h: number): void {
    if (inRect(SchemeB.boostButton(w, h), p, 8)) this.boost.add(pointer);
    else this.right.set(pointer, p.x > w / 2);
  }
  move(pointer: number, p: ScreenPt, w: number): void {
    if (this.right.has(pointer)) this.right.set(pointer, p.x > w / 2);
  }
  up(pointer: number): void {
    this.right.delete(pointer);
    this.boost.delete(pointer);
  }
  update(out: ControlInput): void {
    if (this.rightHeld && this.leftHeld) out.brake = 1;
    else if (this.rightHeld) out.steer = 1;
    else if (this.leftHeld) out.steer = -1;
    if (this.boost.size > 0) out.boost = true;
  }
}

/**
 * C: a virtual steering wheel bottom centre, brake pedal bottom right, handbrake bottom left;
 * v2: a Boost button above the brake pedal.
 */
export class SchemeC implements ControlScheme {
  readonly id = 'c' as const;
  private wheel: number | null = null;
  private grabAngle = 0;
  /** Current wheel rotation, radians, + = clockwise (right). */
  wheelAngle = 0;
  private readonly brake = new Set<number>();
  private readonly hand = new Set<number>();
  private readonly boost = new Set<number>();

  constructor(readonly t: TuningControls) {}

  get brakeHeld(): boolean {
    return this.brake.size > 0;
  }
  get handHeld(): boolean {
    return this.hand.size > 0;
  }
  get boostHeld(): boolean {
    return this.boost.size > 0;
  }

  // Layout in screen-width units (presentation, specs/controls.md).
  static wheelCentre(w: number, h: number): ScreenPt {
    return { x: w / 2, y: h - w * 0.26 };
  }
  static wheelRadius(w: number): number {
    return w * 0.2;
  }
  static pedal(w: number, h: number): ScreenRect {
    return { left: w * 0.8, top: h - w * 0.42, width: w * 0.17, height: w * 0.3 };
  }
  static handButton(w: number, h: number): ScreenRect {
    return { left: w * 0.03, top: h - w * 0.3, width: w * 0.17, height: w * 0.17 };
  }
  static boostButton(w: number, h: number): ScreenRect {
    return { left: w * 0.8, top: h - w * 0.64, width: w * 0.17, height: w * 0.17 };
  }

  private angle(p: ScreenPt, w: number, h: number): number {
    const c = SchemeC.wheelCentre(w, h);
    return Math.atan2(p.x - c.x, -(p.y - c.y));
  }

  down(pointer: number, p: ScreenPt, w: number, h: number): void {
    const c = SchemeC.wheelCentre(w, h);
    if (inRect(SchemeC.pedal(w, h), p, 8)) this.brake.add(pointer);
    else if (inRect(SchemeC.boostButton(w, h), p, 8)) this.boost.add(pointer);
    else if (inRect(SchemeC.handButton(w, h), p, 8)) this.hand.add(pointer);
    else if (this.wheel === null && Math.hypot(p.x - c.x, p.y - c.y) < SchemeC.wheelRadius(w) * 1.6) {
      this.wheel = pointer;
      this.grabAngle = this.angle(p, w, h) - this.wheelAngle;
    }
  }

  move(pointer: number, p: ScreenPt, w: number, h: number): void {
    if (pointer !== this.wheel) return;
    let a = this.angle(p, w, h) - this.grabAngle;
    while (a > Math.PI) a -= 2 * Math.PI;
    while (a < -Math.PI) a += 2 * Math.PI;
    this.wheelAngle = clamp(a, -this.t.cMaxWheelRad, this.t.cMaxWheelRad);
  }

  up(pointer: number): void {
    if (pointer === this.wheel) {
      this.wheel = null;
      this.wheelAngle = 0;
    }
    this.brake.delete(pointer);
    this.hand.delete(pointer);
    this.boost.delete(pointer);
  }

  update(out: ControlInput): void {
    out.steer = this.wheelAngle / this.t.cMaxWheelRad;
    if (this.brake.size > 0) out.brake = 1;
    if (this.hand.size > 0) out.handbrake = true;
    if (this.boost.size > 0) out.boost = true;
  }
}

/** Desktop keyboard (specs/controls.md): arrows/WASD, space = handbrake. */
export function applyKeys(keys: ReadonlySet<string>, out: ControlInput): void {
  const any = (...k: string[]): boolean => k.some((c) => keys.has(c));
  if (any('ArrowLeft', 'KeyA')) out.steer = -1;
  if (any('ArrowRight', 'KeyD')) out.steer = 1;
  if (any('ArrowDown', 'KeyS')) out.brake = 1;
  if (any('ArrowUp', 'KeyW')) out.boost = true;
  if (any('Space')) out.handbrake = true;
}
