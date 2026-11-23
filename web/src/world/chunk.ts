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
  /** Lowest game height under the footprint (m, specs/terrain.md); 0 or absent in a flat pack. */
  baseZ?: number;
}

/** Ground polygons of one kind merged into one list. */
export interface GroundData {
  kind: GroundKind;
  xy: Float32Array;
  indices: Uint32Array;
  /** Water level (game height, m) of a WATER mesh in a pack with terrain; absent = drape on the terrain. */
  z?: number;
}

export interface ChunkData {
  x: number;
  y: number;
  buildings: BuildingData[];
  ground: GroundData[];
  /** Pedestrian-zone bollard lines (specs/zones.md): open polylines, interleaved metres. */
  barriers: Float32Array[];
  /**
   * Terrain (specs/terrain.md): (n + 1)² game heights in metres, rows from the south, step
   * `terrainStep`; absent in a flat pack.
   */
  terrain?: Float32Array | null;
  /** Hillshade per terrain sample, 0–255 (128 = flat); absent in a flat pack. */
  shade?: Uint8Array | null;
}

/** Samples per terrain row (33 for a 256 m chunk at 8 m). */
export const TERRAIN_N = 33;

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
      baseZ: b.baseZDm / 10,
    });
  }
  const byKind = new Map<string, { kind: GroundKind; z?: number; xy: number[]; idx: number[] }>();
  // Water at its level stays apart per level (specs/terrain.md: Ground.z_dm), the rest per kind.
  const terrain = decodeTerrain(c.terrain);
  for (const m of c.ground) {
    const level = terrain !== null && m.kind === GroundKind.WATER ? m.zDm / 10 : undefined;
    const key = level === undefined ? `${m.kind}` : `${m.kind}:${m.zDm}`;
    let acc = byKind.get(key);
    if (!acc) byKind.set(key, (acc = { kind: m.kind, ...(level === undefined ? {} : { z: level }), xy: [], idx: [] }));
    const base = acc.xy.length >> 1;
    for (const v of m.vertices) acc.xy.push(v / 10);
    for (const i of m.indices) acc.idx.push(base + i);
  }
  const ground: GroundData[] = [...byKind.values()].map((a) => ({
    kind: a.kind, ...(a.z === undefined ? {} : { z: a.z }), xy: Float32Array.from(a.xy), indices: Uint32Array.from(a.idx),
  }));
  const barriers = c.barriers
    .filter((b) => b.points.length >= 4)
    .map((b) => Float32Array.from(b.points, (v) => v / 10));
  const shade = terrain !== null && c.shade.length === TERRAIN_N * TERRAIN_N ? Uint8Array.from(c.shade) : null;
  return { x: c.x, y: c.y, buildings, ground, barriers, terrain, shade };
}

/** Chunk.terrain: 33 × 33 int16 LE decimetres → metres; null when absent or malformed. */
export function decodeTerrain(bytes: Uint8Array): Float32Array | null {
  if (bytes.length !== TERRAIN_N * TERRAIN_N * 2) return null;
  const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const out = new Float32Array(TERRAIN_N * TERRAIN_N);
  for (let i = 0; i < out.length; i++) out[i] = dv.getInt16(2 * i, true) / 10;
  return out;
}
