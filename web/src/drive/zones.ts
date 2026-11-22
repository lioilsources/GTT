import { Body, Chain, Edge, World, type Vec2Value } from 'planck';

import { GroundKind } from '../gen/pb/citypack_pb';
import type { TuningDrive } from '../gen/tuning';
import type { ChunkData } from '../world/chunk';
import { chunkKey } from '../world/model';
import { CAT_CAR, CAT_ZONE } from './car';

/** Pedestrian-zone triangles of one chunk with their bounding box (layer 0). */
interface ZoneMesh {
  xy: Float32Array;
  indices: Uint32Array;
  x0: number;
  y0: number;
  x1: number;
  y1: number;
}

/** True when (px, py) lies in triangle (a, b, c), edges included, either winding. */
export function pointInTriangle(
  px: number, py: number, ax: number, ay: number, bx: number, by: number, cx: number, cy: number,
): boolean {
  const d1 = (px - bx) * (ay - by) - (ax - bx) * (py - by);
  const d2 = (px - cx) * (by - cy) - (bx - cx) * (py - cy);
  const d3 = (px - ax) * (cy - ay) - (cx - ax) * (py - ay);
  const neg = d1 < 0 || d2 < 0 || d3 < 0;
  const pos = d1 > 0 || d2 > 0 || d3 > 0;
  return !(neg && pos);
}

/** True when (px, py) lies in a triangle of the mesh (interleaved xy, index triples). */
export function pointInMesh(xy: Float32Array, indices: Uint32Array, px: number, py: number): boolean {
  for (let i = 0; i + 2 < indices.length; i += 3) {
    const a = 2 * indices[i]!, b = 2 * indices[i + 1]!, c = 2 * indices[i + 2]!;
    if (pointInTriangle(px, py, xy[a]!, xy[a + 1]!, xy[b]!, xy[b + 1]!, xy[c]!, xy[c + 1]!)) return true;
  }
  return false;
}

/**
 * Pedestrian zones of the loaded chunks (specs/zones.md): bollard lines as static planck bodies
 * (one per chunk, category CAT_ZONE, mask CAT_CAR) and the PEDESTRIAN ground meshes for the
 * inside test. Same lifecycle as the building colliders of DriveWorld.
 */
export class ZoneWorld {
  private readonly bodies = new Map<number, Body>();
  private readonly meshes = new Map<number, ZoneMesh[]>();

  constructor(
    readonly world: World,
    readonly t: TuningDrive,
  ) {}

  /** Number of chunks with bollard bodies (tests). */
  get bodyCount(): number {
    return this.bodies.size;
  }

  /** The bollard body of chunk (cx, cy), if it has one (tests). */
  bodyOf(cx: number, cy: number): Body | undefined {
    return this.bodies.get(chunkKey(cx, cy));
  }

  addChunk(c: ChunkData): void {
    const key = chunkKey(c.x, c.y);
    if (this.bodies.has(key) || this.meshes.has(key)) return;
    const zones: ZoneMesh[] = [];
    for (const g of c.ground) {
      if (g.kind !== GroundKind.PEDESTRIAN || g.indices.length < 3) continue;
      let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
      for (let i = 0; i < g.xy.length; i += 2) {
        const x = g.xy[i]!, y = g.xy[i + 1]!;
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
      zones.push({ xy: g.xy, indices: g.indices, x0, y0, x1, y1 });
    }
    if (zones.length > 0) this.meshes.set(key, zones);
    if (c.barriers.length === 0) return;
    const body = this.world.createBody({ type: 'static' });
    // Cars bounce off bollards as off buildings (specs/zones.md).
    const opt = {
      friction: this.t.buildingFriction,
      restitution: this.t.buildingRestitution,
      filterCategoryBits: CAT_ZONE,
      filterMaskBits: CAT_CAR,
    };
    for (const line of c.barriers) {
      const pts: Vec2Value[] = [];
      for (let i = 0; i + 1 < line.length; i += 2) {
        const p = { x: line[i]!, y: line[i + 1]! };
        const q = pts[pts.length - 1];
        // planck rejects nearly coincident chain vertices.
        if (q === undefined || Math.hypot(p.x - q.x, p.y - q.y) > 0.01) pts.push(p);
      }
      try {
        if (pts.length >= 3) body.createFixture({ shape: new Chain(pts, false), ...opt });
        else if (pts.length === 2) body.createFixture({ shape: new Edge(pts[0]!, pts[1]!), ...opt });
      } catch {
        // Degenerate polyline; skip it like a degenerate building ring.
      }
    }
    this.bodies.set(key, body);
  }

  removeChunk(c: ChunkData): void {
    const key = chunkKey(c.x, c.y);
    const body = this.bodies.get(key);
    if (body) this.world.destroyBody(body);
    this.bodies.delete(key);
    this.meshes.delete(key);
  }

  /** True when (x, y) is inside a loaded pedestrian zone (ground layer). */
  inside(x: number, y: number): boolean {
    for (const list of this.meshes.values()) {
      for (const m of list) {
        if (x < m.x0 || x > m.x1 || y < m.y0 || y > m.y1) continue;
        if (pointInMesh(m.xy, m.indices, x, y)) return true;
      }
    }
    return false;
  }
}
