import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { create } from '@bufbuild/protobuf';
import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import {
  BuildingRefSchema, ModelPartSchema, ModelRole, ModelSchema, ModelsSchema, PlanPolySchema,
} from '../src/gen/pb/citypack_pb';
import { tokens } from '../src/gen/tokens';
import { Tuning } from '../src/gen/tuning';
import { Tris } from '../src/render/geometry';
import { modelTris, planBuildings, planRoofColor, planTris, roleColors } from '../src/render/modelGeometry';
import { cityPalette, nightPalette, rgba } from '../src/render/palette';
import { cameraHeight, displayHeight, extrusionScale } from '../src/world/camera';
import type { PackSource } from '../src/world/citypack';
import { prepareChunk } from '../src/world/chunk';
import { City, chunkKey } from '../src/world/model';
import { fullModels, loadModels, modelDistance, prepareModels } from '../src/world/models';

// Landmark models (specs/models.md v1, F-085): data, switching with hysteresis, geometry, and the
// Prague pack's castle (skipped without build/packs/prague or a pack without models.pb).

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));

/** A 10 × 10 × 20 m box part at (100, 200) with its roof as the plan. */
function boxModels(): ReturnType<typeof create<typeof ModelsSchema>> {
  const pos: number[] = [];
  for (const z of [0, 200]) for (const [x, y] of [[0, 0], [100, 0], [100, 100], [0, 100]]) pos.push(x!, y!, z);
  // Walls (CCW from outside) and the roof.
  const tri = [0, 1, 5, 0, 5, 4, 1, 2, 6, 1, 6, 5, 2, 3, 7, 2, 7, 6, 3, 0, 4, 3, 4, 7, 4, 5, 6, 4, 6, 7];
  const roles = [0, 0, 0, 0, 0, 0, 0, 0, ModelRole.ROLE_COPPER, ModelRole.ROLE_COPPER];
  return create(ModelsSchema, {
    models: [create(ModelSchema, {
      landmarkId: 'box', tris: 10,
      parts: [create(ModelPartSchema, { anchorX: 1000, anchorY: 2000, baseZDm: 55, positions: pos, triangles: tri, roles: Uint8Array.from(roles) })],
      roofPlan: [create(PlanPolySchema, {
        points: [1000, 2000, 1100, 2000, 1100, 2100, 1000, 2100], ringEnds: [4], triangles: [0, 1, 2, 0, 2, 3], heightM: 20, shade: 2, baseZDm: 55,
      })],
      replaces: [create(BuildingRefSchema, { chunkX: 0, chunkY: 0, index: 3 }), create(BuildingRefSchema, { chunkX: 0, chunkY: 0, index: 5 })],
    })],
  });
}

describe('models data (specs/models.md)', () => {
  const [m] = prepareModels(boxModels(), 256);
  it('decodes parts, plan, replaces and the home chunk', () => {
    expect(m!.parts[0]!.pos[0]).toBeCloseTo(100);
    expect(m!.parts[0]!.pos[1]).toBeCloseTo(200);
    expect(m!.parts[0]!.pos[14]).toBeCloseTo(20);
    expect(m!.parts[0]!.baseZ).toBeCloseTo(5.5);
    expect([...m!.replaces.get(chunkKey(0, 0))!]).toEqual([3, 5]);
    expect(m!.homeChunk).toBe(chunkKey(0, 0));
    expect([m!.minX, m!.minY, m!.maxX, m!.maxY]).toEqual([100, 200, 110, 210]);
  });
  it('distance is to the plan box', () => {
    expect(modelDistance(m!, 105, 205)).toBe(0);
    expect(modelDistance(m!, 113, 214)).toBeCloseTo(5);
  });
  it('a pack without models has none, a broken file too', async () => {
    const src: PackSource = { read: async () => { throw new Error('404'); } };
    expect(await loadModels(src, 0, 256)).toEqual([]);
    expect(await loadModels(src, 1, 256)).toEqual([]);
  });
});

describe('model ↔ footprints with hysteresis', () => {
  const near = tuning.models.nearM, hy = tuning.models.hysteresisM;
  it('switches on within near_m and off only beyond near_m + hysteresis_m', () => {
    let shown = fullModels([near + 10], new Set(), near, hy, 3);
    expect(shown.size).toBe(0);
    shown = fullModels([near - 1], shown, near, hy, 3);
    expect(shown.has(0)).toBe(true);
    shown = fullModels([near + hy - 1], shown, near, hy, 3);
    expect(shown.has(0)).toBe(true);
    shown = fullModels([near + hy + 1], shown, near, hy, 3);
    expect(shown.size).toBe(0);
  });
  it('at most max_full, the nearest win', () => {
    const shown = fullModels([50, 10, 400, 20, 5], new Set(), near, hy, tuning.models.maxFull);
    expect([...shown].sort()).toEqual([1, 3, 4].slice(0, tuning.models.maxFull).sort());
  });
});

describe('model geometry', () => {
  const [m] = prepareModels(boxModels(), 256);
  const pal = cityPalette('prague');
  it('one triangle per source triangle at the display height on base_z', () => {
    const t = new Tris();
    modelTris(m!, pal, 'prague', tuning, t);
    expect(t.idx.length / 3).toBe(10);
    const top = 5.5 + displayHeight(extrusionScale(20, tuning), cameraHeight(tuning));
    const zs = t.pos.filter((_, i) => i % 3 === 1);
    expect(Math.min(...zs)).toBeCloseTo(5.5);
    expect(Math.max(...zs)).toBeCloseTo(top);
    // Flat pack: base 0.
    const f = new Tris();
    modelTris(m!, pal, 'prague', tuning, f, false);
    expect(Math.min(...f.pos.filter((_, i) => i % 3 === 1))).toBeCloseTo(0);
  });
  it('roles take color.model, walls the landmark colour, night its own', () => {
    const c = roleColors(pal, 'prague');
    expect(c[ModelRole.ROLE_WALL]).toEqual(pal.landmark);
    expect(c[ModelRole.ROLE_COPPER]).toEqual(rgba(tokens.colorModelDayCopper));
    expect(roleColors(nightPalette, 'prague')[ModelRole.ROLE_ROOF]).toEqual(rgba(tokens.colorModelNightRoof));
    expect(planRoofColor(pal, 'prague', 3)[0]).toBeGreaterThan(planRoofColor(pal, 'prague', 0)[0]);
  });
  it('the roof plan is a prism per polygon', () => {
    const t = new Tris();
    planTris(m!, pal, 'prague', tuning, t);
    expect(t.idx.length / 3).toBe(4 * 2 + 2);
    const b = planBuildings(m!)[0]!;
    expect(b.height).toBe(20);
    expect(b.baseZ).toBeCloseTo(5.5);
  });
});

const packDir = join(root, 'build', 'packs', 'prague');
const hasModels = existsSync(join(packDir, 'models.pb'));
const src: PackSource = { read: async (p) => new Uint8Array(readFileSync(join(packDir, p))) };

describe.skipIf(!hasModels)('Prague Castle in the pack', () => {
  it('loads with the city, within budget, replaces existing buildings incl. the landmark', async () => {
    const city = await City.load(src);
    expect(city.manifest.modelsVersion).toBe(1);
    expect(city.manifest.attribution.some((a) => a.includes('IPR Praha'))).toBe(true);
    const castle = city.models.find((m) => m.landmarkId === 'prague_castle');
    expect(castle).toBeDefined();
    expect(castle!.tris).toBeLessThanOrEqual(tuning.models.maxTrisException);
    expect(castle!.plan.length).toBeLessThanOrEqual(tuning.models.roofPlanMaxPolys);
    const lmIdx = city.landmarks.items.findIndex((l) => l.id === 'prague_castle') + 1;
    let landmarkReplaced = false;
    for (const [key, set] of castle!.replaces) {
      const ref = city.manifest.chunks.find((c) => chunkKey(c.x, c.y) === key)!;
      const c = await prepareChunk(await src.read(`chunks/${ref.x}_${ref.y}.pb`));
      for (const i of set) {
        expect(i).toBeLessThan(c.buildings.length);
        if (c.buildings[i]!.landmark === lmIdx) landmarkReplaced = true;
      }
    }
    expect(landmarkReplaced).toBe(true);
    // The castle stands near its landmark point.
    const lm = city.landmarks.items[lmIdx - 1]!;
    expect(modelDistance(castle!, lm.x / 10, lm.y / 10)).toBe(0);
    // Whole model geometry builds (degenerate triangles of flattened feet are dropped).
    const t = new Tris();
    modelTris(castle!, cityPalette('prague'), 'prague', tuning, t);
    expect(t.idx.length / 3).toBeLessThanOrEqual(castle!.tris);
    expect(t.idx.length / 3).toBeGreaterThan(castle!.tris * 0.9);
  });
});
