import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { gzipSync } from 'node:zlib';

import { create, toBinary, type DescMessage, type MessageShape } from '@bufbuild/protobuf';
import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { EdgeSchema, GraphSchema, GroundKind, LandmarksSchema, ManifestSchema, NodeSchema, RoadClass, SpotsSchema } from '../src/gen/pb/citypack_pb';
import { Tuning } from '../src/gen/tuning';
import { buildRoads, GROUND_ORDER, ROAD_LIFT, Tris } from '../src/render/geometry';
import { dayPalette } from '../src/render/palette';
import { drapedGroundTris, meshHeight, renderHeights, shadeFactor, terrainTris } from '../src/render/terrainMesh';
import { TERRAIN_N, type ChunkData } from '../src/world/chunk';
import { City } from '../src/world/model';
import { ridesEdge } from '../src/world/terrain';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const gz = <D extends DescMessage>(schema: D, m: MessageShape<D>): Uint8Array => new Uint8Array(gzipSync(toBinary(schema, m)));

/** One east–west edge 0 → 200 m rising 0 → 20 m (10 %), points every 16 m; terrain z = x / 10 + y / 20. */
async function city(terrainVersion: number): Promise<City> {
  const pts: number[] = [], z: number[] = [];
  for (let x = 0; x <= 200; x += 20) {
    pts.push(x * 10, 50 * 10);
    z.push(x);
  }
  const files: Record<string, Uint8Array> = {
    'manifest.pb': gz(ManifestSchema, create(ManifestSchema, { formatVersion: 1, cityId: 'test', chunkM: 256, terrainVersion, z0M: 100, exaggeration: 2 })),
    'graph.pb': gz(GraphSchema, create(GraphSchema, {
      names: [''], nodes: [create(NodeSchema, { x: 0, y: 500, zDm: 0 }), create(NodeSchema, { x: 2000, y: 500, zDm: 200 })],
      edges: [create(EdgeSchema, { from: 0, to: 1, points: pts, zDm: z, class: RoadClass.PRIMARY, lanes: 2, kept: true, widthM: 12 })],
    })),
    'landmarks.pb': gz(LandmarksSchema, create(LandmarksSchema, {})),
    'spots.pb': gz(SpotsSchema, create(SpotsSchema, {})),
  };
  return City.load({ read: async (p) => files[p] ?? Promise.reject(new Error(p)) });
}

function chunk(): ChunkData {
  const N = TERRAIN_N, terrain = new Float32Array(N * N), shade = new Uint8Array(N * N).fill(200);
  for (let j = 0; j < N; j++) for (let i = 0; i < N; i++) terrain[j * N + i] = (i * 8) / 10 + (j * 8) / 20 + ((i * j) % 3) * 0.5;
  const park = { kind: GroundKind.PARK, xy: Float32Array.from([10, 10, 120, 15, 60, 90]), indices: Uint32Array.from([0, 1, 2]) };
  const water = { kind: GroundKind.WATER, z: 2, xy: Float32Array.from([150, 150, 250, 150, 250, 250, 150, 250]), indices: Uint32Array.from([0, 1, 2, 0, 2, 3]) };
  return { x: 0, y: 0, buildings: [], ground: [park, water], barriers: [], terrain, shade };
}

describe('heights (specs/terrain.md "Výška pod bodem")', () => {
  it('a pack without terrain_version is flat: z 0, gradient 0, roads at 0', async () => {
    const c = await city(0);
    c.terrain.addChunk(chunk());
    const g = { x: 1, y: 1 };
    c.terrain.grad(50, 50, null, g);
    expect([c.terrain.groundZ(50, 50, null), c.terrain.groundZ(100, 50, c.graph.edges[0]!), g.x, g.y]).toEqual([0, 0, 0, 0]);
    const roads = buildRoads(c, tuning, dayPalette);
    for (const r of roads.values()) for (let i = 1; i < r.ground.pos.length; i += 3) expect(r.ground.pos[i]!).toBeLessThan(0.2);
  });

  it('terrain bilinear inside a loaded chunk, the nearest node outside, the edge by projection', async () => {
    const c = await city(1);
    const ch = chunk();
    c.terrain.addChunk(ch);
    expect(c.terrain.terrainAt(4, 0)).toBeCloseTo((0 + ch.terrain![1]!) / 2, 6);
    expect(c.terrain.terrainAt(-10, 50)).toBeNull();
    expect(c.terrain.groundZ(-10, 50, null)).toBe(0); // node 0
    expect(c.terrain.groundZ(105, 53, c.graph.edges[0]!)).toBeCloseTo(10.5, 5);
    const g = { x: 0, y: 0 };
    c.terrain.grad(105, 53, c.graph.edges[0]!, g);
    expect(g.x).toBeCloseTo(0.1, 6);
    expect(g.y).toBeCloseTo(0, 6);
    expect(c.terrain.altitude(20)).toBe(110);
  });

  it('the car rides the edge on ramps, bridges and tunnels, the terrain on ground roads', async () => {
    const c = await city(1);
    const e = c.graph.edges[0]!;
    expect(ridesEdge(e, 0, 1, 2)).toBe(false);
    expect(ridesEdge(e, -1, 1, 2)).toBe(true);
  });
});

describe('terrain drawing (specs/terrain.md "Vykreslení terénu", W)', () => {
  it('one mesh per chunk: 33 × 33 vertices, 2 048 triangles, colour × shade', () => {
    const t = new Tris();
    terrainTris(chunk(), 256, [0.5, 0.5, 0.5, 1], t);
    expect(t.vertexCount).toBe(33 * 33);
    expect(t.idx.length / 3).toBe(2048);
    expect(t.col[0]).toBeCloseTo(0.5 * shadeFactor(200), 6);
    expect(shadeFactor(128)).toBeCloseTo(1, 2);
  });

  it('draped ground lies on the mesh and keeps its area; water stays flat at its level', () => {
    const c = chunk();
    const t = new Tris();
    drapedGroundTris(c, dayPalette, 256, t, GROUND_ORDER);
    let area = 0;
    const p = t.pos;
    for (let k = 0; k < t.idx.length; k += 3) {
      const a = t.idx[k]!, b = t.idx[k + 1]!, d = t.idx[k + 2]!;
      const ax = p[3 * a]!, ay = p[3 * a + 2]!, bx = p[3 * b]!, by = p[3 * b + 2]!, dx = p[3 * d]!, dy = p[3 * d + 2]!;
      const s = ((bx - ax) * (dy - ay) - (dx - ax) * (by - ay)) / 2;
      // Water: the 100 × 100 square at level 2.
      if (p[3 * a + 1]! < 2.2 && ax >= 150 && ay >= 150) continue;
      area += Math.abs(s);
    }
    const park = Math.abs(((120 - 10) * (90 - 10) - (60 - 10) * (15 - 10)) / 2);
    expect(area).toBeCloseTo(park, 1);
    for (let v = 0; v < t.vertexCount; v++) {
      const x = p[3 * v]!, y = p[3 * v + 2]!, z = p[3 * v + 1]!;
      if (x >= 150 && y >= 150) expect(z).toBeLessThan(2.2);
      else expect(z - meshHeight(c.terrain!, x / 8, y / 8)).toBeGreaterThan(0);
    }
  });

  it('no terrain sample inside water stands above level − underwater', () => {
    const h = renderHeights(chunk(), 256, 3)!;
    const N = TERRAIN_N;
    for (let j = 19; j < N - 1; j++) for (let i = 19; i < N - 1; i++) expect(h[j * N + i]!).toBeLessThanOrEqual(-1 + 1e-6);
  });

  it('roads on relief at their profile + ROAD_LIFT, uphill arrows on the 10 % edge', async () => {
    const c = await city(1);
    const roads = buildRoads(c, tuning, dayPalette);
    const r = [...roads.values()][0]!;
    let low = Infinity;
    for (let i = 0; i < r.ground.pos.length; i += 3) {
      const x = r.ground.pos[i]!, z = r.ground.pos[i + 1]!;
      if (x > 5 && x < 195) low = Math.min(low, z - x / 10);
    }
    expect(low).toBeGreaterThanOrEqual(ROAD_LIFT - 1.2);
    expect(low).toBeLessThan(ROAD_LIFT + 0.5);
    const marks = (t: Tris): number => {
      let n = 0;
      const m = dayPalette.marking;
      for (let i = 0; i < t.col.length; i += 4) if (t.col[i] === m[0] && t.col[i + 1] === m[1] && t.col[i + 2] === m[2]) n++;
      return n;
    };
    const flat = buildRoads(await city(0), tuning, dayPalette);
    expect(marks([...flat.values()][0]!.ground)).toBe(0);
    // 200 m at 10 %: a chevron (2 quads) every 24 m.
    expect(marks(r.ground)).toBe(8 * 2 * 4);
  });
});
