import { defineConfig } from 'vitest/config';

// Relative base: the same build works on GitHub Pages under /<repo>/ and on any static host.
export default defineConfig({
  base: './',
  build: { target: 'es2022', sourcemap: true },
  test: { include: ['test/**/*.test.ts'] },
});
