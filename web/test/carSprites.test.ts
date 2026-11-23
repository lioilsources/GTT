import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { parse } from 'yaml';
import { describe, expect, it } from 'vitest';

import { ArtIndex } from '../src/art/rules';
import {
  applyDecal, atlasCarIds, maskLuma, packAtlas, POLICE_SPRITE, spriteFiles, spriteWheels, spriteWorldSize, stretchedSize,
  tintPixel, TRAFFIC_SPRITE, uvRect,
} from '../src/cars/sprites';
import { Tuning } from '../src/gen/tuning';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content/tuning.yaml'), 'utf8')));
const layers = (id: string, files: string[]): string[] => files.map((f) => `cars/${id}/${f}.png`);

describe('car sprites: when (specs/art.md v2 "Auta")', () => {
  it('needs body, paint_mask and wheel; lights optional', () => {
    const idx = new ArtIndex(layers('m0_coupe', ['body', 'paint_mask', 'wheel']));
    expect(spriteFiles(idx, 'm0_coupe', 'coupe')).toEqual({
      body: 'cars/m0_coupe/body.png', mask: 'cars/m0_coupe/paint_mask.png', wheel: 'cars/m0_coupe/wheel.png', lights: null,
    });
    const lit = new ArtIndex(layers('m0_coupe', ['body', 'paint_mask', 'wheel', 'lights']));
    expect(spriteFiles(lit, 'm0_coupe', 'coupe')?.lights).toBe('cars/m0_coupe/lights.png');
  });

  it('never half: a missing mask or wheel keeps the whole car procedural', () => {
    expect(spriteFiles(new ArtIndex(layers('lidovka', ['body'])), 'lidovka', 'sedan')).toBeNull();
    expect(spriteFiles(new ArtIndex(layers('lidovka', ['body', 'paint_mask'])), 'lidovka', 'sedan')).toBeNull();
    expect(spriteFiles(new ArtIndex(layers('lidovka', ['body', 'wheel'])), 'lidovka', 'sedan')).toBeNull();
    expect(spriteFiles(new ArtIndex(), 'lidovka', 'sedan')).toBeNull();
  });

  it('the patrol has no mask, micro cars no wheel', () => {
    const idx = new ArtIndex([...layers(POLICE_SPRITE, ['body', 'wheel']), ...layers('kolo', ['body', 'paint_mask'])]);
    expect(spriteFiles(idx, POLICE_SPRITE, 'sedan')?.mask).toBeNull();
    expect(spriteFiles(idx, 'kolo', 'micro')).toEqual({ body: 'cars/kolo/body.png', mask: 'cars/kolo/paint_mask.png', wheel: null, lights: null });
  });

  it('atlas cars: the city cars in id order, then traffic and patrol', () => {
    const cars = [{ id: 'taxi_metro', tags: ['nyc', 'tokyo'] }, { id: 'lidovka', tags: ['prague'] }, { id: 'hatch_pip', tags: ['nyc', 'prague'] }];
    expect(atlasCarIds(cars, 'nyc')).toEqual(['hatch_pip', 'taxi_metro', TRAFFIC_SPRITE, POLICE_SPRITE]);
    expect(atlasCarIds(cars, 'prague')).toEqual(['hatch_pip', 'lidovka', TRAFFIC_SPRITE, POLICE_SPRITE]);
  });
});

describe('car sprites: atlas packing', () => {
  it('rows by height, cells do not overlap and stay inside', () => {
    const items = [{ key: 'a', w: 67, h: 159 }, { key: 'b', w: 62, h: 138 }, { key: 'c', w: 71, h: 191 }, { key: 'd', w: 57, h: 106 }];
    const lay = packAtlas(items, 400, 2);
    expect(lay.dropped).toEqual([]);
    const cells = [...lay.cells.values()];
    for (const c of cells) {
      expect(c.x + c.w).toBeLessThanOrEqual(lay.w);
      expect(c.y + c.h).toBeLessThanOrEqual(lay.h);
    }
    for (let i = 0; i < cells.length; i++) {
      for (let j = i + 1; j < cells.length; j++) {
        const p = cells[i]!, q = cells[j]!;
        expect(p.x + p.w <= q.x || q.x + q.w <= p.x || p.y + p.h <= q.y || q.y + q.h <= p.y).toBe(true);
      }
    }
    // Tallest first in the first row.
    expect(lay.cells.get('c')).toMatchObject({ x: 1, y: 1 });
  });

  it('past the limit the last cars in input order stay procedural', () => {
    const items = Array.from({ length: 10 }, (_, i) => ({ key: `car${i}`, w: 90, h: 90 }));
    const lay = packAtlas(items, 200, 2);
    expect(lay.cells.size).toBe(4);
    expect(lay.dropped).toEqual(['car4', 'car5', 'car6', 'car7', 'car8', 'car9']);
  });

  it('uv rect of a cell', () => {
    expect(uvRect({ x: 10, y: 20, w: 30, h: 40 }, 100, 200)).toEqual([0.1, 0.1, 0.3, 0.2]);
  });
});

describe('car sprites: size, paint and wheels', () => {
  it('px ÷ 32 × car_scale; traffic stretched to its size × 1.1', () => {
    expect(spriteWorldSize(64, 160, 2.5)).toEqual({ len: 12.5, wid: 5 });
    const s = stretchedSize(4.6, 1.9, 2.5);
    expect(s.len).toBeCloseTo(12.65);
    expect(s.wid).toBeCloseTo(5.225);
  });

  it('body × mix(1, paint, mask); mask 0 keeps the body, 1 multiplies', () => {
    const out = [0, 0, 0];
    tintPixel([200, 100, 50], [0.5, 1, 0], 0, out);
    expect(out).toEqual([200, 100, 50]);
    tintPixel([200, 100, 50], [0.5, 1, 0], 1, out);
    expect(out).toEqual([100, 100, 0]);
    tintPixel([200, 200, 200], [0.5, 0.5, 0.5], 0.5, out);
    expect(out).toEqual([150, 150, 150]);
    expect(maskLuma(255, 255, 255)).toBeCloseTo(1);
    expect(maskLuma(0, 0, 0)).toBe(0);
  });

  it('decal only on paint: glass (mask 0) keeps its colour, painted pixels take the decal untinted', () => {
    const glass = [30, 40, 60];
    expect(applyDecal(glass, [255, 255, 255], 1, 0)).toBe(0);
    expect(glass).toEqual([30, 40, 60]);
    const paint = [230, 230, 230];
    expect(applyDecal(paint, [255, 0, 0], 1, 1)).toBe(0);
    expect(paint).toEqual([255, 0, 0]);
  });

  it('wheels on the drive.axle_offset axle at ±0.92 hw, left mirrored, front steering', () => {
    const hl = 5, hw = 2, axle = hl * tuning.drive.axleOffset;
    const w = spriteWheels('coupe', 4.5, hl, hw, axle);
    expect(w).toHaveLength(4);
    expect(w.filter((x) => x.front).every((x) => x.x === axle)).toBe(true);
    expect(w.filter((x) => !x.front).every((x) => x.x === -axle)).toBe(true);
    for (const x of w) {
      expect(Math.abs(x.y)).toBeCloseTo(0.92 * hw);
      expect(x.mirror).toBe(x.y > 0);
    }
    const bus = spriteWheels('bus', 12, 15, 3.2, 15 * 0.62);
    expect(bus.filter((x) => x.front)[0]!.x).toBeCloseTo(0.6 * 15);
    expect(bus.filter((x) => !x.front)[0]!.x).toBeCloseTo(-0.7 * 15);
    const trike = spriteWheels('special', 3.5, 4, 2, 2.5);
    expect(trike[0]).toMatchObject({ x: 3, y: 0, front: true, mirror: false });
    expect(spriteWheels('micro', 1.2, 1, 0.5, 0.6)).toEqual([]);
  });
});

describe('car sprites: shipped assets (docs/art-requests.md §3)', () => {
  // PNG size from the IHDR chunk.
  const size = (p: string): [number, number] => {
    const b = readFileSync(p);
    return [b.readUInt32BE(16), b.readUInt32BE(20)];
  };
  const dir = join(root, 'assets', 'cars');
  const ids = (() => {
    try {
      return readdirSync(dir);
    } catch {
      return [];
    }
  })();
  it.each(ids)('%s: layers as big as the canvas (car × 1.1 × 32 px, ±1 px)', (id) => {
    const files = readdirSync(join(dir, id));
    if (!files.includes('body.png')) return;
    const car = (() => {
      try {
        return JSON.parse(readFileSync(join(root, 'content', 'cars', `${id}.json`), 'utf8')) as { length_m: number; width_m: number };
      } catch {
        return id === POLICE_SPRITE ? { length_m: 4.9, width_m: 1.95 } : { length_m: tuning.traffic.carLengthM, width_m: tuning.traffic.carWidthM };
      }
    })();
    const [w, h] = size(join(dir, id, 'body.png'));
    expect(Math.abs(w - car.width_m * 1.1 * 32)).toBeLessThanOrEqual(1.5);
    expect(Math.abs(h - car.length_m * 1.1 * 32)).toBeLessThanOrEqual(1.5);
    for (const f of ['paint_mask.png', 'lights.png']) {
      if (files.includes(f)) expect(size(join(dir, id, f))).toEqual([w, h]);
    }
  });
});
