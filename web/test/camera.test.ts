import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { parse } from 'yaml';
import { expect, it } from 'vitest';

import { Tuning } from '../src/gen/tuning';
import { cameraHeight, displayHeight, fovX } from '../src/world/camera';

const tuning = Tuning.fromJson(parse(readFileSync(join(__dirname, '..', '..', 'content', 'tuning.yaml'), 'utf8')));

it('camera height and display height reproduce s(h) of the Flutter extrusion', () => {
  const h = cameraHeight(tuning);
  expect(h).toBeCloseTo(1 / tuning.extrusion.k);
  // DUALSTACK 6.2: max_scale 2.2 → 136 m, perspective scale H / (H − z) = s.
  const z = displayHeight(tuning.extrusion.maxScale, h);
  expect(h / (h - z)).toBeCloseTo(tuning.extrusion.maxScale);
  expect(fovX(tuning.viewWidthM.slow, h)).toBeGreaterThan(0);
});

it('tuning parsing is strict', () => {
  const raw = parse(readFileSync(join(__dirname, '..', '..', 'content', 'tuning.yaml'), 'utf8')) as Record<string, unknown>;
  delete raw['car_scale'];
  expect(() => Tuning.fromJson(raw)).toThrow(/car_scale/);
});
