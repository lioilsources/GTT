// Car sprites (specs/art.md v2 "Auta"), DOM part: loads a car's layers once as pixels, composes the
// decal into the body (clipped by the paint mask) and paints the tinted sprite for the garage
// preview and the sale list. The world draws them through render/carSprites.ts (atlas).
import { art, artUrl } from '../art';
import { Lru } from '../art/rules';
import { tokens } from '../gen/tokens';
import { decalPolys } from '../garage/looks';
import { rgba } from '../render/palette';
import { applyDecal, maskLuma, spriteFiles, SPRITE_PX_PER_M, type SpriteFiles } from './sprites';

/** Decoded layers of one car (RGBA pixels, straight alpha). */
export interface CarSprite {
  id: string;
  files: SpriteFiles;
  body: ImageData;
  mask: ImageData | null;
  wheel: ImageData | null;
  lights: ImageData | null;
}

const loaded = new Map<string, Promise<CarSprite | null>>();
const done = new Map<string, CarSprite | null>();

async function pixels(path: string): Promise<ImageData> {
  const img = new Image();
  img.decoding = 'async';
  img.src = artUrl(path);
  await img.decode();
  const c = document.createElement('canvas');
  c.width = img.naturalWidth;
  c.height = img.naturalHeight;
  const ctx = c.getContext('2d', { willReadFrequently: true })!;
  ctx.drawImage(img, 0, 0);
  return ctx.getImageData(0, 0, c.width, c.height);
}

/**
 * The sprite of car [id] (class [cls]) once its layers are decoded, or null when it has none or a
 * required layer fails to load (then the car stays procedural for the session, specs/art.md).
 */
export function loadCarSprite(id: string, cls: string): Promise<CarSprite | null> {
  let p = loaded.get(id);
  if (p) return p;
  const files = spriteFiles(art(), id, cls);
  p = !files ? Promise.resolve(null) : (async (): Promise<CarSprite | null> => {
    const opt = async (path: string | null): Promise<ImageData | null> => (path ? pixels(path) : null);
    try {
      const [body, mask, wheel] = await Promise.all([pixels(files.body), opt(files.mask), opt(files.wheel)]);
      // A broken lights.png only drops the optional layer.
      const lights = await opt(files.lights).catch(() => null);
      return { id, files, body, mask, wheel, lights };
    } catch {
      art().drop(files.body);
      return null;
    }
  })();
  p.then((s) => done.set(id, s));
  loaded.set(id, p);
  return p;
}

/** The decoded sprite if already loaded (undefined = not yet asked or still loading). */
export function carSpriteNow(id: string): CarSprite | null | undefined {
  return done.get(id);
}

/**
 * Body and mask of a cell with the decal (`looks.decal`, specs/art.md "Polep") drawn into the
 * paint only. [carScale]: sprite px per world metre = 32 ÷ car_scale. Decal 0 = the plain layers.
 */
export function composeBody(s: CarSprite, decal: number, carScale: number): { body: ImageData; mask: ImageData } {
  const w = s.body.width, h = s.body.height;
  const mask = s.mask ?? new ImageData(w, h);
  if (decal === 0) return { body: s.body, mask };
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  const ctx = c.getContext('2d', { willReadFrequently: true })!;
  // Car space (x forward, y left, world metres) → sprite px, nose up; the body rectangle is the
  // car's length × width (the canvas minus its 5 % margin).
  const k = SPRITE_PX_PER_M / carScale;
  const hl = (h / 1.1 / 2) / k, hw = (w / 1.1 / 2) / k;
  ctx.fillStyle = '#ffffff';
  for (const p of decalPolys(decal, { x0: -hl, y0: -hw, x1: hl, y1: hw })) {
    ctx.beginPath();
    for (let i = 0; i < p.length; i += 2) {
      const X = w / 2 - p[i + 1]! * k, Y = h / 2 - p[i]! * k;
      if (i === 0) ctx.moveTo(X, Y);
      else ctx.lineTo(X, Y);
    }
    ctx.closePath();
    ctx.fill();
  }
  const cov = ctx.getImageData(0, 0, w, h).data;
  const body = new ImageData(new Uint8ClampedArray(s.body.data), w, h);
  const outMask = new ImageData(new Uint8ClampedArray(mask.data), w, h);
  const dc = rgba(tokens.colorGarageDecal).map((v) => v * 255);
  const px = [0, 0, 0];
  for (let i = 0; i < w * h * 4; i += 4) {
    const d = cov[i + 3]! / 255;
    if (d === 0) continue;
    const m = maskLuma(mask.data[i]!, mask.data[i + 1]!, mask.data[i + 2]!);
    px[0] = body.data[i]!;
    px[1] = body.data[i + 1]!;
    px[2] = body.data[i + 2]!;
    const m2 = applyDecal(px, dc, d, m);
    body.data[i] = px[0]!;
    body.data[i + 1] = px[1]!;
    body.data[i + 2] = px[2]!;
    const v = Math.round(m2 * 255);
    outMask.data[i] = outMask.data[i + 1] = outMask.data[i + 2] = v;
  }
  return { body, mask: outMask };
}

/** Tinted sprites for the previews, per (car, paint, decal); same limit as client F (48). */
const tinted = new Lru<string, HTMLCanvasElement>(48);

/** The body tinted with [paintHex] (null = the patrol, untinted) and the decal, as a canvas. */
export function tintedBody(s: CarSprite, paintHex: string | null, decal: number, carScale: number): HTMLCanvasElement {
  const key = `${s.id}|${paintHex}|${decal}`;
  const hit = tinted.get(key);
  if (hit) return hit;
  const { body, mask } = composeBody(s, decal, carScale);
  const out = new ImageData(new Uint8ClampedArray(body.data), body.width, body.height);
  if (paintHex && s.mask) {
    const p = rgba(paintHex);
    for (let i = 0; i < out.data.length; i += 4) {
      const m = maskLuma(mask.data[i]!, mask.data[i + 1]!, mask.data[i + 2]!);
      for (let c = 0; c < 3; c++) out.data[i + c] = body.data[i + c]! * (1 + (p[c]! - 1) * m);
    }
  }
  const c = document.createElement('canvas');
  c.width = out.width;
  c.height = out.height;
  c.getContext('2d')!.putImageData(out, 0, 0);
  tinted.set(key, c);
  return c;
}

/** A canvas of an ImageData (wheel and lights layers for the previews). */
export function layerCanvas(d: ImageData): HTMLCanvasElement {
  const c = document.createElement('canvas');
  c.width = d.width;
  c.height = d.height;
  c.getContext('2d')!.putImageData(d, 0, 0);
  return c;
}
