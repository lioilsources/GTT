import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { parse } from 'yaml';

import { DriveWorld, LayerTracker } from '../src/drive/driveWorld';
import { TreeContacts } from '../src/drive/nature';
import { RoutePath } from '../src/drive/route';
import type { CarSpec } from '../src/gen/schema';
import { Tuning } from '../src/gen/tuning';
import { chunkPath, type PackSource } from '../src/world/citypack';
import { prepareChunk } from '../src/world/chunk';
import { City, RoadEdge, type EdgeHit } from '../src/world/model';
import { NatureMap, type Tree } from '../src/world/nature';
import { onSurface, structureLayer } from '../src/world/terrain';
import { RoadClass } from '../src/gen/pb/citypack_pb';

// Bridge hotfix (dogfooding: "nebyl jsem schopen přejet ani jeden most"): on the layer-0 half of a
// bridge or ramp edge the car collided with buildings, bollards and trees on the ground under the
// deck, fell into the river under it, and lost the deck surface when it drifted to the railing.
// Pure checks first, then scripted crossings of every Vltava car bridge, Nuselský most and the four
// East River bridges on the real packs (skipped without build/packs).

const root = join(__dirname, '..', '..');
const yaml = parse(readFileSync(join(root, 'content', 'tuning.yaml'), 'utf8'));
const tuning = Tuning.fromJson(yaml);
const CLEAR = tuning.terrain.pipeline.bridgeMinClearM;
const MARGIN = tuning.layers.switchMarginM;

function edge(o: { from?: number; to?: number; bridge?: boolean; tunnel?: boolean; width?: number; z?: number[]; pts?: number[] }): RoadEdge {
  const pts = Float32Array.from(o.pts ?? [0, 0, 100, 0]);
  const z = o.z ? Float32Array.from(o.z) : Float32Array.from({ length: pts.length / 2 }, () => 10);
  return new RoadEdge(0, 0, 1, pts, RoadClass.PRIMARY, '', 2, 0, o.from ?? 0, o.to ?? 0, o.bridge ?? false, o.tunnel ?? false, true, o.width ?? 20, z);
}

describe('structure layer (pure)', () => {
  it('a bridge counts as +1 on its layer-0 half, also level with the terrain', () => {
    const b = edge({ from: 0, to: 1, bridge: true });
    expect(structureLayer(b, 0, 3, MARGIN, 30, 5, 30, CLEAR)).toBe(1);
    // Overture level-0 bridge (Mánesův most): flag only, deck level with the ground.
    const flat = edge({ bridge: true });
    expect(structureLayer(flat, 0, 3, MARGIN, 10, 10, 10, CLEAR)).toBe(1);
  });
  it('the road under the deck and a car beside the corridor stay on 0', () => {
    const b = edge({ from: 0, to: 1, bridge: true });
    expect(structureLayer(b, 0, 3, MARGIN, 30, 5, 5, CLEAR)).toBe(0); // under it
    expect(structureLayer(b, 0, 10 + MARGIN + 0.1, MARGIN, 30, 5, 30, CLEAR)).toBe(0); // beside it
  });
  it('a car flying over the deck lands on it; a ramp without the flag needs clearance', () => {
    const b = edge({ from: 0, to: 1, bridge: true });
    expect(structureLayer(b, 0, 3, MARGIN, 30, 5, 33, CLEAR)).toBe(1);
    const ramp = edge({ from: 0, to: 1 });
    expect(structureLayer(ramp, 0, 3, MARGIN, 10.5, 10, 10.5, CLEAR)).toBe(0); // ramp foot
    expect(structureLayer(ramp, 0, 3, MARGIN, 20, 10, 20, CLEAR)).toBe(1);
  });
  it('a tunnel mouth below the terrain is −1 only for a car down in it', () => {
    const t = edge({ from: 0, to: -1, tunnel: true });
    expect(structureLayer(t, 0, 3, MARGIN, 2, 10, 2, CLEAR)).toBe(-1);
    expect(structureLayer(t, 0, 3, MARGIN, 2, 10, 10, CLEAR)).toBe(0); // on the street above
    expect(onSurface(2, 10, 10, CLEAR)).toBe(false);
    expect(onSurface(30, 5, 40, CLEAR)).toBe(true);
  });
  it('ground edges, other layers and flat packs keep the tracker layer', () => {
    expect(structureLayer(edge({}), 0, 0, MARGIN, 10, 0, 10, CLEAR)).toBe(0);
    expect(structureLayer(edge({ from: 1, to: 1, bridge: true }), 1, 0, MARGIN, 10, 0, 10, CLEAR)).toBe(1);
    const flat = new RoadEdge(0, 0, 1, Float32Array.from([0, 0, 100, 0]), RoadClass.PRIMARY, '', 2, 0, 0, 1, true, false, true, 20, null);
    expect(structureLayer(flat, 0, 0, MARGIN, 0, 0, 0, CLEAR)).toBe(0);
  });
});

describe('soft trees at the car height (pure)', () => {
  it('a trunk under the car but not at its height is skipped', () => {
    const nature = new NatureMap(256);
    const tree: Tree = { x: 5, y: 0, size: 1, jitter: 0, key: '0_0/0' };
    nature.add({ x: 0, y: 0, water: [], green: [], shore: [], trees: [tree], labels: [] });
    const car = { x: 4, y: 0, vx: 20, vy: 0, halfWidth: 1 };
    const t1 = new TreeContacts();
    expect(t1.step(1 / 60, 0, nature, car, tuning, () => false)).toBeNull();
    expect(t1.hits).toBe(0);
    const t2 = new TreeContacts();
    expect(t2.step(1 / 60, 0, nature, car, tuning, () => true)).not.toBeNull();
    expect(t2.hits).toBe(1);
  });
});

describe('layer tracker height test (pure)', () => {
  it('a car on a deck does not switch to the road under it', async () => {
    // Deck A along x at z 30 (bridge, layer 0 → 1); road B at z 5 along y = 12 m, half under the
    // deck, not adjacent. Points in decimetres.
    const { create } = await import('@bufbuild/protobuf');
    const { GraphSchema, NodeSchema, EdgeSchema } = await import('../src/gen/pb/citypack_pb');
    const Node = (o: object) => create(NodeSchema, o), Edge = (o: object) => create(EdgeSchema, o);
    const { RoadGraph } = await import('../src/world/model');
    const g = create(GraphSchema, {
      nodes: [Node({ x: 0, y: 0, zDm: 300 }), Node({ x: 20000, y: 0, zDm: 300 }), Node({ x: 0, y: 120, zDm: 50 }), Node({ x: 20000, y: 120, zDm: 50 })],
      edges: [
        Edge({ from: 0, to: 1, points: [0, 0, 20000, 0], layerFrom: 0, layerTo: 1, bridge: true, kept: true, widthM: 20, zDm: [300, 300] }),
        Edge({ from: 2, to: 3, points: [0, 120, 20000, 120], layerFrom: 0, layerTo: 0, kept: true, widthM: 20, zDm: [50, 50] }),
      ],
    });
    const graph = RoadGraph.fromPb(g);
    const reach = (h: EdgeHit): boolean => Math.abs((h.edge.z?.[0] ?? 0) - 30) <= CLEAR;
    const lt = new LayerTracker(graph, tuning.layers);
    lt.reset(10, 0, (h) => h.edge.index === 0);
    expect(lt.edge?.index).toBe(0);
    // The car 9 m off the deck axis (near its railing), 3 m from the road's axis below.
    lt.update(50, 9, reach);
    expect(lt.edge?.index).toBe(0);
    // A car on the road (its height) next to the deck does switch to the road it is on.
    const ground = (h: EdgeHit): boolean => Math.abs((h.edge.z?.[0] ?? 0) - 5) <= CLEAR;
    lt.update(50, 9, ground);
    expect(lt.edge?.index).toBe(1);
  });
});

// ---- scripted crossings on the real packs ----

const specs = new Map<string, CarSpec>(readdirSync(join(root, 'content', 'cars')).map((f) => {
  const s = JSON.parse(readFileSync(join(root, 'content', 'cars', f), 'utf8')) as CarSpec;
  return [s.id, s];
}));
const packDir = (id: string): string => join(root, 'build', 'packs', id);
const src = (id: string): PackSource => ({ read: async (p) => new Uint8Array(readFileSync(join(packDir(id), p))) });

const LOG = process.env.BRIDGE_LOG;
const trace: string[] = [];
const dump = (name: string): void => {
  if (LOG) writeFileSync(join(LOG, name.replace(/\W+/g, '_') + '.log'), trace.join('\n'));
  trace.length = 0;
};

const isStructure = (e: RoadEdge): boolean => e.bridge || e.tunnel || e.layerFrom !== 0 || e.layerTo !== 0;

interface Bridge {
  label: string;
  /** Edges of the bridge (one carriageway is chosen from them). */
  pick: (e: RoadEdge) => boolean;
}

/** Overture names: Manhattan Bridge's roadways carry the street names "Canal Street" / "Chrystie Street". */
export const BRIDGES: Record<string, Bridge[]> = {
  prague: ['Mánesův most', 'Čechův most', 'most Legií', 'Jiráskův most', 'Palackého most', 'Hlávkův most', 'Štefánikův most', 'Libeňský most', 'Nuselský most']
    .map((n) => ({ label: n, pick: (e: RoadEdge) => e.name === n })),
  nyc: [
    { label: 'Brooklyn Bridge', pick: (e) => e.name === 'Brooklyn Bridge' },
    { label: 'Manhattan Bridge (Canal Street)', pick: (e) => e.name === 'Canal Street' && isStructure(e) && e.length > 1000 },
    { label: 'Williamsburg Bridge', pick: (e) => e.name === 'Williamsburg Bridge' },
    { label: 'Queensboro Bridge upper', pick: (e) => e.name === 'Ed Koch Queensboro Bridge Upper Level' },
    { label: 'Queensboro Bridge lower', pick: (e) => e.name === 'Ed Koch Queensboro Bridge Lower Level' },
  ],
};

interface Route {
  pts: number[];
  cum: number[];
  /** Distance range of the bridge chain along the route. */
  s0: number;
  s1: number;
  chain: Set<number>;
  startsOnGround: boolean;
}

export function buildRoute(city: City, b: Bridge): Route {
  const g = city.graph;
  const set = g.edges.filter((e) => b.pick(e) && !e.tunnel);
  expect(set.length, `${b.label}: edges in the pack`).toBeGreaterThan(0);
  const nx = (n: number): number => g.nodeXY[2 * n]!, ny = (n: number): number => g.nodeXY[2 * n + 1]!;
  const adj = new Map<number, { e: RoadEdge; o: number }[]>();
  const link = (n: number, e: RoadEdge, o: number): void => {
    const l = adj.get(n);
    if (l) l.push({ e, o });
    else adj.set(n, [{ e, o }]);
  };
  for (const e of set) {
    link(e.from, e, e.to);
    link(e.to, e, e.from);
  }
  // The two chain ends farthest apart that are connected: one carriageway across.
  const ends = [...adj.keys()].filter((n) => adj.get(n)!.length === 1);
  const cand = ends.length >= 2 ? ends : [...adj.keys()];
  let best: { a: number; b: number; prev: Map<number, { e: RoadEdge; p: number } | null> } | null = null, bd = -1;
  for (const a of cand) {
    const prev = new Map<number, { e: RoadEdge; p: number } | null>([[a, null]]);
    const q = [a];
    while (q.length) {
      const n = q.shift()!;
      for (const { e, o } of adj.get(n)!) if (!prev.has(o)) { prev.set(o, { e, p: n }); q.push(o); }
    }
    for (const z of cand) {
      const d = Math.hypot(nx(a) - nx(z), ny(a) - ny(z));
      if (z !== a && prev.has(z) && d > bd) { bd = d; best = { a, b: z, prev }; }
    }
  }
  expect(best, `${b.label}: a chain`).not.toBeNull();
  const chain: { e: RoadEdge; from: number }[] = [];
  for (let n = best!.b; best!.prev.get(n); n = best!.prev.get(n)!.p) chain.unshift({ e: best!.prev.get(n)!.e, from: best!.prev.get(n)!.p });
  const used = new Set(chain.map((c) => c.e.index));
  // Approaches: the straightest continuation until 100 m past the last structure edge.
  const extend = (node: number, dx0: number, dy0: number): { e: RoadEdge; from: number }[] => {
    const out: { e: RoadEdge; from: number }[] = [];
    let len = 0, cur = node, dx = dx0, dy = dy0, ground = false;
    while ((len < 100 || !ground) && len < 800) {
      let pick: RoadEdge | null = null, pd = -2;
      for (const ei of g.nodeEdges[cur]!) {
        const e = g.edges[ei]!;
        if (used.has(e.index) || e.tunnel || e.stairs) continue;
        const o = e.from === cur ? e.to : e.from;
        const l = Math.hypot(nx(o) - nx(cur), ny(o) - ny(cur)) || 1;
        const d = ((nx(o) - nx(cur)) * dx + (ny(o) - ny(cur)) * dy) / l - (e.kept ? 0 : 0.5);
        if (d > pd) { pd = d; pick = e; }
      }
      if (!pick || pd < 0.3) break;
      used.add(pick.index);
      const o = pick.from === cur ? pick.to : pick.from;
      out.push({ e: pick, from: cur });
      len += pick.length;
      const l = Math.hypot(nx(o) - nx(cur), ny(o) - ny(cur)) || 1;
      dx = (nx(o) - nx(cur)) / l;
      dy = (ny(o) - ny(cur)) / l;
      ground = !isStructure(pick);
      cur = o;
    }
    return out;
  };
  const first = chain[0]!, last = chain[chain.length - 1]!;
  const a = first.from, a1 = first.e.from === a ? first.e.to : first.e.from;
  const z1 = last.e.from === last.from ? last.e.to : last.e.from, z0 = last.from;
  const pre = extend(a, nx(a) - nx(a1), ny(a) - ny(a1)).map((c) => ({ e: c.e, from: c.e.from === c.from ? c.e.to : c.e.from })).reverse();
  const post = extend(z1, nx(z1) - nx(z0), ny(z1) - ny(z0));
  const pts: number[] = [];
  let s0 = 0, s1 = 0;
  const cumOf = (p: number[]): number[] => {
    const c = [0];
    for (let i = 2; i < p.length; i += 2) c.push(c[c.length - 1]! + Math.hypot(p[i]! - p[i - 2]!, p[i + 1]! - p[i - 1]!));
    return c;
  };
  for (const [k, c] of [...pre, ...chain, ...post].entries()) {
    if (k === pre.length) s0 = cumOf(pts).pop() ?? 0;
    const n = c.e.pointCount;
    for (let i = pts.length ? 1 : 0; i < n; i++) {
      const j = c.from === c.e.from ? i : n - 1 - i;
      pts.push(c.e.pts[2 * j]!, c.e.pts[2 * j + 1]!);
    }
    if (k === pre.length + chain.length - 1) s1 = cumOf(pts).pop() ?? 0;
  }
  const startEdge = (pre[0] ?? chain[0])!.e;
  return { pts, cum: cumOf(pts), s0, s1, chain: used.size > 0 ? new Set(chain.map((c) => c.e.index)) : new Set(), startsOnGround: !isStructure(startEdge) };
}

function reversed(r: Route): Route {
  const pts: number[] = [];
  for (let i = r.pts.length - 2; i >= 0; i -= 2) pts.push(r.pts[i]!, r.pts[i + 1]!);
  const L = r.cum[r.cum.length - 1]!;
  const cum = r.cum.map((c) => L - c).reverse();
  return { pts, cum, s0: L - r.s1, s1: L - r.s0, chain: r.chain, startsOnGround: false };
}

function at(r: Route, s: number, off: number): { x: number; y: number; dir: number } {
  const c = r.cum, p = r.pts;
  s = Math.min(Math.max(s, 0), c[c.length - 1]!);
  let i = 0;
  while (i < c.length - 2 && c[i + 1]! < s) i++;
  const ax = p[2 * i]!, ay = p[2 * i + 1]!, bx = p[2 * i + 2]!, by = p[2 * i + 3]!;
  const l = c[i + 1]! - c[i]! || 1, t = (s - c[i]!) / l;
  const dx = (bx - ax) / l, dy = (by - ay) / l;
  return { x: ax + (bx - ax) * t + dy * off, y: ay + (by - ay) * t - dx * off, dir: Math.atan2(by - ay, bx - ax) };
}

function project(r: Route, x: number, y: number, s0: number, s1: number): number {
  let best = Infinity, bs = s0;
  for (let i = 0; i + 1 < r.cum.length; i++) {
    if (r.cum[i + 1]! < s0 || r.cum[i]! > s1) continue;
    const ax = r.pts[2 * i]!, ay = r.pts[2 * i + 1]!, bx = r.pts[2 * i + 2]!, by = r.pts[2 * i + 3]!;
    const dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy;
    const t = l2 === 0 ? 0 : Math.min(1, Math.max(0, ((x - ax) * dx + (y - ay) * dy) / l2));
    const d = Math.hypot(ax + dx * t - x, ay + dy * t - y);
    if (d < best) { best = d; bs = r.cum[i]! + Math.sqrt(l2) * t; }
  }
  return bs;
}

export interface CrossResult {
  finished: boolean;
  falls: number;
  treeHits: number;
  rescues: number;
  /** Steps on a structure edge of the chain, within its corridor, riding the terrain instead. */
  deckLost: number;
  /** Largest gap under the car on the chain (m): a fall off the deck shows here. */
  maxGap: number;
  maxSpeed: number;
}

async function world(city: City, speed: number): Promise<DriveWorld> {
  const y = structuredClone(yaml);
  y.speed_mps.cruise = speed;
  y.speed_mps.top_default = Math.max(y.speed_mps.top_default, speed);
  const t = Tuning.fromJson(y);
  t.traffic.enabled = false;
  t.trams.enabled = false;
  return new DriveWorld(city, specs.get('sedan_regent')!, t);
}

async function loadAround(drive: DriveWorld, city: City, r: Route): Promise<void> {
  const cm = city.chunkM, s = src(city.id);
  let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
  for (let i = 0; i < r.pts.length; i += 2) {
    x0 = Math.min(x0, r.pts[i]!); x1 = Math.max(x1, r.pts[i]!);
    y0 = Math.min(y0, r.pts[i + 1]!); y1 = Math.max(y1, r.pts[i + 1]!);
  }
  for (const ch of city.manifest.chunks) {
    if ((ch.x + 1) * cm < x0 - 200 || ch.x * cm > x1 + 200 || (ch.y + 1) * cm < y0 - 200 || ch.y * cm > y1 + 200) continue;
    drive.addChunk(await prepareChunk(await s.read(chunkPath(ch.x, ch.y)), { chunkM: cm, version: city.manifest.natureVersion }));
  }
}

/**
 * Drives route r with the car where it is (a lane `off` metres right of the axis; `railOff` on the
 * bridge chain), steering like the bench autopilot at constant cruise `speed`.
 */
function drive(d: DriveWorld, r: Route, speed: number, off: number, railOff: number | null): CrossResult {
  const b = d.tuning.bench, L = r.cum[r.cum.length - 1]!;
  const path = new RoutePath(Float64Array.from(r.pts), 1);
  let s = project(r, d.car.x, d.car.y, 0, L), rescues = 0, falls = 0, treeHits = 0;
  // Counted from 60 m before the bridge chain to 60 m after it (street trees on the approaches
  // are not the bridge's business).
  const inWindow = (): boolean => s > r.s0 - 60 && s < r.s1 + 60;
  d.onRescue = () => { if (inWindow()) rescues++; };
  // On the chain: along the railing, and for 60 m in the middle 3 m through it (the rail holds).
  const mid = (r.s0 + r.s1) / 2;
  const offAt = (q: number): number => {
    if (railOff === null || q < r.s0 + 20 || q > r.s1 - 20) return off;
    return q > mid && q < mid + 60 ? railOff + 3 : railOff;
  };
  d.beforeStep = () => {
    const car = d.car;
    s = project(r, car.x, car.y, s - 30, s + 60);
    const q = s + b.lookaheadM + b.lookaheadPerMps * car.speed;
    const tg = at(r, q, offAt(q));
    let e = Math.atan2(tg.y - car.y, tg.x - car.x) - car.heading;
    while (e > Math.PI) e -= 2 * Math.PI;
    while (e < -Math.PI) e += 2 * Math.PI;
    d.input.reset();
    d.input.steer = Math.min(1, Math.max(-1, -b.steerGain * e));
    d.input.boost = speed > d.tuning.speedMps.topDefault - 1;
    // Slow for turns of the approach roads like the bench autopilot (more look-ahead when fast).
    if (path.maxTurn(s, s + b.cornerLookaheadM + 1.5 * car.speed) > b.cornerTurnRad) {
      const want = Math.max(b.cornerSpeedMps, 15);
      d.input.brake = Math.min(1, Math.max(0, (car.speed - want) * b.brakePerMps));
      d.input.boost = false;
    }
  };
  let t = 0, deckLost = 0, maxGap = 0, maxSpeed = 0;
  const limit = L / (speed * 0.5) + 10;
  while (t < limit && s < L - 15) {
    const f0 = d.water.falls, h0 = d.trees.hits;
    d.update(1 / 60);
    if (inWindow()) {
      falls += d.water.falls - f0;
      treeHits += d.trees.hits - h0;
    }
    t += 1 / 60;
    const h = d.layers.hit;
    if (LOG) {
      const c = d.car, j = d.jump;
      let cats = '';
      for (let ce = c.body.getContactList(); ce; ce = ce.next) if (ce.contact.isTouching()) cats += 'c' + (ce.contact.getFixtureA().getBody() === c.body ? ce.contact.getFixtureB() : ce.contact.getFixtureA()).getFilterCategoryBits();
      trace.push([t.toFixed(3), s.toFixed(1), c.x.toFixed(1), c.y.toFixed(1), c.speed.toFixed(1), c.layer, h ? `${h.edge.index}:${h.edge.layerFrom}${h.edge.layerTo}${h.edge.bridge ? 'b' : ''}:${h.dist.toFixed(1)}/${(h.edge.width / 2).toFixed(0)}` : '-', d.rideEdge?.index ?? 'T', j.z.toFixed(2), (j.z - j.gap).toFixed(2), d.terrain.terrainAt(c.x, c.y)?.toFixed(2), j.airborne ? 'AIR' : '-', d.trees.hits, d.water.falls, rescues, cats].join(' '));
    }
    if (h !== null && r.chain.has(h.edge.index)) {
      maxGap = Math.max(maxGap, d.jump.gap);
      maxSpeed = Math.max(maxSpeed, d.car.speed);
      if (isStructure(h.edge) && h.dist <= h.edge.width / 2 && d.rideEdge === null) deckLost++;
    }
  }
  d.beforeStep = null;
  d.onRescue = null;
  return { finished: s >= L - 15, falls, treeHits, rescues, deckLost, maxGap, maxSpeed };
}

/** Start 100 m before the chain when that point is on a ground road, else at the route start. */
function startAt(city: City, r: Route, off: number): { x: number; y: number; dir: number } {
  const p = at(r, Math.max(0, r.s0 - 100), off);
  const h = city.graph.nearest(p.x, p.y, 15);
  return h !== null && !isStructure(h.edge) ? p : at(r, 0, off);
}

/**
 * One crossing in direction `rev`: from the ground approach. A bridge whose end is the edge of the
 * pack (a roadblock on the deck) is driven back after a U-turn there, as a player would.
 */
export async function cross(city: City, b: Bridge, speed: number, rev: boolean, off = 2, railOff: number | null = null): Promise<CrossResult> {
  const fwd = buildRoute(city, b), back = reversed(fwd);
  back.startsOnGround = (() => {
    const p = at(back, 0, 0);
    const h = city.graph.nearest(p.x, p.y, 15);
    return h !== null && !isStructure(h.edge);
  })();
  const r = rev ? back : fwd, other = rev ? fwd : back;
  const d = await world(city, speed);
  await loadAround(d, city, fwd);
  if (!r.startsOnGround) {
    // Up the other way first, then a U-turn at the end of the deck.
    const p = startAt(city, other, off);
    d.spawn(p.x, p.y, p.dir);
    const first = drive(d, other, speed, off, null);
    expect(first.finished, `${b.label}: way up for the U-turn`).toBe(true);
    const body = d.car.body;
    body.setLinearVelocity({ x: 0, y: 0 });
    body.setTransform(body.getPosition(), body.getAngle() + Math.PI);
  } else {
    const p = startAt(city, r, off);
    d.spawn(p.x, p.y, p.dir);
    const v0 = Math.min(speed, 15);
    d.car.body.setLinearVelocity({ x: Math.cos(p.dir) * v0, y: Math.sin(p.dir) * v0 });
  }
  return drive(d, r, speed, off, railOff);
}

const cities = Object.keys(BRIDGES).filter((id) => existsSync(join(packDir(id), 'manifest.pb')));
const loaded = new Map<string, Promise<City>>();
const cityOf = (id: string): Promise<City> => {
  let c = loaded.get(id);
  if (!c) loaded.set(id, (c = City.load(src(id))));
  return c;
};

/** 25 m/s (cruise) by default; BRIDGE_SPEEDS=15,25,40 runs the soak at other speeds too. */
const SPEEDS = (process.env.BRIDGE_SPEEDS ?? '25').split(',').map(Number);

describe.skipIf(cities.length === 0)('bridge crossings on the real packs (both directions)', () => {
  for (const id of cities) {
    for (const b of BRIDGES[id]!) {
      for (const speed of SPEEDS) for (const rev of [false, true]) {
        it(`${id}: ${b.label} ${rev ? 'back' : 'there'} at ${speed} m/s`, async () => {
          const city = await cityOf(id);
          if (!city.terrain.enabled) return;
          const r = await cross(city, b, speed, rev);
          dump(`${id} ${b.label} ${rev ? 'back' : 'there'} ${speed}`);
          expect(r, `${b.label} ${JSON.stringify(r)}`).toMatchObject({ finished: true, falls: 0, treeHits: 0, rescues: 0, deckLost: 0 });
          expect(r.maxGap, `${b.label}: gap under the car on the bridge`).toBeLessThan(CLEAR);
        }, 120000);
      }
    }
  }
});

describe.skipIf(cities.length === 0)('bridge railings keep the car on the deck', () => {
  for (const id of cities) {
    for (const b of BRIDGES[id]!) {
      it(`${id}: ${b.label} along the railing`, async () => {
        const city = await cityOf(id);
        if (!city.terrain.enabled) return;
        // Hug the railing of the narrowest structure edge of the chain (body edge at the rail).
        const route = buildRoute(city, b);
        let w = Infinity;
        for (const ei of route.chain) { const e = city.graph.edges[ei]!; if (isStructure(e)) w = Math.min(w, e.width); }
        const r = await cross(city, b, 25, false, 2, w / 2 - 1.2);
        dump(`${id} ${b.label} rail`);
        expect(r, `${b.label} ${JSON.stringify(r)}`).toMatchObject({ finished: true, falls: 0, treeHits: 0, deckLost: 0 });
        expect(r.maxGap).toBeLessThan(CLEAR);
      }, 120000);
    }
  }
});
