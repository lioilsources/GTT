import type { Manifest } from '../gen/pb/citypack_pb';
import { TERRAIN_N, type ChunkData } from './chunk';
import { chunkKey, type RoadEdge, type RoadGraph } from './model';

/** One loaded chunk's terrain grid (game heights in metres) and hillshade. */
interface Grid {
  h: Float32Array;
  shade: Uint8Array | null;
}

/**
 * Heights of the world (specs/terrain.md "Výška pod bodem"): the terrain grids of the loaded
 * chunks and the road graph's profiles. A pack without `terrain_version` is flat: every height
 * is 0, every gradient 0. Pure logic, no Babylon.
 */
export class Terrain {
  /** The pack carries heights (manifest.terrain_version > 0); `?flat` (debug) turns them off. */
  enabled: boolean;
  /** Real elevation of game height 0 (m). */
  readonly z0: number;
  readonly exaggeration: number;
  readonly chunkM: number;
  /** Grid step (m): chunk_m / 32. */
  readonly step: number;
  private readonly grids = new Map<number, Grid>();
  /** Bumped when a grid is added or removed (renderers rebuild what depends on it). */
  version = 0;

  constructor(
    manifest: Pick<Manifest, 'terrainVersion' | 'z0M' | 'exaggeration' | 'chunkM'>,
    readonly graph: RoadGraph,
  ) {
    this.enabled = manifest.terrainVersion > 0;
    this.z0 = manifest.z0M;
    this.exaggeration = manifest.exaggeration > 0 ? manifest.exaggeration : 1;
    this.chunkM = manifest.chunkM > 0 ? manifest.chunkM : 256;
    this.step = this.chunkM / (TERRAIN_N - 1);
  }

  addChunk(c: ChunkData): void {
    if (!this.enabled || !c.terrain) return;
    this.grids.set(chunkKey(c.x, c.y), { h: c.terrain, shade: c.shade ?? null });
    this.version++;
  }

  removeChunk(c: ChunkData): void {
    if (this.grids.delete(chunkKey(c.x, c.y))) this.version++;
  }

  hasGrid(cx: number, cy: number): boolean {
    return this.grids.has(chunkKey(cx, cy));
  }

  /** The grid of chunk (cx, cy) or undefined (renderers build the terrain mesh from it). */
  grid(cx: number, cy: number): { h: Float32Array; shade: Uint8Array | null } | undefined {
    return this.grids.get(chunkKey(cx, cy));
  }

  /** Bilinear terrain height at (x, y), or null outside the loaded chunks (flat pack: 0). */
  terrainAt(x: number, y: number): number | null {
    if (!this.enabled) return 0;
    const cm = this.chunkM;
    const cx = Math.floor(x / cm), cy = Math.floor(y / cm);
    const g = this.grids.get(chunkKey(cx, cy));
    if (!g) return null;
    return bilinear(g.h, (x - cx * cm) / this.step, (y - cy * cm) / this.step);
  }

  /** Hillshade 0–255 at (x, y) (128 = flat, also outside the loaded chunks and in a flat pack). */
  shadeAt(x: number, y: number): number {
    if (!this.enabled) return 128;
    const cm = this.chunkM;
    const cx = Math.floor(x / cm), cy = Math.floor(y / cm);
    const g = this.grids.get(chunkKey(cx, cy));
    if (!g || !g.shade) return 128;
    return bilinear(g.shade, (x - cx * cm) / this.step, (y - cy * cm) / this.step);
  }

  /** Height of the node nearest to (x, y) (specs/terrain.md: outside the loaded chunks). */
  nearestNodeZ(x: number, y: number): number {
    const g = this.graph;
    const hit = g.nearest(x, y, 400);
    if (!hit) return 0;
    const e = hit.edge;
    const ax = g.nodeXY[2 * e.from]!, ay = g.nodeXY[2 * e.from + 1]!, bx = g.nodeXY[2 * e.to]!, by = g.nodeXY[2 * e.to + 1]!;
    const n = (x - ax) ** 2 + (y - ay) ** 2 <= (x - bx) ** 2 + (y - by) ** 2 ? e.from : e.to;
    return g.nodeZ[n] ?? 0;
  }

  /** Height of an edge's surface under (x, y): projection onto its polyline, linear between vertices. */
  edgeZ(e: RoadEdge, x: number, y: number): number {
    if (!this.enabled || e.z === null) return 0;
    const p = e.pts;
    let best = Infinity, z = e.z[0]!;
    for (let s = 0; s + 1 < e.pointCount; s++) {
      const ax = p[2 * s]!, ay = p[2 * s + 1]!, bx = p[2 * s + 2]!, by = p[2 * s + 3]!;
      const dx = bx - ax, dy = by - ay;
      const l2 = dx * dx + dy * dy;
      const t = l2 === 0 ? 0 : Math.min(1, Math.max(0, ((x - ax) * dx + (y - ay) * dy) / l2));
      const qx = ax + dx * t - x, qy = ay + dy * t - y;
      const d = qx * qx + qy * qy;
      if (d < best) {
        best = d;
        z = e.zOnSeg(s, t);
      }
    }
    return z;
  }

  /**
   * groundZ(x, y, surface) of specs/terrain.md: the edge's surface when `surface` is an edge,
   * else the terrain (the nearest node's height outside the loaded chunks).
   */
  groundZ(x: number, y: number, surface: RoadEdge | null): number {
    if (!this.enabled) return 0;
    if (surface !== null) return this.edgeZ(surface, x, y);
    return this.terrainAt(x, y) ?? this.nearestNodeZ(x, y);
  }

  /** Gradient (m/m) of groundZ at (x, y) by central differences over ±1 m; written to out. */
  grad(x: number, y: number, surface: RoadEdge | null, out: { x: number; y: number }): void {
    if (!this.enabled) {
      out.x = 0;
      out.y = 0;
      return;
    }
    out.x = (this.groundZ(x + 1, y, surface) - this.groundZ(x - 1, y, surface)) / 2;
    out.y = (this.groundZ(x, y + 1, surface) - this.groundZ(x, y - 1, surface)) / 2;
  }

  /**
   * Height of a thing on layer `layer` at (x, y) for drawing: on the ground the terrain, on a
   * bridge or in a tunnel the nearest edge of that layer (trams and loose cars have no edge).
   */
  heightAt(x: number, y: number, layer: number): number {
    if (!this.enabled) return 0;
    if (layer !== 0) {
      const hit = this.graph.nearest(x, y, 30, (e) => e.drawLayer === layer);
      if (hit) return hit.edge.zAt(hit.t * hit.edge.length);
    }
    return this.terrainAt(x, y) ?? this.nearestNodeZ(x, y);
  }

  /** Approximate real elevation (m) of game height z (specs/terrain.md HUD). */
  altitude(z: number): number {
    return this.z0 + z / this.exaggeration;
  }
}

/** Bilinear sample of a TERRAIN_N² grid at fractional grid coordinates (clamped to the grid). */
export function bilinear(h: ArrayLike<number>, u: number, v: number): number {
  const N = TERRAIN_N;
  const i = Math.min(Math.max(Math.floor(u), 0), N - 2), j = Math.min(Math.max(Math.floor(v), 0), N - 2);
  const fu = Math.min(Math.max(u - i, 0), 1), fv = Math.min(Math.max(v - j, 0), 1);
  const a = h[j * N + i]!, b = h[j * N + i + 1]!, c = h[(j + 1) * N + i]!, d = h[(j + 1) * N + i + 1]!;
  return (a * (1 - fu) + b * fu) * (1 - fv) + (c * (1 - fu) + d * fu) * fv;
}

/** Whether the car rides an edge's own surface (specs/terrain.md: ramps, bridges, tunnels). */
export function ridesEdge(e: RoadEdge | null, layer: number, dist: number, margin: number): boolean {
  if (e === null || e.z === null) return false;
  if (layer !== 0) return true;
  const ground = !e.bridge && !e.tunnel && e.layerFrom === 0 && e.layerTo === 0;
  return !ground && dist <= e.width / 2 + margin;
}

/**
 * Collision layer of the player's car on its road edge (specs/terrain.md "Výška pod bodem"): the
 * tracker's layer, except on the layer-0 part of a structure (a bridge, also an Overture level-0
 * one, or a ramp): where its surface stands more than `clear` above the terrain it counts as +1,
 * more than `clear` below it as −1 (level with the ground, at a junction, it stays 0), while the
 * car is on that surface: within width/2 + margin of the axis and at its height (onSurface: a car
 * on the road under a deck stays on 0). Buildings, bollards, trees,
 * water and props of the ground then leave the car alone and the rails keep it on the deck.
 */
export function structureLayer(
  e: RoadEdge, layer: number, dist: number, margin: number, edgeZ: number, terrainZ: number | null, carZ: number, clear: number,
): number {
  if (layer !== 0 || e.z === null) return layer;
  if (!e.bridge && !e.tunnel && e.layerFrom === 0 && e.layerTo === 0) return 0;
  if (dist > e.width / 2 + margin || !onSurface(edgeZ, terrainZ, carZ, clear)) return 0;
  if (terrainZ !== null && edgeZ < terrainZ - clear) return -1;
  return terrainZ !== null && edgeZ > terrainZ + clear ? 1 : 0;
}

/**
 * The car (body height carZ) is on an edge surface at edgeZ, or over it: not more than `clear`
 * below it (a car on the road under a deck is not on the deck; one flying over it will land
 * there). A surface sunk under the terrain (a tunnel mouth) needs both ways, so a car on the
 * ground above does not drop into it.
 */
export function onSurface(edgeZ: number, terrainZ: number | null, carZ: number, clear: number): boolean {
  if (carZ < edgeZ - clear) return false;
  return !(terrainZ !== null && edgeZ < terrainZ - clear) || carZ <= edgeZ + clear;
}

/**
 * structureLayer for a pack without heights: on the layer-0 half of a ramp (an edge changing
 * layer) the car is on the structure's layer (`drawLayer`: +1 bridge, −1 tunnel) while within
 * width/2 + margin of the axis, but only when it got onto the edge along the graph (`linked`: from
 * the ramp), never from a road under it. A level-0 edge stays 0 (nothing tells its height).
 */
export function flatStructureLayer(e: RoadEdge, layer: number, dist: number, margin: number, linked: boolean): number {
  if (layer !== 0 || !linked || e.layerFrom === e.layerTo) return layer;
  return dist > e.width / 2 + margin ? 0 : e.drawLayer;
}
