// Save storage of client W (specs/save.md "Úložiště"): IndexedDB `metropole` / store `save`,
// key `save:<cityId>`, value = JSON text; localStorage under the same key when IndexedDB fails.

export interface SaveStore {
  read(cityId: string): Promise<unknown>;
  write(cityId: string, save: unknown): Promise<void>;
}

const DB = 'metropole';
const STORE = 'save';
const key = (cityId: string): string => `save:${cityId}`;

function parse(text: unknown): unknown {
  if (typeof text !== 'string') return null;
  try {
    return JSON.parse(text) as unknown;
  } catch {
    return null;
  }
}

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    if (typeof indexedDB === 'undefined') return reject(new Error('no IndexedDB'));
    const req = indexedDB.open(DB, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(STORE);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error ?? new Error('IndexedDB open failed'));
  });
}

function tx<T>(db: IDBDatabase, mode: IDBTransactionMode, f: (s: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    const r = f(db.transaction(STORE, mode).objectStore(STORE));
    r.onsuccess = () => resolve(r.result);
    r.onerror = () => reject(r.error ?? new Error('IndexedDB request failed'));
  });
}

const local = {
  read(cityId: string): unknown {
    try {
      return parse(localStorage.getItem(key(cityId)));
    } catch {
      return null;
    }
  },
  write(cityId: string, text: string): void {
    try {
      localStorage.setItem(key(cityId), text);
    } catch {
      // Storage full or blocked: the game goes on without saving.
    }
  },
};

export class BrowserSaveStore implements SaveStore {
  private db: Promise<IDBDatabase | null> = openDb().catch(() => null);

  async read(cityId: string): Promise<unknown> {
    const db = await this.db;
    if (db) {
      try {
        const v = parse(await tx(db, 'readonly', (s) => s.get(key(cityId)) as IDBRequest<unknown>));
        if (v !== null) return v;
      } catch {
        // fall through to localStorage
      }
    }
    return local.read(cityId);
  }

  async write(cityId: string, save: unknown): Promise<void> {
    const text = JSON.stringify(save);
    const db = await this.db;
    if (db) {
      try {
        await tx(db, 'readwrite', (s) => s.put(text, key(cityId)));
        return;
      } catch {
        // fall through to localStorage
      }
    }
    local.write(cityId, text);
  }
}

/** In-memory store for tests. */
export class MemorySaveStore implements SaveStore {
  readonly data = new Map<string, string>();
  read(cityId: string): Promise<unknown> {
    return Promise.resolve(parse(this.data.get(key(cityId))));
  }
  write(cityId: string, save: unknown): Promise<void> {
    this.data.set(key(cityId), JSON.stringify(save));
    return Promise.resolve();
  }
}
