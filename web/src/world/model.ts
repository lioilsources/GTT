import type { Graph, Landmarks, Manifest, Spots } from '../gen/pb/citypack_pb';
import { RoadClass } from '../gen/pb/citypack_pb';
import { decodeGraph, decodeLandmarks, decodeManifest, decodeSpots, type PackSource } from './citypack';

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
  ) {
    let l = 0;
    for (let i = 2; i < pts.length; i += 2) l += dist(pts[i - 2]!, pts[i - 1]!, pts[i]!, pts[i + 1]!);
    this.length = l;
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
  ) {
    this.index();
  }

  static fromPb(g: Graph): RoadGraph {
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
      return new RoadEdge(
        i, e.from, e.to, pts, e.class, g.names[e.name] ?? '', e.lanes, e.oneway,
        e.layerFrom, e.layerTo, e.bridge, e.tunnel, e.kept, e.widthM,
      );
    });
    return new RoadGraph(xy, border, edges, nodeEdges);
  }

  private index(): void {
    for (const e of this.edges) {
      const cum = new Float64Array(e.pointCount);
      for (let s = 1; s < e.pointCount; s++) {
        const ax = e.pts[2 * s - 2]!, ay = e.pts[2 * s - 1]!, bx = e.pts[2 * s]!, by = e.pts[2 * s + 1]!;
        cum[s] = cum[s - 1]! + dist(ax, ay, bx, by);
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

  private constructor(
    readonly manifest: Manifest,
    readonly graph: RoadGraph,
    readonly landmarks: Landmarks,
    readonly spots: Spots,
    readonly districts: { name: string; ring: Float32Array }[],
    readonly area: Float32Array,
  ) {
    this.chunkKeys = new Set(manifest.chunks.map((c) => chunkKey(c.x, c.y)));
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
    const manifest = await decodeManifest(m!);
    if (manifest.formatVersion !== 1) throw new Error(`citypack format ${manifest.formatVersion} is not supported`);
    return new City(
      manifest,
      RoadGraph.fromPb(await decodeGraph(g!)),
      await decodeLandmarks(l!),
      await decodeSpots(s!),
      manifest.districts.map((d) => ({ name: d.name, ring: ringM(d.ring) })),
      ringM(manifest.area),
    );
  }
}
