import { Body, Fixture, Polygon, World, type Vec2Value } from 'planck';

import type { TuningDrive } from '../gen/tuning';
import type { CarSpec } from '../gen/schema';
import type { ControlInput } from './controls';

/** Collision categories. */
export const CAT_BUILDINGS = 1;
export const CAT_CAR = 2;
/** AI traffic (specs/traffic.md): collides with the player's car and, on the ground, parked cars. */
export const CAT_TRAFFIC = 4;
/** Parked cars (specs/cars.md): dynamic bodies the player and traffic can push. */
export const CAT_PARKED = 8;
/** Tram cars (specs/trams.md): kinematic, never pushed; collide with the player in the same layer. */
export const CAT_TRAM = 64;
/** Pedestrian-zone bollard lines (specs/zones.md): static, layer 0, collide with the player only. */
export const CAT_ZONE = 32;

/**
 * Whether the player's mask contains CAT_ZONE (specs/zones.md "Kdo smí do zóny"): micro vehicles
 * pass bollards, and a car whose centre is inside a zone always gets out again.
 */
export function zoneMask(carClass: CarSpec['class'], insideZone: boolean): boolean {
  return carClass !== 'micro' && !insideZone;
}

const clamp = (v: number, lo: number, hi: number): number => Math.min(hi, Math.max(lo, v));

/**
 * Player car on a planck.js body with the custom tyre model of specs/drive.md (port of
 * drive_core car.dart): each step the lateral velocity at each axle is cancelled by an
 * impulse capped by that axle's grip; past the cap the axle slides, which is the drift.
 */
export class Car {
  readonly body: Body;
  readonly halfLength: number;
  readonly halfWidth: number;
  private readonly fixture: Fixture;

  /** Current front wheel angle (radians, + = left). */
  wheelAngle = 0;
  layer = 0;
  /** CAT_ZONE is in the mask (only effective on layer 0); see zoneMask. */
  zone = false;
  /** In the air (specs/hop.md): the mask holds buildings only. */
  airborne = false;
  /** Lateral slip left over at each axle in the last step, m/s (skid marks). */
  rearSlip = 0;
  frontSlip = 0;
  braking = false;
  /** Multiplies both axles' grip (weather input, specs/weather.md); 1 = the spec's grip. */
  gripScale = 1;
  reversing = false;
  /** Longitudinal engine/brake acceleration of the last drive step (m/s²); 0 = no throttle. */
  accel = 0;

  // Scratch vectors: no allocations in the step.
  private readonly f: Vec2Value = { x: 0, y: 0 };
  private readonly p: Vec2Value = { x: 0, y: 0 };

  constructor(
    readonly world: World,
    readonly spec: CarSpec,
    readonly t: TuningDrive,
    x: number,
    y: number,
    heading: number,
    readonly scale: number,
  ) {
    this.halfLength = (spec.length_m * scale) / 2;
    this.halfWidth = (spec.width_m * scale) / 2;
    this.body = world.createBody({
      type: 'dynamic',
      position: { x, y },
      angle: heading,
      angularDamping: t.angularDamping,
      bullet: true,
    });
    // Box2D v3 (client F) uses a box rounded by body_round_m; planck has no rounded polygons,
    // so the same outline is approximated by a box with chamfered corners.
    const r = t.bodyRoundM, hl = this.halfLength + r, hw = this.halfWidth + r;
    const outline = [
      { x: hl, y: hw - r }, { x: hl - r, y: hw }, { x: -hl + r, y: hw }, { x: -hl, y: hw - r },
      { x: -hl, y: -hw + r }, { x: -hl + r, y: -hw }, { x: hl - r, y: -hw }, { x: hl, y: -hw + r },
    ];
    this.fixture = this.body.createFixture({
      shape: new Polygon(outline),
      density: spec.mass / (4 * this.halfLength * this.halfWidth),
      friction: t.carFriction,
      restitution: t.carRestitution,
      filterCategoryBits: CAT_CAR,
      filterMaskBits: CAT_BUILDINGS | CAT_TRAFFIC | CAT_PARKED | CAT_TRAM,
    });
    // Same mass as client F: its density over the area of the rounded box, not of the chamfer.
    const density = spec.mass / (4 * this.halfLength * this.halfWidth);
    const mass = density * ((2 * this.halfLength + 2 * r) * (2 * this.halfWidth + 2 * r) - (4 - Math.PI) * r * r);
    const k = mass / this.body.getMass();
    this.body.setMassData({ mass, center: { x: 0, y: 0 }, I: this.body.getInertia() * k });
  }

  get x(): number {
    return this.body.getPosition().x;
  }
  get y(): number {
    return this.body.getPosition().y;
  }
  get heading(): number {
    return this.body.getAngle();
  }
  get speed(): number {
    const v = this.body.getLinearVelocity();
    return Math.sqrt(v.x * v.x + v.y * v.y);
  }
  get axleOffset(): number {
    return this.halfLength * this.t.axleOffset;
  }

  /** Signed speed along the car's nose. */
  get forwardSpeed(): number {
    const a = this.body.getAngle(), v = this.body.getLinearVelocity();
    return v.x * Math.cos(a) + v.y * Math.sin(a);
  }

  /** Sideways slip angle of the whole car (radians), 0 when slow. */
  get slipAngle(): number {
    const a = this.body.getAngle(), v = this.body.getLinearVelocity();
    if (Math.sqrt(v.x * v.x + v.y * v.y) < this.t.countersteerMinMps) return 0;
    const c = Math.cos(a), s = Math.sin(a);
    const f = v.x * c + v.y * s;
    const l = -v.x * s + v.y * c;
    return Math.atan2(l, Math.abs(f));
  }

  setLayer(l: number): void {
    if (l === this.layer) return;
    this.layer = l;
    this.refilter();
  }

  /** Adds or removes CAT_ZONE from the mask (zoneMask); refilters only on a change. */
  setZone(on: boolean): void {
    if (on === this.zone) return;
    this.zone = on;
    this.refilter();
  }

  /** Hop take-off / landing (specs/hop.md): buildings only in the air, the layer mask back on landing. */
  setAirborne(on: boolean): void {
    if (on === this.airborne) return;
    this.airborne = on;
    this.refilter();
  }

  private refilter(): void {
    if (this.airborne) {
      this.fixture.setFilterData({ groupIndex: 0, categoryBits: CAT_CAR, maskBits: CAT_BUILDINGS });
      return;
    }
    // Buildings, parked cars and bollards only exist on the ground layer; bridges and tunnels use
    // rails instead. Traffic cars and trams switch their own masks by layer (traffic.ts, trams.ts).
    const ground = CAT_BUILDINGS | CAT_PARKED | (this.zone ? CAT_ZONE : 0);
    this.fixture.setFilterData({ groupIndex: 0, categoryBits: CAT_CAR, maskBits: (this.layer === 0 ? ground : 0) | CAT_TRAFFIC | CAT_TRAM });
  }

  /** Applies controls and tyre forces; call before world.step. */
  drive(input: ControlInput, dt: number, cruise: number, top: number): void {
    const t = this.t, spec = this.spec, body = this.body;
    const ang = body.getAngle();
    const fx = Math.cos(ang), fy = Math.sin(ang);
    const v = body.getLinearVelocity();
    const vx = v.x, vy = v.y;
    const w = body.getAngularVelocity();
    const m = body.getMass();
    const speedF = vx * fx + vy * fy;
    const speed = Math.sqrt(vx * vx + vy * vy);
    const topSpeed = Math.min(top, spec.top_speed);
    const px = this.x, py = this.y;

    // Steering: wheels turn at steer_speed, less lock at speed.
    const lock = t.steerLockRad - t.steerLockDropRad * clamp(speed / Math.max(topSpeed, 1), 0, 1);
    let target = -input.steer * lock;
    const slip = this.slipAngle;
    if (speedF > t.countersteerMinMps && Math.abs(slip) > t.countersteerMinSlipRad && Math.abs(input.steer) < t.countersteerMaxInput) {
      target += clamp(slip * t.countersteerGain, -lock, lock);
    }
    const maxStep = spec.steer_speed * dt;
    this.wheelAngle += clamp(target - this.wheelAngle, -maxStep, maxStep);

    // Longitudinal: auto-throttle to cruise (or top with boost), brake, reverse.
    const wantSpeed = input.boost ? topSpeed : Math.min(cruise, topSpeed);
    let accel = 0;
    this.braking = false;
    this.reversing = false;
    if (input.brake > 0) {
      if (speedF > t.brakeMinMps) {
        accel = -spec.brake * input.brake;
        this.braking = true;
      } else {
        this.reversing = true;
        accel = speedF > -t.reverseMaxMps ? -spec.power * t.reversePower : 0;
      }
    } else if (!input.coast) {
      const thr = input.throttle > 0 ? input.throttle : speedF < wantSpeed ? 1 : 0;
      const k = 1 - clamp(speedF / topSpeed, 0, 1) ** 2;
      accel = spec.power * thr * k;
      if (speedF > wantSpeed + t.overspeedMps) accel = -t.engineBrakeMps2;
    }
    if (input.handbrake) {
      accel = Math.min(accel, speedF > t.brakeMinMps ? -t.handbrakeDecelMps2 : 0);
      // Kick the tail out: yaw towards the steer direction, stronger with speed. Micro vehicles
      // only slow down (specs/zones.md "Mikrovozidla": handbrake_yaw × 0).
      if (speedF > t.handbrakeMinMps && spec.class !== 'micro') {
        const k = clamp(speedF / t.handbrakeYawRefMps, 0, t.handbrakeYawMax);
        body.applyAngularImpulse(-input.steer * body.getInertia() * t.handbrakeYaw * k * dt, true);
      }
    }
    this.accel = accel;
    const rearOff = -this.axleOffset;
    this.f.x = fx * accel * m;
    this.f.y = fy * accel * m;
    this.p.x = px + fx * rearOff;
    this.p.y = py + fy * rearOff;
    body.applyForce(this.f, this.p, true);

    // Drag: rolling + air.
    const drag = m * (t.dragLinear + t.dragQuadratic * speed);
    this.f.x = -vx * drag;
    this.f.y = -vy * drag;
    body.applyForceToCenter(this.f, true);

    // Lateral tyre impulses.
    const g = this.gripScale;
    this.frontSlip = this.axle(this.axleOffset, this.wheelAngle, spec.grip_front * g, dt, fx, fy, vx, vy, w, m, px, py);
    const rearGrip = (input.handbrake ? spec.grip_rear * spec.drift_bias : spec.grip_rear) * g;
    this.rearSlip = this.axle(rearOff, 0, rearGrip, dt, fx, fy, vx, vy, w, m, px, py);
    if (speed < t.stopSpeedMps && input.brake === 0 && input.steer === 0) {
      body.setAngularVelocity(w * t.stopSpinDamping);
    }
  }

  /**
   * One step in the air (specs/hop.md): no input, no tyres (drive step 5 skipped), no spin; the
   * linear velocity only loses drag (step 4). Call before world.step instead of drive().
   */
  fly(): void {
    const t = this.t, body = this.body;
    const v = body.getLinearVelocity();
    const vx = v.x, vy = v.y;
    const speed = Math.sqrt(vx * vx + vy * vy);
    const drag = body.getMass() * (t.dragLinear + t.dragQuadratic * speed);
    this.f.x = -vx * drag;
    this.f.y = -vy * drag;
    body.applyForceToCenter(this.f, true);
    body.setAngularVelocity(0);
    this.braking = false;
    this.reversing = false;
    this.rearSlip = 0;
    this.frontSlip = 0;
  }

  /**
   * One step airborne after a terrain edge (specs/terrain.md "Skok"): no tyres, throttle, brake,
   * steering or slope, only drag; the angular velocity is kept. Call before world.step.
   */
  coast(): void {
    const t = this.t, body = this.body;
    const v = body.getLinearVelocity();
    const speed = Math.sqrt(v.x * v.x + v.y * v.y);
    const drag = body.getMass() * (t.dragLinear + t.dragQuadratic * speed);
    this.f.x = -v.x * drag;
    this.f.y = -v.y * drag;
    body.applyForceToCenter(this.f, true);
    this.accel = 0;
    this.braking = false;
    this.reversing = false;
    this.rearSlip = 0;
    this.frontSlip = 0;
  }

  /** Cancels lateral velocity at an axle up to its grip; returns the remaining slip (m/s). */
  private axle(
    offset: number, steerAngle: number, grip: number, dt: number, fx: number, fy: number,
    vx: number, vy: number, w: number, m: number, px: number, py: number,
  ): number {
    const rx = fx * offset, ry = fy * offset;
    const vpx = vx - w * ry, vpy = vy + w * rx;
    const c = Math.cos(steerAngle), s = Math.sin(steerAngle);
    const dx = fx * c - fy * s, dy = fx * s + fy * c; // wheel direction
    const nx = -dy, ny = dx; // wheel lateral
    const vlat = vpx * nx + vpy * ny;
    const mAxle = m / 2;
    let j = -vlat * mAxle;
    const maxJ = grip * mAxle * dt;
    let slip = 0;
    if (Math.abs(j) > maxJ) {
      slip = (Math.abs(j) - maxJ) / mAxle;
      j = Math.sign(j) * maxJ;
    }
    this.f.x = nx * j;
    this.f.y = ny * j;
    this.p.x = px + rx;
    this.p.y = py + ry;
    this.body.applyLinearImpulse(this.f, this.p, true);
    return slip;
  }

  destroy(): void {
    this.world.destroyBody(this.body);
  }
}
