// Garage cosmetics sprites (specs/art.md v3), DOM part: decodes the indexed decal and wheel
// sprites once (decals shrunk to the 128 × 256 atlas cell) into the registry of cosmetics.ts.
// A file that fails to load is dropped from the index: that choice stays procedural.
import { art } from '../art';
import { pixels } from '../cars/spriteArt';
import { cosmeticFiles, DECAL_CELL_H, DECAL_CELL_W, setCosmeticArt } from './cosmetics';

let loading: Promise<void> | null = null;
let loaded = false;

/** True once every indexed cosmetics sprite has been tried. */
export function cosmeticsLoaded(): boolean {
  return loaded;
}

/** Loads the indexed cosmetics sprites (once; later calls share the same promise). */
export function loadCosmetics(): Promise<void> {
  if (loading) return loading;
  const { decals, wheels } = cosmeticFiles(art());
  const one = async (kind: 'decal' | 'wheel', i: number, path: string): Promise<void> => {
    try {
      setCosmeticArt(kind, i, kind === 'decal' ? await pixels(path, DECAL_CELL_W, DECAL_CELL_H) : await pixels(path));
    } catch {
      art().drop(path);
    }
  };
  loading = Promise.all([
    ...[...decals].map(([i, p]) => one('decal', i, p)),
    ...[...wheels].map(([i, p]) => one('wheel', i, p)),
  ]).then(() => {
    loaded = true;
  });
  return loading;
}
