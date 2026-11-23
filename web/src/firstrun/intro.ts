import type { MessageKey } from '../gen/i18n';

/**
 * The intro card of the first run (specs/firstrun.md "Úvodní karta"): controls in three lines and
 * the city choice, once per device (localStorage `metropole:intro`, every access in try/catch).
 */

export const INTRO_KEY = 'metropole:intro';
/** Parameters of automated runs and deep links: no intro card. */
export const INTRO_SKIP_PARAMS = ['bench', 'demo', 'gallery', 'mg', 'skits', 'cars', 'nointro'] as const;

export interface IntroStore {
  getItem(k: string): string | null;
  setItem(k: string, v: string): void;
}

/** Pure: whether the card shows for these parameters and this storage (null = no storage). */
export function shouldShowIntro(params: URLSearchParams, store: IntroStore | null): boolean {
  if (INTRO_SKIP_PARAMS.some((p) => params.has(p))) return false;
  try {
    return store?.getItem(INTRO_KEY) !== '1';
  } catch {
    return true;
  }
}

export function rememberIntro(store: IntroStore | null): void {
  try {
    store?.setItem(INTRO_KEY, '1');
  } catch {
    // Storage blocked: the card shows again next time, the game goes on.
  }
}

/** localStorage, or null when even the accessor throws. */
export function introStore(): IntroStore | null {
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

export interface IntroDeps {
  parent: HTMLElement;
  t: (key: MessageKey, args?: Record<string, string | number>) => string;
  cities: readonly string[];
  names: Readonly<Record<string, string>>;
  current: string;
  /** Called once when the card closes: null = stay, else the chosen other city. */
  onClose: (city: string | null) => void;
}

/** Shows the card; returns a function that closes it as if staying. */
export function showIntro(d: IntroDeps): () => void {
  const card = document.createElement('div');
  card.className = 'intro';
  card.setAttribute('role', 'dialog');
  const box = document.createElement('div');
  box.className = 'intro-box';
  const h = document.createElement('h2');
  h.textContent = d.t('introTitle');
  box.append(h);
  for (const k of ['introLine1', 'introLine2', 'introLine3'] as const) {
    const p = document.createElement('p');
    p.textContent = d.t(k);
    box.append(p);
  }
  const ch = document.createElement('h3');
  ch.textContent = d.t('introCity');
  box.append(ch);
  const row = document.createElement('div');
  row.className = 'intro-cities';
  let closed = false;
  const close = (city: string | null): void => {
    if (closed) return;
    closed = true;
    card.remove();
    d.onClose(city);
  };
  for (const id of d.cities) {
    const b = document.createElement('button');
    b.type = 'button';
    b.textContent = d.names[id] ?? id;
    b.dataset.city = id;
    if (id === d.current) b.classList.add('current');
    b.addEventListener('click', () => close(id === d.current ? null : id));
    row.append(b);
  }
  box.append(row);
  const go = document.createElement('button');
  go.type = 'button';
  go.className = 'intro-go';
  go.textContent = d.t('introGo');
  go.addEventListener('click', () => close(null));
  box.append(go);
  card.append(box);
  d.parent.append(card);
  return () => close(null);
}
