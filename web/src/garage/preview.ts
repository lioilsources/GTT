import { carPrims, wheelRects, type WheelRect } from '../cars/carTris';
import { carSpriteNow, layerCanvas, loadCarSprite, tintedBody, type CarSprite } from '../cars/spriteArt';
import { POLICE_SPRITE, spriteWheels, SPRITE_PX_PER_M } from '../cars/sprites';
import type { CarSpec } from '../gen/schema';
import { tokens } from '../gen/tokens';
import type { Tuning } from '../gen/tuning';
import { rgba, type Rgba } from '../render/palette';
import { glowPoly, lookGlow, lookPaint, lookRim, type Poly } from './looks';
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
  // Sprite (specs/art.md v2 "Kde"): the same picture as in the world, scaled down. Not loaded yet:
  // the vector drawing now, redrawn once the layers are in.
  const sprite = carSpriteNow(spec.id);
  if (sprite === undefined) {
    void loadCarSprite(spec.id, spec.class).then((s) => {
      if (s && canvas.isConnected !== false) drawCarPreview(canvas, spec, look, tuning);
    });
  }
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
  const axle = hl * tuning.drive.axleOffset;
  if (sprite) {
    drawSprite(ctx, sprite, spec, look, tuning, w / 2, h / 2, s, hl, hw, axle, fill);
    return;
  }
  // Wheels by class (specs/cars.md); the single front wheel of a trike or rickshaw goes over the body.
  // [look] null = a catalog car (the sale list): drawn like a parked car, without rims.
  const tyre = rgba(tokens.colorCarTyre), rim = look ? rgba(lookRim(look)) : null;
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

/** Wheel layer multiplied by the garage rim colour (`looks.wheels > 0`), cached per colour. */
const wheelTints = new Map<string, HTMLCanvasElement>();
function wheelCanvas(sp: CarSprite, hex: string | null): HTMLCanvasElement {
  const key = `${sp.id}|${hex}`;
  let c = wheelTints.get(key);
  if (c) return c;
  const d = new ImageData(new Uint8ClampedArray(sp.wheel!.data), sp.wheel!.width, sp.wheel!.height);
  if (hex) {
    const t = rgba(hex);
    for (let i = 0; i < d.data.length; i += 4) for (let k = 0; k < 3; k++) d.data[i + k] = d.data[i + k]! * t[k]!;
  }
  c = layerCanvas(d);
  wheelTints.set(key, c);
  return c;
}

/** The sprite car (specs/art.md v2): procedural shadow, wheels under the tinted body. */
function drawSprite(ctx: CanvasRenderingContext2D, sp: CarSprite, spec: CarSpec, look: Look | null, tuning: Tuning,
  cx: number, cy: number, s: number, hl: number, hw: number, axle: number, fill: (p: Poly, c: Rgba) => void): void {
  for (const p of carPrims(spec, hl, hw, false, null, undefined, axle)) if (p.part === 'shadow') fill(p.poly, p.color);
  // px of the sprite → canvas: (1 ÷ 32 × car_scale) m per px × s canvas px per m.
  const k = (tuning.carScale / SPRITE_PX_PER_M) * s;
  ctx.imageSmoothingEnabled = true;
  if (sp.wheel) {
    const wc = wheelCanvas(sp, look && (look.wheels ?? 0) > 0 ? lookRim(look) : null);
    const ww = wc.width * k, wh = wc.height * k;
    for (const wl of spriteWheels(spec.class, spec.length_m, hl, hw, axle)) {
      ctx.save();
      ctx.translate(cx - wl.y * s, cy - wl.x * s);
      if (wl.mirror) ctx.scale(-1, 1);
      ctx.drawImage(wc, -ww / 2, -wh / 2, ww, wh);
      ctx.restore();
    }
  }
  const paint = spec.id === POLICE_SPRITE ? null : lookPaint(spec, look);
  const body = tintedBody(sp, paint, look?.decal ?? 0, tuning.carScale);
  ctx.drawImage(body, cx - (body.width * k) / 2, cy - (body.height * k) / 2, body.width * k, body.height * k);
}
