import type { PackSource } from '../world/citypack';

/**
 * Download progress before the first frame (specs/firstrun.md "Postup stahování"): bytes read from
 * the pack over the sum of Content-Length of the responses seen so far plus chunk sizes announced
 * from the manifest. Pure apart from fetch; the percent never goes down.
 */
export class LoadProgress {
  private loaded = 0;
  private total = 0;
  private shown = 0;
  private readonly announced = new Set<string>();
  private stopped = false;

  constructor(private readonly onChange: (pct: number) => void = () => {}) {}

  /** Adds the size of a file before its response arrives (ChunkRef.bytes). */
  announce(path: string, bytes: number): void {
    if (this.announced.has(path)) return;
    this.announced.add(path);
    this.total += bytes;
    this.emit();
  }

  /** A response arrived; its Content-Length (null = unknown) joins the total unless announced. */
  started(path: string, length: number | null): void {
    if (length === null || this.announced.has(path)) return;
    this.announced.add(path);
    this.total += length;
    this.emit();
  }

  received(bytes: number): void {
    this.loaded += bytes;
    this.emit();
  }

  /** After the first frame: later reads (streaming) no longer touch the loading text. */
  stop(): void {
    this.stopped = true;
  }

  /** floor(99 · loaded / total), monotonic, 0 while the total is unknown. */
  get percent(): number {
    return this.shown;
  }

  private emit(): void {
    if (this.stopped) return;
    const pct = this.total > 0 ? Math.min(99, Math.floor((99 * this.loaded) / this.total)) : 0;
    if (pct > this.shown) {
      this.shown = pct;
      this.onChange(pct);
    }
  }
}

/** Wraps a pack source so every read streams its bytes into the progress. */
export class ProgressSource implements PackSource {
  constructor(
    private readonly root: string,
    readonly progress: LoadProgress,
    private readonly fetchFn: typeof fetch = (...a) => fetch(...a),
  ) {}

  async read(path: string): Promise<Uint8Array> {
    const res = await this.fetchFn(this.root + path);
    if (!res.ok) throw new Error(`${path}: HTTP ${res.status}`);
    const len = Number.parseInt(res.headers.get('content-length') ?? '', 10);
    this.progress.started(path, Number.isFinite(len) && len >= 0 ? len : null);
    if (!res.body) {
      const b = new Uint8Array(await res.arrayBuffer());
      this.progress.received(b.length);
      return b;
    }
    const parts: Uint8Array[] = [];
    let n = 0;
    const reader = res.body.getReader();
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      parts.push(value);
      n += value.length;
      this.progress.received(value.length);
    }
    const out = new Uint8Array(n);
    let o = 0;
    for (const p of parts) {
      out.set(p, o);
      o += p.length;
    }
    return out;
  }
}
