import type { CarSpec } from '../gen/schema';
import type { TuningHop } from '../gen/tuning';

/** Hop over traffic with an air tank (specs/hop.md, F-035). Pure rules; DriveWorld applies them. */

/** Full tank of [spec] (`hop.charges`), or null when the car cannot hop. */
export function hopCharges(spec: Pick<CarSpec, 'hop'>): number | null {
  const c = spec.hop?.['charges'];
  return typeof c === 'number' && c > 0 ? Math.floor(c) : null;
}

/**
 * The hop can start: the car has `hop`, a charge left, is on the ground and fast enough; any layer
 * (hop.md v2: bridges and tunnels too). [layer] stays in the signature of the spec.
 */
export function canHop(spec: Pick<CarSpec, 'hop'>, charges: number, air: number, _layer: number, speed: number, t: TuningHop): boolean {
  return hopCharges(spec) !== null && charges > 0 && air <= 0 && speed >= t.minSpeedMps;
}

/** Height of the arc after t seconds of an airS flight peaking at heightM (drawing only). */
export function hopArc(t: number, airS: number, heightM: number): number {
  if (airS <= 0 || t <= 0 || t >= airS) return 0;
  const u = t / airS;
  return 4 * heightM * u * (1 - u);
}

/** Body width factor of the flip (specs/hop.md "Kreslení"): cos(2π · flips · t / air_s). */
export function hopFlip(t: number, airS: number, flips: number): number {
  return airS > 0 ? Math.cos((2 * Math.PI * flips * t) / airS) : 1;
}

/** Roll angle of the flip in the chase view (radians): 2π · flips · t / air_s; cos of it is hopFlip. */
export function hopRoll(t: number, airS: number, flips: number): number {
  return airS > 0 ? (2 * Math.PI * flips * t) / airS : 0;
}

/** Session state of the hop (not saved). */
export class HopState {
  /** Charges left. */
  charges = 0;
  /** Flight time left; 0 = on the ground. */
  air = 0;
  /** Flight time so far. */
  t = 0;

  get airborne(): boolean {
    return this.air > 0;
  }

  /** Full tank for [spec] (game load, boarding or selecting a hop car); lands at once. */
  fill(spec: Pick<CarSpec, 'hop'>): void {
    this.charges = hopCharges(spec) ?? 0;
    this.air = 0;
    this.t = 0;
  }

  /** Garage refill (free); true when something was added. */
  refill(spec: Pick<CarSpec, 'hop'>): boolean {
    const full = hopCharges(spec);
    if (full === null || this.charges >= full) return false;
    this.charges = full;
    return true;
  }

  /** Starts a hop if canHop allows it. */
  start(spec: Pick<CarSpec, 'hop'>, layer: number, speed: number, tuning: TuningHop): boolean {
    if (!canHop(spec, this.charges, this.air, layer, speed, tuning)) return false;
    this.charges -= 1;
    this.air = tuning.airS;
    this.t = 0;
    return true;
  }

  /** Advances the flight by one step; true on the step it lands. */
  step(dt: number): boolean {
    if (this.air <= 0) return false;
    this.t += dt;
    this.air -= dt;
    if (this.air > 1e-9) return false;
    this.air = 0;
    return true;
  }
}
