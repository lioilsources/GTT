import type { TuningSlopePhysics } from '../gen/tuning';

/**
 * Fixed numbers of specs/terrain.md (v1) that are part of the rule text, not tuning: they are
 * written into the specification itself and change only with a new spec version.
 */
export const TERRAIN_SPEC = {
  /** AI drives uphill slower above this grade… */
  aiUphillGrade: 0.08,
  /** …by this factor. */
  aiUphillFactor: 0.8,
  /** A hard landing keeps this share of the speed. */
  hardLandingKeep: 0.85,
  /** Camera shake after a hard landing (s). */
  shakeS: 0.3,
  /** Car shadow scale 1 / (1 + gap / this) (m). */
  shadowGapM: 4,
  /** Short zoom-out at an edge (start of airborne) and on a hard landing: factor and duration (s). */
  zoomOut: 1.15,
  zoomOutS: 0.4,
  /** z_ref follows the ground under the car exponentially at this rate (1/s). */
  zRefRate: 2,
  /** Uphill arrows on road segments steeper than this, every arrowSpacingM metres. */
  arrowGrade: 0.08,
  arrowSpacingM: 24,
  /** The HUD shows the grade only above this. */
  hudMinGrade: 0.02,
  /** Projection clamp of client F: z − z_ref in [−2H, 0.8H]. */
  projMin: -2,
  projMax: 0.8,
} as const;

/**
 * Slope step (specs/terrain.md "Svah"): acceleration along the gradient and the grip factor.
 * out = −gravity · slope_force_scale · grad · k; returns k = 1 / sqrt(1 + |grad|²).
 */
export function slopeAccel(gx: number, gy: number, t: TuningSlopePhysics, out: { x: number; y: number }): number {
  const k = 1 / Math.sqrt(1 + gx * gx + gy * gy);
  const a = -t.gravity * t.slopeForceScale * k;
  out.x = a * gx;
  out.y = a * gy;
  return k;
}

/**
 * Vertical state of the player's car (specs/terrain.md "Skok"): body height z and speed vz,
 * airborne past the suspension travel. step() runs after the horizontal move of each step.
 */
export class JumpState {
  z = 0;
  vz = 0;
  airborne = false;
  /** Ground height of the previous step. */
  gPrev = 0;
  /** z − g after the last step (drives the shadow). */
  gap = 0;
  /** Was airborne since the last ground contact (a landing is reported at the next contact). */
  private flew = false;

  /** Teleport or a new surface start: z = g, vz = 0, on the ground. */
  reset(g: number): void {
    this.z = g;
    this.vz = 0;
    this.gPrev = g;
    this.gap = 0;
    this.airborne = false;
    this.flew = false;
  }

  /** On a surface change (ramp) g_prev is taken on the new surface: no false ground speed. */
  rebase(g: number): void {
    this.gPrev = g;
  }

  /**
   * One step with ground height g: returns the landing speed (m/s, positive) when the body
   * touches the ground after having been airborne, else null.
   */
  step(g: number, dt: number, gravity: number, travel: number): number | null {
    const vg = (g - this.gPrev) / dt;
    this.vz -= gravity * dt;
    this.z += this.vz * dt;
    let landing: number | null = null;
    if (this.z <= g) {
      if (this.flew) landing = vg - this.vz;
      this.flew = false;
      this.z = g;
      this.vz = vg;
    }
    this.gap = this.z - g;
    this.airborne = this.gap > travel;
    if (this.airborne) this.flew = true;
    this.gPrev = g;
    return landing;
  }
}

/** Shadow scale of the car at gap (m) above the ground (specs/terrain.md). */
export function shadowScale(gap: number): number {
  return 1 / (1 + Math.max(0, gap) / TERRAIN_SPEC.shadowGapM);
}

/**
 * Projection of client F (specs/terrain.md "Jednotná zobrazená výška"): the factor s for a point
 * dz = z − z_ref above the reference at camera height H (dz clamped to [−2H, 0.8H]).
 */
export function projectionScale(dz: number, H: number): number {
  const d = Math.min(Math.max(dz, TERRAIN_SPEC.projMin * H), TERRAIN_SPEC.projMax * H);
  return H / (H - d);
}
