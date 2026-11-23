import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { defineConfig, type Plugin } from 'vitest/config';

/** Escapes text for an HTML attribute value. */
const attr = (s: string): string => s.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;');

// Link preview (Prompts/05 L-S8): crawlers do not run JS, so the texts go into index.html at build
// time. %OG_TITLE% and %OG_DESCRIPTION% become ogTitle and ogDescription of the Czech locale
// (texts live only in i18n/).
const ogText = (): Plugin => ({
  name: 'metro-og-text',
  transformIndexHtml(html) {
    const cs = JSON.parse(readFileSync(fileURLToPath(new URL('../i18n/cs.json', import.meta.url)), 'utf8')) as Record<string, string>;
    return html.replaceAll('%OG_TITLE%', attr(cs['ogTitle'] ?? '')).replaceAll('%OG_DESCRIPTION%', attr(cs['ogDescription'] ?? ''));
  },
});

// Relative base: the same build works on GitHub Pages under /<repo>/ and on any static host.
export default defineConfig({
  base: './',
  plugins: [ogText()],
  build: { target: 'es2022', sourcemap: true },
  test: { include: ['test/**/*.test.ts'] },
});
