import type { Graph, Landmarks, Manifest, Spots, TramGraph } from '../gen/pb/citypack_pb';
import { RoadClass } from '../gen/pb/citypack_pb';
import { decodeGraph, decodeLandmarks, decodeManifest, decodeSpots, decodeTrams, type PackSource } from './citypack';
import { loadModels, type ModelData } from './models';
import { Terrain } from './terrain';

/** A drivable road edge in world metres (port of world_engine model.dart). */
export class RoadEdge {
  readonly length: number;

  constructor(
    readonly index: number,
    readonly from: number,
    readonly to: number,
    /** Interleaved x, y in metres, both end nodes included. */
    readonly pts: Float32Array,
    readonly roadClass: RoadClass,
    readonly name: string,
    readonly lanes: number,
    readonly oneway: number,
    readonly layerFrom: number,
    readonly layerTo: number,
    readonly bridge: boolean,
    readonly tunnel: boolean,
    /** false = alley: drivable, no traffic, no GPS. */
    readonly kept: boolean,
    /** Full corridor width incl. sidewalks. */
    readonly width: number,
    /**
     * Game height of every point of `pts` (m, specs/terrain.md); null in a flat pack. Edges with
     * relief are densified to segments of at most 16 m.
     */
    readonly z: Float32Array | null = null,
    /** Steeper than terrain.max_grade allows: a wall for cars (specs/terrain.md). */
    readonly stairs = false,
  ) {
    const n = pts.length >> 1;
    const cum = new Float64Array(Math.max(1, n));
    for (let i = 1; i < n; i++) cum[i] = cum[i - 1]! + dist(pts[2 * i - 2]!, pts[2 * i - 1]!, pts[2 * i]!, pts[2 * i + 1]!);
    this.cum = cum;
    this.length = n > 0 ? cum[n - 1]! : 0;
  }

  /** Cumulative distance from `from` at each point (m). */
  readonly cum: Float64Array;

  /** Game height at parameter f (0..1) of segment `seg` (specs/terrain.md: linear between vertices). */
  zOnSeg(seg: number, f: number): number {
    const z = this.z;
    if (z === null) return 0;
    const s = Math.min(Math.max(seg, 0), z.length - 2);
    if (s < 0) return z[0] ?? 0;
    return z[s]! + (z[s + 1]! - z[s]!) * Math.min(1, Math.max(0, f));
  }

  /** Game height at distance d from `from` along the edge. */
  zAt(d: number): number {
    const z = this.z;
    if (z === null) return 0;
    const n = this.pointCount;
    if (n < 2) return z[0] ?? 0;
    let s = 0;
    while (s < n - 2 && this.cum[s + 1]! < d) s++;
    const l = this.cum[s + 1]! - this.cum[s]!;
    return this.zOnSeg(s, l > 0 ? (d - this.cum[s]!) / l : 0);
  }

  /** Grade of segment `seg` from → to (dz / length), 0 in a flat pack. */
  gradeOfSeg(seg: number): number {
    const z = this.z;
    if (z === null || seg < 0 || seg + 1 >= this.pointCount) return 0;
    const l = this.cum[seg + 1]! - this.cum[seg]!;
    return l > 1e-6 ? (z[seg + 1]! - z[seg]!) / l : 0;
  }

  get pointCount(): number {
    return this.pts.length >> 1;
  }
  get isGround(): boolean {
    return !this.tunnel && this.layerFrom === 0 && this.layerTo === 0;
  }

  /** The layer at parameter t (0..1 along the edge); a ramp switches halfway. */
  layerAt(t: number): number {
    return this.layerFrom === this.layerTo ? this.layerFrom : t < 0.5 ? this.layerFrom : this.layerTo;
  }

  /** The highest layer the edge touches; used to pick its draw pass. */
  get drawLayer(): number {
    if (this.tunnel) return -1;
    return Math.max(this.layerFrom, this.layerTo) > 0 ? 1 : Math.min(this.layerFrom, this.layerTo);
  }
}

/** Result of a nearest-edge query. */
export interface EdgeHit {
  edge: RoadEdge;
  segment: number;
  x: number;
  y: number;
  dist: number;
  /** Parameter along the whole edge, 0..1. */
  t: number;
  /** Unit direction of the segment, from → to. */
  dirX: number;
  dirY: number;
}

function dist(ax: number, ay: number, bx: number, by: number): number {
  const dx = bx - ax,
    dy = by - ay;
  return Math.sqrt(dx * dx + dy * dy);
}

const CELL = 32;
const gridKey = (cx: number, cy: number): number => (cx + 32768) * 65536 + (cy + 32768);

export class RoadGraph {
  private readonly grid = new Map<number, number[]>();
  private readonly cumLen: Float64Array[] = [];

  private constructor(
    readonly nodeXY: Float32Array,
    readonly border: boolean[],
    readonly edges: RoadEdge[],
    readonly nodeEdges: number[][],
    /** Game height of every node (m, specs/terrain.md); zeros in a flat pack. */
    readonly nodeZ: Float32Array = new Float32Array(nodeXY.length >> 1),
  ) {
    this.index();
  }

  static fromPb(g: Graph): RoadGraph {
    const xy = new Float32Array(g.nodes.length * 2);
    const nodeZ = new Float32Array(g.nodes.length);
    const border: boolean[] = [];
    g.nodes.forEach((n, i) => {
      xy[2 * i] = n.x / 10;
      xy[2 * i + 1] = n.y / 10;
      nodeZ[i] = n.zDm / 10;
      border.push(n.border);
    });
    const nodeEdges: number[][] = g.nodes.map(() => []);
    const edges = g.edges.map((e, i) => {
      const pts = new Float32Array(e.points.length);
      for (let j = 0; j < pts.length; j++) pts[j] = e.points[j]! / 10;
      nodeEdges[e.from]!.push(i);
      nodeEdges[e.to]!.push(i);
      // Heights per vertex (specs/terrain.md); a flat pack or a count mismatch has none.
      const z = e.zDm.length * 2 === e.points.length && e.zDm.length > 0 ? Float32Array.from(e.zDm, (v) => v / 10) : null;
      return new RoadEdge(
        i, e.from, e.to, pts, e.class, g.names[e.name] ?? '', e.lanes, e.oneway,
        e.layerFrom, e.layerTo, e.bridge, e.tunnel, e.kept, e.widthM, z, e.stairs,
      );
    });
    return new RoadGraph(xy, border, edges, nodeEdges, nodeZ);
  }

  private index(): void {
    for (const e of this.edges) {
      const cum = e.cum;
      for (let s = 1; s < e.pointCount; s++) {
        const ax = e.pts[2 * s - 2]!, ay = e.pts[2 * s - 1]!, bx = e.pts[2 * s]!, by = e.pts[2 * s + 1]!;
        const r = e.width / 2;
        const x0 = Math.floor((Math.min(ax, bx) - r) / CELL), x1 = Math.floor((Math.max(ax, bx) + r) / CELL);
        const y0 = Math.floor((Math.min(ay, by) - r) / CELL), y1 = Math.floor((Math.max(ay, by) + r) / CELL);
        for (let cx = x0; cx <= x1; cx++) {
          for (let cy = y0; cy <= y1; cy++) {
            const k = gridKey(cx, cy);
            let list = this.grid.get(k);
            if (!list) this.grid.set(k, (list = []));
            list.push(e.index * 4096 + (s - 1));
          }
        }
      }
      this.cumLen.push(cum);
    }
  }

  /** Edges sharing a node with `edge` (including itself). */
  neighbours(edge: number): number[] {
    const e = this.edges[edge]!;
    return [...this.nodeEdges[e.from]!, ...this.nodeEdges[e.to]!];
  }

  /** Nearest edge segment to (x, y) within maxDist, optionally filtered. */
  nearest(x: number, y: number, maxDist = 40, where?: (e: RoadEdge) => boolean): EdgeHit | null {
    let best: EdgeHit | null = null;
    const r = Math.ceil(maxDist / CELL);
    const cx = Math.floor(x / CELL), cy = Math.floor(y / CELL);
    const seen = new Set<number>();
    for (let ix = cx - r; ix <= cx + r; ix++) {
      for (let iy = cy - r; iy <= cy + r; iy++) {
        const list = this.grid.get(gridKey(ix, iy));
        if (!list) continue;
        for (const code of list) {
          if (seen.has(code)) continue;
          seen.add(code);
          const e = this.edges[Math.floor(code / 4096)]!;
          if (where && !where(e)) continue;
          const hit = this.project(e, code % 4096, x, y);
          if (hit.dist <= maxDist && (best === null || hit.dist < best.dist)) best = hit;
        }
      }
    }
    return best;
  }

  /** All edges with a segment within radius of (x, y), each with its closest hit. */
  near(x: number, y: number, radius: number): EdgeHit[] {
    const out = new Map<number, EdgeHit>();
    const r = Math.ceil(radius / CELL);
    const cx = Math.floor(x / CELL), cy = Math.floor(y / CELL);
    for (let ix = cx - r; ix <= cx + r; ix++) {
      for (let iy = cy - r; iy <= cy + r; iy++) {
        const list = this.grid.get(gridKey(ix, iy));
        if (!list) continue;
        for (const code of list) {
          const e = this.edges[Math.floor(code / 4096)]!;
          const hit = this.project(e, code % 4096, x, y);
          if (hit.dist > radius) continue;
          const prev = out.get(e.index);
          if (!prev || hit.dist < prev.dist) out.set(e.index, hit);
        }
      }
    }
    return [...out.values()];
  }

  /** Projects (x, y) onto one segment of an edge. */
  project(e: RoadEdge, seg: number, x: number, y: number): EdgeHit {
    const ax = e.pts[2 * seg]!, ay = e.pts[2 * seg + 1]!, bx = e.pts[2 * seg + 2]!, by = e.pts[2 * seg + 3]!;
    const dx = bx - ax, dy = by - ay;
    const l2 = dx * dx + dy * dy;
    let t = l2 === 0 ? 0 : ((x - ax) * dx + (y - ay) * dy) / l2;
    t = Math.min(1, Math.max(0, t));
    const px = ax + dx * t, py = ay + dy * t;
    const l = Math.sqrt(l2);
    const along = e.length === 0 ? 0 : (this.cumLen[e.index]![seg]! + l * t) / e.length;
    return {
      edge: e, segment: seg, x: px, y: py, dist: dist(px, py, x, y), t: along,
      dirX: l === 0 ? 1 : dx / l, dirY: l === 0 ? 0 : dy / l,
    };
  }
}

/** A tram track edge in world metres (specs/trams.md, trams.pb); always two-way. */
export class TrackEdge {
  readonly length: number;
  /** Cumulative distance from `from` at each point (m). */
  readonly cum: Float64Array;

  constructor(
    readonly index: number,
    readonly from: number,
    readonly to: number,
    /** Interleaved x, y in metres, both end nodes included. */
    readonly pts: Float32Array,
    readonly layerFrom: number,
    readonly layerTo: number,
    readonly bridge: boolean,
    readonly tunnel: boolean,
  ) {
    const n = pts.length >> 1;
    const cum = new Float64Array(Math.max(1, n));
    for (let i = 1; i < n; i++) cum[i] = cum[i - 1]! + dist(pts[2 * i - 2]!, pts[2 * i - 1]!, pts[2 * i]!, pts[2 * i + 1]!);
    this.cum = cum;
    this.length = n > 0 ? cum[n - 1]! : 0;
  }

  get pointCount(): number {
    return this.pts.length >> 1;
  }
  get isGround(): boolean {
    return !this.tunnel && this.layerFrom === 0 && this.layerTo === 0;
  }

  /** The layer at parameter t (0..1 along the edge); a ramp switches halfway (as RoadEdge). */
  layerAt(t: number): number {
    return this.layerFrom === this.layerTo ? this.layerFrom : t < 0.5 ? this.layerFrom : this.layerTo;
  }

  /** The draw pass of the edge, as RoadEdge.drawLayer. */
  get drawLayer(): number {
    if (this.tunnel) return -1;
    return Math.max(this.layerFrom, this.layerTo) > 0 ? 1 : Math.min(this.layerFrom, this.layerTo);
  }

  /**
   * Point and unit direction (from → to) at distance d from `from`, clamped to the edge; written
   * into out = [x, y, dirX, dirY]. Allocation-free.
   */
  pointAt(d: number, out: Float64Array | number[]): void {
    const n = this.pointCount;
    if (n < 2) {
      out[0] = n > 0 ? this.pts[0]! : 0;
      out[1] = n > 0 ? this.pts[1]! : 0;
      out[2] = 1;
      out[3] = 0;
      return;
    }
    let s = 0;
    while (s < n - 2 && this.cum[s + 1]! < d) s++;
    const ax = this.pts[2 * s]!, ay = this.pts[2 * s + 1]!, bx = this.pts[2 * s + 2]!, by = this.pts[2 * s + 3]!;
    const l = this.cum[s + 1]! - this.cum[s]!;
    const f = l > 0 ? Math.min(1, Math.max(0, (d - this.cum[s]!) / l)) : 0;
    out[0] = ax + (bx - ax) * f;
    out[1] = ay + (by - ay) * f;
    out[2] = l > 0 ? (bx - ax) / l : 1;
    out[3] = l > 0 ? (by - ay) / l : 0;
  }
}

/** A generated tram stop (specs/trams.md "Zastávky"): `s` metres from the edge's `from` end. */
export interface TrackStop {
  readonly index: number;
  readonly edge: number;
  readonly s: number;
  readonly x: number;
  readonly y: number;
  /** Unit direction of the track at the stop, from → to. */
  readonly dirX: number;
  readonly dirY: number;
}

/** Tram tracks and stops of a city (trams.pb, specs/citypack.md v3); empty without trams. */
export class TrackGraph {
  /** Per edge: stop indices sorted by s ascending. */
  readonly stopsByEdge: number[][];

  private constructor(
    readonly nodeXY: Float32Array,
    readonly border: boolean[],
    readonly edges: TrackEdge[],
    readonly nodeEdges: number[][],
    readonly stops: TrackStop[],
  ) {
    this.stopsByEdge = edges.map(() => []);
    for (const st of stops) this.stopsByEdge[st.edge]?.push(st.index);
    for (const list of this.stopsByEdge) list.sort((a, b) => stops[a]!.s - stops[b]!.s || a - b);
  }

  static empty(): TrackGraph {
    return new TrackGraph(new Float32Array(0), [], [], [], []);
  }

  get isEmpty(): boolean {
    return this.edges.length === 0;
  }

  static fromPb(g: TramGraph): TrackGraph {
    const xy = new Float32Array(g.nodes.length * 2);
    const border: boolean[] = [];
    g.nodes.forEach((n, i) => {
      xy[2 * i] = n.x / 10;
      xy[2 * i + 1] = n.y / 10;
      border.push(n.border);
    });
    const nodeEdges: number[][] = g.nodes.map(() => []);
    const edges = g.edges.map((e, i) => {
      const pts = new Float32Array(e.points.length);
      for (let j = 0; j < pts.length; j++) pts[j] = e.points[j]! / 10;
      nodeEdges[e.from]!.push(i);
      nodeEdges[e.to]!.push(i);
      return new TrackEdge(i, e.from, e.to, pts, e.layerFrom, e.layerTo, e.bridge, e.tunnel);
    });
    const p = [0, 0, 0, 0];
    const stops: TrackStop[] = [];
    for (const st of g.stops) {
      const e = edges[st.edge];
      if (!e) continue;
      const s = Math.max(0, Math.min(st.sM, e.length));
      e.pointAt(s, p);
      stops.push({ index: stops.length, edge: st.edge, s, x: p[0]!, y: p[1]!, dirX: p[2]!, dirY: p[3]! });
    }
    return new TrackGraph(xy, border, edges, nodeEdges, stops);
  }
}

/** Even-odd point in polygon over an interleaved ring. */
export function pointInRing(x: number, y: number, ring: Float32Array): boolean {
  let inside = false;
  const n = ring.length >> 1;
  for (let i = 0, j = n - 1; i < n; j = i++) {
    const xi = ring[2 * i]!, yi = ring[2 * i + 1]!, xj = ring[2 * j]!, yj = ring[2 * j + 1]!;
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

const ringM = (dm: number[]): Float32Array => Float32Array.from(dm, (v) => v / 10);

export const chunkKey = (x: number, y: number): number => (x + 32768) * 65536 + (y + 32768);

/** The static, always-loaded part of a citypack. */
export class City {
  readonly chunkKeys: Set<number>;
  /** Heights (specs/terrain.md): flat when the pack has no terrain_version. */
  readonly terrain: Terrain;

  private constructor(
    readonly manifest: Manifest,
    readonly graph: RoadGraph,
    readonly landmarks: Landmarks,
    readonly spots: Spots,
    readonly districts: { name: string; ring: Float32Array }[],
    readonly area: Float32Array,
    /** Raw graph (dm integers) for the GPS route (specs/route.md). */
    readonly graphPb: Graph,
    /** Tram tracks and stops (specs/trams.md); empty for a city without trams or an old pack. */
    readonly trams: TrackGraph,
    /** Landmark models (specs/models.md, models.pb); empty without them. */
    readonly models: ModelData[] = [],
  ) {
    this.chunkKeys = new Set(manifest.chunks.map((c) => chunkKey(c.x, c.y)));
    this.terrain = new Terrain(manifest, graph);
  }

  get id(): string {
    return this.manifest.cityId;
  }
  get chunkM(): number {
    return this.manifest.chunkM;
  }
  get imperial(): boolean {
    return this.manifest.units === 'imperial';
  }
  get startX(): number {
    return (this.manifest.start?.x ?? 0) / 10;
  }
  get startY(): number {
    return (this.manifest.start?.y ?? 0) / 10;
  }
  get startHeading(): number {
    return this.manifest.start?.headingRad ?? 0;
  }

  hasChunk(x: number, y: number): boolean {
    return this.chunkKeys.has(chunkKey(x, y));
  }

  districtAt(x: number, y: number): string | null {
    for (const d of this.districts) if (pointInRing(x, y, d.ring)) return d.name;
    return null;
  }

  static async load(src: PackSource): Promise<City> {
    const [m, g, l, s] = await Promise.all(
      ['manifest.pb', 'graph.pb', 'landmarks.pb', 'spots.pb'].map((p) => src.read(p)),
    );
    // trams.pb exists from citypack v3 on; an older pack has none = an empty track graph.
    const trams = await src.read('trams.pb').then((b) => decodeTrams(b)).then(
      (pb) => TrackGraph.fromPb(pb),
      () => TrackGraph.empty(),
    );
    const manifest = await decodeManifest(m!);
    if (manifest.formatVersion !== 1) throw new Error(`citypack format ${manifest.formatVersion} is not supported`);
    const graph = await decodeGraph(g!);
    const models = await loadModels(src, manifest.modelsVersion, manifest.chunkM);
    return new City(
      manifest,
      RoadGraph.fromPb(graph),
      await decodeLandmarks(l!),
      await decodeSpots(s!),
      manifest.districts.map((d) => ({ name: d.name, ring: ringM(d.ring) })),
      ringM(manifest.area),
      graph,
      trams,
      models,
    );
  }
}
