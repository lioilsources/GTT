// Generated art wiring (specs/art.md v1), pure part: expression by vibe, lookups in the asset
// index written by `metro sync` (assets/index.json) and the LRU of decoded images. No DOM.

/** specs/art.md "Výkon a velikost": decoded images kept, least recently used dropped. */
export const ART_CACHE_SIZE = 24;

export type Expression ='happy' | 'neutral' | 'annoyed';

/** specs/art.md "Výraz podle vibe": ≥ contactMinVibe happy, < vibeStart annoyed, else neutral. */
export function expressionFor(vibe: number, t: { vibeStart: number; contactMinVibe: number }): Expression {
  if (vibe >= t.contactMinVibe) return 'happy';
  if (vibe < t.vibeStart) return 'annoyed';
  return 'neutral';
}

/**
 * The set of PNGs that exist (relative to `assets/`). A path not in the index does not exist; the
 * client never probes. An empty index (missing index.json) = no art, every lookup is null.
 */
export class ArtIndex {
  private readonly files: Set<string>;

  constructor(paths: Iterable<string> = []) {
    this.files = new Set(paths);
  }

  /** Forgets a path (an indexed file that failed to load): later lookups fall back past it. */
  drop(path: string): void {
    this.files.delete(path);
  }

  /** Parses the JSON body of index.json; anything but an array of strings = empty index. */
  static parse(json: unknown): ArtIndex {
    return new ArtIndex(Array.isArray(json) ? json.filter((p): p is string => typeof p === 'string') : []);
  }

  get size(): number {
    return this.files.size;
  }

  has(path: string): boolean {
    return this.files.has(path);
  }

  private first(...paths: string[]): string | null {
    return paths.find((p) => this.files.has(p)) ?? null;
  }

  /** Dialogue portrait: `npc/<id>_<expr>.png`, then `npc/<id>.png`, then null (initials). */
  portrait(id: string, expr: Expression): string | null {
    return this.first(`npc/${id}_${expr}.png`, `npc/${id}.png`);
  }

  /** Contacts and the rival: `npc/<id>.png` or null (initials). */
  avatar(id: string): string | null {
    return this.first(`npc/${id}.png`);
  }

  /** Feed card and booth offer host: `npc/<id>_bust.png` or null (silhouette). */
  bust(id: string): string | null {
    return this.first(`npc/${id}_bust.png`);
  }

  /** Souvenir on the Garage shelf (specs/shops.md): `souvenirs/<id>.png` or null (icon). */
  souvenir(id: string): string | null {
    return this.first(`souvenirs/${id}.png`);
  }

  /** Landmark postcard: `postcards/<city>/<id>.png` or null (placeholder drawing). */
  postcard(city: string, id: string): string | null {
    return this.first(`postcards/${city}/${id}.png`);
  }
}

/** Least-recently-used map with a fixed capacity; `get` refreshes, `set` evicts the oldest. */
export class Lru<K, V> {
  private readonly map = new Map<K, V>();

  constructor(readonly capacity: number, private readonly onEvict?: (key: K, value: V) => void) {}

  get size(): number {
    return this.map.size;
  }

  has(key: K): boolean {
    return this.map.has(key);
  }

  get(key: K): V | undefined {
    if (!this.map.has(key)) return undefined;
    const v = this.map.get(key) as V;
    this.map.delete(key);
    this.map.set(key, v);
    return v;
  }

  set(key: K, value: V): void {
    if (this.map.has(key)) this.map.delete(key);
    this.map.set(key, value);
    while (this.map.size > Math.max(0, this.capacity)) {
      const [k, v] = this.map.entries().next().value as [K, V];
      this.map.delete(k);
      this.onEvict?.(k, v);
    }
  }

  /** Keys from least to most recently used. */
  keys(): K[] {
    return [...this.map.keys()];
  }
}
