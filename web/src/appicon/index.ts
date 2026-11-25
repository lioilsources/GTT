import type { MessageKey } from '../gen/i18n';
import { h } from '../minigames/dom';

/**
 * App icon colour mode (specs/appicon.md v1): five modes, the choice is a device preference kept
 * in localStorage outside the save; the tab icon and the apple-touch-icon follow it.
 */

/** Picker order (specs/appicon.md "Režimy"). */
export const appIconModes = ['day', 'night', 'sunset', 'teal', 'japan'] as const;
export type AppIconMode = (typeof appIconModes)[number];
export const APP_ICON_DEFAULT: AppIconMode = 'sunset';
export const APP_ICON_KEY = 'metro:appIcon';
/** Generated sizes present for every mode (web/scripts/icons.py): tab icon, apple-touch-icon. */
export type AppIconSize = 32 | 180;

/** The slice of Storage the setting uses (localStorage in the browser, a fake in tests). */
export interface AppIconStore {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
}

/** The `<link>` elements the choice rewrites (anything with an `href`). */
export interface AppIconLinks {
  icon: { href: string } | null;
  touch: { href: string } | null;
}

function defaultStore(): AppIconStore | null {
  try {
    return typeof localStorage === 'undefined' ? null : localStorage;
  } catch {
    return null;
  }
}

const isMode = (v: unknown): v is AppIconMode => (appIconModes as readonly unknown[]).includes(v);

/** Start mode: `?icon=` (debug, not stored) wins, else the remembered choice; anything unknown = sunset. */
export function readAppIcon(param: string | null, store: AppIconStore | null = defaultStore()): AppIconMode {
  if (param !== null) return isMode(param) ? param : APP_ICON_DEFAULT;
  try {
    const v = store?.getItem(APP_ICON_KEY);
    return isMode(v) ? v : APP_ICON_DEFAULT;
  } catch {
    return APP_ICON_DEFAULT;
  }
}

export function writeAppIcon(mode: AppIconMode, store: AppIconStore | null = defaultStore()): void {
  try {
    store?.setItem(APP_ICON_KEY, mode);
  } catch {
    // Private mode or blocked storage: the choice lasts until the page closes.
  }
}

/** Icon file of a mode, relative to the page (web/public/icons/). */
export const appIconUrl = (mode: AppIconMode, size: AppIconSize): string => `./icons/${mode}-${size}.png`;

/** The two links of index.html. */
export function appIconLinks(doc: Pick<Document, 'querySelector'>): AppIconLinks {
  return {
    icon: doc.querySelector<HTMLLinkElement>('link[rel="icon"]'),
    touch: doc.querySelector<HTMLLinkElement>('link[rel="apple-touch-icon"]'),
  };
}

/** The current mode: applied to the links on creation and on every pick, stored on a pick. */
export class AppIconChoice {
  mode: AppIconMode;

  constructor(
    param: string | null,
    private readonly links: AppIconLinks,
    private readonly store: AppIconStore | null = defaultStore(),
  ) {
    this.mode = readAppIcon(param, store);
    this.apply();
  }

  /** Selects a mode; false (no write, no change) when it already is the current one. */
  pick(mode: AppIconMode): boolean {
    if (mode === this.mode) return false;
    this.mode = mode;
    writeAppIcon(mode, this.store);
    this.apply();
    return true;
  }

  private apply(): void {
    if (this.links.icon) this.links.icon.href = appIconUrl(this.mode, 32);
    if (this.links.touch) this.links.touch.href = appIconUrl(this.mode, 180);
  }
}

/** The Settings section (specs/appicon.md "Výběr ve hře"): title, five tiles, a note. */
export function appIconSection(choice: AppIconChoice, t: (k: MessageKey) => string): HTMLElement {
  const tiles = appIconModes.map((m) =>
    h('button.appicon-tile', { type: 'button', 'data-mode': m, onclick: () => {
      choice.pick(m);
      sync();
    } }, h('img.appicon-img', { src: appIconUrl(m, 180), alt: '' }), h('span.appicon-name', {}, t(`appIcon_${m}`))));
  const sync = (): void => tiles.forEach((el, i) => el.setAttribute('aria-pressed', String(appIconModes[i] === choice.mode)));
  sync();
  return h('div.appicon', {},
    h('div.travel-title', {}, t('appIconTitle')),
    h('div.appicon-grid', {}, ...tiles),
    h('div.appicon-note', {}, t('appIconTab')));
}
