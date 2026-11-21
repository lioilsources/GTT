import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { Tuning } from '../src/gen/tuning';
import { buildingTris, Tris } from '../src/render/geometry';
import { dayPalette } from '../src/render/palette';
import { cameraHeight, displayHeight, extrusionScale } from '../src/world/camera';
import type { ChunkData } from '../src/world/chunk';

const tuning = Tuning.fromJson(parse(readFileSync(join(__dirname, '..', '..', 'content', 'tuning.yaml'), 'utf8')));

/** Signed area of a triangle in Babylon X/Z (positive = counter-clockwise seen from above). */
function areaXZ(t: Tris, k: number): number {
  const p = (i: number): [number, number] => [t.pos[3 * t.idx[k + i]!]!, t.pos[3 * t.idx[k + i]! + 2]!];
  const [a, b, c] = [p(0), p(1), p(2)];
  return (b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1]);
}

describe('geometry for client W', () => {
  it('perspective at the display height gives the 2.5D scale of client F (DUALSTACK 6.2)', () => {
    const H = cameraHeight(tuning);
    for (const h of [5, 20, 50, 120, 400]) {
      const s = extrusionScale(h, tuning);
      const z = displayHeight(s, H);
      expect(H / (H - z)).toBeCloseTo(s, 9);
    }
    expect(displayHeight(extrusionScale(20, tuning), H)).toBeCloseTo(18.5, 1);
  });

  it('flat triangles are wound clockwise seen from above (front faces)', () => {
    const t = new Tris();
    t.quad(0, 0, 10, 0, 2, 0, [1, 1, 1, 1]);
    t.disc(0, 0, 3, 0, [1, 1, 1, 1]);
    for (let k = 0; k < t.idx.length; k += 3) expect(areaXZ(t, k)).toBeLessThan(0);
  });

  it('a square building gives four walls and a roof at the display height', () => {
    const chunk: ChunkData = {
      x: 0, y: 0, ground: [],
      buildings: [{
        xy: Float32Array.from([0, 0, 10, 0, 10, 10, 0, 10]), ringEnds: Int32Array.from([4]),
        roof: Uint16Array.from([0, 1, 2, 0, 2, 3]), height: 30, minHeight: 0, landmark: 0, collide: true,
        seed: 7, cx: 5, cy: 5, radius: 7.1, wallU: Float32Array.from([0, 10, 20, 30]),
      }],
    };
    const t = new Tris();
    buildingTris(chunk, dayPalette, tuning, t);
    expect(t.idx.length).toBe(4 * 6 + 6);
    const top = Math.max(...t.pos.filter((_, i) => i % 3 === 1));
    expect(top).toBeCloseTo(displayHeight(extrusionScale(30, tuning), cameraHeight(tuning)), 5);
  });
});
