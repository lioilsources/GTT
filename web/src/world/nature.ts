import { GreenClass, GroundKind, Surface, WaterClass, type Chunk, type Mesh as PbMesh } from '../gen/pb/citypack_pb';
import { chunkKey } from './model';

/**
 * Water and green of one chunk (specs/nature.md, citypack v4) in world metres: classed water and
 * green pieces, the shore band, trees and name labels. Pure (no Babylon), shared by the drive
 * (surface under the car, water, soft trees) and the renderer.
 */

/** A triangulated piece of water or green, with its bounding box for point queries. */
export interface NaturePiece {
  xy: Float32Array;
  idx: Uint32Array;
  name: string;
  x0: number;
  y0: number;
  x1: number;
  y1: number;
  /** Area of the piece (m²): the smaller named piece wins the HUD name. */
  area: number;
}

export interface WaterPiece extends NaturePiece {
  cls: WaterClass;
  /** Water level (game height, m). */
  z: number;
}

export interface GreenPiece extends NaturePiece {
  cls: GreenClass;
  surface: Surface;
}

/** Tree sizes (Chunk.trees low 2 bits): S sapling, M, L. */
export const TREE_S = 0;
export const TREE_M = 1;
export const TREE_L = 2;

export interface Tree {
  x: number;
  y: number;
  /** 0 S, 1 M, 2 L. */
  size: number;
  /** Colour jitter 0..63. */
  jitter: number;
  /** Tree key `"<cx>_<cy>/<index in Chunk.trees>"` (specs/flow.md). */
  key: string;
}

export interface NatureLabel {
  name: string;
  /** Polyline (water) or one point (green), interleaved metres. */
  axis: Float32Array;
  water: boolean;
  /** Area of the whole body (m²). */
  area: number;
}

export interface NatureChunk {
  x: number;
  y: number;
  water: WaterPiece[];
  green: GreenPiece[];
  /** Shallow band inside the water along the bank. */
  shore: NaturePiece[];
  trees: Tree[];
  labels: NatureLabel[];
}

function piece(m: PbMesh): NaturePiece | null {
  const n = m.vertices.length >> 1;
  if (n < 3 || m.indices.length < 3) return null;
  const xy = Float32Array.from(m.vertices, (v) => v / 10);
  const idx = Uint32Array.from(m.indices);
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  for (let i = 0; i < xy.length; i += 2) {
    x0 = Math.min(x0, xy[i]!);
    x1 = Math.max(x1, xy[i]!);
    y0 = Math.min(y0, xy[i + 1]!);
    y1 = Math.max(y1, xy[i + 1]!);
  }
  let area = 0;
  for (let i = 0; i + 2 < idx.length; i += 3) {
    const a = idx[i]!, b = idx[i + 1]!, c = idx[i + 2]!;
    area += Math.abs((xy[2 * b]! - xy[2 * a]!) * (xy[2 * c + 1]! - xy[2 * a + 1]!) - (xy[2 * c]! - xy[2 * a]!) * (xy[2 * b + 1]! - xy[2 * a + 1]!)) / 2;
  }
  return { xy, idx, name: m.name, x0, y0, x1, y1, area };
}

/** Decodes Chunk.trees (3 bytes per tree: x, y in metres from the chunk's south-west corner, size | jitter << 2). */
export function decodeTrees(bytes: Uint8Array, cx: number, cy: number, chunkM: number): Tree[] {
  const out: Tree[] = [];
  const ox = cx * chunkM, oy = cy * chunkM;
  for (let i = 0; i + 2 < bytes.length; i += 3) {
    const b = bytes[i + 2]!;
    out.push({ x: ox + bytes[i]!, y: oy + bytes[i + 1]!, size: Math.min(b & 3, TREE_L), jitter: b >> 2, key: `${cx}_${cy}/${i / 3}` });
  }
  return out;
}

/**
 * The nature part of a decoded chunk, or null for a pack without nature (Manifest.nature_version 0):
 * then the ground draws as in citypack v3 and the surface is asphalt everywhere.
 */
export function prepareNature(c: Chunk, chunkM: number, natureVersion: number): NatureChunk | null {
  if (natureVersion <= 0) return null;
  const water: WaterPiece[] = [], green: GreenPiece[] = [], shore: NaturePiece[] = [];
  for (const m of c.ground) {
    if (m.kind === GroundKind.WATER) {
      const p = piece(m);
      if (p) water.push({ ...p, cls: m.waterClass === WaterClass.WATER_NONE ? WaterClass.WATER_RIVER : m.waterClass, z: m.zDm / 10 });
    } else if (m.kind === GroundKind.PARK) {
      const p = piece(m);
      if (p) green.push({ ...p, cls: m.greenClass === GreenClass.GREEN_NONE ? GreenClass.GREEN_PARKLAND : m.greenClass, surface: m.surface });
    }
  }
  for (const m of c.shore) {
    const p = piece(m);
    if (p) shore.push(p);
  }
  const labels = c.labels
    .filter((l) => l.name !== '' && l.axis.length >= 2)
    .map((l) => ({ name: l.name, axis: Float32Array.from(l.axis, (v) => v / 10), water: l.water, area: l.areaM2 }));
  return { x: c.x, y: c.y, water, green, shore, trees: decodeTrees(c.trees, c.x, c.y, chunkM), labels };
}

/** Point in a triangulated piece (bounding box first). */
export function inPiece(p: NaturePiece, x: number, y: number): boolean {
  if (x < p.x0 || x > p.x1 || y < p.y0 || y > p.y1) return false;
  const xy = p.xy, idx = p.idx;
  for (let i = 0; i + 2 < idx.length; i += 3) {
    const a = 2 * idx[i]!, b = 2 * idx[i + 1]!, c = 2 * idx[i + 2]!;
    const ax = xy[a]!, ay = xy[a + 1]!, bx = xy[b]!, by = xy[b + 1]!, cx = xy[c]!, cy = xy[c + 1]!;
    const d1 = (x - bx) * (ay - by) - (ax - bx) * (y - by);
    const d2 = (x - cx) * (by - cy) - (bx - cx) * (y - cy);
    const d3 = (x - ax) * (cy - ay) - (cx - ax) * (y - ay);
    const neg = d1 < 0 || d2 < 0 || d3 < 0, pos = d1 > 0 || d2 > 0 || d3 > 0;
    if (!(neg && pos)) return true;
  }
  return false;
}

/** Driving surface names as in nature.grip (specs/nature.md "Jízda"). */
export type SurfaceName = 'asphalt' | 'grass' | 'sand' | 'dirt' | 'forest';

export function surfaceName(s: Surface): SurfaceName {
  switch (s) {
    case Surface.GRASS: return 'grass';
    case Surface.SAND: return 'sand';
    case Surface.DIRT: return 'dirt';
    case Surface.FOREST: return 'forest';
    default: return 'asphalt';
  }
}

/**
 * Nature of the loaded chunks with point queries. Pieces are clipped to the chunk grid, so a point
 * only needs its own chunk; a tree belongs to the chunk of its trunk.
 */
export class NatureMap {
  readonly chunks = new Map<number, NatureChunk>();
  /** Bumped on every add or remove (renderers and the tree candidate cache rebuild on it). */
  version = 0;

  constructor(readonly chunkM: number) {}

  add(n: NatureChunk): void {
    this.chunks.set(chunkKey(n.x, n.y), n);
    this.version++;
  }

  remove(x: number, y: number): void {
    if (this.chunks.delete(chunkKey(x, y))) this.version++;
  }

  get empty(): boolean {
    return this.chunks.size === 0;
  }

  private at(x: number, y: number): NatureChunk | undefined {
    return this.chunks.get(chunkKey(Math.floor(x / this.chunkM), Math.floor(y / this.chunkM)));
  }

  /** The water piece under (x, y), or null. */
  waterAt(x: number, y: number): WaterPiece | null {
    const c = this.at(x, y);
    if (!c) return null;
    for (const w of c.water) if (inPiece(w, x, y)) return w;
    return null;
  }

  /** The green piece under (x, y) (the smallest when pieces overlap), or null. */
  greenAt(x: number, y: number): GreenPiece | null {
    const c = this.at(x, y);
    if (!c) return null;
    let best: GreenPiece | null = null;
    for (const g of c.green) if ((best === null || g.area < best.area) && inPiece(g, x, y)) best = g;
    return best;
  }

  /** Surface under (x, y): the green piece's, asphalt outside green (specs/nature.md "Jízda"). */
  surfaceAt(x: number, y: number): SurfaceName {
    const g = this.greenAt(x, y);
    return g ? surfaceName(g.surface) : 'asphalt';
  }

  /** Name of the named park the point is in ("" when none): HUD "street · park". */
  parkAt(x: number, y: number): string {
    const c = this.at(x, y);
    if (!c) return '';
    let best: GreenPiece | null = null;
    for (const g of c.green) if (g.name !== '' && (best === null || g.area < best.area) && inPiece(g, x, y)) best = g;
    return best?.name ?? '';
  }

  /** Trees whose trunk is within r of (x, y), appended to out. */
  treesNear(x: number, y: number, r: number, out: Tree[]): Tree[] {
    const cm = this.chunkM;
    const x0 = Math.floor((x - r) / cm), x1 = Math.floor((x + r) / cm);
    const y0 = Math.floor((y - r) / cm), y1 = Math.floor((y + r) / cm);
    const r2 = r * r;
    for (let cx = x0; cx <= x1; cx++) {
      for (let cy = y0; cy <= y1; cy++) {
        const c = this.chunks.get(chunkKey(cx, cy));
        if (!c) continue;
        for (const t of c.trees) {
          const dx = t.x - x, dy = t.y - y;
          if (dx * dx + dy * dy <= r2) out.push(t);
        }
      }
    }
    return out;
  }
}
