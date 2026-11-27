import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { create } from '@bufbuild/protobuf';
import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import {
  BuildingRefSchema, ModelPartSchema, ModelRole, ModelSchema, ModelSurface, ModelsSchema, PlanPolySchema,
} from '../src/gen/pb/citypack_pb';
import { tokens } from '../src/gen/tokens';
import { Tuning } from '../src/gen/tuning';
import { Tris } from '../src/render/geometry';
import { modelTris, modelUV, newModelTris, planBuildings, planRoofColor, planTris, roleColors, type ModelTris } from '../src/render/modelGeometry';
import { cityPalette, nightPalette, rgba } from '../src/render/palette';
import { cameraHeight, displayHeight, extrusionScale } from '../src/world/camera';
import type { PackSource } from '../src/world/citypack';
import { prepareChunk } from '../src/world/chunk';
import { City, chunkKey } from '../src/world/model';
import { fullModels, loadModels, modelDistance, prepareModels } from '../src/world/models';

// Landmark models (specs/models.md v2, F-085): data, switching with hysteresis, geometry, and the
// Prague pack's castle (skipped without build/packs/prague or a pack without models.pb).

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));

/** All triangles of the three model meshes. */
function allTris(t: ModelTris): number {
  return (t.walls.idx.length + t.stone.idx.length + t.roofs.idx.length) / 3;
}

/** All heights (Babylon y) of the three model meshes. */
function allZ(t: ModelTris): number[] {
  return [t.walls, t.stone, t.roofs].flatMap((x) => x.pos.filter((_, i) => i % 3 === 1));
}

/** A 10 × 10 × 20 m box part at (100, 200) with its roof as the plan; v2 surfaces, [wallRole] on the walls. */
function boxModels(wallRole: ModelRole = ModelRole.ROLE_WALL, surfaces = true): ReturnType<typeof create<typeof ModelsSchema>> {
  const pos: number[] = [];
  for (const z of [0, 200]) for (const [x, y] of [[0, 0], [100, 0], [100, 100], [0, 100]]) pos.push(x!, y!, z);
  // Walls (CCW from outside) and the roof.
  const tri = [0, 1, 5, 0, 5, 4, 1, 2, 6, 1, 6, 5, 2, 3, 7, 2, 7, 6, 3, 0, 4, 3, 4, 7, 4, 5, 6, 4, 6, 7];
  const roles = [...Array<number>(8).fill(wallRole), ModelRole.ROLE_COPPER, ModelRole.ROLE_COPPER];
  const surf = surfaces ? [...Array<number>(8).fill(ModelSurface.SURFACE_WALL), ModelSurface.SURFACE_ROOF, ModelSurface.SURFACE_ROOF] : [];
  return create(ModelsSchema, {
    models: [create(ModelSchema, {
      landmarkId: 'box', tris: 10,
      parts: [create(ModelPartSchema, { anchorX: 1000, anchorY: 2000, baseZDm: 55, positions: pos, triangles: tri, roles: Uint8Array.from(roles), surfaces: Uint8Array.from(surf) })],
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
    const t = newModelTris();
    modelTris(m!, pal, 'prague', tuning, t);
    expect(allTris(t)).toBe(10);
    const top = 5.5 + displayHeight(extrusionScale(20, tuning), cameraHeight(tuning));
    expect(Math.min(...allZ(t))).toBeCloseTo(5.5);
    expect(Math.max(...allZ(t))).toBeCloseTo(top);
    // Flat pack: base 0.
    const f = newModelTris();
    modelTris(m!, pal, 'prague', tuning, f, false);
    expect(Math.min(...allZ(f))).toBeCloseTo(0);
  });
  it('splits by surface and role: window walls, stone walls, roofs (v2 "Fasáda")', () => {
    const t = newModelTris();
    modelTris(m!, pal, 'prague', tuning, t);
    expect([t.walls.idx.length / 3, t.stone.idx.length / 3, t.roofs.idx.length / 3]).toEqual([8, 0, 2]);
    const [s] = prepareModels(boxModels(ModelRole.ROLE_STONE), 256);
    const st = newModelTris();
    modelTris(s!, pal, 'prague', tuning, st);
    expect([st.walls.idx.length / 3, st.stone.idx.length / 3, st.roofs.idx.length / 3]).toEqual([0, 8, 2]);
    // A v1 pack (no surfaces): roofs by role.
    const [v1] = prepareModels(boxModels(ModelRole.ROLE_WALL, false), 256);
    const o = newModelTris();
    modelTris(v1!, pal, 'prague', tuning, o);
    expect([o.walls.idx.length / 3, o.roofs.idx.length / 3]).toEqual([8, 2]);
  });
  it('stone walls tile one bay across and one storey up, continuous along a wall', () => {
    const [s] = prepareModels(boxModels(ModelRole.ROLE_STONE), 256);
    const t = newModelTris();
    modelTris(s!, pal, 'prague', tuning, t);
    const H = displayHeight(extrusionScale(20, tuning), cameraHeight(tuning));
    const uv = t.stone.uv, pos = t.stone.pos;
    // A wall is two triangles (6 vertices in order): a corner shared by both has the same UV.
    const seen = new Map<string, string>();
    for (let i = 0; i < pos.length / 3; i++) {
      const key = `${Math.floor(i / 6)}|` + pos.slice(3 * i, 3 * i + 3).map((x) => x.toFixed(3)).join();
      const val = `${uv[2 * i]!.toFixed(4)},${uv[2 * i + 1]!.toFixed(4)}`;
      if (seen.has(key)) expect(seen.get(key)).toBe(val);
      seen.set(key, val);
    }
    const vs = Array.from({ length: uv.length / 2 }, (_, i) => uv[2 * i + 1]!);
    expect(Math.min(...vs)).toBeCloseTo(0);
    expect(Math.max(...vs)).toBeCloseTo(H / tuning.models.facadeStoreyM);
    // The south wall (y = 200, normal −y) runs along +x: a 10 m wall spans 10 / bay in u.
    expect(modelUV('stone', 110, 200, 0, 1, 0, tuning)[0] - modelUV('stone', 100, 200, 0, 1, 0, tuning)[0]).toBeCloseTo(10 / tuning.models.facadeBayM);
    // Roofs: stripes across the slope, constant down it.
    const r0 = modelUV('roofs', 100, 200, 3, 1, 0, tuning), r1 = modelUV('roofs', 100, 205, 9, 1, 0, tuning);
    expect(r0).toEqual(r1);
    expect(modelUV('roofs', 100 + 4 * tuning.models.roofSeamM, 200, 0, 1, 0, tuning)[0] - r0[0]).toBeCloseTo(1);
  });
  it('roles take color.model, plaster walls (not the landmark colour), night its own', () => {
    const c = roleColors(pal, 'prague');
    expect(c[ModelRole.ROLE_WALL]).toEqual(rgba(tokens.colorModelDayWall));
    expect(c[ModelRole.ROLE_WALL]).not.toEqual(pal.landmark);
    expect(c[ModelRole.ROLE_STONE]).toEqual(rgba(tokens.colorModelDayStone));
    expect(c[ModelRole.ROLE_SLATE]).toEqual(rgba(tokens.colorModelDaySlate));
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
    expect(city.manifest.modelsVersion).toBeGreaterThanOrEqual(1);
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
    const t = newModelTris();
    modelTris(castle!, cityPalette('prague'), 'prague', tuning, t);
    expect(allTris(t)).toBeLessThanOrEqual(castle!.tris);
    expect(allTris(t)).toBeGreaterThan(castle!.tris * 0.9);
    if (city.manifest.modelsVersion >= 2) {
      // v2: the cathedral is stone under slate and copper, the palaces plaster (models.yaml).
      const roles = new Map<number, number>();
      for (const p of castle!.parts) for (const r of p.roles) roles.set(r, (roles.get(r) ?? 0) + 1);
      for (const r of [ModelRole.ROLE_WALL, ModelRole.ROLE_ROOF, ModelRole.ROLE_STONE, ModelRole.ROLE_SLATE, ModelRole.ROLE_COPPER]) {
        expect(roles.get(r) ?? 0).toBeGreaterThan(0);
      }
      expect(t.stone.idx.length).toBeGreaterThan(0);
      expect(castle!.parts.every((p) => p.surfaces.length === p.roles.length)).toBe(true);
    }
  });
});
