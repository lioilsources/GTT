import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { World } from 'planck';
import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { Car } from '../src/drive/car';
import type { CarSpec } from '../src/gen/schema';
import { Tuning } from '../src/gen/tuning';
import { articulate, feasibleNext, Trail } from '../src/trams/trackRules';
import { Trams } from '../src/trams/trams';
import { City, type TrackGraph } from '../src/world/model';

/**
 * L-S10 acceptance (specs/trams.md v2 "Plynulost"): on the whole Prague network the axis of every
 * tram car turns by at most trams.max_turn_deg_per_m per metre the nose travels.
 */
const root = join(__dirname, '..', '..');
const tuning = Tuning.fromJson(parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8')));
const t = tuning.trams;
const spec = JSON.parse(readFileSync(join(root, 'content', 'cars', 'm0_coupe.json'), 'utf8')) as CarSpec;
const dt = 1 / tuning.drive.stepHz;
const prague = join(root, 'build', 'packs', 'prague');
const cosMin = Math.cos((t.maxSwitchDeg * Math.PI) / 180);
const DEG = 180 / Math.PI;

/** Change of a car's axis (a heading modulo π), radians in [0, π/2]. */
function axisDelta(a: number, b: number): number {
  let d = (b - a) % Math.PI;
  if (d < 0) d += Math.PI;
  return Math.min(d, Math.PI - d);
}

/** Edge `ei` as travel-order points leaving `node`. */
function leaving(g: TrackGraph, ei: number, node: number): number[] {
  const e = g.edges[ei]!;
  const n = e.pointCount, out: number[] = [];
  for (let j = 0; j < n; j++) {
    const i = e.from === node ? j : n - 1 - j;
    out.push(e.pts[2 * i]!, e.pts[2 * i + 1]!);
  }
  return out;
}

/**
 * Drives an articulated tram (the client's Trail + articulate) along the polyline `path` in
 * `ds` steps and returns the largest axis change per metre of any car and where it happened.
 */
function worstRate(path: number[], ds: number): { rate: number; s: number } {
  const cum = [0];
  for (let i = 2; i < path.length; i += 2) cum.push(cum[cum.length - 1]! + Math.hypot(path[i]! - path[i - 2]!, path[i + 1]! - path[i - 1]!));
  const total = cum[cum.length - 1]!;
  let d0x = 1, d0y = 0;
  for (let i = 2; i < path.length; i += 2) {
    const dx = path[i]! - path[i - 2]!, dy = path[i + 1]! - path[i - 1]!, l = Math.hypot(dx, dy);
    if (l > 1e-9) {
      d0x = dx / l;
      d0y = dy / l;
      break;
    }
  }
  const tr = new Trail(t.trailPoints);
  tr.reset(path[0]!, path[1]!, d0x, d0y);
  tr.pushOldest(path[0]!, path[1]!);
  const prev = new Array<number>(t.carsPerTram).fill(NaN);
  let seg = 0, worst = 0, at = 0;
  for (let s = 0; s <= total; s += ds) {
    while (seg < cum.length - 2 && s > cum[seg + 1]!) {
      seg++;
      tr.push(path[2 * seg]!, path[2 * seg + 1]!);
    }
    const l = cum[seg + 1]! - cum[seg]!, f = l > 0 ? (s - cum[seg]!) / l : 0;
    tr.headX = path[2 * seg]! + (path[2 * seg + 2]! - path[2 * seg]!) * f;
    tr.headY = path[2 * seg + 1]! + (path[2 * seg + 3]! - path[2 * seg + 1]!) * f;
    for (let k = 0; k < t.carsPerTram; k++) {
      const h = articulate(tr, k, t.carLengthM, t.jointGapM).heading;
      if (!Number.isNaN(prev[k]!)) {
        const r = (axisDelta(prev[k]!, h) * DEG) / ds;
        if (r > worst) {
          worst = r;
          at = s;
        }
      }
      prev[k] = h;
    }
  }
  return { rate: worst, s: at };
}

describe.skipIf(!existsSync(join(prague, 'trams.pb')))('tram motion is smooth on the whole Prague network (L-S10)', () => {
  it('every track connection (arriving edge → each feasible next edge) stays under max_turn_deg_per_m', async () => {
    const city = await City.load({ read: async (p) => new Uint8Array(readFileSync(join(prague, p))) });
    const g = city.trams;
    expect(g.edges.length).toBeGreaterThan(1000);
    const out: number[] = [];
    let pairs = 0, worst = 0, where = '';
    const covered = new Set<number>();
    for (let node = 0; node < g.nodeEdges.length; node++) {
      const arrivals = [...new Set(g.nodeEdges[node]!)];
      for (const a of arrivals) {
        if (g.edges[a]!.from === g.edges[a]!.to) continue;
        const inPts = leaving(g, a, node);
        const arrive: number[] = [];
        for (let i = inPts.length - 2; i >= 0; i -= 2) arrive.push(inPts[i]!, inPts[i + 1]!);
        for (const b of feasibleNext(g, node, a, cosMin, t.turnProbeM, out)) {
          const path = arrive.concat(leaving(g, b, node).slice(2));
          const r = worstRate(path, 0.1);
          pairs++;
          covered.add(a).add(b);
          if (r.rate > worst) {
            worst = r.rate;
            where = `node ${node} (${g.nodeXY[2 * node]!.toFixed(0)}, ${g.nodeXY[2 * node + 1]!.toFixed(0)}) e${a} → e${b} at ${r.s.toFixed(1)} m`;
          }
        }
      }
    }
    console.log(`L-S10: ${pairs} connections, ${covered.size}/${g.edges.length} edges, max ${worst.toFixed(2)}°/m (${where})`);
    expect(pairs).toBeGreaterThan(g.edges.length);
    expect(worst, where).toBeLessThanOrEqual(t.maxTurnDegPerM);
    // Every edge is driven end to end in both directions (also those between two termini).
    for (const e of g.edges) {
      if (e.from === e.to || e.pointCount < 2) continue;
      for (const node of [e.from, e.to]) {
        const r = worstRate(leaving(g, e.index, node), 0.1);
        expect(r.rate, `e${e.index} from node ${node} at ${r.s.toFixed(1)} m`).toBeLessThanOrEqual(t.maxTurnDegPerM);
      }
    }
  }, 300000);

  it('live trams (spawn, switches, stops, termini) stay under max_turn_deg_per_m', async () => {
    const city = await City.load({ read: async (p) => new Uint8Array(readFileSync(join(prague, p))) });
    const g = city.trams;
    let worst = 0, metres = 0, changes = 0, where = '';
    // The player stands still beside the track at stops spread over the city; trams ignore it.
    const spots = g.stops.filter((_, i) => i % Math.max(1, Math.floor(g.stops.length / 12)) === 0);
    for (const st of spots) {
      const world = new World({ gravity: { x: 0, y: 0 } });
      const player = new Car(world, spec, tuning.drive, st.x - st.dirY * 30, st.y + st.dirX * 30, 0, tuning.carScale);
      const trams = new Trams(world, g, tuning);
      trams.solid = false;
      const last = new Map<object, number[]>();
      for (let i = 0; i < 120 / dt; i++) {
        trams.preStep(dt, player);
        world.step(dt, tuning.drive.velocityIterations, tuning.drive.positionIterations);
        trams.postStep(player);
        for (const tr of trams.trams) {
          const ds = tr.speed * dt;
          for (const c of tr.cars) {
            const prev = last.get(c);
            last.set(c, [c.heading, c.x, c.y, tr.trail.headX, tr.trail.headY, tr.reversals]);
            if (prev === undefined) continue;
            const d = axisDelta(prev[0]!, c.heading) * DEG;
            // Per metre of the tram's path (its nose). At the change of ends the nose jumps to the
            // tail; the axis turns only by the last bit of travel before it (≤ speed · dt).
            if (tr.reversals !== prev[5]) {
              changes++;
              expect(d, `tram ${tr.id} car ${c.index} changing ends at step ${i}`).toBeLessThanOrEqual(t.maxTurnDegPerM * t.speedMps * dt);
              continue;
            }
            const nose = Math.hypot(tr.trail.headX - prev[3]!, tr.trail.headY - prev[4]!);
            if (nose < 1e-3) {
              expect(d, `tram ${tr.id} car ${c.index} standing at step ${i}`).toBeLessThan(0.01);
              continue;
            }
            const r = d / nose;
            if (r > worst) {
              worst = r;
              where = `tram ${tr.id} car ${c.index} at (${c.x.toFixed(0)}, ${c.y.toFixed(0)}) on edge ${tr.edge.index}`;
            }
          }
          metres += ds;
        }
      }
      trams.destroy();
    }
    console.log(`L-S10 live: ${metres.toFixed(0)} m driven, ${changes / t.carsPerTram} changes of ends, max ${worst.toFixed(2)}°/m (${where})`);
    expect(metres).toBeGreaterThan(5000);
    expect(changes).toBeGreaterThan(0);
    expect(worst, where).toBeLessThanOrEqual(t.maxTurnDegPerM);
  }, 300000);
});
