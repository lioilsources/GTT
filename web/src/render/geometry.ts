import { GroundKind } from '../gen/pb/citypack_pb';
import { tokens } from '../gen/tokens';
import type { Tuning } from '../gen/tuning';
import type { BuildingData, ChunkData } from '../world/chunk';
import { chunkKey, type City, type RoadEdge, type RoadGraph, type TrackGraph } from '../world/model';
import { extrusionScale, displayHeight, cameraHeight } from '../world/camera';
import { groundColor, rgba, type Palette, type Rgba } from './palette';
import { cityFlag } from './risograph';
import { TERRAIN_SPEC } from '../drive/slope';
import type { Terrain } from '../world/terrain';

/**
 * Pure geometry for client W: triangles with colours (and UVs for facades) in Babylon axes
 * (X = world x, Y = up, Z = world y). No Babylon import, so it runs in unit tests.
 * The same shapes and draw order as world_engine roads.dart / extrusion.dart; small widths of
 * markings are presentation (P2) and mirror client F.
 */
export class Tris {
  pos: number[] = [];
  col: number[] = [];
  uv: number[] = [];
  idx: number[] = [];

  get vertexCount(): number {
    return this.pos.length / 3;
  }

  vertex(x: number, y: number, h: number, c: Rgba, u = 0, v = 0): number {
    this.pos.push(x, h, y);
    this.col.push(c[0], c[1], c[2], c[3]);
    this.uv.push(u, v);
    return this.vertexCount - 1;
  }

  /** Triangle given counter-clockwise in world x/y (seen from above). */
  tri(a: number, b: number, c: number): void {
    // Materials use ClockWiseSideOrientation: a CCW world triangle is clockwise once swapped.
    this.idx.push(a, c, b);
  }

  /** A strip piece from a to b, hw to each side of `offset`; heights h + za at a, h + zb at b. */
  quad(ax: number, ay: number, bx: number, by: number, hw: number, h: number, c: Rgba, offset = 0, za = 0, zb = za): void {
    const dx = bx - ax, dy = by - ay;
    const l = Math.sqrt(dx * dx + dy * dy);
    if (l < 1e-3) return;
    const nx = -dy / l, ny = dx / l;
    const o0 = offset - hw, o1 = offset + hw;
    const v0 = this.vertex(ax + nx * o0, ay + ny * o0, h + za, c);
    const v1 = this.vertex(bx + nx * o0, by + ny * o0, h + zb, c);
    const v2 = this.vertex(bx + nx * o1, by + ny * o1, h + zb, c);
    const v3 = this.vertex(ax + nx * o1, ay + ny * o1, h + za, c);
    this.tri(v0, v1, v2);
    this.tri(v0, v2, v3);
  }

  /** A disc; on relief tilted to the plane rising by `gx`, `gy` (m/m) so it lies in the road. */
  disc(cx: number, cy: number, r: number, h: number, c: Rgba, segs = 10, gx = 0, gy = 0): void {
    const b = this.vertex(cx, cy, h, c);
    for (let i = 0; i < segs; i++) {
      const a = (i * 2 * Math.PI) / segs;
      const dx = r * Math.cos(a), dy = r * Math.sin(a);
      this.vertex(cx + dx, cy + dy, h + gx * dx + gy * dy, c);
    }
    for (let i = 0; i < segs; i++) this.tri(b, b + 1 + i, b + 1 + ((i + 1) % segs));
  }

  /** Rectangle in a local frame at (ox, oy) rotated by ang, from local (x0, y0) to (x1, y1). */
  rect(ox: number, oy: number, ang: number, x0: number, y0: number, x1: number, y1: number, h: number, c: Rgba): void {
    const cs = Math.cos(ang), sn = Math.sin(ang);
    const p = (x: number, y: number): number => this.vertex(ox + x * cs - y * sn, oy + x * sn + y * cs, h, c);
    const a = p(x0, y0), b = p(x1, y0), d = p(x1, y1), e = p(x0, y1);
    this.tri(a, b, d);
    this.tri(a, d, e);
  }

  get empty(): boolean {
    return this.idx.length === 0;
  }
}

/**
 * Terrain packs (specs/terrain.md): roads and everything on them are drawn this far above their
 * profile, draped ground polygons DRAPE_LIFT above the terrain mesh; covers the road-to-terrain
 * gap the pipeline allows (terrain.pipeline.road_gap_max_m 0.3). Presentation (P2).
 */
export const ROAD_LIFT = 0.4;
export const DRAPE_LIFT = 0.05;
/**
 * On relief the road passes are stacked RELIEF_Z times further apart (sidewalk, asphalt, lines…),
 * so joints of edges with different grades do not show through; things on roads stand on top.
 */
export const RELIEF_Z = 5;
export const VEHICLE_LIFT = ROAD_LIFT + RELIEF_Z * 0.11;
/** Longest drawn piece of a road on relief (m): the pack densifies strips to 8 m (specs/terrain.md). */
export const PIECE_M = 8;

/**
 * Base height of a vehicle or figure at (x, y) on `layer` (Z.car etc. go on top): a flat pack lifts
 * bridges by deck_lift_m; with terrain it is the given height `z` (a lane's profile) or the height
 * of the terrain or of the nearest edge of that layer, plus ROAD_LIFT.
 */
export function baseHeight(terrain: Terrain | null, x: number, y: number, layer: number, deckLift: number, z: number | null = null): number {
  if (!terrain?.enabled) return layer > 0 ? deckLift * layer : 0;
  return (z ?? terrain.heightAt(x, y, layer)) + VEHICLE_LIFT;
}

/** Heights of the flat layers above the ground plane (m); keeps the draw order of METROPOLE_PLAN 6.3. */
export const Z = {
  ground: [0.0, 0.01, 0.02, 0.03, 0.05] as const, // park, plaza, rail, water, pedestrian
  sidewalk: 0.06, alley: 0.07, asphalt: 0.08, laneLines: 0.09, centerLines: 0.1,
  // Style A (specs/style.md v2): zebras over the lane markings, building shadows over the zebras, below rails.
  crosswalks: 0.102, castShadow: 0.103, rails: 0.104, tramStop: 0.106,
  roadblock: 0.11, skids: 0.12, props: 0.14, car: 0.3,
  tunnelShade: 0.2, tunnel: 0.22, tunnelLines: 0.23, tunnelRails: 0.234,
  bridgeEdge: 0.0, bridgeDeck: 0.02, bridgeLines: 0.04, bridgeRails: 0.044,
  /** Parapet band (style A) just above its roof. */
  roofEdgeLift: 0.02,
} as const;

/** Z scaled for relief (RELIEF_Z); the road functions read the active set through RZ. */
const ZR = Object.fromEntries(Object.entries(Z).map(([k, v]) => [k, typeof v === 'number' ? v * RELIEF_Z : v.map((x) => x * RELIEF_Z)])) as unknown as typeof Z;
let RZ: typeof Z = Z;

// Pedestrian-zone paving sits above parks, plazas, rail yards and water (Charles Bridge), below roads (specs/zones.md).
export const GROUND_ORDER = [GroundKind.PARK, GroundKind.PLAZA, GroundKind.RAIL, GroundKind.WATER, GroundKind.PEDESTRIAN];

export function groundTris(c: ChunkData, pal: Palette, out: Tris): void {
  GROUND_ORDER.forEach((kind, k) => {
    // A pack with nature (specs/nature.md): water is the water plane, green the class fills.
    if (c.nature && (kind === GroundKind.WATER || kind === GroundKind.PARK)) return;
    const col = groundColor(pal, kind);
    for (const g of c.ground) {
      if (g.kind !== kind) continue;
      const base = out.vertexCount;
      for (let i = 0; i < g.xy.length; i += 2) out.vertex(g.xy[i]!, g.xy[i + 1]!, Z.ground[k]!, col);
      for (let i = 0; i + 2 < g.indices.length; i += 3) {
        out.tri(base + g.indices[i]!, base + g.indices[i + 1]!, base + g.indices[i + 2]!);
      }
    }
  });
}

/**
 * Bollard positions along the barriers of one chunk (specs/zones.md "Kreslení"), interleaved x, y:
 * one at the start of each line and then every `spacing` metres along it.
 */
export function bollardPoints(c: ChunkData, spacing: number): Float32Array {
  const out: number[] = [];
  if (spacing <= 0) return new Float32Array(0);
  for (const line of c.barriers) {
    if (line.length < 4) continue;
    let next = 0, along = 0;
    for (let i = 0; i + 3 < line.length; i += 2) {
      const ax = line[i]!, ay = line[i + 1]!, bx = line[i + 2]!, by = line[i + 3]!;
      const l = Math.hypot(bx - ax, by - ay);
      while (next <= along + l) {
        const k = l > 0 ? (next - along) / l : 0;
        out.push(ax + (bx - ax) * k, ay + (by - ay) * k);
        next += spacing;
      }
      along += l;
    }
  }
  return Float32Array.from(out);
}

/**
 * One bollard as a unit cylinder (radius 1, height 1, base at 0): shaded walls like building
 * walls and a lit top, colour props.bollard. Instances scale it to radius and display height.
 */
export function bollardTris(pal: Palette, out: Tris, segs = 8): void {
  const base = rgba(tokens.colorPropsBollard);
  for (let i = 0; i < segs; i++) {
    const a0 = (i * 2 * Math.PI) / segs, a1 = ((i + 1) * 2 * Math.PI) / segs, am = (a0 + a1) / 2;
    const light = pal.ambient + (1 - pal.ambient) * Math.max(0, Math.cos(am) * pal.sunX + Math.sin(am) * pal.sunY);
    const col = shade(base, light);
    const ax = Math.cos(a0), ay = Math.sin(a0), bx = Math.cos(a1), by = Math.sin(a1);
    const v0 = out.vertex(ax, ay, 0, col), v1 = out.vertex(bx, by, 0, col);
    const v2 = out.vertex(bx, by, 1, col), v3 = out.vertex(ax, ay, 1, col);
    // CCW ring: clockwise seen from outside = front face, as building walls.
    out.idx.push(v0, v2, v1, v0, v3, v2);
  }
  out.disc(0, 0, 1, 1, shade(base, pal.roofLight), segs);
}

/** Road meshes of one chunk, split by layer. */
export interface RoadChunk {
  ground: Tris;
  bridge: Tris;
  tunnel: Tris;
}

/** One drawn piece of an edge: from (ax, ay, az) to (bx, by, bz); `first`/`last` of its segment. */
export interface Piece {
  ax: number; ay: number; az: number; bx: number; by: number; bz: number; seg: number; first: boolean; last: boolean;
}

/**
 * The pieces an edge is drawn in: its segments, on relief cut to at most `maxLen` metres with
 * heights linear between the vertices (z 0 in a flat pack).
 */
export function edgePieces(e: RoadEdge, maxLen: number, relief = true): Piece[] {
  const out: Piece[] = [];
  for (let s = 0; s + 1 < e.pointCount; s++) {
    const ax = e.pts[2 * s]!, ay = e.pts[2 * s + 1]!, bx = e.pts[2 * s + 2]!, by = e.pts[2 * s + 3]!;
    const l = Math.hypot(bx - ax, by - ay);
    const k = e.z === null || !relief ? 1 : Math.max(1, Math.ceil(l / maxLen));
    for (let i = 0; i < k; i++) {
      const f0 = i / k, f1 = (i + 1) / k;
      out.push({
        ax: ax + (bx - ax) * f0, ay: ay + (by - ay) * f0, az: relief ? e.zOnSeg(s, f0) : 0,
        bx: ax + (bx - ax) * f1, by: ay + (by - ay) * f1, bz: relief ? e.zOnSeg(s, f1) : 0, seg: s, first: i === 0, last: i === k - 1,
      });
    }
  }
  return out;
}

/** Height of a point on the road network: the nearest edge of `layer` (any edge as fallback). */
export function networkZ(g: RoadGraph, x: number, y: number, layer: number): number {
  const hit = g.nearest(x, y, 25, (e) => e.z !== null && e.drawLayer === layer) ?? g.nearest(x, y, 200, (e) => e.z !== null);
  return hit ? hit.edge.zAt(hit.t * hit.edge.length) : 0;
}

/** Road geometry of the whole graph bucketed by chunk (port of world_engine roads.dart). */
export function buildRoads(city: City, tuning: Tuning, pal: Palette): Map<number, RoadChunk> {
  const relief = city.terrain.enabled;
  // Flat pack: bridges at deck_lift_m (DUALSTACK 6.2); with terrain every road at its real height.
  const lift = relief ? 0 : tuning.layers.deckLiftM;
  const base = relief ? ROAD_LIFT : 0;
  RZ = relief ? ZR : Z;
  try {
    return roadsOf(city, tuning, pal, relief, lift, base);
  } finally {
    RZ = Z;
  }
}

function roadsOf(city: City, tuning: Tuning, pal: Palette, relief: boolean, lift: number, base: number): Map<number, RoadChunk> {
  const graph = city.graph;
  const cm = city.chunkM;
  const out = new Map<number, RoadChunk>();
  const bucket = (x: number, y: number): RoadChunk => {
    const k = chunkKey(Math.floor(x / cm), Math.floor(y / cm));
    let r = out.get(k);
    if (!r) out.set(k, (r = { ground: new Tris(), bridge: new Tris(), tunnel: new Tris() }));
    return r;
  };
  const sidewalkM = tuning.sidewalkWidthM, laneM = tuning.laneWidthM;

  for (const e of graph.edges) {
    const layer = e.drawLayer;
    const hw = e.width / 2;
    const carriage = e.kept ? Math.max(e.width - 2 * sidewalkM, laneM) / 2 : hw;
    const pieces = edgePieces(e, PIECE_M, relief);
    // Each pass is drawn for the whole edge before the next one, like client F.
    const passes: [Rgba, number, number, 'ground' | 'bridge' | 'tunnel'][] =
      layer < 0 ? [[pal.tunnel, carriage, base + RZ.tunnel, 'tunnel']]
      : layer > 0 ? [[pal.bridgeEdge, hw + 1.2, base + lift + RZ.bridgeEdge, 'bridge'], [pal.bridgeDeck, carriage + 1.0, base + lift + RZ.bridgeDeck, 'bridge']]
      : e.kept ? [[pal.sidewalk, hw, base + RZ.sidewalk, 'ground'], [pal.asphalt, carriage, base + RZ.asphalt, 'ground']]
      : [[pal.alley, hw, base + RZ.alley, 'ground']];
    // Joint discs lie in the road's plane at the vertex (mean of the grades in and out).
    const slope = (s: number): [number, number] => {
      let gx = 0, gy = 0, n = 0;
      for (const k of [s - 1, s]) {
        if (k < 0 || k + 1 >= e.pointCount) continue;
        const l = e.cum[k + 1]! - e.cum[k]!;
        if (l < 1e-6) continue;
        const g = e.gradeOfSeg(k);
        gx += (g * (e.pts[2 * k + 2]! - e.pts[2 * k]!)) / l;
        gy += (g * (e.pts[2 * k + 3]! - e.pts[2 * k + 1]!)) / l;
        n++;
      }
      return n > 0 ? [gx / n, gy / n] : [0, 0];
    };
    // Joints need a disc only where the edge bends (densified vertices on a straight line do not).
    const turn = (s: number): number => {
      const ax = e.pts[2 * s]! - e.pts[2 * s - 2]!, ay = e.pts[2 * s + 1]! - e.pts[2 * s - 1]!;
      const bx = e.pts[2 * s + 2]! - e.pts[2 * s]!, by = e.pts[2 * s + 3]! - e.pts[2 * s + 1]!;
      return Math.abs(Math.atan2(ax * by - ay * bx, ax * bx + ay * by));
    };
    for (const [col, r, h, which] of passes) {
      for (const p of pieces) {
        const t = bucket((p.ax + p.bx) / 2, (p.ay + p.by) / 2)[which];
        t.quad(p.ax, p.ay, p.bx, p.by, r, h, col, 0, p.az, p.bz);
        if (p.first && (!relief || p.seg === 0 || turn(p.seg) > 0.1)) t.disc(p.ax, p.ay, r, h + p.az, col, 10, ...(relief ? slope(p.seg) : [0, 0] as const));
        if (p.last && p.seg + 2 === e.pointCount) t.disc(p.bx, p.by, r, h + p.bz, col, 10, ...(relief ? slope(p.seg + 1) : [0, 0] as const));
      }
    }
    if (relief && layer > 0) bridgeSides(pieces, hw + 1.2, base, pal, (x, y) => bucket(x, y).bridge);
    if (e.kept) markings(e, pieces, layer, carriage, laneM, base, layer > 0 ? lift : 0, pal, bucket);
    if (relief && layer >= 0 && !e.stairs) uphillArrows(e, layer, base, pal, bucket);
  }
  if (relief) tunnelPortals(graph, base, pal, (x, y) => bucket(x, y).ground);
  const zArm = relief ? (x: number, y: number): number => networkZ(graph, x, y, 0) : null;
  if (cityFlag(tuning.style.crosswalks, city.id, pal.night)) {
    crosswalkTris(graph, tuning, pal.marking, (x, y) => bucket(x, y).ground, base, zArm);
  }
  tramTracks(city, tuning, bucket, base);
  roadblocks(graph, bucket, base, relief);
  return out;
}

/** Darker shade of a colour (presentation: railings and portals derive from the palette). */
function dim(c: Rgba, k: number): Rgba {
  return [c[0] * k, c[1] * k, c[2] * k, c[3]];
}

/**
 * Bridge sides on relief (specs/terrain.md "Vykreslení terénu", W): a railing on both deck edges
 * and a fascia wall hanging 2 m under the deck, so the profile reads in the perspective view.
 */
function bridgeSides(pieces: Piece[], half: number, base: number, pal: Palette, put: (x: number, y: number) => Tris): void {
  const rail = dim(pal.bridgeEdge, 0.55), wall = dim(pal.bridgeEdge, 0.75);
  for (const p of pieces) {
    const dx = p.bx - p.ax, dy = p.by - p.ay;
    const l = Math.hypot(dx, dy);
    if (l < 1e-3) continue;
    const nx = -dy / l, ny = dx / l;
    const t = put((p.ax + p.bx) / 2, (p.ay + p.by) / 2);
    for (const side of [-1, 1]) {
      // Railing: a 0.7 m band 1.1 m above the deck at the outer edge.
      t.quad(p.ax, p.ay, p.bx, p.by, 0.35, base + RZ.bridgeRails + 1.1, rail, side * (half - 0.35), p.az, p.bz);
      // Fascia: a vertical wall along the edge, both faces.
      const ox = nx * side * half, oy = ny * side * half;
      const top = base + RZ.bridgeEdge, bot = top - 2;
      const v0 = t.vertex(p.ax + ox, p.ay + oy, p.az + top, wall), v1 = t.vertex(p.bx + ox, p.by + oy, p.bz + top, wall);
      const v2 = t.vertex(p.bx + ox, p.by + oy, p.bz + bot, wall), v3 = t.vertex(p.ax + ox, p.ay + oy, p.az + bot, wall);
      t.idx.push(v0, v1, v2, v0, v2, v3, v0, v2, v1, v0, v3, v2);
    }
  }
}

/**
 * Uphill arrows (specs/terrain.md "Nápovědy reliéfu shora"): on segments steeper than 8 %, a
 * chevron in the marking colour every 24 m along the edge, pointing uphill.
 */
function uphillArrows(e: RoadEdge, layer: number, base: number, pal: Palette, bucket: (x: number, y: number) => RoadChunk): void {
  const which = layer > 0 ? 'bridge' : 'ground';
  const h = base + (layer > 0 ? RZ.bridgeLines : RZ.centerLines) + 0.002;
  const sp = TERRAIN_SPEC.arrowSpacingM;
  for (let s = 0; s + 1 < e.pointCount; s++) {
    const g = e.gradeOfSeg(s);
    if (Math.abs(g) <= TERRAIN_SPEC.arrowGrade) continue;
    const d0 = e.cum[s]!, d1 = e.cum[s + 1]!, l = d1 - d0;
    const ax = e.pts[2 * s]!, ay = e.pts[2 * s + 1]!, bx = e.pts[2 * s + 2]!, by = e.pts[2 * s + 3]!;
    const ux = ((bx - ax) / l) * Math.sign(g), uy = ((by - ay) / l) * Math.sign(g);
    const rise = Math.abs(g);
    for (let d = Math.ceil((d0 - sp / 2) / sp) * sp + sp / 2; d < d1; d += sp) {
      const f = (d - d0) / l;
      const x = ax + (bx - ax) * f, y = ay + (by - ay) * f, z = e.zOnSeg(s, f);
      const t = bucket(x, y)[which];
      // Chevron: tip 2 m uphill, wings 1.6 m back and 1.4 m aside, 0.9 m thick.
      const tipX = x + ux * 2, tipY = y + uy * 2;
      for (const side of [-1, 1]) {
        const wx = x - ux * 1.6 - uy * side * 1.4, wy = y - uy * 1.6 + ux * side * 1.4;
        t.quad(wx, wy, tipX, tipY, 0.45, h, pal.marking, 0, z - rise * 1.6, z + rise * 2);
      }
    }
  }
}

/**
 * Tunnel portals on relief: where a tunnel edge meets a road that is not a tunnel, a dark mouth
 * across the road on the tunnel side with a frame (from above, the tunnel roof stays hidden).
 */
function tunnelPortals(g: RoadGraph, base: number, pal: Palette, put: (x: number, y: number) => Tris): void {
  const mouth = dim(pal.tunnel, 0.45), frame = dim(pal.bridgeEdge, 0.6);
  for (let n = 0; n < g.nodeEdges.length; n++) {
    const ids = g.nodeEdges[n]!;
    if (!ids.some((i) => g.edges[i]!.drawLayer >= 0)) continue;
    for (const i of ids) {
      const e = g.edges[i]!;
      if (e.drawLayer >= 0 || e.pointCount < 2) continue;
      const k = e.to === n ? e.pointCount - 2 : 1;
      const x = g.nodeXY[2 * n]!, y = g.nodeXY[2 * n + 1]!, z = g.nodeZ[n]!;
      const ang = Math.atan2(e.pts[2 * k + 1]! - y, e.pts[2 * k]! - x);
      const hw = e.width / 2 + 1;
      const t = put(x, y);
      t.rect(x, y, ang, 0, -hw, 6, hw, base + z + RZ.roadblock, mouth);
      t.rect(x, y, ang, -0.8, -hw - 0.8, 0, hw + 0.8, base + z + RZ.roadblock + 0.01, frame);
    }
  }
}

/** Half width of one drawn rail (m); presentation (P2), like the marking widths. */
const RAIL_HW = 0.2;

/**
 * Tram tracks (specs/trams.md "Kreslení"): two rails rail_gauge_m apart along every track edge,
 * above the asphalt and markings, below cars; stops as a platform beside the track. On relief the
 * rails follow the road they run on (tracks carry no heights of their own).
 */
function tramTracks(city: City, tuning: Tuning, bucket: (x: number, y: number) => RoadChunk, base: number): void {
  const g = city.trams;
  if (g.isEmpty) return;
  const relief = city.terrain.enabled;
  const t = tuning.trams;
  const lift = relief ? 0 : tuning.layers.deckLiftM;
  const rail = rgba(tokens.colorTramsRail), stopCol = rgba(tokens.colorTramsStop);
  const half = t.railGaugeM / 2;
  const zAt = (x: number, y: number, layer: number): number => (relief ? networkZ(city.graph, x, y, layer) : 0);
  for (const e of g.edges) {
    const layer = e.drawLayer;
    const which = layer < 0 ? 'tunnel' : layer > 0 ? 'bridge' : 'ground';
    const h = base + (layer < 0 ? RZ.tunnelRails : layer > 0 ? lift + RZ.bridgeRails : RZ.rails);
    for (let s = 0; s + 1 < e.pointCount; s++) {
      const ax = e.pts[2 * s]!, ay = e.pts[2 * s + 1]!, bx = e.pts[2 * s + 2]!, by = e.pts[2 * s + 3]!;
      const dx = bx - ax, dy = by - ay;
      const l = Math.sqrt(dx * dx + dy * dy);
      if (l < 1e-3) continue;
      // Overlap the joints a little so bends have no gaps.
      const ex = (dx / l) * RAIL_HW, ey = (dy / l) * RAIL_HW;
      const k = relief ? Math.max(1, Math.ceil(l / PIECE_M)) : 1;
      let pz = zAt(ax, ay, layer);
      for (let i = 0; i < k; i++) {
        const px = ax + (dx * i) / k, py = ay + (dy * i) / k, qx = ax + (dx * (i + 1)) / k, qy = ay + (dy * (i + 1)) / k;
        const qz = zAt(qx, qy, layer);
        const tr = bucket((px + qx) / 2, (py + qy) / 2)[which];
        tr.quad(px - ex, py - ey, qx + ex, qy + ey, RAIL_HW, h, rail, -half, pz, qz);
        tr.quad(px - ex, py - ey, qx + ex, qy + ey, RAIL_HW, h, rail, half, pz, qz);
        pz = qz;
      }
    }
  }
  // Platform as long as a whole tram, beside the track on the right of from → to.
  const len = t.carsPerTram * t.carLengthM + Math.max(0, t.carsPerTram - 1) * t.jointGapM;
  const w = t.carWidthM / 4, off = t.carWidthM / 2 + w;
  for (const st of g.stops) {
    const ang = Math.atan2(st.dirY, st.dirX);
    const z = zAt(st.x, st.y, g.edges[st.edge]?.drawLayer ?? 0);
    bucket(st.x, st.y).ground.rect(st.x, st.y, ang, -len / 2, -off - w, len / 2, -off + w, base + z + RZ.tramStop, stopCol);
  }
}

function markings(
  e: RoadEdge, pieces: Piece[], layer: number, carriage: number, laneM: number, base: number, lift: number, pal: Palette,
  bucket: (x: number, y: number) => RoadChunk,
): void {
  const which = layer < 0 ? 'tunnel' : layer > 0 ? 'bridge' : 'ground';
  const laneH = base + (layer < 0 ? RZ.tunnelLines : layer > 0 ? lift + RZ.bridgeLines : RZ.laneLines);
  const centerH = base + (layer > 0 ? lift + RZ.bridgeLines : RZ.centerLines);
  const lanes = Math.max(1, Math.round((2 * carriage) / laneM));
  const laneW = (2 * carriage) / lanes;
  const lineHw = 0.3;
  let dist = 0;
  for (const p of pieces) {
    const ax = p.ax, ay = p.ay, bx = p.bx, by = p.by;
    const t = bucket((ax + bx) / 2, (ay + by) / 2)[which];
    const dx = bx - ax, dy = by - ay;
    const l = Math.sqrt(dx * dx + dy * dy);
    if (l < 1e-3) continue;
    const zAt = (d: number): number => p.az + ((p.bz - p.az) * d) / l;
    const twoWay = e.oneway === 0 && lanes >= 2;
    if (twoWay && layer >= 0) {
      t.quad(ax, ay, bx, by, lineHw, centerH, pal.centerLine, -0.5, p.az, p.bz);
      t.quad(ax, ay, bx, by, lineHw, centerH, pal.centerLine, 0.5, p.az, p.bz);
    }
    // Dashed lane dividers: 6 m paint, 9 m gap.
    for (let k = 1; k < lanes; k++) {
      const off = -carriage + k * laneW;
      if (twoWay && Math.abs(off) < laneW / 2) continue;
      let d = (15 - (dist % 15)) % 15;
      while (d < l) {
        const d1 = Math.min(d + 6, l);
        t.quad(ax + (dx * d) / l, ay + (dy * d) / l, ax + (dx * d1) / l, ay + (dy * d1) / l, lineHw, laneH, pal.marking, off, zAt(d), zAt(d1));
        d += 15;
      }
    }
    dist += l;
  }
}

/** Half width of the carriageway (without sidewalks) of an edge, as the asphalt pass draws it. */
function carriageHalf(e: RoadEdge, tuning: Tuning): number {
  return e.kept ? Math.max(e.width - 2 * tuning.sidewalkWidthM, tuning.laneWidthM) / 2 : e.width / 2;
}

/** Kept ground edges meeting node n, one entry per end (a self-loop meets it twice). */
function groundEnds(g: RoadGraph, n: number): { e: RoadEdge; rev: boolean }[] {
  const ends: { e: RoadEdge; rev: boolean }[] = [];
  for (const ei of new Set(g.nodeEdges[n]!)) {
    const e = g.edges[ei]!;
    if (!e.kept || !e.isGround) continue;
    if (e.from === n) ends.push({ e, rev: false });
    if (e.to === n) ends.push({ e, rev: true });
  }
  return ends;
}

/**
 * The street leaving node n along one edge end, as a polyline from the node outward: it goes on
 * through nodes with exactly two kept ground edges until it is [need] metres long, reaches
 * another junction or a dead end, or comes back to n (specs/style.md v2 "Zebry"; the packs split
 * roads at every connector). Same walk as world_engine style_geometry.dart `_street`.
 */
export function roadArm(g: RoadGraph, n: number, start: { e: RoadEdge; rev: boolean }, need: number): { pts: number[]; length: number } {
  const pts: number[] = [];
  let length = 0, cur = start;
  const seen = new Set<RoadEdge>();
  while (!seen.has(cur.e)) {
    seen.add(cur.e);
    const e = cur.e, k = e.pointCount;
    for (let i = pts.length === 0 ? 0 : 1; i < k; i++) {
      const j = cur.rev ? k - 1 - i : i;
      pts.push(e.pts[2 * j]!, e.pts[2 * j + 1]!);
    }
    length += e.length;
    const at = cur.rev ? e.from : e.to;
    if (length >= need || at === n) break;
    const ends = groundEnds(g, at);
    if (ends.length !== 2) break;
    // Leave by the other end than the one we came in by (entering end has rev !== cur.rev).
    cur = ends[0]!.e === e && ends[0]!.rev !== cur.rev ? ends[1]! : ends[0]!;
  }
  return { pts, length };
}

/**
 * Stripes of one crossing between distances d0 and d1 along [pts], following its bends: stripe =
 * gap = [stripe], parallel to the road, from the carriageway edge −half, the last one clipped at +half.
 */
function crossingTris(
  pts: number[], d0: number, d1: number, half: number, stripe: number, col: Rgba, put: (x: number, y: number) => Tris,
  base: number, zAt: ((x: number, y: number) => number) | null,
): void {
  let dist = 0;
  for (let i = 0; i + 3 < pts.length && dist < d1; i += 2) {
    const ax = pts[i]!, ay = pts[i + 1]!, bx = pts[i + 2]!, by = pts[i + 3]!;
    const l = Math.hypot(bx - ax, by - ay);
    if (l < 1e-6) continue;
    const t0 = Math.max(d0 - dist, 0), t1 = Math.min(d1 - dist, l);
    dist += l;
    if (t1 <= t0) continue;
    const ux = (bx - ax) / l, uy = (by - ay) / l;
    const sx = ax + ux * t0, sy = ay + uy * t0, ex = ax + ux * t1, ey = ay + uy * t1;
    const t = put((sx + ex) / 2, (sy + ey) / 2);
    const za = zAt ? zAt(sx, sy) : 0, zb = zAt ? zAt(ex, ey) : 0;
    for (let o = -half; o < half - 1e-6; o += 2 * stripe) {
      const o1 = Math.min(o + stripe, half);
      t.quad(sx, sy, ex, ey, (o1 - o) / 2, base + RZ.crosswalks, col, (o + o1) / 2, za, zb);
    }
  }
}

/**
 * Zebra crossings (specs/style.md v2 "Zebry"): at every node with at least three kept ground
 * edges, each of them gets a crossing from c to c + crosswalk_len_m away from the node along its
 * street (roadArm), where c = max(half width of the node's other such edges) + crosswalk_gap_m;
 * none on a street shorter than 2 (c + len). Stripes span the carriageway of the junction's edge.
 */
export function crosswalkTris(
  g: RoadGraph, tuning: Tuning, col: Rgba, put: (x: number, y: number) => Tris,
  base = 0, zAt: ((x: number, y: number) => number) | null = null,
): void {
  const st = tuning.style;
  const len = st.crosswalkLenM, sw = st.crosswalkStripeM;
  if (len <= 0 || sw <= 0) return;
  for (let n = 0; n < g.nodeEdges.length; n++) {
    const ends = groundEnds(g, n);
    if (ends.length < 3) continue;
    for (let i = 0; i < ends.length; i++) {
      let half = 0;
      for (let j = 0; j < ends.length; j++) if (j !== i) half = Math.max(half, ends[j]!.e.width / 2);
      const c = half + st.crosswalkGapM;
      const arm = roadArm(g, n, ends[i]!, 2 * (c + len));
      if (arm.length < 2 * (c + len)) continue;
      crossingTris(arm.pts, c, c + len, carriageHalf(ends[i]!.e, tuning), sw, col, put, base, zAt);
    }
  }
}

/** Striped barriers where a road leaves the playable area. */
function roadblocks(g: RoadGraph, bucket: (x: number, y: number) => RoadChunk, base: number, relief: boolean): void {
  const a = rgba(tokens.colorWorldRoadblockA), b = rgba(tokens.colorWorldRoadblockB);
  for (let n = 0; n < g.border.length; n++) {
    if (!g.border[n]) continue;
    const x = g.nodeXY[2 * n]!, y = g.nodeXY[2 * n + 1]!;
    for (const ei of g.nodeEdges[n]!) {
      const e = g.edges[ei]!;
      const k = e.to === n ? e.pointCount - 2 : 1;
      const ang = Math.atan2(e.pts[2 * k + 1]! - y, e.pts[2 * k]! - x);
      const hw = e.width / 2;
      const stripes = 8;
      const t = bucket(x, y).ground;
      for (let i = 0; i < stripes; i++) {
        const y0 = -hw + (i * 2 * hw) / stripes;
        t.rect(x, y, ang, 1, y0, 3.5, y0 + (2 * hw) / stripes, base + (relief ? g.nodeZ[n]! : 0) + RZ.roadblock, i % 2 === 0 ? a : b);
      }
    }
  }
}

/** Window texture tiling: one window cell is 4 m wide and 3.2 m tall, 64 px of a 256 px texture. */
export const TEX_SIZE = 256;
const U_PER_M = 16 / TEX_SIZE;
const V_PER_M = 20 / TEX_SIZE;
const ROOF_UV = 2 / TEX_SIZE;

/**
 * Building masses of one chunk in true 3D at the display height z = H·(1 − 1/s(h)) (DUALSTACK 6.2),
 * so a camera at H straight above gives the same image as the 2.5D extrusion of client F.
 */
export function buildingTris(c: ChunkData, pal: Palette, tuning: Tuning, out: Tris, relief = true): void {
  const H = cameraHeight(tuning);
  for (const b of c.buildings) building(b, pal, tuning, H, out, relief);
}

function shade(c: Rgba, k: number): Rgba {
  return [Math.min(1, c[0] * k), Math.min(1, c[1] * k), Math.min(1, c[2] * k), 1];
}

function building(b: BuildingData, pal: Palette, tuning: Tuning, H: number, out: Tris, relief: boolean): void {
  // On relief the mass stands on base_z, the lowest terrain under it (specs/terrain.md): the wall
  // on the uphill side reaches below the terrain.
  const zBase = relief ? (b.baseZ ?? 0) : 0;
  const z0 = zBase + (b.minHeight > 0.5 ? displayHeight(extrusionScale(b.minHeight, tuning), H) : 0);
  const z1 = zBase + displayHeight(extrusionScale(b.height, tuning), H);
  const base = b.landmark > 0 ? pal.landmark : pal.facades[b.seed % pal.facades.length]!;
  const jitter = 0.94 + (((b.seed >> 8) & 0xff) / 255) * 0.12;
  const uOff = ((b.seed >> 16) & 0xff) / TEX_SIZE;
  const vBot = b.minHeight * V_PER_M, vTop = b.height * V_PER_M;
  const xy = b.xy;
  let start = 0;
  for (const end of b.ringEnds) {
    for (let i = start; i < end; i++) {
      const j = i + 1 < end ? i + 1 : start;
      const ax = xy[2 * i]!, ay = xy[2 * i + 1]!, bx = xy[2 * j]!, by = xy[2 * j + 1]!;
      const ex = bx - ax, ey = by - ay;
      const len = Math.sqrt(ex * ex + ey * ey);
      if (len < 0.05) continue;
      // Outward normal (rings are CCW outer, CW holes).
      const nx = ey / len, ny = -ex / len;
      const light = pal.ambient + (1 - pal.ambient) * Math.max(0, nx * pal.sunX + ny * pal.sunY);
      const col = shade(base, light * jitter);
      const u0 = uOff + b.wallU[i]! * U_PER_M, u1 = u0 + len * U_PER_M;
      const v0 = out.vertex(ax, ay, z0, col, u0, vBot);
      const v1 = out.vertex(bx, by, z0, col, u1, vBot);
      const v2 = out.vertex(bx, by, z1, col, u1, vTop);
      const v3 = out.vertex(ax, ay, z1, col, u0, vTop);
      // Clockwise seen from outside the wall = front face (materials use ClockWiseSideOrientation).
      out.idx.push(v0, v2, v1, v0, v3, v2);
    }
    start = end;
  }
  // Style A (specs/style.md v2): a flat light roof with a parapet band; landmarks keep v1.
  const flat = b.landmark <= 0 && pal.roof !== undefined && pal.roofEdge !== undefined;
  const roofC = flat ? shade(pal.roof!, jitter) : shade(base, pal.roofLight * jitter);
  const rb = out.vertexCount;
  for (let i = 0; i < b.xy.length / 2; i++) out.vertex(xy[2 * i]!, xy[2 * i + 1]!, z1, roofC, ROOF_UV, ROOF_UV);
  for (let k = 0; k + 2 < b.roof.length; k += 3) out.tri(rb + b.roof[k]!, rb + b.roof[k + 1]!, rb + b.roof[k + 2]!);
  if (flat) roofEdgeTris(b, tuning.style.roofEdgeM, z1 + Z.roofEdgeLift, pal.roofEdge!, out);
}

/**
 * Parapet band (specs/style.md v2 "Střechy"): along every ring edge a strip [w] wide on the inner
 * side (left of the edge: rings are CCW outer, CW courtyards). Corners need not meet exactly.
 */
export function roofEdgeTris(b: BuildingData, w: number, h: number, col: Rgba, out: Tris): void {
  if (w <= 0) return;
  const xy = b.xy;
  let start = 0;
  for (const end of b.ringEnds) {
    for (let i = start; i < end; i++) {
      const j = i + 1 < end ? i + 1 : start;
      const ax = xy[2 * i]!, ay = xy[2 * i + 1]!, bx = xy[2 * j]!, by = xy[2 * j + 1]!;
      const len = Math.hypot(bx - ax, by - ay);
      if (len < 0.05) continue;
      const nx = (-(by - ay) / len) * w, ny = ((bx - ax) / len) * w;
      const v0 = out.vertex(ax, ay, h, col, ROOF_UV, ROOF_UV);
      const v1 = out.vertex(bx, by, h, col, ROOF_UV, ROOF_UV);
      const v2 = out.vertex(bx + nx, by + ny, h, col, ROOF_UV, ROOF_UV);
      const v3 = out.vertex(ax + nx, ay + ny, h, col, ROOF_UV, ROOF_UV);
      out.tri(v0, v1, v2);
      out.tri(v0, v2, v3);
    }
    start = end;
  }
}

/** Cast shadow length (specs/style.md v2): min(height × shadow_ratio, shadow_max_m). */
export function shadowLength(height: number, tuning: Tuning): number {
  return Math.max(0, Math.min(height * tuning.style.shadowRatio, tuning.style.shadowMaxM));
}

/**
 * Ground shadows of one chunk's buildings (specs/style.md v2 "Vržené stíny"), all at Z.castShadow
 * in [pal.castShadow]. Only buildings standing on the ground (minHeight 0) cast; the sun is
 * the palette's (light.day). Empty without a castShadow colour or sun.
 */
export function castShadowTris(
  c: ChunkData, pal: Palette, tuning: Tuning, out: Tris, zAt: ((x: number, y: number) => number) | null = null,
): void {
  const col = pal.castShadow;
  const sl = Math.hypot(pal.sunX, pal.sunY);
  if (!col || sl < 1e-6) return;
  const sx = -pal.sunX / sl, sy = -pal.sunY / sl;
  for (const b of c.buildings) {
    if (b.minHeight > 0) continue;
    buildingShadow(b, shadowLength(b.height, tuning), sx, sy, Z.castShadow + (zAt ? DRAPE_LIFT + 0.3 : 0), col, out, zAt);
  }
}

/**
 * Shadow of one prism on flat ground: the footprint moved by L·s, plus for every ring edge the
 * quad (a, b, b + L·s, a + L·s), wound counter-clockwise. The union is not computed; overlaps
 * are flattened by the renderer.
 */
export function buildingShadow(
  b: BuildingData, L: number, sx: number, sy: number, h: number, col: Rgba, out: Tris,
  zAt: ((x: number, y: number) => number) | null = null,
): void {
  if (L <= 1e-3) return;
  const dx = sx * L, dy = sy * L;
  const xy = b.xy;
  const base = out.vertexCount;
  // On relief every vertex lies on the terrain under it (the shadow drapes over the slope).
  const z = zAt ?? ((): number => 0);
  for (let i = 0; i < xy.length / 2; i++) out.vertex(xy[2 * i]! + dx, xy[2 * i + 1]! + dy, h + z(xy[2 * i]! + dx, xy[2 * i + 1]! + dy), col);
  for (let k = 0; k + 2 < b.roof.length; k += 3) out.tri(base + b.roof[k]!, base + b.roof[k + 1]!, base + b.roof[k + 2]!);
  let start = 0;
  for (const end of b.ringEnds) {
    for (let i = start; i < end; i++) {
      const j = i + 1 < end ? i + 1 : start;
      const ax = xy[2 * i]!, ay = xy[2 * i + 1]!, bx = xy[2 * j]!, by = xy[2 * j + 1]!;
      const cross = (bx - ax) * dy - (by - ay) * dx;
      if (Math.abs(cross) < 1e-4) continue;
      const v0 = out.vertex(ax, ay, h + z(ax, ay), col), v1 = out.vertex(bx, by, h + z(bx, by), col);
      const v2 = out.vertex(bx + dx, by + dy, h + z(bx + dx, by + dy), col), v3 = out.vertex(ax + dx, ay + dy, h + z(ax + dx, ay + dy), col);
      if (cross > 0) {
        out.tri(v0, v1, v2);
        out.tri(v0, v2, v3);
      } else {
        out.tri(v0, v2, v1);
        out.tri(v0, v3, v2);
      }
    }
    start = end;
  }
}
