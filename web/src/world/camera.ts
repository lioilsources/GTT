import type { Tuning } from '../gen/tuning';

/** Camera height H = 1 / extrusion.k (DUALSTACK 6.2). */
export function cameraHeight(t: Tuning): number {
  return 1 / t.extrusion.k;
}

/** Horizontal field of view for a view `width` in metres at camera height `h`. */
export function fovX(width: number, h: number): number {
  return 2 * Math.atan(width / (2 * h));
}

/** Height a building of real height `hReal` is built at so perspective gives the same s(h) as the Flutter extrusion. */
export function displayHeight(sOfH: number, h: number): number {
  return h * (1 - 1 / sOfH);
}

/**
 * Roof scale for height h (METROPOLE_PLAN 6.2), as world_engine extrusionScale:
 * h_eff = h for h ≤ knee, knee + (h − knee)^exp above; s = min(1 + k·h_eff, max_scale).
 */
export function extrusionScale(h: number, t: Tuning): number {
  const e = t.extrusion;
  const he = h <= e.kneeM ? h : e.kneeM + (h - e.kneeM) ** e.exp;
  return Math.min(1 + e.k * he, e.maxScale);
}
