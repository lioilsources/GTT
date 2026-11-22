import { carPrims, wheelRects, type WheelRect } from '../cars/carTris';
import type { CarSpec } from '../gen/schema';
import { tokens } from '../gen/tokens';
import type { Tuning } from '../gen/tuning';
import { rgba, type Rgba } from '../render/palette';
import { glowPoly, lookGlow, lookRim, type Poly } from './looks';
import type { Look } from './rules';

const css = (c: Rgba): string => `rgba(${Math.round(c[0] * 255)}, ${Math.round(c[1] * 255)}, ${Math.round(c[2] * 255)}, ${c[3]})`;

/**
 * Live top-down preview of a car with a look (specs/garage.md "Vzhled"): the same polygons as the
 * world mesh (carPrims, wheel rims, underglow), nose up, fitted into the canvas.
 */
export function drawCarPreview(canvas: HTMLCanvasElement, spec: CarSpec, look: Look | null, tuning: Tuning): void {
  const dpr = Math.min(globalThis.devicePixelRatio || 1, 3);
  const w = canvas.clientWidth || canvas.width, h = canvas.clientHeight || canvas.height;
  canvas.width = Math.round(w * dpr);
  canvas.height = Math.round(h * dpr);
  const ctx = canvas.getContext('2d');
  if (!ctx) return;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, w, h);
  const hl = (spec.length_m * tuning.carScale) / 2, hw = (spec.width_m * tuning.carScale) / 2;
  const margin = tuning.garage.glowMarginM;
  const s = Math.min((h * 0.86) / (2 * (hl + margin + 0.6)), (w * 0.86) / (2 * (hw + margin + 0.6)));
  // Car space (x forward, y left) → canvas, nose up.
  const fill = (p: Poly, c: Rgba): void => {
    ctx.fillStyle = css(c);
    ctx.beginPath();
    for (let i = 0; i < p.length; i += 2) {
      const X = w / 2 - p[i + 1]! * s, Y = h / 2 - p[i]! * s;
      if (i === 0) ctx.moveTo(X, Y);
      else ctx.lineTo(X, Y);
    }
    ctx.closePath();
    ctx.fill();
  };
  const glow = lookGlow(look);
  if (glow) fill(glowPoly(hl, hw, margin), rgba(glow));
  // Wheels by class (specs/cars.md); the single front wheel of a trike or rickshaw goes over the body.
  // [look] null = a catalog car (the sale list): drawn like a parked car, without rims.
  const tyre = rgba(tokens.colorCarTyre), rim = look ? rgba(lookRim(look)) : null;
  const axle = hl * tuning.drive.axleOffset;
  const wheels = wheelRects(hl, hw, axle, spec.class, spec.length_m);
  const wheel = (r: WheelRect): void => {
    fill([r.x0, r.y0, r.x1, r.y0, r.x1, r.y1, r.x0, r.y1], tyre);
    const [a, b, c, d] = r.rim;
    if (rim) fill([a, b, c, b, c, d, a, d], rim);
  };
  for (const r of wheels) if (!r.top) wheel(r);
  for (const p of carPrims(spec, hl, hw, false, look, undefined, axle)) fill(p.poly, p.color);
  for (const r of wheels) if (r.top) wheel(r);
}
