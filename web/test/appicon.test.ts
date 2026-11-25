import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { describe, expect, it } from 'vitest';

import {
  APP_ICON_DEFAULT, APP_ICON_KEY, AppIconChoice, appIconModes, appIconUrl, readAppIcon, writeAppIcon,
  type AppIconStore,
} from '../src/appicon';
import { t, type MessageKey } from '../src/gen/i18n';
import { tokens } from '../src/gen/tokens';

// App icon and its colour mode (specs/appicon.md v1, parity F-083).

const web = join(__dirname, '..');
const pub = join(web, 'public');

class FakeStore implements AppIconStore {
  readonly data = new Map<string, string>();
  writes = 0;
  getItem(k: string): string | null {
    return this.data.get(k) ?? null;
  }
  setItem(k: string, v: string): void {
    this.writes++;
    this.data.set(k, v);
  }
}
const broken: AppIconStore = {
  getItem: () => {
    throw new Error('blocked');
  },
  setItem: () => {
    throw new Error('blocked');
  },
};
const pngSize = (file: string): [number, number] => {
  const png = readFileSync(file);
  expect(png.subarray(1, 4).toString('ascii')).toBe('PNG');
  return [png.readUInt32BE(16), png.readUInt32BE(20)];
};

describe('app icon choice', () => {
  it('has the five modes of the spec with sunset as the default and a name in both languages', () => {
    expect([...appIconModes]).toEqual(['day', 'night', 'sunset', 'teal', 'japan']);
    expect(APP_ICON_DEFAULT).toBe('sunset');
    for (const m of appIconModes) {
      for (const locale of ['cs', 'en'] as const) expect(t(locale, `appIcon_${m}` satisfies MessageKey)).not.toBe('');
    }
  });

  it('reads the stored mode; unknown, missing or blocked storage gives sunset', () => {
    const store = new FakeStore();
    expect(readAppIcon(null, store)).toBe('sunset');
    store.data.set(APP_ICON_KEY, 'teal');
    expect(readAppIcon(null, store)).toBe('teal');
    store.data.set(APP_ICON_KEY, 'neon');
    expect(readAppIcon(null, store)).toBe('sunset');
    expect(readAppIcon(null, null)).toBe('sunset');
    expect(readAppIcon(null, broken)).toBe('sunset');
  });

  it('?icon= wins over the stored mode without storing; an unknown value is sunset', () => {
    const store = new FakeStore();
    store.data.set(APP_ICON_KEY, 'teal');
    expect(readAppIcon('japan', store)).toBe('japan');
    expect(readAppIcon('neon', store)).toBe('sunset');
    const links = { icon: { href: '' }, touch: { href: '' } };
    const choice = new AppIconChoice('night', links, store);
    expect(choice.mode).toBe('night');
    expect(links.icon.href).toBe('./icons/night-32.png');
    expect(store.writes).toBe(0);
    expect(store.data.get(APP_ICON_KEY)).toBe('teal');
  });

  it('writing survives blocked storage', () => {
    expect(() => writeAppIcon('day', broken)).not.toThrow();
    expect(() => writeAppIcon('day', null)).not.toThrow();
  });

  it('applies the remembered mode to both links at start', () => {
    const store = new FakeStore();
    store.data.set(APP_ICON_KEY, 'japan');
    const links = { icon: { href: './icons/sunset-32.png' }, touch: { href: './icons/sunset-180.png' } };
    const choice = new AppIconChoice(null, links, store);
    expect(choice.mode).toBe('japan');
    expect(links).toEqual({ icon: { href: './icons/japan-32.png' }, touch: { href: './icons/japan-180.png' } });
  });

  it('a pick rewrites both links and stores the mode; picking the current mode does nothing', () => {
    const store = new FakeStore();
    const links = { icon: { href: '' }, touch: { href: '' } };
    const choice = new AppIconChoice(null, links, store);
    expect(links.icon.href).toBe(appIconUrl('sunset', 32));
    expect(choice.pick('sunset')).toBe(false);
    expect(store.writes).toBe(0);

    expect(choice.pick('teal')).toBe(true);
    expect(choice.mode).toBe('teal');
    expect(links).toEqual({ icon: { href: './icons/teal-32.png' }, touch: { href: './icons/teal-180.png' } });
    expect(store.data.get(APP_ICON_KEY)).toBe('teal');
    expect(choice.pick('teal')).toBe(false);
    expect(store.writes).toBe(1);
    // The next load starts with the stored mode.
    expect(new AppIconChoice(null, { icon: null, touch: null }, store).mode).toBe('teal');
  });

  it('works without the links and without storage', () => {
    const choice = new AppIconChoice(null, { icon: null, touch: null }, null);
    expect(choice.pick('day')).toBe(true);
    expect(choice.mode).toBe('day');
  });
});

describe('app icon files', () => {
  it('every mode has a 32 px and a 180 px icon of that size', () => {
    for (const m of appIconModes) {
      for (const size of [32, 180] as const) {
        const file = join(pub, appIconUrl(m, size));
        expect(existsSync(file), file).toBe(true);
        expect(pngSize(file)).toEqual([size, size]);
      }
    }
  });

  it('index.html points the tab icon, the apple-touch-icon and the manifest at the sunset files', () => {
    const html = readFileSync(join(web, 'index.html'), 'utf8');
    expect(html).toMatch(/<link rel="icon" type="image\/png" sizes="32x32" href="\/icons\/sunset-32\.png" \/>/);
    expect(html).toMatch(/<link rel="apple-touch-icon" sizes="180x180" href="\/icons\/sunset-180\.png" \/>/);
    expect(html).toMatch(/<link rel="manifest" href="\/manifest\.webmanifest" \/>/);
  });

  it('the manifest lists existing sunset icons of the stated size and takes its colours from the tokens', () => {
    const manifest = JSON.parse(readFileSync(join(pub, 'manifest.webmanifest'), 'utf8')) as {
      display: string; background_color: string; theme_color: string;
      icons: Array<{ src: string; sizes: string; type: string; purpose: string }>;
    };
    expect(manifest.display).toBe('standalone');
    expect(manifest.background_color).toBe(tokens.colorUiBackground);
    expect(manifest.theme_color).toBe(tokens.colorUiBackground);
    expect(manifest.icons.map((i) => `${i.sizes} ${i.purpose}`).sort()).toEqual(['192x192 any', '192x192 maskable', '512x512 any', '512x512 maskable']);
    for (const icon of manifest.icons) {
      expect(icon.src).toMatch(/^icons\/sunset-\d+\.png$/);
      expect(icon.type).toBe('image/png');
      const [w, h] = icon.sizes.split('x').map(Number);
      expect(pngSize(join(pub, icon.src))).toEqual([w, h]);
    }
  });

  // Checks the built dist/ like test/og.test.ts (CI builds before the tests).
  const dist = join(web, 'dist');
  const built = existsSync(join(dist, 'index.html'));
  it.runIf(built || !!process.env['CI'])('the build keeps the links relative and ships the icons', () => {
    const html = readFileSync(join(dist, 'index.html'), 'utf8');
    expect(html).toContain('href="./icons/sunset-32.png"');
    expect(html).toContain('href="./icons/sunset-180.png"');
    expect(html).toContain('href="./manifest.webmanifest"');
    for (const m of appIconModes) expect(existsSync(join(dist, 'icons', `${m}-32.png`))).toBe(true);
    expect(existsSync(join(dist, 'manifest.webmanifest'))).toBe(true);
  });
});
