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
import { prepareChunk, type ChunkData } from '../src/world/chunk';
import { City, RoadEdge, type EdgeHit } from '../src/world/model';
import { NatureMap, type Tree } from '../src/world/nature';
import { flatStructureLayer, onSurface, structureLayer } from '../src/world/terrain';
import { RoadClass, WaterClass } from '../src/gen/pb/citypack_pb';

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
  it('a bridge counts as +1 on its layer-0 half where it stands over the ground', () => {
    const b = edge({ from: 0, to: 1, bridge: true });
    expect(structureLayer(b, 0, 3, MARGIN, 30, 5, 30, CLEAR)).toBe(1);
    // Overture level-0 bridge (Mánesův most): flag only; over the river +1, at its bank junction 0.
    const lvl0 = edge({ bridge: true });
    expect(structureLayer(lvl0, 0, 3, MARGIN, 10, -5, 10, CLEAR)).toBe(1);
    expect(structureLayer(lvl0, 0, 3, MARGIN, 10, 10, 10, CLEAR)).toBe(0);
  });
  it('flat packs: a ramp half reached from the ramp is on its layer, never from below', () => {
    const ramp = edge({ from: 0, to: 1, bridge: true, z: undefined });
    expect(flatStructureLayer(ramp, 0, 3, MARGIN, true)).toBe(1);
    expect(flatStructureLayer(ramp, 0, 3, MARGIN, false)).toBe(0);
    expect(flatStructureLayer(edge({ bridge: true }), 0, 3, MARGIN, true)).toBe(0);
    expect(flatStructureLayer(edge({ from: 0, to: -1, tunnel: true }), 0, 3, MARGIN, true)).toBe(-1);
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
  /** Rescues while on the bridge chain (a car held on the deck). */
  deckRescues: number;
  /** The car got past the far end of the chain. */
  crossed: boolean;
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

const chunkCache = new Map<string, ChunkData>();

async function loadAround(drive: DriveWorld, city: City, r: { pts: number[] }, pad = 200): Promise<void> {
  const cm = city.chunkM, s = src(city.id);
  let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
  for (let i = 0; i < r.pts.length; i += 2) {
    x0 = Math.min(x0, r.pts[i]!); x1 = Math.max(x1, r.pts[i]!);
    y0 = Math.min(y0, r.pts[i + 1]!); y1 = Math.max(y1, r.pts[i + 1]!);
  }
  for (const ch of city.manifest.chunks) {
    if ((ch.x + 1) * cm < x0 - pad || ch.x * cm > x1 + pad || (ch.y + 1) * cm < y0 - pad || ch.y * cm > y1 + pad) continue;
    const k = `${city.id}/${ch.x}_${ch.y}`;
    let c = chunkCache.get(k);
    if (!c) chunkCache.set(k, (c = await prepareChunk(await s.read(chunkPath(ch.x, ch.y)), { chunkM: cm, version: city.manifest.natureVersion })));
    drive.addChunk(c);
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
  let deckRescues = 0, crossed = false;
  d.onRescue = () => {
    if (inWindow()) rescues++;
    const h = d.layers.hit;
    if (h !== null && r.chain.has(h.edge.index)) deckRescues++;
  };
  // On the chain: along the railing, and for 25 m in the middle 2 m through it (the rail holds).
  const mid = (r.s0 + r.s1) / 2;
  const offAt = (q: number): number => {
    // The railing is there where the deck is (the car on a structure layer), not at the ramp foot.
    if (railOff === null || q < r.s0 + 20 || q > r.s1 - 20 || d.car.layer === 0) return off;
    return q > mid && q < mid + 25 ? railOff + 2 : railOff;
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
    const turn = path.maxTurn(s, s + b.cornerLookaheadM + 1.5 * car.speed);
    if (turn > b.cornerTurnRad) {
      const want = turn > 1.2 ? b.cornerSpeedMps : Math.max(b.cornerSpeedMps, 15);
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
    if (s >= r.s1) crossed = true;
    if (h !== null && r.chain.has(h.edge.index)) {
      maxGap = Math.max(maxGap, d.jump.gap);
      maxSpeed = Math.max(maxSpeed, d.car.speed);
      // On the deck: its surface (terrain packs) or its layer (flat packs, Tokyo).
      const off = d.terrain.enabled && h.edge.z !== null ? d.rideEdge === null : d.car.layer === 0 && h.edge.drawLayer !== 0;
      if (isStructure(h.edge) && h.dist <= h.edge.width / 2 - 1 && off) deckLost++;
    }
  }
  d.beforeStep = null;
  d.onRescue = null;
  return { finished: s >= L - 15, falls, treeHits, rescues, deckRescues, crossed, deckLost, maxGap, maxSpeed };
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
        const r = await cross(city, b, 25, false, 2, w / 2 - 2);
        dump(`${id} ${b.label} rail`);
        expect(r, `${b.label} ${JSON.stringify(r)}`).toMatchObject({ falls: 0, treeHits: 0, deckLost: 0 });
        expect(r.maxGap).toBeLessThan(CLEAR);
      }, 120000);
    }
  }
});

// ---- L-S11 (Prompts/05-METROPOLE_LAUNCH_PLAN.md D): every bridge of every pack ----
// Bank to bank over every bridge keeps the car on the deck; onto a deck only from its ramp (a
// road under it passes through on layer 0); driving off the bank into water is a fall and a tow.

const ALL = ['prague', 'nyc', 'tokyo'].filter((id) => existsSync(join(packDir(id), 'manifest.pb')));
const isGroundRoad = (e: RoadEdge): boolean => e.isGround && !e.bridge && !e.stairs;

/** A shared world per city (chunks stay loaded); each run spawns the car anew. */
const worlds = new Map<string, Promise<DriveWorld>>();
const worldOf = (city: City): Promise<DriveWorld> => {
  let w = worlds.get(city.id);
  if (!w) worlds.set(city.id, (w = world(city, 25)));
  return w;
};

/** Polyline of edges walked from node to node, as a Route; the chain = the structure edges. */
function routeOf(steps: { e: RoadEdge; from: number }[]): Route {
  const pts: number[] = [];
  let s0 = -1, s1 = 0;
  const len = (): number => {
    let l = 0;
    for (let i = 2; i < pts.length; i += 2) l += Math.hypot(pts[i]! - pts[i - 2]!, pts[i + 1]! - pts[i - 1]!);
    return l;
  };
  for (const { e, from } of steps) {
    if (s0 < 0 && isStructure(e)) s0 = len();
    const n = e.pointCount;
    for (let i = pts.length ? 1 : 0; i < n; i++) {
      const j = from === e.from ? i : n - 1 - i;
      pts.push(e.pts[2 * j]!, e.pts[2 * j + 1]!);
    }
    if (isStructure(e)) s1 = len();
  }
  const cum = [0];
  for (let i = 2; i < pts.length; i += 2) cum.push(cum[cum.length - 1]! + Math.hypot(pts[i]! - pts[i - 2]!, pts[i + 1]! - pts[i - 1]!));
  return { pts, cum, s0: Math.max(0, s0), s1, chain: new Set(steps.filter((x) => isStructure(x.e)).map((x) => x.e.index)), startsOnGround: true };
}

/** The straightest ground road leaving `node` away from direction (dx, dy), one edge. */
function groundStep(city: City, node: number, dx: number, dy: number, not: number): { e: RoadEdge; from: number } | null {
  const g = city.graph;
  let pick: RoadEdge | null = null, pd = -2;
  for (const ei of g.nodeEdges[node]!) {
    const e = g.edges[ei]!;
    if (ei === not || !isGroundRoad(e) || e.length < 15) continue;
    const o = e.from === node ? e.to : e.from;
    const ox = g.nodeXY[2 * o]! - g.nodeXY[2 * node]!, oy = g.nodeXY[2 * o + 1]! - g.nodeXY[2 * node + 1]!;
    const d = (ox * dx + oy * dy) / (Math.hypot(ox, oy) || 1) - (e.kept ? 0 : 0.5);
    if (d > pd) { pd = d; pick = e; }
  }
  return pick ? { e: pick, from: pick.from === node ? pick.to : pick.from } : null;
}

interface Crossing {
  label: string;
  steps: { e: RoadEdge; from: number }[];
}

/**
 * Every bridge of the pack: connected structure edges (bridge flag or a layer change, no tunnels)
 * that contain a bridge; from the two ramp feet farthest apart (nodes with a ground road), the
 * shortest path between them plus a ground road on each side. Bridges with fewer than two feet
 * in the pack (a deck cut by the pack border, a ramp-only spur) are counted apart.
 */
function bridgeCrossings(city: City): { list: Crossing[]; oneFoot: number } {
  const g = city.graph;
  const structure = (e: RoadEdge): boolean => isStructure(e) && !e.tunnel && !e.stairs;
  const seen = new Set<number>();
  const list: Crossing[] = [];
  let oneFoot = 0;
  for (const start of g.edges) {
    if (!start.bridge || start.tunnel || seen.has(start.index)) continue;
    const comp: RoadEdge[] = [];
    const q = [start];
    seen.add(start.index);
    while (q.length) {
      const e = q.pop()!;
      comp.push(e);
      for (const n of [e.from, e.to]) for (const ei of g.nodeEdges[n]!) {
        const f = g.edges[ei]!;
        if (!seen.has(ei) && structure(f)) { seen.add(ei); q.push(f); }
      }
    }
    const nodes = new Set(comp.flatMap((e) => [e.from, e.to]));
    const feet = [...nodes].filter((n) => !g.border[n] && g.nodeEdges[n]!.some((ei) => isGroundRoad(g.edges[ei]!) && g.edges[ei]!.length >= 15));
    if (feet.length < 2) { oneFoot++; continue; }
    const inComp = new Set(comp.map((e) => e.index));
    // Dijkstra inside the component from each foot; the farthest pair (straight line) that connects.
    let best: { a: number; b: number; prev: Map<number, { e: RoadEdge; p: number }> } | null = null, bd = -1;
    for (const a of feet) {
      const dist = new Map<number, number>([[a, 0]]), prev = new Map<number, { e: RoadEdge; p: number }>();
      const open = [a];
      while (open.length) {
        open.sort((x, y) => dist.get(y)! - dist.get(x)!);
        const n = open.pop()!;
        for (const ei of g.nodeEdges[n]!) {
          if (!inComp.has(ei)) continue;
          const e = g.edges[ei]!, o = e.from === n ? e.to : e.from, d = dist.get(n)! + e.length;
          if (d < (dist.get(o) ?? Infinity)) { dist.set(o, d); prev.set(o, { e, p: n }); open.push(o); }
        }
      }
      for (const b of feet) {
        const d = Math.hypot(g.nodeXY[2 * a]! - g.nodeXY[2 * b]!, g.nodeXY[2 * a + 1]! - g.nodeXY[2 * b + 1]!);
        if (b !== a && dist.has(b) && d > bd) { bd = d; best = { a, b, prev }; }
      }
    }
    if (!best) { oneFoot++; continue; }
    const chain: { e: RoadEdge; from: number }[] = [];
    for (let n = best.b; n !== best.a; n = best.prev.get(n)!.p) chain.unshift({ e: best.prev.get(n)!.e, from: best.prev.get(n)!.p });
    if (!chain.some((c) => c.e.bridge)) { oneFoot++; continue; }
    const nx = (n: number): number => g.nodeXY[2 * n]!, ny = (n: number): number => g.nodeXY[2 * n + 1]!;
    const c0 = chain[0]!, cl = chain[chain.length - 1]!;
    const a1 = c0.e.from === c0.from ? c0.e.to : c0.e.from, bEnd = cl.e.from === cl.from ? cl.e.to : cl.e.from;
    const pre = groundStep(city, best.a, nx(best.a) - nx(a1), ny(best.a) - ny(a1), c0.e.index);
    const post = groundStep(city, bEnd, nx(bEnd) - nx(cl.from), ny(bEnd) - ny(cl.from), cl.e.index);
    if (!pre || !post) { oneFoot++; continue; }
    // pre runs away from the foot: drive it towards the foot.
    const steps = [{ e: pre.e, from: pre.from }, ...chain, { e: post.e, from: bEnd }];
    const name = chain.find((c) => c.e.name)?.e.name ?? '';
    list.push({ label: `${name || 'bridge'} #${start.index}`, steps });
  }
  return { list, oneFoot };
}

function reverseSteps(steps: { e: RoadEdge; from: number }[]): { e: RoadEdge; from: number }[] {
  return steps.map(({ e, from }) => ({ e, from: e.from === from ? e.to : e.from })).reverse();
}

/** Drives a route from its start (the car spawned on the ground road there). */
async function runRoute(city: City, r: Route): Promise<CrossResult> {
  const d = await worldOf(city);
  await loadAround(d, city, r, 120);
  const p = at(r, Math.max(0, r.s0 - 25), 0);
  d.spawn(p.x, p.y, p.dir);
  d.car.body.setLinearVelocity({ x: Math.cos(p.dir) * 12, y: Math.sin(p.dir) * 12 });
  return drive(d, r, 25, 0, null);
}

describe.skipIf(ALL.length === 0)('L-S11: bank to bank over every bridge of every pack', () => {
  for (const id of ALL) {
    it(`${id}: every bridge, both ways, on the deck`, async () => {
      const city = await cityOf(id);
      const { list, oneFoot } = bridgeCrossings(city);
      expect(list.length, `${id}: bridges with two ramps`).toBeGreaterThan(0);
      // Hard: never off the deck (no fall, no ride on the terrain under it, no drop). Soft: the
      // scripted driver gets across without a rescue (it cannot take every helix and junction).
      const bad: string[] = [], stuck: string[] = [];
      for (const c of list) {
        for (const rev of [false, true]) {
          const r = await runRoute(city, routeOf(rev ? reverseSteps(c.steps) : c.steps));
          dump(`all ${id} ${c.label} ${rev ? 'back' : 'there'}`);
          const line = `${c.label} ${rev ? 'back' : 'there'} ${JSON.stringify(r)}`;
          if (r.falls || r.deckLost || r.maxGap >= CLEAR) bad.push(line);
          else if (!r.crossed || r.deckRescues) stuck.push(line);
        }
      }
      if (LOG) writeFileSync(join(LOG, `all_${id}.txt`), `${list.length} bridges, ${oneFoot} with < 2 ramps in the pack\nOFF THE DECK\n${bad.join('\n')}\nNOT ACROSS\n${stuck.join('\n')}`);
      expect(bad, `${id}: ${list.length} bridges × 2`).toEqual([]);
      expect(stuck.length, `${id}: not across: ${stuck.join('; ')}`).toBeLessThanOrEqual(Math.floor(list.length * 2 * 0.1));
    }, 900000);
  }
});

/** Ground roads that pass under a bridge deck (2D crossing, not a shared node), at most `max`. */
function underpasses(city: City, max: number): { e: RoadEdge; deck: RoadEdge; x: number; y: number }[] {
  const g = city.graph, t = city.terrain;
  const out: { e: RoadEdge; deck: RoadEdge; x: number; y: number }[] = [];
  for (const e of g.edges) {
    if (!isGroundRoad(e) || !e.kept || e.length < 40) continue;
    for (let s = 0; s + 1 < e.pointCount && out.length < max * 20; s++) {
      const ax = e.pts[2 * s]!, ay = e.pts[2 * s + 1]!, bx = e.pts[2 * s + 2]!, by = e.pts[2 * s + 3]!;
      const mx = (ax + bx) / 2, my = (ay + by) / 2;
      for (const h of g.near(mx, my, Math.hypot(bx - ax, by - ay) / 2 + 1)) {
        const d = h.edge;
        if (!d.bridge || d.from === e.from || d.from === e.to || d.to === e.from || d.to === e.to) continue;
        // Segment intersection of e's segment with d's nearest segment.
        const cx = d.pts[2 * h.segment]!, cy = d.pts[2 * h.segment + 1]!, ex = d.pts[2 * h.segment + 2]!, ey = d.pts[2 * h.segment + 3]!;
        const den = (bx - ax) * (ey - cy) - (by - ay) * (ex - cx);
        if (Math.abs(den) < 1e-6) continue;
        const u = ((cx - ax) * (ey - cy) - (cy - ay) * (ex - cx)) / den, v = ((cx - ax) * (by - ay) - (cy - ay) * (bx - ax)) / den;
        if (u < 0 || u > 1 || v < 0.05 || v > 0.95) continue;
        const x = ax + (bx - ax) * u, y = ay + (by - ay) * u;
        const along = e.cum[s]! + Math.hypot(x - ax, y - ay);
        if (along < 20 || along > e.length - 20) continue;
        // Really above: deck ≥ 4 m over the road (terrain packs) or its layer-1 half (flat packs).
        const tz = t.enabled && d.z !== null && e.z !== null ? t.edgeZ(d, x, y) - t.edgeZ(e, x, y) : null;
        if (tz !== null ? tz < CLEAR + 2 : d.layerAt(h.t) < 1) continue;
        out.push({ e, deck: d, x, y });
        break;
      }
    }
  }
  // Spread over the city, deterministic.
  const step = Math.max(1, Math.floor(out.length / max));
  return out.filter((_, i) => i % step === 0).slice(0, max);
}

describe.skipIf(ALL.length === 0)('L-S11: onto a deck only from its ramp; under it along the road', () => {
  for (const id of ALL) {
    it(`${id}: roads under bridges pass through on layer 0`, async () => {
      const city = await cityOf(id);
      const list = underpasses(city, 40);
      expect(list.length, `${id}: underpasses`).toBeGreaterThan(0);
      const bad: string[] = [];
      for (const u of list) {
        // The road edge itself with a ground road beyond each end.
        const g = city.graph, e = u.e;
        const dir = (n: number, o: number): [number, number] => [g.nodeXY[2 * n]! - g.nodeXY[2 * o]!, g.nodeXY[2 * n + 1]! - g.nodeXY[2 * o + 1]!];
        const pre = groundStep(city, e.from, ...dir(e.from, e.to), e.index);
        const post = groundStep(city, e.to, ...dir(e.to, e.from), e.index);
        const steps = [...(pre ? [{ e: pre.e, from: pre.from }] : []), { e, from: e.from }, ...(post ? [{ e: post.e, from: e.to }] : [])];
        const r = routeOf(steps);
        const d = await worldOf(city);
        await loadAround(d, city, r, 120);
        const p = at(r, 0, 0);
        d.spawn(p.x, p.y, p.dir);
        let under = 0, onDeck = 0, minSpeed = Infinity, minDist = Infinity;
        const L = r.cum[r.cum.length - 1]!;
        const b = d.tuning.bench;
        let s = 0, t = 0, rescues = 0;
        d.onRescue = () => rescues++;
        d.beforeStep = () => {
          const c = d.car;
          s = project(r, c.x, c.y, s - 30, s + 60);
          const tg = at(r, s + b.lookaheadM + b.lookaheadPerMps * c.speed, 0);
          let a = Math.atan2(tg.y - c.y, tg.x - c.x) - c.heading;
          while (a > Math.PI) a -= 2 * Math.PI;
          while (a < -Math.PI) a += 2 * Math.PI;
          d.input.reset();
          d.input.steer = Math.min(1, Math.max(-1, -b.steerGain * a));
        };
        while (t < L / 10 + 10 && s < L - 15) {
          d.update(1 / 60);
          t += 1 / 60;
          const c = d.car;
          minDist = Math.min(minDist, Math.hypot(c.x - u.x, c.y - u.y));
          if (Math.hypot(c.x - u.x, c.y - u.y) < 10) {
            under++;
            minSpeed = Math.min(minSpeed, c.speed);
            // On a deck: its layer, or riding a structure (a ground road over water or a dip in the
            // terrain is ridden on its own surface, specs/terrain.md, and is no deck).
            if (c.layer !== 0 || (d.rideEdge !== null && isStructure(d.rideEdge))) onDeck++;
          }
        }
        d.beforeStep = null;
        d.onRescue = null;
        const ok = s >= L - 15 && under > 0 && onDeck === 0 && rescues === 0 && minSpeed > 5;
        if (!ok) bad.push(`${e.name || e.index} under ${u.deck.name || u.deck.index} at (${u.x.toFixed(0)}, ${u.y.toFixed(0)}): finished ${s >= L - 15} under ${under} onDeck ${onDeck} rescues ${rescues} minSpeed ${minSpeed.toFixed(1)} closest ${minDist.toFixed(1)} m, route ${steps.map((x) => x.e.index).join(' ')}`);
      }
      if (LOG) writeFileSync(join(LOG, `under_${id}.txt`), `${list.length} underpasses\n${bad.join('\n')}`);
      expect(bad, `${id}: ${list.length} underpasses`).toEqual([]);
    }, 900000);
  }
});

/** Bank spots: a point of a ground road with water (not small) 12–40 m to one side of it. */
function bankSpots(city: City, d: DriveWorld, max: number): { x: number; y: number; h: number }[] {
  const g = city.graph, out: { x: number; y: number; h: number }[] = [];
  for (const e of g.edges) {
    if (!isGroundRoad(e) || !e.kept) continue;
    for (let s = 20; s < e.length - 20; s += 60) {
      const k = Math.min(e.pointCount - 2, e.cum.findIndex((c) => c > s) - 1);
      if (k < 0) continue;
      const ax = e.pts[2 * k]!, ay = e.pts[2 * k + 1]!, bx = e.pts[2 * k + 2]!, by = e.pts[2 * k + 3]!;
      const l = Math.hypot(bx - ax, by - ay) || 1, f = (s - e.cum[k]!) / l;
      const x = ax + (bx - ax) * f, y = ay + (by - ay) * f;
      if (d.nature.waterAt(x, y) !== null) continue;
      for (const side of [1, -1]) {
        const nx = (-(by - ay) / l) * side, ny = ((bx - ax) / l) * side;
        let hit = false;
        for (let r = 12; r <= 40 && !hit; r += 4) {
          const w = d.nature.waterAt(x + nx * r, y + ny * r);
          // Not across a bridge or another road (a deck over the water, a quay road).
          if (g.nearest(x + nx * r, y + ny * r, 6, (q) => q !== e) !== null) break;
          if (w !== null && w.cls !== WaterClass.WATER_SMALL) hit = true;
        }
        if (hit) out.push({ x, y, h: Math.atan2(ny, nx) });
      }
    }
  }
  const step = Math.max(1, Math.floor(out.length / max));
  return out.filter((_, i) => i % step === 0).slice(0, max);
}

const NATURE = ALL.filter((id) => id !== 'tokyo');

describe.skipIf(NATURE.length === 0)('L-S11: off the bank into the water = fall and tow', () => {
  for (const id of NATURE) {
    it(`${id}: driving off the bank anywhere falls in`, async () => {
      const city = await cityOf(id);
      if (city.manifest.natureVersion === 0) return;
      const d = await worldOf(city);
      // Water lives in the chunks: load the whole pack once.
      const all = { pts: [] as number[] };
      for (const ch of city.manifest.chunks) all.pts.push((ch.x + 0.5) * city.chunkM, (ch.y + 0.5) * city.chunkM);
      await loadAround(d, city, all, 0);
      const spots = bankSpots(city, d, 60);
      expect(spots.length, `${id}: bank spots`).toBeGreaterThan(10);
      const bad: string[] = [];
      let reached = 0;
      for (const sp of spots) {
        d.spawn(sp.x, sp.y, sp.h);
        let tows = 0, inWater = 0, fell = false;
        d.onSunk = () => tows++;
        for (let i = 0; i < 60 * 8 && tows === 0; i++) {
          d.input.reset();
          d.update(1 / 60);
          const c = d.car, w = d.nature.waterAt(c.x, c.y), h = d.layers.hit;
          fell ||= d.water.sinking;
          const carriageway = h !== null && h.edge.isGround && h.dist <= h.edge.width / 2;
          if (!fell && w !== null && w.cls !== WaterClass.WATER_SMALL && c.layer === 0 && d.rideEdge === null && !d.jump.airborne && !carriageway) inWater++;
        }
        d.onSunk = null;
        if (fell) reached++;
        if (inWater > 0 || (fell && tows === 0)) bad.push(`(${sp.x.toFixed(0)}, ${sp.y.toFixed(0)}) heading ${sp.h.toFixed(2)}: in water without a fall ${inWater} steps, fell ${fell}, tows ${tows}`);
      }
      if (LOG) writeFileSync(join(LOG, `water_${id}.txt`), `${spots.length} spots, ${reached} fell\n${bad.join('\n')}`);
      expect(bad, `${id}: ${spots.length} bank spots`).toEqual([]);
      // Many spots end in the water (the rest stop at a wall, a building or a railing on the quay).
      expect(reached, `${id}: falls of ${spots.length}`).toBeGreaterThan(spots.length / 3);
    }, 900000);
  }
});
