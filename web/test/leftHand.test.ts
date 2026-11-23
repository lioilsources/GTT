import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { create } from '@bufbuild/protobuf';
import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { generateParked } from '../src/cars/parked';
import { EdgeSchema, GraphSchema, NodeSchema, RoadClass } from '../src/gen/pb/citypack_pb';
import type { CarSpec } from '../src/gen/schema';
import { Tuning } from '../src/gen/tuning';
import { spawnPassenger } from '../src/minigames/taxi/shift';
import { RoadGraph } from '../src/world/model';

// Left-hand traffic (specs/cities.md v2): with manifest driveSide = left the parked cars face along
// their lane on the left of the segment and the taxi passenger waits on the left curb.
const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const specs = new Map<string, CarSpec>(
  readdirSync(join(root, 'content', 'cars')).filter((f) => f.endsWith('.json')).map((f) => {
    const s = JSON.parse(readFileSync(join(root, 'content', 'cars', f), 'utf8')) as CarSpec;
    return [s.id, s] as const;
  }),
);

/** One straight two-way primary road west → east along y = 10 m (the pb holds dm). */
function road(x0: number, x1: number): RoadGraph {
  const pts: number[] = [];
  for (let x = x0; x <= x1; x += 40) pts.push(x * 10, 100);
  return RoadGraph.fromPb(create(GraphSchema, {
    names: [''],
    nodes: [create(NodeSchema, { x: x0 * 10, y: 100 }), create(NodeSchema, { x: x1 * 10, y: 100 })],
    edges: [create(EdgeSchema, { from: 0, to: 1, points: pts, class: RoadClass.PRIMARY, lanes: 4, oneway: 0, kept: true, widthM: 42 })],
  }));
}

/** Angle difference folded into [0, π]. */
const angle = (a: number, b: number): number => Math.abs(Math.atan2(Math.sin(a - b), Math.cos(a - b)));

describe('left-hand traffic (specs/cities.md v2)', () => {
  it('parked cars: same places, heading along the lane on the driving side', () => {
    const g = road(0, 256);
    const far = { x: 1e9, y: 1e9 };
    const right = generateParked(g, 0, 0, 1, tuning, specs, [], far, 'nyc', false);
    const left = generateParked(g, 0, 0, 1, tuning, specs, [], far, 'nyc', true);
    expect(right.length).toBeGreaterThan(1);
    expect(left.map((p) => [p.carId, p.x, p.y])).toEqual(right.map((p) => [p.carId, p.x, p.y]));
    let sides = 0;
    for (let i = 0; i < left.length; i++) {
      const l = left[i]!, r = right[i]!;
      expect(angle(l.heading, r.heading)).toBeCloseTo(Math.PI, 9);
      // North of the road is left of its direction (east): left-hand cars there face east.
      const onLeft = l.y > 10;
      sides |= onLeft ? 1 : 2;
      expect(angle(l.heading, 0)).toBeCloseTo(onLeft ? 0 : Math.PI, 9);
      expect(angle(r.heading, 0)).toBeCloseTo(onLeft ? Math.PI : 0, 9);
    }
    expect(sides).toBe(3);
  });

  it('taxi passenger waits on the curb left of the edge direction', () => {
    const g = road(-500, 500);
    const tt = tuning.minigames.taxi;
    const car = { x: -200, y: 10, heading: 0, speed: 0, layer: 0 };
    const r = spawnPassenger(g, car, tt, false)!;
    const l = spawnPassenger(g, car, tt, true)!;
    expect(r.x).toBeCloseTo(l.x, 9);
    expect(r.y).toBeCloseTo(10 - 21 - tt.curbM, 9);
    expect(l.y).toBeCloseTo(10 + 21 + tt.curbM, 9);
    expect(l.target).toEqual(r.target);
  });
});
