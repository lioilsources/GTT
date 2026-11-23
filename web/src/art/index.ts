// Generated art wiring for client W (specs/art.md v1): loads assets/index.json once at start,
// builds <img> elements for indexed files (lazy, decoded images kept in an LRU of 24) and falls
// back to the placeholder drawing when a file is not in the index or fails to load.
import { ASSET_BASE_URL } from '../config';
import { ART_CACHE_SIZE, ArtIndex, Lru } from './rules';
import './art.css';

export { ART_CACHE_SIZE, ArtIndex, expressionFor, Lru, type Expression } from './rules';

let index = new ArtIndex();
const decoded = new Lru<string, HTMLImageElement>(ART_CACHE_SIZE);

/** The asset index (empty until `loadArt` resolves, and when index.json is missing). */
export function art(): ArtIndex {
  return index;
}

/** Fetches `assets/index.json`; a missing or broken file = no art (never throws). */
export async function loadArt(base: string = ASSET_BASE_URL): Promise<ArtIndex> {
  try {
    const res = await fetch(`${base}assets/index.json`, { cache: 'no-cache' });
    index = res.ok ? ArtIndex.parse(await res.json()) : new ArtIndex();
  } catch {
    index = new ArtIndex();
  }
  return index;
}

/** For tests and debug: replace the index. */
export function setArt(i: ArtIndex): void {
  index = i;
}

/** The path when it can be shown (still in the index, i.e. not failed to load), else null. */
export function usable(path: string | null): string | null {
  return path && index.has(path) ? path : null;
}

export function artUrl(path: string): string {
  return `${ASSET_BASE_URL}assets/${path}`;
}

/**
 * An <img> for an indexed path, loaded lazily on first display. Once decoded the image is kept in
 * the LRU; later calls clone it (same, already decoded source). `onFail` runs when the file does
 * not load, so the caller can put the placeholder back.
 */
export function artImage(path: string, cls: string, onFail?: () => void): HTMLImageElement {
  const hit = decoded.get(path);
  if (hit) {
    const img = hit.cloneNode() as HTMLImageElement;
    img.className = cls;
    return img;
  }
  const img = new Image();
  img.className = cls;
  img.alt = '';
  img.loading = 'lazy';
  img.decoding = 'async';
  img.draggable = false;
  img.addEventListener('load', () => {
    img.decode().then(
      () => decoded.set(path, img),
      () => undefined,
    );
  }, { once: true });
  img.addEventListener('error', () => {
    // Failed file = missing for the rest of the session (no retry; lookups fall back past it).
    index.drop(path);
    img.remove();
    onFail?.();
  }, { once: true });
  img.src = artUrl(path);
  return img;
}

/**
 * A UI icon (specs/art.md v3 "Ikony UI") for an indexed `ui/<id>.png`: a span masked by the glyph
 * over `currentColor` (the colour of today's drawing), sized by the caller's CSS. A file that does
 * not load is dropped from the index and `onFail` puts today's drawing back.
 */
export function artIcon(path: string, cls = '', onFail?: () => void): HTMLSpanElement {
  const el = document.createElement('span');
  el.className = cls ? `art-icon ${cls}` : 'art-icon';
  el.setAttribute('aria-hidden', 'true');
  // Absolute: a relative url() inside a custom property would resolve against the stylesheet.
  const url = new URL(artUrl(path), document.baseURI).href;
  el.style.setProperty('--art-icon', `url("${url}")`);
  if (!decoded.has(path)) {
    const probe = new Image();
    probe.decoding = 'async';
    probe.addEventListener('load', () => decoded.set(path, probe), { once: true });
    probe.addEventListener('error', () => {
      index.drop(path);
      onFail?.();
    }, { once: true });
    probe.src = url;
  }
  return el;
}
