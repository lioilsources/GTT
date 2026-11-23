// Mobile web smoke test (specs/bench.md "Kouřový test mobilního webu", Prompts/05 L-S6).
// Usage: npm run build && npm run smoke [-- --url http://localhost:4173/]  (starts vite preview itself
// when --url is not given). Exit code 1 on the first failed step; numbers go to stdout as JSON.
import { spawn, type ChildProcess } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { chromium, type Browser, type BrowserContext, type CDPSession, type Page } from 'playwright';

import { t } from '../src/gen/i18n';
import { Tuning } from '../src/gen/tuning';

const webDir = join(dirname(fileURLToPath(import.meta.url)), '..');
const tuning = Tuning.fromJson(JSON.parse(readFileSync(join(webDir, 'public/shared/content/tuning.json'), 'utf8')));
const s = tuning.smoke;

interface Profile {
  name: string;
  width: number;
  height: number;
  dpr: number;
}
const profiles: Profile[] = [
  { name: 'pixel_8a', width: 412, height: 915, dpr: 2.625 },
  { name: 'iphone_12_mini', width: 375, height: 812, dpr: 3 },
];
const cities = ['nyc', 'prague', 'tokyo'] as const;

const argUrl = (() => {
  const i = process.argv.indexOf('--url');
  return i > 0 ? process.argv[i + 1] : undefined;
})();

async function startPreview(): Promise<{ url: string; proc: ChildProcess }> {
  const port = 4173 + Math.floor(Math.random() * 500);
  const proc = spawn('npx', ['vite', 'preview', '--port', String(port), '--strictPort'], { cwd: webDir, stdio: 'pipe' });
  const url = `http://localhost:${port}/`;
  for (let i = 0; i < 120; i++) {
    try {
      if ((await fetch(url)).ok) return { url, proc };
    } catch {
      // not up yet
    }
    await new Promise((r) => setTimeout(r, 500));
  }
  proc.kill();
  throw new Error('vite preview did not start');
}

class StepError extends Error {}
const check = (ok: boolean, msg: string): void => {
  if (!ok) throw new StepError(msg);
};

/** Console errors and uncaught exceptions of one page. */
function watchConsole(page: Page, errors: string[]): void {
  page.on('console', (m) => {
    if (m.type() === 'error') errors.push(`console: ${m.text()}`);
  });
  page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}`));
}

async function loadCity(page: Page, url: string): Promise<number> {
  const t0 = Date.now();
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForFunction(() => {
    const m = (window as unknown as { metro?: { timing(): { firstFrameMs: number } } }).metro;
    return document.getElementById('loading')?.hidden === true && !!m && m.timing().firstFrameMs > 0;
  }, undefined, { timeout: s.firstFrameMs });
  const ms = await page.evaluate(() => (window as unknown as { metro: { timing(): { firstFrameMs: number } } }).metro.timing().firstFrameMs);
  check(ms <= s.firstFrameMs, `first frame ${Math.round(ms)} ms over budget ${s.firstFrameMs} ms (wall ${Date.now() - t0} ms)`);
  return ms;
}

const carPos = (page: Page): Promise<{ x: number; y: number }> =>
  page.evaluate(() => {
    const c = (window as unknown as { metro: { drive: { car: { x: number; y: number } } } }).metro.drive.car;
    return { x: c.x, y: c.y };
  });

async function touch(cdp: CDPSession, type: 'touchStart' | 'touchMove' | 'touchEnd', x: number, y: number): Promise<void> {
  await cdp.send('Input.dispatchTouchEvent', { type, touchPoints: type === 'touchEnd' ? [] : [{ x, y, id: 1 }] });
}

/** One finger from (x, y) by dy in steps, held for holdMs, then lifted. */
async function drag(cdp: CDPSession, x: number, y: number, dy: number, holdMs: number): Promise<void> {
  await touch(cdp, 'touchStart', x, y);
  const n = 12;
  for (let i = 1; i <= n; i++) {
    await touch(cdp, 'touchMove', x, y + (dy * i) / n);
    await new Promise((r) => setTimeout(r, 16));
  }
  if (holdMs > 0) await new Promise((r) => setTimeout(r, holdMs));
  await touch(cdp, 'touchEnd', x, y + dy);
}

/** Text of the feed card in the middle of the feed (null = no card there); names repeat across spots. */
const centreCard = (page: Page): Promise<string | null> =>
  page.evaluate(() => {
    const f = document.querySelector('.feed');
    if (!f) return null;
    const r = f.getBoundingClientRect();
    const el = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
    return el?.closest('.feed-card')?.textContent ?? null;
  });

async function runProfile(browser: Browser, base: string, p: Profile): Promise<Record<string, unknown>> {
  const ctx: BrowserContext = await browser.newContext({
    viewport: { width: p.width, height: p.height },
    deviceScaleFactor: p.dpr,
    isMobile: true,
    hasTouch: true,
    locale: 'cs-CZ',
  });
  const page = await ctx.newPage();
  const errors: string[] = [];
  watchConsole(page, errors);
  const cdp = await ctx.newCDPSession(page);
  const out: Record<string, unknown> = { profile: p.name };
  try {
    // 1. Root URL (debug API on), 2. intro card.
    out['first_frame_ms'] = Math.round(await loadCity(page, `${base}?debug`));
    const go = page.locator('.intro-go');
    if (await go.isVisible().catch(() => false)) await go.tap();
    check(!(await page.locator('.intro').isVisible().catch(() => false)), 'intro card did not close');

    // 3. Drive by touch: thumb up (boost), held.
    const a = await carPos(page);
    await drag(cdp, p.width / 2, p.height * 0.7, -s.dragPx, s.driveS * 1000);
    const b = await carPos(page);
    const moved = Math.hypot(b.x - a.x, b.y - a.y);
    out['drive_m'] = Math.round(moved * 10) / 10;
    check(moved >= s.minDriveM, `car moved ${moved.toFixed(1)} m in ${s.driveS} s, want ≥ ${s.minDriveM} m`);

    // 4. Phone and feed swipe up, then down.
    await page.locator('#buttons button', { hasText: '☎' }).tap();
    const feedApp = page.locator('.phone-app', { hasText: t('cs', 'app_feed') });
    if (await feedApp.isVisible().catch(() => false)) await feedApp.tap();
    await page.waitForSelector('.feed-card', { timeout: 10000 });
    await page.waitForTimeout(400);
    const first = await centreCard(page);
    check(first !== null, 'no feed card in the middle of the feed');
    // Start the swipe on the card, not on its buttons (a touch on a button is not a swipe).
    const { cx, top, bottom } = await page.evaluate((swipe) => {
      const f = document.querySelector('.feed')!.getBoundingClientRect();
      for (let fx = 0.5; fx > 0.05; fx -= 0.1) {
        const x = f.left + f.width * fx;
        for (let y = f.top + f.height * 0.85; y - swipe > f.top + 8; y -= 8) {
          // Inline (no helper): tsx would wrap a named function in __name, unknown in the page.
          if (!document.elementFromPoint(x, y)?.closest('button') && !document.elementFromPoint(x, y - swipe)?.closest('button')) return { cx: x, top: y - swipe, bottom: y };
        }
      }
      return { cx: f.left + 8, top: f.top + 8, bottom: f.top + 8 + swipe };
    }, s.swipePx);
    await drag(cdp, cx, bottom, -s.swipePx, 0);
    await page.waitForTimeout(tuning.phone.feedSnapMs + 400);
    const second = await centreCard(page);
    check(second !== null && second !== first, `swipe up kept the card (${first} → ${second})`);
    await drag(cdp, cx, top, s.swipePx, 0);
    await page.waitForTimeout(tuning.phone.feedSnapMs + 400);
    const back = await centreCard(page);
    check(back === first, `swipe down did not return (${first} → ${second} → ${back})`);

    // 5. Cities.
    const cityMs: Record<string, number> = {};
    for (const c of cities) cityMs[c] = Math.round(await loadCity(page, `${base}?city=${c}&debug&nointro`));
    out['city_first_frame_ms'] = cityMs;

    // 6. Console.
    check(errors.length === 0, `console errors:\n  ${errors.join('\n  ')}`);
    out['ok'] = true;
  } catch (e) {
    out['ok'] = false;
    out['error'] = e instanceof Error ? e.message : String(e);
    if (errors.length) out['console'] = errors;
  } finally {
    await ctx.close();
  }
  return out;
}

async function main(): Promise<void> {
  const preview = argUrl ? null : await startPreview();
  const base = argUrl ?? preview!.url;
  // Software WebGL in headless CI: SwiftShader via ANGLE.
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const results: Record<string, unknown>[] = [];
  try {
    for (const p of profiles) results.push(await runProfile(browser, base, p));
  } finally {
    await browser.close();
    preview?.proc.kill();
  }
  console.log(JSON.stringify(results, null, 1));
  if (results.some((r) => !r['ok'])) process.exit(1);
}

main().catch((e: unknown) => {
  console.error(e);
  process.exit(1);
});
