import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

import { parse } from 'yaml';
import { afterEach, describe, expect, it } from 'vitest';

import { ArtIndex } from '../src/art/rules';
import { carPrims, wheelPrims, wheelRects } from '../src/cars/carTris';
import { carShape } from '../src/cars/shape';
import {
  clearCosmeticArt, cosmeticFiles, DECAL_CELL_H, DECAL_CELL_W, decalArt, decalPath, decalRaster, setCosmeticArt, wheelPath,
  type Pixels,
} from '../src/garage/cosmetics';
import { decalPolys, type Poly } from '../src/garage/looks';
import { decalIds, garageConfig, partCounts, wheelIds } from '../src/garage/rules';
import type { CarSpec } from '../src/gen/schema';
import { tokens } from '../src/gen/tokens';
import { Tuning } from '../src/gen/tuning';
import { phoneAppIds } from '../src/phone/phone';
import { rgba } from '../src/render/palette';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const specs = new Map<string, CarSpec>(
  readdirSync(join(root, 'content', 'cars')).map((f) => {
    const s = JSON.parse(readFileSync(join(root, 'content', 'cars', f), 'utf8')) as CarSpec;
    return [s.id, s];
  }),
);
const coupe = specs.get('m0_coupe')!;
const i18n = JSON.parse(readFileSync(join(root, 'i18n', 'en.json'), 'utf8')) as Record<string, string>;

/** A solid fixture sprite (every pixel [r, g, b, a]). */
const solid = (w: number, h: number, px: [number, number, number, number]): Pixels => {
  const data = new Uint8ClampedArray(w * h * 4);
  for (let i = 0; i < data.length; i += 4) data.set(px, i);
  return { width: w, height: h, data };
};

/** Every point of [p] inside the convex counter-clockwise [clip] (with a small tolerance). */
const inside = (p: Poly, clip: Poly): boolean => {
  const n = clip.length / 2;
  for (let i = 0; i < p.length; i += 2) {
    for (let e = 0; e < n; e++) {
      const ax = clip[e * 2]!, ay = clip[e * 2 + 1]!, bx = clip[((e + 1) % n) * 2]!, by = clip[((e + 1) % n) * 2 + 1]!;
      if ((bx - ax) * (p[i + 1]! - ay) - (by - ay) * (p[i]! - ax) < -1e-6) return false;
    }
  }
  return true;
};

afterEach(() => clearCosmeticArt());

describe('garage v2 parts (specs/garage.md v2 "Vzhled")', () => {
  it('decal has 9 choices, wheels one per color.garage.wheels (7)', () => {
    const c = partCounts();
    expect(c.decal).toBe(9);
    expect(c.wheels).toBe(tokens.colorGarageWheels.length);
    expect(c.wheels).toBe(7);
    expect(decalIds.length).toBe(c.decal);
    expect(wheelIds.length).toBe(c.wheels);
    expect(garageConfig(tuning.garage, specs.values()).parts).toEqual(c);
  });

  it('every decal and wheel choice has a label', async () => {
    // index.ts pulls in CSS; the labels are plain data.
    const { decalKeys, wheelKeys } = await import('../src/garage/index');
    expect(decalKeys.length).toBe(partCounts().decal);
    expect(wheelKeys.length).toBe(partCounts().wheels);
    for (const k of [...decalKeys, ...wheelKeys]) expect(i18n[k], k).toBeTruthy();
    expect(new Set(decalKeys).size).toBe(decalKeys.length);
    expect(new Set(wheelKeys).size).toBe(wheelKeys.length);
  });

  it('sprite paths follow the choice order', () => {
    expect(decalPath(0)).toBeNull();
    expect(decalPath(4)).toBe('garage/decals/stars.png');
    expect(decalPath(8)).toBe('garage/decals/halftone.png');
    expect(decalPath(9)).toBeNull();
    expect(wheelPath(3)).toBe('garage/wheels/five_spoke.png');
    expect(wheelPath(6)).toBe('garage/wheels/offroad.png');
    expect(wheelPath(7)).toBeNull();
  });
});

describe('procedural decals 4–8 (specs/garage.md v2 "Kreslení")', () => {
  const b = { x0: -2.5, y0: -1, x1: 2.5, y1: 1 };

  it('stars = three diamonds on the long axis at +0.55, 0, −0.55 hl', () => {
    const stars = decalPolys(4, b);
    expect(stars.length).toBe(3);
    const cx = stars.map((p) => (Math.max(...p.filter((_, i) => i % 2 === 0)) + Math.min(...p.filter((_, i) => i % 2 === 0))) / 2);
    expect(cx.sort((a, c) => a - c)).toEqual([-0.55, 0, 0.55].map((v) => expect.closeTo(v * 2.5, 6)));
    for (const p of stars) {
      const xs = p.filter((_, i) => i % 2 === 0), ys = p.filter((_, i) => i % 2 === 1);
      expect(Math.max(...ys) - Math.min(...ys)).toBeCloseTo(0.5 * 1);
      expect(Math.max(...xs) - Math.min(...xs)).toBeCloseTo(0.25 * 2.5);
    }
  });

  it('lightning and waves are drawn as stripes, camo and halftone as checker', () => {
    expect(decalPolys(5, b)).toEqual(decalPolys(1, b));
    expect(decalPolys(6, b)).toEqual(decalPolys(1, b));
    expect(decalPolys(7, b)).toEqual(decalPolys(3, b));
    expect(decalPolys(8, b)).toEqual(decalPolys(3, b));
    expect(decalPolys(9, b)).toEqual([]);
  });

  it('every decal stays inside the body of every class (the trike nose included)', () => {
    for (const s of specs.values()) {
      const hl = (s.length_m * tuning.carScale) / 2, hw = (s.width_m * tuning.carScale) / 2, axle = hl * tuning.drive.axleOffset;
      const body = carShape(s.class, hl, hw, s.length_m, axle).find((r) => r.part === 'body');
      for (let d = 1; d < 9; d++) {
        const prims = carPrims(s, hl, hw, false, { decal: d }, undefined, axle).filter((p) => p.part === 'decal');
        if (!body) {
          expect(prims).toEqual([]);
          continue;
        }
        const clip = body.poly ?? [body.x0, body.y0, body.x1, body.y0, body.x1, body.y1, body.x0, body.y1];
        expect(prims.length, `${s.id} ${d}`).toBeGreaterThan(0);
        for (const p of prims) expect(inside(p.poly, clip), `${s.id} decal ${d}`).toBe(true);
      }
    }
    expect(carShape('special', 1, 0.5, 3.2).find((r) => r.part === 'body')?.poly).toBeTruthy();
  });
});

describe('cosmetics sprites (specs/art.md v3 "Kosmetika z garáže")', () => {
  it('discovered through index.json only; nothing indexed = procedural', () => {
    const none = cosmeticFiles(new ArtIndex());
    expect(none.decals.size).toBe(0);
    expect(none.wheels.size).toBe(0);
    const some = cosmeticFiles(new ArtIndex(['garage/decals/stars.png', 'garage/wheels/mesh.png', 'garage/decals/nope.png']));
    expect([...some.decals]).toEqual([[4, 'garage/decals/stars.png']]);
    expect([...some.wheels]).toEqual([[4, 'garage/wheels/mesh.png']]);
  });

  it('without a decoded sprite the procedural decal is drawn (fallback)', () => {
    expect(decalArt(4)).toBeNull();
    const hl = 2.2, hw = 0.9;
    const prims = carPrims(coupe, hl, hw, false, { decal: 4 }).filter((p) => p.part === 'decal');
    expect(prims.length).toBe(3);
  });

  it('a decal sprite replaces the procedural decal: stretched over 2 hl × 2 hw, clipped to the body, right over it', () => {
    // Left half opaque (image left = car +y).
    const px = solid(DECAL_CELL_W, DECAL_CELL_H, [255, 255, 255, 0]);
    for (let y = 0; y < px.height; y++) for (let x = 0; x < px.width / 2; x++) px.data[(y * px.width + x) * 4 + 3] = 255;
    setCosmeticArt('decal', 4, px);
    const raster = decalRaster(px, 2, 1);
    expect(raster.length).toBe(48);
    for (const p of raster) {
      const ys = p.filter((_, i) => i % 2 === 1);
      expect(Math.min(...ys)).toBeCloseTo(0);
      expect(Math.max(...ys)).toBeCloseTo(1);
    }
    for (const s of [coupe, specs.get('spec_trike')!]) {
      const hl = (s.length_m * tuning.carScale) / 2, hw = (s.width_m * tuning.carScale) / 2, axle = hl * tuning.drive.axleOffset;
      const prims = carPrims(s, hl, hw, false, { decal: 4 }, undefined, axle);
      const body = carShape(s.class, hl, hw, s.length_m, axle).find((r) => r.part === 'body')!;
      const clip = body.poly ?? [body.x0, body.y0, body.x1, body.y0, body.x1, body.y1, body.x0, body.y1];
      const decals = prims.map((p, i) => [p, i] as const).filter(([p]) => p.part === 'decal');
      expect(decals.length).toBeGreaterThan(10);
      for (const [p] of decals) {
        expect(inside(p.poly, clip)).toBe(true);
        expect(p.color).toEqual(rgba(tokens.colorGarageDecal));
        expect(Math.min(...p.poly.filter((_, i) => i % 2 === 1))).toBeGreaterThanOrEqual(-1e-6);
      }
      // Right after the body: under the glass, details and lights.
      const bodyAt = prims.findIndex((p) => p.part === 'body');
      expect(decals[0]![1]).toBe(bodyAt + 1);
      expect(decals.every(([, i], k) => i === bodyAt + 1 + k)).toBe(true);
    }
    // Other decals stay procedural.
    expect(carPrims(coupe, 2, 1, false, { decal: 2 }).filter((p) => p.part === 'decal').length).toBe(3);
  });

  it('a garage wheel sprite replaces the procedural wheel, tinted by the rim colour; else tyre + rim', () => {
    const w = wheelRects(2, 1, 1.2, 'coupe')[0]!;
    const plain = wheelPrims(w, { wheels: 3 });
    expect(plain.map((p) => p.color)).toEqual([rgba(tokens.colorCarTyre), rgba(tokens.colorGarageWheels[3]!)]);
    expect(wheelPrims(w, null).length).toBe(1);
    setCosmeticArt('wheel', 3, solid(128, 128, [255, 255, 255, 255]));
    const art = wheelPrims(w, { wheels: 3 });
    expect(art.length).toBe(100);
    const rim = rgba(tokens.colorGarageWheels[3]!);
    for (const p of art) {
      expect(p.color[0]).toBeCloseTo(rim[0]);
      expect(p.color[2]).toBeCloseTo(rim[2]);
      const xs = p.poly.filter((_, i) => i % 2 === 0), ys = p.poly.filter((_, i) => i % 2 === 1);
      expect(Math.min(...xs)).toBeGreaterThanOrEqual(w.x0 - 1e-9);
      expect(Math.max(...xs)).toBeLessThanOrEqual(w.x1 + 1e-9);
      expect(Math.min(...ys)).toBeGreaterThanOrEqual(w.y0 - 1e-9);
      expect(Math.max(...ys)).toBeLessThanOrEqual(w.y1 + 1e-9);
    }
    // Stock wheels (0) never use a sprite.
    expect(wheelPrims(w, { wheels: 0 }).length).toBe(2);
  });
});

describe('UI icons (specs/art.md v3 "Ikony UI")', () => {
  it('ui/<id>.png when indexed, else today\'s drawing', () => {
    const idx = new ArtIndex(['ui/feed.png', 'ui/garage.png', 'ui/wanted_star.png', 'ui/weather_rain.png']);
    expect(phoneAppIds.map((id) => idx.uiIcon(id))).toEqual(
      phoneAppIds.map((id) => (id === 'feed' || id === 'garage' ? `ui/${id}.png` : null)));
    expect(idx.uiIcon('wanted_star')).toBe('ui/wanted_star.png');
    expect(idx.uiIcon('weather_rain')).toBe('ui/weather_rain.png');
    expect(idx.uiIcon('weather_fog')).toBeNull();
    expect(new ArtIndex().uiIcon('feed')).toBeNull();
    // A file that failed to load falls back too.
    idx.drop('ui/feed.png');
    expect(idx.uiIcon('feed')).toBeNull();
  });
});
