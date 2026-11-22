import { GroundKind } from '../gen/pb/citypack_pb';
import { decodeChunk } from './citypack';

/** Render- and physics-ready building mass, in world metres (port of world_engine chunk.dart). */
export interface BuildingData {
  /** Interleaved footprint vertices of all rings. */
  xy: Float32Array;
  /** Exclusive end vertex index per ring; ring 0 is the CCW outer ring. */
  ringEnds: Int32Array;
  roof: Uint16Array;
  height: number;
  minHeight: number;
  landmark: number;
  collide: boolean;
  seed: number;
  cx: number;
  cy: number;
  radius: number;
  /** Cumulative wall length at each vertex (texture u), per ring. */
  wallU: Float32Array;
}

/** Ground polygons of one kind merged into one list. */
export interface GroundData {
  kind: GroundKind;
  xy: Float32Array;
  indices: Uint32Array;
}

export interface ChunkData {
  x: number;
  y: number;
  buildings: BuildingData[];
  ground: GroundData[];
  /** Pedestrian-zone bollard lines (specs/zones.md): open polylines, interleaved metres. */
  barriers: Float32Array[];
}

/** Decodes and prepares one chunk. */
export async function prepareChunk(gz: Uint8Array): Promise<ChunkData> {
  const c = await decodeChunk(gz);
  const buildings: BuildingData[] = [];
  for (const b of c.buildings) {
    const n = b.rings.length >> 1;
    if (n < 3 || n > 65535) continue;
    const xy = Float32Array.from(b.rings, (v) => v / 10);
    const outerEnd = b.ringEnds.length === 0 ? n : b.ringEnds[0]!;
    let sx = 0, sy = 0;
    for (let i = 0; i < outerEnd; i++) {
      sx += xy[2 * i]!;
      sy += xy[2 * i + 1]!;
    }
    const cx = sx / outerEnd, cy = sy / outerEnd;
    let r2 = 0;
    for (let i = 0; i < outerEnd; i++) {
      const dx = xy[2 * i]! - cx, dy = xy[2 * i + 1]! - cy;
      r2 = Math.max(r2, dx * dx + dy * dy);
    }
    const ends = Int32Array.from(b.ringEnds.length === 0 ? [n] : b.ringEnds);
    const wallU = new Float32Array(n);
    let start = 0;
    for (const end of ends) {
      let u = 0;
      for (let i = start; i < end; i++) {
        wallU[i] = u;
        const j = i + 1 < end ? i + 1 : start;
        const dx = xy[2 * j]! - xy[2 * i]!, dy = xy[2 * j + 1]! - xy[2 * i + 1]!;
        u += Math.sqrt(dx * dx + dy * dy);
      }
      start = end;
    }
    buildings.push({
      xy, ringEnds: ends, roof: Uint16Array.from(b.roof), height: b.heightM, minHeight: b.minHeightM,
      landmark: b.landmark, collide: b.collide, seed: b.wallSeed, cx, cy, radius: Math.sqrt(r2), wallU,
    });
  }
  const byKind = new Map<GroundKind, { xy: number[]; idx: number[] }>();
  for (const m of c.ground) {
    let acc = byKind.get(m.kind);
    if (!acc) byKind.set(m.kind, (acc = { xy: [], idx: [] }));
    const base = acc.xy.length >> 1;
    for (const v of m.vertices) acc.xy.push(v / 10);
    for (const i of m.indices) acc.idx.push(base + i);
  }
  const ground = [...byKind].map(([kind, a]) => ({
    kind, xy: Float32Array.from(a.xy), indices: Uint32Array.from(a.idx),
  }));
  const barriers = c.barriers
    .filter((b) => b.points.length >= 4)
    .map((b) => Float32Array.from(b.points, (v) => v / 10));
  return { x: c.x, y: c.y, buildings, ground, barriers };
}
