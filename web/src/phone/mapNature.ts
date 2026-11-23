import { LodKind } from '../gen/pb/citypack_pb';
import { chunkPath, decodeChunk, decodeLod, type PackSource } from '../world/citypack';
import type { City } from '../world/model';

/**
 * Water and parks of the whole city for the phone Map (specs/nature.md "mapa v telefonu"): fills
 * from the lod tiles (water as one surface, wood and parkland masses), names from the chunks'
 * labels, biggest first. Loaded once in the background when the Map first opens.
 */

export interface MapLabel {
  name: string;
  x: number;
  y: number;
  /** Axis direction (radians, world), 0 for a point label. */
  angle: number;
  water: boolean;
  area: number;
}

export interface MapNature {
  /** Water triangles, interleaved metres (x0, y0, x1, y1, x2, y2 per triangle). */
  water: Float32Array[];
  /** Mass outlines (all rings, `ends` exclusive vertex ends per ring), metres. */
  wood: Array<{ xy: Float32Array; ends: number[] }>;
  park: Array<{ xy: Float32Array; ends: number[] }>;
  /** Unique names sorted by area, biggest first. */
  labels: MapLabel[];
  /** Bumped while data arrives (the map re-renders its fill layer). */
  version: number;
}

/** Concurrent chunk reads for the labels (the drive streams in parallel). */
const LABEL_FETCHES = 3;

/** Midpoint of a polyline by length and its direction there. */
export function axisMid(axis: ArrayLike<number>): { x: number; y: number; angle: number } {
  const n = axis.length >> 1;
  if (n <= 1) return { x: axis[0] ?? 0, y: axis[1] ?? 0, angle: 0 };
  let total = 0;
  for (let i = 1; i < n; i++) total += Math.hypot(axis[2 * i]! - axis[2 * i - 2]!, axis[2 * i + 1]! - axis[2 * i - 1]!);
  let acc = 0;
  for (let i = 1; i < n; i++) {
    const ax = axis[2 * i - 2]!, ay = axis[2 * i - 1]!, bx = axis[2 * i]!, by = axis[2 * i + 1]!;
    const l = Math.hypot(bx - ax, by - ay);
    if (acc + l >= total / 2 && l > 0) {
      const k = (total / 2 - acc) / l;
      return { x: ax + (bx - ax) * k, y: ay + (by - ay) * k, angle: Math.atan2(by - ay, bx - ax) };
    }
    acc += l;
  }
  return { x: axis[0]!, y: axis[1]!, angle: 0 };
}

export class MapNatureSource {
  readonly data: MapNature = { water: [], wood: [], park: [], labels: [], version: 0 };
  private started = false;
  private readonly names = new Map<string, MapLabel>();

  constructor(
    readonly city: City,
    readonly source: PackSource,
  ) {}

  /** Starts the background load (idempotent); a pack without nature has nothing to load. */
  start(): void {
    if (this.started || this.city.manifest.natureVersion <= 0) return;
    this.started = true;
    void this.loadLods().then(() => this.loadLabels());
  }

  private async loadLods(): Promise<void> {
    for (const r of this.city.manifest.lods) {
      try {
        const l = await decodeLod(await this.source.read(`lod/${r.x}_${r.y}.pb`));
        for (const w of l.water) {
          const out = new Float32Array(w.indices.length * 2);
          for (let i = 0; i < w.indices.length; i++) {
            out[2 * i] = w.vertices[2 * w.indices[i]!]! / 10;
            out[2 * i + 1] = w.vertices[2 * w.indices[i]! + 1]! / 10;
          }
          this.data.water.push(out);
        }
        for (const m of l.masses) {
          if (m.kind === LodKind.LOD_BLOCK) continue;
          const g = { xy: Float32Array.from(m.rings, (v) => v / 10), ends: m.ringEnds.length ? [...m.ringEnds] : [m.rings.length >> 1] };
          (m.kind === LodKind.LOD_WOOD ? this.data.wood : this.data.park).push(g);
        }
        this.data.version++;
      } catch {
        // A missing tile only leaves a gap on the map.
      }
    }
  }

  private async loadLabels(): Promise<void> {
    const refs = [...this.city.manifest.chunks];
    let changed = false, sinceSort = 0;
    const next = async (): Promise<void> => {
      for (let r = refs.shift(); r; r = refs.shift()) {
        try {
          const c = await decodeChunk(await this.source.read(chunkPath(r.x, r.y)));
          for (const l of c.labels) {
            if (l.name === '' || l.axis.length < 2) continue;
            const prev = this.names.get(l.name);
            if (prev && prev.area >= l.areaM2) continue;
            const m = axisMid(Float32Array.from(l.axis, (v) => v / 10));
            this.names.set(l.name, { name: l.name, x: m.x, y: m.y, angle: l.water ? m.angle : 0, water: l.water, area: l.areaM2 });
            changed = true;
          }
          if (changed && ++sinceSort >= 25) {
            this.sortLabels();
            sinceSort = 0;
            changed = false;
          }
        } catch {
          // Skipped; the name may come from another chunk of the same body.
        }
      }
    };
    await Promise.all(Array.from({ length: LABEL_FETCHES }, next));
    this.sortLabels();
  }

  private sortLabels(): void {
    this.data.labels = [...this.names.values()].sort((a, b) => b.area - a.area || (a.name < b.name ? -1 : 1));
    this.data.version++;
  }
}
