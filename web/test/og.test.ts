import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { describe, expect, it } from 'vitest';

// Link preview (Prompts/05 L-S8): checks the built dist/ (CI builds before the tests). Locally
// without a build the test is skipped; in CI a missing dist/ fails it.
const dist = join(__dirname, '..', 'dist');
const built = existsSync(join(dist, 'index.html'));
const cs = JSON.parse(readFileSync(join(__dirname, '..', '..', 'i18n', 'cs.json'), 'utf8')) as Record<string, string>;

const meta = (html: string, attr: 'name' | 'property', key: string): string | null => {
  const m = html.match(new RegExp(`<meta\\s+${attr}="${key.replace(':', '\\:')}"\\s+content="([^"]*)"`));
  return m ? m[1]! : null;
};
const unescape = (s: string): string => s.replaceAll('&quot;', '"').replaceAll('&lt;', '<').replaceAll('&amp;', '&');

describe('link preview in dist/', () => {
  it.runIf(!built && !process.env['CI'])('skipped: no dist/ (run npm run build)', () => {});
  it.runIf(built || !!process.env['CI'])('index.html carries every tag with absolute URLs, og.png is 1200×627', () => {
    expect(built).toBe(true);
    const html = readFileSync(join(dist, 'index.html'), 'utf8');
    expect(html).not.toContain('%OG_');
    expect(unescape(meta(html, 'name', 'description') ?? '')).toBe(cs['ogDescription']);
    expect(meta(html, 'property', 'og:type')).toBe('website');
    expect(unescape(meta(html, 'property', 'og:title') ?? '')).toBe(cs['ogTitle']);
    expect(unescape(meta(html, 'property', 'og:description') ?? '')).toBe(cs['ogDescription']);
    expect(meta(html, 'property', 'og:url')).toBe('https://lioilsources.github.io/GTT/');
    const img = meta(html, 'property', 'og:image') ?? '';
    expect(img).toMatch(/^https:\/\/[^/]+\/.+\.png$/);
    expect(img).toBe('https://lioilsources.github.io/GTT/og.png');
    expect(meta(html, 'property', 'og:image:width')).toBe('1200');
    expect(meta(html, 'property', 'og:image:height')).toBe('627');
    expect(meta(html, 'name', 'twitter:card')).toBe('summary_large_image');

    const png = readFileSync(join(dist, 'og.png'));
    expect(png.subarray(1, 4).toString('ascii')).toBe('PNG');
    expect(png.readUInt32BE(16)).toBe(1200);
    expect(png.readUInt32BE(20)).toBe(627);
    expect(png.length).toBeLessThan(5 * 1024 * 1024);
  });
});
