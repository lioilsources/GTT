import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { findRoute, polylineDm, routeGraphFromConfig, routeGraphFromPb } from '../src/drive/gps';
import { Tuning } from '../src/gen/tuning';
import { decodeGraph, decodeSpots } from '../src/world/citypack';

const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const cost = tuning.route.classCost;

describe('GPS route (specs/route.md)', () => {
  it('measures polylines with floor(sqrt) per segment', () => {
    expect(polylineDm([0, 0, 3, 4, 3, 5])).toBe(6);
    expect(polylineDm([0, 0, 1, 1])).toBe(1);
  });

  // 0 —(a)— 1 —(b, one-way 1→2)— 2, plus an alley 0—2.
  const g = routeGraphFromConfig({
    nodes: [0, 0, 100, 0, 200, 0],
    edges: [
      [0, 1, 3, 0, 1, 0, 0, 100, 0],
      [1, 2, 3, 1, 1, 100, 0, 200, 0],
      [0, 2, 3, 0, 0, 0, 0, 200, 0],
    ],
    classCost: cost,
  });

  it('respects one-ways and skips alleys', () => {
    expect(findRoute(g, 0, 2)).toEqual({ cost: 200 * cost[3]!, nodes: [0, 1, 2], edges: [0, 1] });
    expect(findRoute(g, 2, 0)).toEqual({ cost: -1, nodes: [], edges: [] });
    expect(findRoute(g, 1, 1)).toEqual({ cost: 0, nodes: [1], edges: [] });
  });

  it('prefers the cheaper of parallel edges, then the lower index', () => {
    const p = routeGraphFromConfig({
      nodes: [0, 0, 100, 0],
      edges: [
        [0, 1, 6, 0, 1, 0, 0, 100, 0],
        [0, 1, 3, 0, 1, 0, 0, 100, 0],
        [0, 1, 3, 0, 1, 0, 0, 100, 0],
      ],
      classCost: cost,
    });
    expect(findRoute(p, 0, 1).edges).toEqual([1]);
  });

  const pack = join(root, 'build', 'packs', 'nyc');
  it.skipIf(!existsSync(pack))('reaches every NYC spot from every other over kept roads', async () => {
    const graph = await decodeGraph(new Uint8Array(readFileSync(join(pack, 'graph.pb'))));
    const spots = await decodeSpots(new Uint8Array(readFileSync(join(pack, 'spots.pb'))));
    const rg = routeGraphFromPb(graph, cost);
    const first = spots.items[0]!;
    for (const s of spots.items) {
      const a = graph.edges[first.edge]!, b = graph.edges[s.edge]!;
      const r = findRoute(rg, a.to, b.from);
      const r2 = r.cost >= 0 ? r : findRoute(rg, a.to, b.to);
      expect(r2.cost, s.id).toBeGreaterThanOrEqual(0);
    }
  });
});
