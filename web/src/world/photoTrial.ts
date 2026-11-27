import { ASSET_BASE_URL } from '../config';

/**
 * Photo texture trial (local experiment, no spec, not for main): the IPR photorealistic mesh
 * (CC BY 4.0 © IPR Praha) baked onto the LOD2 triangles of one model part by
 * tools/citypack/cmd/phototrial. Files live next to the packs, outside the pack itself:
 * `<ASSET_BASE_URL>packs/<city>/photo/<size>/{photo.json, uv.bin, atlas_<size>.jpg}`.
 * Enabled only by the query parameter `?photo=<variant>` (a folder: `2048`, `1024`, `2048g` …;
 * `1` = 2048).
 */
export interface PhotoTrial {
  /** Landmark id of the model. */
  model: string;
  /** Part index → u, v per triangle corner (0…1, v up). */
  parts: Map<number, Float32Array>;
  atlasUrl: string;
  credit: string;
}

export function photoTrialVariant(search: string = typeof location === 'undefined' ? '' : location.search): string | null {
  const v = new URLSearchParams(search).get('photo');
  if (v === null || v === '0') return null;
  return /^[0-9a-z]{1,16}$/.test(v) && v !== '1' ? v : '2048';
}

export interface PhotoMeta {
  model: string;
  atlas: string;
  credit: string;
  parts: { part: number; tris: number }[];
}

/** Splits uv.bin (uint16 pairs per corner, parts in photo.json order) into per-part arrays. */
export function photoParts(meta: PhotoMeta, raw: Uint16Array): Map<number, Float32Array> {
  const out = new Map<number, Float32Array>();
  let o = 0;
  for (const p of meta.parts) {
    const n = p.tris * 6;
    const a = new Float32Array(n);
    for (let i = 0; i < n; i++) a[i] = raw[o + i]! / 65535;
    out.set(p.part, a);
    o += n;
  }
  return out;
}

export async function loadPhotoTrial(cityId: string, variant: string): Promise<PhotoTrial | null> {
  const base = `${ASSET_BASE_URL}packs/${cityId}/photo/${variant}/`;
  try {
    const mr = await fetch(base + 'photo.json', { cache: 'no-cache' });
    if (!mr.ok) return null;
    const meta = (await mr.json()) as PhotoMeta;
    const ur = await fetch(base + 'uv.bin', { cache: 'no-cache' });
    if (!ur.ok) return null;
    const raw = new Uint16Array(await ur.arrayBuffer());
    return { model: meta.model, parts: photoParts(meta, raw), atlasUrl: base + meta.atlas, credit: meta.credit };
  } catch {
    return null;
  }
}
