import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { create } from '@bufbuild/protobuf';
import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { EdgeSchema, GraphSchema, NodeSchema, RoadClass } from '../src/gen/pb/citypack_pb';
import { tokens } from '../src/gen/tokens';
import { Tuning } from '../src/gen/tuning';
import {
  buildingShadow, buildingTris, castShadowTris, crosswalkTris, roadArm, roofEdgeTris, shadowLength, Tris, Z,
} from '../src/render/geometry';
import { cityPalette, dayPalette, nightPalette, rgba } from '../src/render/palette';
import { cityFlag } from '../src/render/risograph';
import type { BuildingData, ChunkData } from '../src/world/chunk';
import { RoadGraph } from '../src/world/model';

const tuning = Tuning.fromJson(parse(readFileSync(join(__dirname, '..', '..', 'content', 'tuning.yaml'), 'utf8')));
const st = tuning.style;

function square(x0: number, y0: number, s: number, extra: Partial<BuildingData> = {}): BuildingData {
  return {
    xy: Float32Array.from([x0, y0, x0 + s, y0, x0 + s, y0 + s, x0, y0 + s]), ringEnds: Int32Array.from([4]),
    roof: Uint16Array.from([0, 1, 2, 0, 2, 3]), height: 30, minHeight: 0, landmark: 0, collide: true,
    seed: 7, cx: x0 + s / 2, cy: y0 + s / 2, radius: s * 0.71, wallU: Float32Array.from([0, s, 2 * s, 3 * s]),
    ...extra,
  };
}

/** Signed area in Babylon X/Z (negative = counter-clockwise in world x/y, a front face). */
function areaXZ(t: Tris, k: number): number {
  const p = (i: number): [number, number] => [t.pos[3 * t.idx[k + i]!]!, t.pos[3 * t.idx[k + i]! + 2]!];
  const [a, b, c] = [p(0), p(1), p(2)];
  return (b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1]);
}

/** Is world point (x, y) inside any triangle of t? */
function covered(t: Tris, x: number, y: number): boolean {
  for (let k = 0; k < t.idx.length; k += 3) {
    const p = (i: number): [number, number] => [t.pos[3 * t.idx[k + i]!]!, t.pos[3 * t.idx[k + i]! + 2]!];
    const [a, b, c] = [p(0), p(1), p(2)];
    const d1 = (x - b[0]) * (a[1] - b[1]) - (a[0] - b[0]) * (y - b[1]);
    const d2 = (x - c[0]) * (b[1] - c[1]) - (b[0] - c[0]) * (y - c[1]);
    const d3 = (x - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (y - a[1]);
    const neg = d1 < 0 || d2 < 0 || d3 < 0, pos = d1 > 0 || d2 > 0 || d3 > 0;
    if (!(neg && pos)) return true;
  }
  return false;
}

function xs(t: Tris): number[] { return t.pos.filter((_, i) => i % 3 === 0); }
function ys(t: Tris): number[] { return t.pos.filter((_, i) => i % 3 === 2); }
function hs(t: Tris): number[] { return t.pos.filter((_, i) => i % 3 === 1); }

describe('style A flat vector (specs/style.md v2)', () => {
  it('per-city switches: nyc shadows and zebras by day only, prague and unknown cities never', () => {
    expect(cityFlag(st.castShadow, 'nyc', false)).toBe(true);
    expect(cityFlag(st.castShadow, 'nyc', true)).toBe(false);
    expect(cityFlag(st.crosswalks, 'nyc', false)).toBe(true);
    expect(cityFlag(st.crosswalks, 'nyc', true)).toBe(false);
    expect(cityFlag(st.castShadow, 'prague', false)).toBe(false);
    expect(cityFlag(st.crosswalks, 'prague', false)).toBe(false);
    expect(cityFlag(st.castShadow, 'atlantis', false)).toBe(false);
    expect(cityFlag(st.castShadow, 'toString', false)).toBe(false);
  });

  it('tokyo: own skin with roof, roofEdge and castShadow; shadows and zebras on, risograph off', () => {
    const p = cityPalette('tokyo');
    expect(p).not.toBe(dayPalette);
    expect(p.facades).toEqual(tokens.colorCityTokyoFacades.map((h) => rgba(h)));
    expect(p.roof).toEqual(rgba(tokens.colorCityTokyoRoof));
    expect(p.roofEdge).toEqual(rgba(tokens.colorCityTokyoRoofEdge));
    expect(p.castShadow).toEqual(rgba(tokens.colorCityTokyoCastShadow));
    expect(cityFlag(st.castShadow, 'tokyo', false)).toBe(true);
    expect(cityFlag(st.crosswalks, 'tokyo', false)).toBe(true);
    expect(cityFlag(st.risograph, 'tokyo', false)).toBe(false);
  });

  it('moscow (style E): own skin from color.city.moscow incl. roof, roofEdge and castShadow; shadows and zebras on, risograph off', () => {
    const p = cityPalette('moscow');
    expect(p).not.toBe(dayPalette);
    expect(p).not.toBe(cityPalette('tokyo'));
    expect(p.night).toBe(false);
    expect(p.land).toEqual(rgba(tokens.colorCityMoscowLand));
    expect(p.water).toEqual(rgba(tokens.colorCityMoscowWater));
    expect(p.asphalt).toEqual(rgba(tokens.colorCityMoscowAsphalt));
    expect(p.landmark).toEqual(rgba(tokens.colorCityMoscowLandmark));
    expect(p.facades).toEqual(tokens.colorCityMoscowFacades.map((h) => rgba(h)));
    expect(p.roof).toEqual(rgba(tokens.colorCityMoscowRoof));
    expect(p.roofEdge).toEqual(rgba(tokens.colorCityMoscowRoofEdge));
    expect(p.castShadow).toEqual(rgba(tokens.colorCityMoscowCastShadow));
    expect(cityFlag(st.castShadow, 'moscow', false)).toBe(true);
    expect(cityFlag(st.castShadow, 'moscow', true)).toBe(false);
    expect(cityFlag(st.crosswalks, 'moscow', false)).toBe(true);
    expect(cityFlag(st.risograph, 'moscow', false)).toBe(false);
  });

  it('palette: nyc gets roof, roofEdge and castShadow; prague, the default and night do not', () => {
    const p = cityPalette('nyc');
    expect(p.roof).toEqual(rgba(tokens.colorCityNycRoof));
    expect(p.roofEdge).toEqual(rgba(tokens.colorCityNycRoofEdge));
    expect(p.castShadow).toEqual(rgba(tokens.colorCityNycCastShadow));
    expect(p.castShadow![3]).toBeLessThan(1);
    for (const q of [cityPalette('prague'), dayPalette, nightPalette]) {
      expect(q.roof).toBeUndefined();
      expect(q.roofEdge).toBeUndefined();
      expect(q.castShadow).toBeUndefined();
    }
  });

  it('shadow length is height × shadow_ratio capped at shadow_max_m', () => {
    expect(shadowLength(10, tuning)).toBeCloseTo(10 * st.shadowRatio, 9);
    expect(shadowLength(1000, tuning)).toBe(st.shadowMaxM);
    expect(shadowLength(st.shadowMaxM / st.shadowRatio, tuning)).toBeCloseTo(st.shadowMaxM, 9);
    expect(shadowLength(0, tuning)).toBe(0);
  });

  it('shadow of a prism = footprint swept by L·s, front faces, at Z.castShadow in castShadow', () => {
    const b = square(0, 0, 10);
    const L = 8, sx = 0.6, sy = -0.8;
    const t = new Tris();
    const col = rgba(tokens.colorCityNycCastShadow);
    buildingShadow(b, L, sx, sy, Z.castShadow, col, t);
    // Shifted roof (2 tris) + one quad per edge not parallel to s (4 edges).
    expect(t.idx.length).toBe(6 + 4 * 6);
    for (let k = 0; k < t.idx.length; k += 3) expect(areaXZ(t, k)).toBeLessThan(0);
    for (const h of hs(t)) expect(h).toBe(Z.castShadow);
    for (let i = 0; i < t.col.length; i += 4) expect(t.col.slice(i, i + 4)).toEqual([...col]);
    // Coverage equals the Minkowski sum of the square and the segment [0, L·s].
    const inSq = (x: number, y: number, m: number): boolean => x > -m && x < 10 + m && y > -m && y < 10 + m;
    const inSwept = (x: number, y: number, m: number): boolean => {
      for (let k = 0; k <= 400; k++) {
        const d = (L * k) / 400;
        if (inSq(x - sx * d, y - sy * d, m)) return true;
      }
      return false;
    };
    for (let x = -5; x <= 20; x += 0.7) {
      for (let y = -15; y <= 15; y += 0.7) {
        if (inSwept(x, y, -0.1)) expect(covered(t, x, y)).toBe(true);
        else if (!inSwept(x, y, 0.1)) expect(covered(t, x, y)).toBe(false);
      }
    }
  });

  it('cast shadows of a chunk: sun from light.day, length capped, parts above ground and v1 cities cast none', () => {
    const nyc = cityPalette('nyc');
    const sl = Math.hypot(nyc.sunX, nyc.sunY);
    const sx = -nyc.sunX / sl, sy = -nyc.sunY / sl;
    const tower = square(0, 0, 10, { height: 1000 });
    const chunk: ChunkData = { x: 0, y: 0, ground: [], barriers: [], buildings: [tower, square(50, 0, 10, { minHeight: 12, height: 40 })] };
    const t = new Tris();
    castShadowTris(chunk, nyc, tuning, t);
    expect(t.empty).toBe(false);
    // Only the tower casts, and its shadow reaches exactly shadow_max_m beyond the footprint along s.
    expect(Math.max(...xs(t))).toBeLessThan(50);
    let far = -Infinity, foot = -Infinity;
    for (let i = 0; i < t.pos.length; i += 3) far = Math.max(far, t.pos[i]! * sx + t.pos[i + 2]! * sy);
    for (let i = 0; i < tower.xy.length; i += 2) foot = Math.max(foot, tower.xy[i]! * sx + tower.xy[i + 1]! * sy);
    expect(far - foot).toBeCloseTo(st.shadowMaxM, 4);
    const none = new Tris();
    castShadowTris(chunk, cityPalette('prague'), tuning, none);
    castShadowTris(chunk, nightPalette, tuning, none);
    expect(none.empty).toBe(true);
  });

  it('roof: nyc buildings get roof × jitter and a parapet band inside the outline; landmarks and v1 do not', () => {
    const nyc = cityPalette('nyc');
    const chunk: ChunkData = { x: 0, y: 0, ground: [], barriers: [], buildings: [square(0, 0, 10)] };
    const t = new Tris();
    buildingTris(chunk, nyc, tuning, t);
    // 4 walls + roof (2 tris) + 4 band quads.
    expect(t.idx.length).toBe(4 * 6 + 6 + 4 * 6);
    const tops = hs(t);
    const z1 = Math.max(...tops.filter((h) => h < Math.max(...tops)));
    const jitter = 0.94 + (((7 >> 8) & 0xff) / 255) * 0.12;
    const roofCols = new Set<string>(), edgeCols = new Set<string>();
    for (let i = 0; i < tops.length; i++) {
      const c = t.col.slice(4 * i, 4 * i + 4).map((v) => v.toFixed(4)).join();
      if (tops[i] === Math.max(...tops)) edgeCols.add(c);
      else if (tops[i] === z1) roofCols.add(c);
    }
    expect([...edgeCols]).toEqual([[...nyc.roofEdge!].map((v) => v.toFixed(4)).join()]);
    expect(roofCols.has([nyc.roof![0] * jitter, nyc.roof![1] * jitter, nyc.roof![2] * jitter, 1].map((v) => v.toFixed(4)).join())).toBe(true);
    expect(Math.max(...tops) - z1).toBeCloseTo(Z.roofEdgeLift, 6);

    const lm = new Tris();
    buildingTris({ ...chunk, buildings: [square(0, 0, 10, { landmark: 1 })] }, nyc, tuning, lm);
    expect(lm.idx.length).toBe(4 * 6 + 6);
    const v1 = new Tris();
    buildingTris(chunk, cityPalette('prague'), tuning, v1);
    expect(v1.idx.length).toBe(4 * 6 + 6);
  });

  it('parapet band is roof_edge_m wide on the inner side of outer rings and courtyards', () => {
    const w = st.roofEdgeM;
    // 20 m square with a CW 10 m courtyard in the middle.
    const b = square(0, 0, 20, {
      xy: Float32Array.from([0, 0, 20, 0, 20, 20, 0, 20, 5, 5, 5, 15, 15, 15, 15, 5]),
      ringEnds: Int32Array.from([4, 8]),
    });
    const t = new Tris();
    roofEdgeTris(b, w, 1, [1, 1, 1, 1], t);
    expect(t.idx.length).toBe(8 * 6);
    for (let k = 0; k < t.idx.length; k += 3) expect(areaXZ(t, k)).toBeLessThan(0);
    // Never outside the outline, never inside the courtyard, never farther than w from an edge.
    for (let i = 0; i < t.pos.length; i += 3) {
      const x = t.pos[i]!, y = t.pos[i + 2]!;
      expect(x).toBeGreaterThanOrEqual(-1e-6);
      expect(x).toBeLessThanOrEqual(20 + 1e-6);
      expect(y).toBeGreaterThanOrEqual(-1e-6);
      expect(y).toBeLessThanOrEqual(20 + 1e-6);
      const inHole = x > 5 + 1e-6 && x < 15 - 1e-6 && y > 5 + 1e-6 && y < 15 - 1e-6;
      expect(inHole).toBe(false);
      const dOuter = Math.min(x, y, 20 - x, 20 - y);
      const dHole = Math.max(Math.abs(x - 10), Math.abs(y - 10)) - 5;
      expect(Math.min(dOuter, dHole)).toBeLessThanOrEqual(w + 1e-6);
    }
    expect(covered(t, 10, w / 2)).toBe(true);
    expect(covered(t, 10, 5 - w / 2)).toBe(true);
    expect(covered(t, 10, 2.5)).toBe(w >= 2.5);
  });
});

describe('zebra crossings (specs/style.md v2 "Zebry")', () => {
  /**
   *                2 (0,100)
   *                | e1 w16
   *  3 (-10,0) ─e2 w12─ 0 ─e0 w20─ 1 (100,0)
   *                | e3 alley w30 (not kept)
   *                4 (0,-100)
   *  e4: bridge 0→5 (layer 1); 1 has e0 + e5 + alley e6 only.
   */
  function graph(): RoadGraph {
    const n = (x: number, y: number) => create(NodeSchema, { x: x * 10, y: y * 10 });
    const e = (from: number, to: number, pts: number[], kept: boolean, widthM: number, layer = 0) =>
      create(EdgeSchema, {
        from, to, points: pts.map((v) => v * 10), class: RoadClass.RESIDENTIAL, lanes: 2, oneway: 0, kept, widthM,
        layerFrom: layer, layerTo: layer, bridge: layer > 0,
      });
    return RoadGraph.fromPb(create(GraphSchema, {
      names: [''],
      nodes: [n(0, 0), n(100, 0), n(0, 100), n(-10, 0), n(0, -100), n(-50, 50), n(100, 100), n(200, 0)],
      edges: [
        e(0, 1, [0, 0, 50, 0, 100, 0], true, 20),
        e(0, 2, [0, 0, 0, 100], true, 16),
        e(3, 0, [-10, 0, 0, 0], true, 12),
        e(0, 4, [0, 0, 0, -100], false, 30),
        e(0, 5, [0, 0, -50, 50], true, 40, 1),
        e(1, 6, [100, 0, 100, 100], true, 16),
        e(1, 7, [100, 0, 200, 0], false, 12),
      ],
    }));
  }

  it('crossings on the long kept ground edges of a 3-way node, none on short edges or 2-way nodes', () => {
    const t = new Tris();
    const col = cityPalette('nyc').marking;
    crosswalkTris(graph(), tuning, col, () => t);
    expect(t.empty).toBe(false);
    for (const h of hs(t)) expect(h).toBe(Z.crosswalks);
    for (let i = 0; i < t.col.length; i += 4) expect(t.col.slice(i, i + 4)).toEqual([...col]);
    const carriage = (w: number) => Math.max(w - 2 * tuning.sidewalkWidthM, tuning.laneWidthM) / 2;
    const stripes = (w: number) => {
      let k = 0;
      for (let o = -carriage(w); o < carriage(w) - 1e-6; o += 2 * st.crosswalkStripeM) k++;
      return k;
    };
    // Node 0: e0 (w20), e1 (w16), e2 (w12) count; alley and bridge do not. e2 is too short.
    const cEast = 16 / 2 + st.crosswalkGapM, cNorth = 20 / 2 + st.crosswalkGapM;
    expect(10).toBeLessThan(2 * (20 / 2 + st.crosswalkGapM + st.crosswalkLenM));
    expect(t.idx.length).toBe((stripes(20) + stripes(16)) * 6);
    const east: number[] = [], north: number[] = [];
    for (let i = 0; i < t.pos.length; i += 3) {
      const x = t.pos[i]!, y = t.pos[i + 2]!;
      if (Math.abs(y) <= carriage(20) + 1e-4 && x > 1) east.push(i);
      else if (Math.abs(x) <= carriage(16) + 1e-4 && y > 1) north.push(i);
      else throw new Error(`stray crossing vertex at ${x}, ${y}`);
    }
    expect(east.length).toBe(stripes(20) * 4);
    expect(north.length).toBe(stripes(16) * 4);
    expect(Math.min(...east.map((i) => t.pos[i]!))).toBeCloseTo(cEast, 4);
    expect(Math.max(...east.map((i) => t.pos[i]!))).toBeCloseTo(cEast + st.crosswalkLenM, 4);
    expect(Math.min(...north.map((i) => t.pos[i + 2]!))).toBeCloseTo(cNorth, 4);
    expect(Math.max(...north.map((i) => t.pos[i + 2]!))).toBeCloseTo(cNorth + st.crosswalkLenM, 4);
    // First stripe flush with the carriageway edge, stripes stay on the carriageway.
    const ey = east.map((i) => t.pos[i + 2]!);
    expect(Math.min(...ey)).toBeCloseTo(-carriage(20), 4);
    expect(Math.max(...ey)).toBeLessThanOrEqual(carriage(20) + 1e-4);
    // The last stripe is clipped at the carriageway edge (or ends in a gap before it).
    expect(Math.max(...ey)).toBeGreaterThan(carriage(20) - 2 * st.crosswalkStripeM);
    for (let k = 0; k < t.idx.length; k += 3) expect(areaXZ(t, k)).toBeLessThan(0);
  });

  it('stripes alternate with gaps of the same width (crosswalk_stripe_m)', () => {
    const t = new Tris();
    crosswalkTris(graph(), tuning, [1, 1, 1, 1], () => t);
    const ys0 = new Set(ys(t).filter((y, i) => xs(t)[i]! > 5 && Math.abs(y) < 9).map((v) => v.toFixed(3)));
    const sorted = [...ys0].map(Number).sort((a, b) => a - b);
    // Every edge but the clipped last one sits a stripe width from the previous edge.
    for (let i = 1; i + 1 < sorted.length; i++) expect(sorted[i]! - sorted[i - 1]!).toBeCloseTo(st.crosswalkStripeM, 3);
    expect(sorted[sorted.length - 1]! - sorted[sorted.length - 2]!).toBeLessThanOrEqual(st.crosswalkStripeM + 1e-3);
  });

  it('a street split by pass-through nodes counts as one; it stops at the next junction', () => {
    // 0 is a junction; east and west are split by degree-2 nodes 1 and 3 (west drawn towards 0),
    // south reaches junction 6 after 8 m, too short for a crossing at either end.
    const n = (x: number, y: number) => create(NodeSchema, { x: x * 10, y: y * 10 });
    const e = (from: number, to: number, pts: number[]) =>
      create(EdgeSchema, { from, to, points: pts.map((v) => v * 10), class: RoadClass.RESIDENTIAL, lanes: 2, kept: true, widthM: 20 });
    const g = RoadGraph.fromPb(create(GraphSchema, {
      names: [''],
      nodes: [n(0, 0), n(6, 0), n(100, 0), n(-6, 0), n(0, 100), n(-100, 0), n(0, -8), n(50, -8), n(-50, -8)],
      edges: [
        e(0, 1, [0, 0, 6, 0]), e(1, 2, [6, 0, 100, 0]),
        e(5, 3, [-100, 0, -6, 0]), e(3, 0, [-6, 0, 0, 0]),
        e(0, 4, [0, 0, 0, 100]),
        e(0, 6, [0, 0, 0, -8]), e(6, 7, [0, -8, 50, -8]), e(6, 8, [0, -8, -50, -8]),
      ],
    }));
    const c = 10 + st.crosswalkGapM;
    const east = roadArm(g, 0, { e: g.edges[0]!, rev: false }, 1000);
    expect(east.length).toBeCloseTo(100, 4);
    const west = roadArm(g, 0, { e: g.edges[3]!, rev: true }, 1000);
    expect(west.length).toBeCloseTo(100, 4);
    expect(west.pts.slice(-2)).toEqual([-100, 0]);
    expect(roadArm(g, 0, { e: g.edges[5]!, rev: false }, 1000).length).toBeCloseTo(8, 4);
    // Stops once long enough.
    expect(roadArm(g, 0, { e: g.edges[0]!, rev: false }, 3).length).toBeCloseTo(6, 4);

    const t = new Tris();
    crosswalkTris(g, tuning, [1, 1, 1, 1], () => t);
    const x = xs(t), y = ys(t);
    const onE = x.filter((v, i) => v > 1 && Math.abs(y[i]!) < 10);
    const onW = x.filter((v, i) => v < -1 && Math.abs(y[i]!) < 10);
    expect(Math.min(...onE)).toBeCloseTo(c, 4);
    expect(Math.max(...onE)).toBeCloseTo(c + st.crosswalkLenM, 4);
    expect(Math.max(...onW)).toBeCloseTo(-c, 4);
    expect(Math.min(...onW)).toBeCloseTo(-c - st.crosswalkLenM, 4);
    expect(y.some((v) => v > 1)).toBe(true);
    expect(y.some((v, i) => v < -1 && Math.abs(x[i]!) < 10)).toBe(false);
  });
});
