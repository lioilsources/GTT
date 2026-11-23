import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { create } from '@bufbuild/protobuf';
import { parse } from 'yaml';
import { describe, expect, it } from 'vitest';

import { LodKind, LodMassSchema, LodSchema, MeshSchema } from '../src/gen/pb/citypack_pb';
import { Tuning } from '../src/gen/tuning';
import { hopFlip, hopRoll } from '../src/drive/hop';
import {
  CAMERA_KEY, chaseFov, chasePitch, chasePose, DOUBLE_TAP_S, fogFactor, FOG_END_M, FOG_START_M, occludes, readCameraMode, TwoFingerTap, writeCameraMode,
} from '../src/render/chase';
import { gridAt, gridShade, lodGrid, lodTris, tilesWithin } from '../src/render/lodGeometry';
import { dayPalette } from '../src/render/palette';

const tuning = Tuning.fromJson(parse(readFileSync(join(__dirname, '..', '..', 'content', 'tuning.yaml'), 'utf8')));
const chase = tuning.camera.chase;

describe('chase camera pose (specs/terrain.md "Šikmý pohled")', () => {
  it('stands distance_m behind and height_m above, aims look_ahead_m ahead about 27° down', () => {
    const p = chasePose(100, 50, 10, Math.PI / 2, chase);
    expect(p.eye.x).toBeCloseTo(100);
    expect(p.eye.y).toBeCloseTo(50 - chase.distanceM);
    expect(p.eye.z).toBeCloseTo(10 + chase.heightM);
    expect(p.target.y).toBeCloseTo(50 + chase.lookAheadM);
    expect(p.target.z).toBeCloseTo(10);
    expect((chasePitch(chase) * 180) / Math.PI).toBeGreaterThan(24);
    expect((chasePitch(chase) * 180) / Math.PI).toBeLessThan(30);
  });

  it('the relief zoom-out stretches distance and height; a hill behind lifts the eye', () => {
    const p = chasePose(0, 0, 0, 0, chase, 1.15);
    expect(p.eye.x).toBeCloseTo(-chase.distanceM * 1.15);
    expect(p.eye.z).toBeCloseTo(chase.heightM * 1.15);
    const hill = chasePose(0, 0, 0, 0, chase, 1, () => chase.heightM + 10);
    expect(hill.eye.z).toBeGreaterThan(chase.heightM + 10);
  });

  it('fov_deg holds for the shorter side', () => {
    expect(chaseFov(chase, 400, 800)).toEqual({ fov: (chase.fovDeg * Math.PI) / 180, horizontal: true });
    expect(chaseFov(chase, 800, 400).horizontal).toBe(false);
  });

  it('occluder test: only between the eye and the car, near the line, not below the car', () => {
    const eye = { x: 0, y: -55, z: 40 }, car = { x: 0, y: 0, z: 1 };
    expect(occludes(eye, car, { x: 0, y: -20, z: 17 })).toBe(true);
    expect(occludes(eye, car, { x: 10, y: -20, z: 17 })).toBe(false);
    expect(occludes(eye, car, { x: 0, y: 10, z: 1 })).toBe(false);
    expect(occludes(eye, car, { x: 0, y: -2, z: -0.5 })).toBe(false);
  });

  it('fog ramps in squared from start to end', () => {
    expect(fogFactor(FOG_START_M)).toBe(0);
    expect(fogFactor(FOG_END_M)).toBe(1);
    expect(fogFactor((FOG_START_M + FOG_END_M) / 2)).toBeCloseTo(0.25);
    expect(fogFactor(1e5)).toBe(1);
  });
});

describe('camera mode setting', () => {
  const store = (): { getItem(k: string): string | null; setItem(k: string, v: string): void; data: Map<string, string> } => {
    const data = new Map<string, string>();
    return { data, getItem: (k) => data.get(k) ?? null, setItem: (k, v) => void data.set(k, v) };
  };

  it('defaults to top-down (K1 = A), remembers the choice, ?camera= wins', () => {
    const s = store();
    expect(readCameraMode(null, s)).toBe('topdown');
    writeCameraMode('chase', s);
    expect(s.data.get(CAMERA_KEY)).toBe('chase');
    expect(readCameraMode(null, s)).toBe('chase');
    expect(readCameraMode('topdown', s)).toBe('topdown');
    expect(readCameraMode('bogus', s)).toBe('chase');
    expect(readCameraMode(null, null)).toBe('topdown');
  });

  it('survives a throwing storage', () => {
    const bad = { getItem: (): string | null => { throw new Error('blocked'); }, setItem: (): void => { throw new Error('blocked'); } };
    expect(readCameraMode(null, bad)).toBe('topdown');
    expect(() => writeCameraMode('chase', bad)).not.toThrow();
  });
});

describe('two-finger double tap', () => {
  const tap = (g: TwoFingerTap, t: number): boolean => {
    g.pointerDown(1, 100, 100, t);
    g.pointerDown(2, 200, 100, t + 0.01);
    g.pointerUp(1, t + 0.08);
    return g.pointerUp(2, t + 0.09);
  };

  it('fires on the second two-finger tap in time', () => {
    const g = new TwoFingerTap();
    expect(tap(g, 0)).toBe(false);
    expect(tap(g, 0.25)).toBe(true);
    // A third tap starts over.
    expect(tap(g, 0.5)).toBe(false);
  });

  it('ignores slow pairs, drags and one-finger taps', () => {
    const late = new TwoFingerTap();
    tap(late, 0);
    expect(tap(late, DOUBLE_TAP_S + 0.2)).toBe(false);
    const drag = new TwoFingerTap();
    tap(drag, 0);
    drag.pointerDown(1, 100, 100, 0.2);
    drag.pointerDown(2, 200, 100, 0.21);
    drag.pointerMove(2, 200, 180);
    drag.pointerUp(1, 0.25);
    expect(drag.pointerUp(2, 0.26)).toBe(false);
    const one = new TwoFingerTap();
    one.pointerDown(1, 0, 0, 0);
    expect(one.pointerUp(1, 0.05)).toBe(false);
    one.pointerDown(1, 0, 0, 0.1);
    expect(one.pointerUp(1, 0.15)).toBe(false);
  });
});

describe('lod far ring geometry (specs/terrain.md "Upřesnění T2")', () => {
  const N = 33;
  const terrain = (f: (i: number, j: number) => number): Uint8Array => {
    const b = new Uint8Array(N * N * 2);
    const dv = new DataView(b.buffer);
    for (let j = 0; j < N; j++) for (let i = 0; i < N; i++) dv.setInt16(2 * (j * N + i), Math.round(f(i, j) * 10), true);
    return b;
  };
  const opts = { gridM: 32, tileM: 1024, relief: true };

  it('reads the 33 × 33 dm grid and shades a flat tile 128', () => {
    const l = create(LodSchema, { x: 1, y: -1, terrain: terrain((i) => i) });
    const g = lodGrid(l, 32, 1024);
    expect(g.n).toBe(N);
    expect(g.x0).toBe(1024);
    expect(g.y0).toBe(-1024);
    expect(gridAt(g, 1024 + 16, -1024)).toBeCloseTo(0.5);
    const flat = lodGrid(create(LodSchema, { terrain: terrain(() => 5) }), 32, 1024);
    expect([...gridShade(flat)].every((s) => s === 128)).toBe(true);
    // The sun stands in the north-west: a slope facing it is lit, the opposite one darker.
    const nw = gridShade(lodGrid(create(LodSchema, { terrain: terrain((i, j) => i + (N - j)) }), 32, 1024));
    const se = gridShade(lodGrid(create(LodSchema, { terrain: terrain((i, j) => (N - i) + j) }), 32, 1024));
    expect(nw[16 * N + 16]!).toBeGreaterThan(128);
    expect(se[16 * N + 16]!).toBeLessThan(128);
  });

  it('one triangle set: terrain, water at its level, masses on base_z', () => {
    const square = [0, 0, 1000, 0, 1000, 1000, 0, 1000];
    const l = create(LodSchema, {
      terrain: terrain(() => 20),
      water: [create(MeshSchema, { vertices: [0, 0, 3000, 0, 0, 3000], indices: [0, 1, 2], zDm: 50 })],
      masses: [
        create(LodMassSchema, { kind: LodKind.LOD_BLOCK, rings: square, ringEnds: [4], roof: [0, 1, 2, 0, 2, 3], heightM: 20, baseZDm: 200 }),
        create(LodMassSchema, { kind: LodKind.LOD_WOOD, rings: square.map((v) => v + 2000), ringEnds: [4], roof: [0, 1, 2, 0, 2, 3], heightM: 14, baseZDm: 200 }),
      ],
    });
    const t = lodTris(l, dayPalette, tuning, 250, opts);
    // 32 × 32 × 2 terrain + 1 water + 2 × (4 walls × 2 + 2 roof).
    expect(t.idx.length / 3).toBe(2048 + 1 + 2 * 10);
    // Grid samples under the water are capped at level − underwater.
    const ys: number[] = [];
    for (let i = 1; i < t.pos.length; i += 3) ys.push(t.pos[i]!);
    expect(Math.min(...ys.slice(0, N * N))).toBeCloseTo(5 - tuning.terrain.pipeline.underwaterM);
    expect(Math.max(...ys)).toBeGreaterThan(20 + 15);
    // A flat pack draws everything at 0.
    const flat = lodTris(l, dayPalette, tuning, 250, { ...opts, relief: false });
    const fy: number[] = [];
    for (let i = 1; i < flat.pos.length; i += 3) fy.push(flat.pos[i]!);
    expect(Math.min(...fy)).toBeCloseTo(0);
  });

  it('picks the tiles within the ring', () => {
    const refs = [{ x: 0, y: 0 }, { x: 1, y: 0 }, { x: 3, y: 0 }, { x: 0, y: -2 }];
    expect(tilesWithin(refs, 1024, 512, 512, 1500)).toEqual([{ x: 0, y: 0 }, { x: 1, y: 0 }]);
  });
});

describe('hop in the chase view', () => {
  it('rolls 2π · flips over the flight, its cos is the top-down width factor', () => {
    expect(hopRoll(0.7, 1.4, 1)).toBeCloseTo(Math.PI);
    expect(hopRoll(1.4, 1.4, 1)).toBeCloseTo(2 * Math.PI);
    expect(Math.cos(hopRoll(0.3, 1.4, 1))).toBeCloseTo(hopFlip(0.3, 1.4, 1));
    expect(hopRoll(1, 0, 1)).toBe(0);
  });
});
