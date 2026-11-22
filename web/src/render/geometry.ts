import { GroundKind } from '../gen/pb/citypack_pb';
import { tokens } from '../gen/tokens';
import type { Tuning } from '../gen/tuning';
import type { BuildingData, ChunkData } from '../world/chunk';
import { chunkKey, type City, type RoadEdge, type RoadGraph } from '../world/model';
import { extrusionScale, displayHeight, cameraHeight } from '../world/camera';
import { groundColor, rgba, type Palette, type Rgba } from './palette';

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

  quad(ax: number, ay: number, bx: number, by: number, hw: number, h: number, c: Rgba, offset = 0): void {
    const dx = bx - ax, dy = by - ay;
    const l = Math.sqrt(dx * dx + dy * dy);
    if (l < 1e-3) return;
    const nx = -dy / l, ny = dx / l;
    const o0 = offset - hw, o1 = offset + hw;
    const v0 = this.vertex(ax + nx * o0, ay + ny * o0, h, c);
    const v1 = this.vertex(bx + nx * o0, by + ny * o0, h, c);
    const v2 = this.vertex(bx + nx * o1, by + ny * o1, h, c);
    const v3 = this.vertex(ax + nx * o1, ay + ny * o1, h, c);
    this.tri(v0, v1, v2);
    this.tri(v0, v2, v3);
  }

  disc(cx: number, cy: number, r: number, h: number, c: Rgba, segs = 10): void {
    const b = this.vertex(cx, cy, h, c);
    for (let i = 0; i < segs; i++) {
      const a = (i * 2 * Math.PI) / segs;
      this.vertex(cx + r * Math.cos(a), cy + r * Math.sin(a), h, c);
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

/** Heights of the flat layers above the ground plane (m); keeps the draw order of METROPOLE_PLAN 6.3. */
export const Z = {
  ground: [0.0, 0.01, 0.02, 0.03, 0.05] as const, // park, plaza, rail, water, pedestrian
  sidewalk: 0.06, alley: 0.07, asphalt: 0.08, laneLines: 0.09, centerLines: 0.1, roadblock: 0.11,
  skids: 0.12, props: 0.14, car: 0.3,
  tunnelShade: 0.2, tunnel: 0.22, tunnelLines: 0.23,
  bridgeEdge: 0.0, bridgeDeck: 0.02, bridgeLines: 0.04,
} as const;

// Pedestrian-zone paving sits above parks, plazas, rail yards and water (Charles Bridge), below roads (specs/zones.md).
const GROUND_ORDER = [GroundKind.PARK, GroundKind.PLAZA, GroundKind.RAIL, GroundKind.WATER, GroundKind.PEDESTRIAN];

export function groundTris(c: ChunkData, pal: Palette, out: Tris): void {
  GROUND_ORDER.forEach((kind, k) => {
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

/** Road geometry of the whole graph bucketed by chunk (port of world_engine roads.dart). */
export function buildRoads(city: City, tuning: Tuning, pal: Palette): Map<number, RoadChunk> {
  const graph = city.graph;
  const cm = city.chunkM;
  const lift = tuning.layers.deckLiftM;
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
    const n = e.pointCount;
    // Each pass is drawn for the whole edge before the next one, like client F.
    const passes: [Rgba, number, number, 'ground' | 'bridge' | 'tunnel'][] =
      layer < 0 ? [[pal.tunnel, carriage, Z.tunnel, 'tunnel']]
      : layer > 0 ? [[pal.bridgeEdge, hw + 1.2, lift + Z.bridgeEdge, 'bridge'], [pal.bridgeDeck, carriage + 1.0, lift + Z.bridgeDeck, 'bridge']]
      : e.kept ? [[pal.sidewalk, hw, Z.sidewalk, 'ground'], [pal.asphalt, carriage, Z.asphalt, 'ground']]
      : [[pal.alley, hw, Z.alley, 'ground']];
    for (const [col, r, h, which] of passes) {
      for (let s = 0; s + 1 < n; s++) {
        const ax = e.pts[2 * s]!, ay = e.pts[2 * s + 1]!, bx = e.pts[2 * s + 2]!, by = e.pts[2 * s + 3]!;
        const t = bucket((ax + bx) / 2, (ay + by) / 2)[which];
        t.quad(ax, ay, bx, by, r, h, col);
        t.disc(ax, ay, r, h, col);
        if (s + 2 === n) t.disc(bx, by, r, h, col);
      }
    }
    if (e.kept) markings(e, layer, carriage, laneM, lift, pal, bucket);
  }
  roadblocks(graph, bucket);
  return out;
}

function markings(
  e: RoadEdge, layer: number, carriage: number, laneM: number, lift: number, pal: Palette,
  bucket: (x: number, y: number) => RoadChunk,
): void {
  const which = layer < 0 ? 'tunnel' : layer > 0 ? 'bridge' : 'ground';
  const laneH = layer < 0 ? Z.tunnelLines : layer > 0 ? lift + Z.bridgeLines : Z.laneLines;
  const centerH = layer > 0 ? lift + Z.bridgeLines : Z.centerLines;
  const lanes = Math.max(1, Math.round((2 * carriage) / laneM));
  const laneW = (2 * carriage) / lanes;
  const lineHw = 0.3;
  let dist = 0;
  for (let s = 0; s + 1 < e.pointCount; s++) {
    const ax = e.pts[2 * s]!, ay = e.pts[2 * s + 1]!, bx = e.pts[2 * s + 2]!, by = e.pts[2 * s + 3]!;
    const t = bucket((ax + bx) / 2, (ay + by) / 2)[which];
    const dx = bx - ax, dy = by - ay;
    const l = Math.sqrt(dx * dx + dy * dy);
    if (l < 1e-3) continue;
    const twoWay = e.oneway === 0 && lanes >= 2;
    if (twoWay && layer >= 0) {
      t.quad(ax, ay, bx, by, lineHw, centerH, pal.centerLine, -0.5);
      t.quad(ax, ay, bx, by, lineHw, centerH, pal.centerLine, 0.5);
    }
    // Dashed lane dividers: 6 m paint, 9 m gap.
    for (let k = 1; k < lanes; k++) {
      const off = -carriage + k * laneW;
      if (twoWay && Math.abs(off) < laneW / 2) continue;
      let d = (15 - (dist % 15)) % 15;
      while (d < l) {
        const d1 = Math.min(d + 6, l);
        t.quad(ax + (dx * d) / l, ay + (dy * d) / l, ax + (dx * d1) / l, ay + (dy * d1) / l, lineHw, laneH, pal.marking, off);
        d += 15;
      }
    }
    dist += l;
  }
}

/** Striped barriers where a road leaves the playable area. */
function roadblocks(g: RoadGraph, bucket: (x: number, y: number) => RoadChunk): void {
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
        t.rect(x, y, ang, 1, y0, 3.5, y0 + (2 * hw) / stripes, Z.roadblock, i % 2 === 0 ? a : b);
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
export function buildingTris(c: ChunkData, pal: Palette, tuning: Tuning, out: Tris): void {
  const H = cameraHeight(tuning);
  for (const b of c.buildings) building(b, pal, tuning, H, out);
}

function shade(c: Rgba, k: number): Rgba {
  return [Math.min(1, c[0] * k), Math.min(1, c[1] * k), Math.min(1, c[2] * k), 1];
}

function building(b: BuildingData, pal: Palette, tuning: Tuning, H: number, out: Tris): void {
  const z0 = b.minHeight > 0.5 ? displayHeight(extrusionScale(b.minHeight, tuning), H) : 0;
  const z1 = displayHeight(extrusionScale(b.height, tuning), H);
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
  const roofC = shade(base, pal.roofLight * jitter);
  const rb = out.vertexCount;
  for (let i = 0; i < b.xy.length / 2; i++) out.vertex(xy[2 * i]!, xy[2 * i + 1]!, z1, roofC, ROOF_UV, ROOF_UV);
  for (let k = 0; k + 2 < b.roof.length; k += 3) out.tri(rb + b.roof[k]!, rb + b.roof[k + 1]!, rb + b.roof[k + 2]!);
}
