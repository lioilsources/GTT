import type { Tuning } from '../gen/tuning';
import { chunkPath, type PackSource } from './citypack';
import { prepareChunk, type ChunkData } from './chunk';
import { chunkKey, type City } from './model';

/**
 * Which chunks to keep loaded around the player (METROPOLE_PLAN 6.4). Pure logic, port of
 * world_engine chunk_window.dart: `side` chunks to each side, `behind` back and `ahead`
 * forward along the driving direction, plus the 3×3 ring around the player's own chunk.
 */
export class ChunkWindow {
  constructor(
    readonly city: City,
    readonly tuning: Tuning,
  ) {}

  /** Chunks wanted for a player at (x, y) heading `heading` (radians, 0 = east); own chunk first. */
  wanted(x: number, y: number, heading: number): [number, number][] {
    const cm = this.city.chunkM;
    const s = this.tuning.streaming;
    const fx = Math.cos(heading), fy = Math.sin(heading);
    const out: [number, number][] = [];
    const seen = new Set<number>();
    const add = (px: number, py: number): void => {
      const cx = Math.floor(px / cm), cy = Math.floor(py / cm);
      const k = chunkKey(cx, cy);
      if (this.city.hasChunk(cx, cy) && !seen.has(k)) {
        seen.add(k);
        out.push([cx, cy]);
      }
    };
    add(x, y);
    for (let dx = -1; dx <= 1; dx++) for (let dy = -1; dy <= 1; dy++) add(x + dx * cm, y + dy * cm);
    for (let j = -s.behind; j <= s.ahead; j++) {
      for (let i = -s.side; i <= s.side; i++) add(x + (fx * j - fy * i) * cm, y + (fy * j + fx * i) * cm);
    }
    return out;
  }

  /** True when chunk (cx, cy) is outside the keep ring around (x, y) and can be dropped. */
  drop(cx: number, cy: number, x: number, y: number): boolean {
    const cm = this.city.chunkM;
    const k = this.tuning.streaming.keep;
    return Math.abs(cx - Math.floor(x / cm)) > k || Math.abs(cy - Math.floor(y / cm)) > k;
  }
}

/** Loads the ChunkWindow around the player (port of world_engine streaming.dart). */
export class ChunkStreamer {
  readonly window: ChunkWindow;
  readonly loaded = new Map<number, ChunkData>();
  private readonly inFlight = new Set<number>();
  private readonly failedAt = new Map<number, number>();
  private disposed = false;

  constructor(
    readonly city: City,
    readonly source: PackSource,
    readonly tuning: Tuning,
    readonly onLoaded: (c: ChunkData) => void,
    readonly onUnloaded: (c: ChunkData) => void,
  ) {
    this.window = new ChunkWindow(city, tuning);
  }

  /** Call every frame; schedules loads and drops chunks outside the keep ring. */
  update(x: number, y: number, heading: number, now: number): void {
    if (this.disposed) return;
    for (const [cx, cy] of this.window.wanted(x, y, heading)) {
      const key = chunkKey(cx, cy);
      if (this.loaded.has(key) || this.inFlight.has(key)) continue;
      const failed = this.failedAt.get(key);
      if (failed !== undefined && now - failed < this.tuning.streaming.retryS * 1000) continue;
      if (this.inFlight.size >= this.tuning.streaming.maxInFlight) break;
      void this.load(cx, cy, key);
    }
    for (const [key, c] of this.loaded) {
      if (!this.window.drop(c.x, c.y, x, y)) continue;
      this.loaded.delete(key);
      this.onUnloaded(c);
    }
  }

  /** Loads everything the window needs and waits for it (start-up, teleports). */
  async preload(x: number, y: number, heading: number): Promise<void> {
    await Promise.all(
      this.window
        .wanted(x, y, heading)
        .filter(([cx, cy]) => !this.loaded.has(chunkKey(cx, cy)))
        .map(([cx, cy]) => this.load(cx, cy, chunkKey(cx, cy))),
    );
  }

  private async load(cx: number, cy: number, key: number): Promise<void> {
    this.inFlight.add(key);
    try {
      const data = await prepareChunk(await this.source.read(chunkPath(cx, cy)));
      if (this.disposed || this.loaded.has(key)) return;
      this.loaded.set(key, data);
      this.failedAt.delete(key);
      this.onLoaded(data);
    } catch (e) {
      // A missing or broken chunk must not stop the drive (specs/citypack.md); update() retries it.
      this.failedAt.set(key, performance.now());
      console.warn(`chunk ${cx},${cy} failed to load`, e);
    } finally {
      this.inFlight.delete(key);
    }
  }

  dispose(): void {
    this.disposed = true;
    for (const c of this.loaded.values()) this.onUnloaded(c);
    this.loaded.clear();
  }
}
