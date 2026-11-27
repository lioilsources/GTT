import { fromBinary } from '@bufbuild/protobuf';

import { ModelsSchema, type Models } from '../gen/pb/citypack_pb';
import { gunzip, type PackSource } from './citypack';
import { chunkKey } from './model';

/** One source building of a landmark model (specs/models.md, ModelPart) in world metres. */
export interface ModelPartData {
  /** Anchor (m). */
  ax: number;
  ay: number;
  /** Game height of the foot (m). */
  baseZ: number;
  /** x, y absolute (m), z real metres above the foot. */
  pos: Float32Array;
  tris: Uint32Array;
  roles: Uint8Array;
}

/** A roof-plan polygon (PlanPoly) in world metres. */
export interface PlanPolyData {
  xy: Float32Array;
  ringEnds: Int32Array;
  tris: Uint32Array;
  height: number;
  shade: number;
  baseZ: number;
}

export interface ModelData {
  landmarkId: string;
  parts: ModelPartData[];
  plan: PlanPolyData[];
  /** Pack buildings hidden while the model is drawn: chunk key → indices into Chunk.buildings. */
  replaces: Map<number, Set<number>>;
  /** Chunk whose loading builds the model's meshes (the first part's anchor). */
  homeChunk: number;
  /** Bounding box of the roof plan (m). */
  minX: number; minY: number; maxX: number; maxY: number;
  tris: number;
}

/** models.pb → world data; an empty list for a pack without models (specs/citypack.md v5). */
export function prepareModels(m: Models, chunkM: number): ModelData[] {
  const out: ModelData[] = [];
  for (const md of m.models) {
    if (md.parts.length === 0) continue;
    const parts = md.parts.map((p): ModelPartData => {
      const ax = p.anchorX / 10, ay = p.anchorY / 10;
      const pos = new Float32Array(p.positions.length);
      for (let i = 0; i + 2 < p.positions.length; i += 3) {
        pos[i] = ax + p.positions[i]! / 10;
        pos[i + 1] = ay + p.positions[i + 1]! / 10;
        pos[i + 2] = p.positions[i + 2]! / 10;
      }
      return { ax, ay, baseZ: p.baseZDm / 10, pos, tris: Uint32Array.from(p.triangles), roles: Uint8Array.from(p.roles) };
    });
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    const plan = md.roofPlan.map((pp): PlanPolyData => {
      const xy = Float32Array.from(pp.points, (v) => v / 10);
      for (let i = 0; i + 1 < xy.length; i += 2) {
        minX = Math.min(minX, xy[i]!); maxX = Math.max(maxX, xy[i]!);
        minY = Math.min(minY, xy[i + 1]!); maxY = Math.max(maxY, xy[i + 1]!);
      }
      return {
        xy, ringEnds: Int32Array.from(pp.ringEnds.length ? pp.ringEnds : [xy.length >> 1]), tris: Uint32Array.from(pp.triangles),
        height: pp.heightM, shade: pp.shade, baseZ: pp.baseZDm / 10,
      };
    });
    if (!Number.isFinite(minX)) {
      for (const p of parts) {
        minX = Math.min(minX, p.ax); maxX = Math.max(maxX, p.ax);
        minY = Math.min(minY, p.ay); maxY = Math.max(maxY, p.ay);
      }
    }
    const replaces = new Map<number, Set<number>>();
    for (const r of md.replaces) {
      const k = chunkKey(r.chunkX, r.chunkY);
      let s = replaces.get(k);
      if (!s) replaces.set(k, (s = new Set()));
      s.add(r.index);
    }
    const p0 = parts[0]!;
    out.push({
      landmarkId: md.landmarkId, parts, plan, replaces, minX, minY, maxX, maxY, tris: md.tris,
      homeChunk: chunkKey(Math.floor(p0.ax / chunkM), Math.floor(p0.ay / chunkM)),
    });
  }
  return out;
}

/** Reads models.pb when the manifest announces it; any failure = no models (the pack still works). */
export async function loadModels(src: PackSource, modelsVersion: number, chunkM: number): Promise<ModelData[]> {
  if (modelsVersion < 1) return [];
  try {
    return prepareModels(fromBinary(ModelsSchema, await gunzip(await src.read('models.pb'))), chunkM);
  } catch {
    return [];
  }
}

/** Distance (m) from (x, y) to the model's plan bounding box. */
export function modelDistance(m: ModelData, x: number, y: number): number {
  const dx = Math.max(m.minX - x, 0, x - m.maxX), dy = Math.max(m.minY - y, 0, y - m.maxY);
  return Math.hypot(dx, dy);
}

/**
 * Which models are drawn in full in the chase view (specs/models.md): within near_m of the car,
 * kept until near_m + hysteresis_m, at most max_full, the nearest win. [shown] is last frame's set.
 */
export function fullModels(dists: readonly number[], shown: ReadonlySet<number>, nearM: number, hysteresisM: number, maxFull: number): Set<number> {
  const cand: number[] = [];
  dists.forEach((d, i) => {
    if (d <= nearM || (shown.has(i) && d <= nearM + hysteresisM)) cand.push(i);
  });
  cand.sort((a, b) => dists[a]! - dists[b]! || a - b);
  return new Set(cand.slice(0, Math.max(0, maxFull)));
}
