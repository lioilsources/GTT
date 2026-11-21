import { minigameCatalog, minigameIdValues, type MinigameId } from '../gen/ids';
import type { MessageKey } from '../gen/i18n';
import type { MinigameResult } from '../gen/schema';
import type { MinigameEnv } from './api';
import { h } from './dom';
import { minigames } from './registry';

/**
 * Debug Gallery (METROPOLE_PLAN 9.2): every catalog minigame without driving.
 * `?gallery` lists them; `?mg=<id>&seed=<n>&level=<1-5>` opens one directly (DUALSTACK 6.6).
 */
export function runGallery(host: HTMLElement, env: MinigameEnv, params: URLSearchParams): void {
  const { t } = env;
  let level = clampInt(params.get('level'), 1, 5, 3);
  let seed = clampInt(params.get('seed'), 0, 0xffffffff, randomSeed());

  function list(): void {
    const seedLabel = h('span', {}, t('seed', { seed }));
    const levelLabel = h('span', {}, t('difficulty', { level }));
    const rows = minigameIdValues.map((id) => {
      const has = id in minigames;
      return h('button.gallery-row', { type: 'button', disabled: !has, onclick: () => open(id) },
        h('span.name', {}, t(`mg_${id}` as MessageKey)),
        h('span.meta', {}, has ? `${minigameCatalog[id].engine} · ${Math.round(minigameCatalog[id].targetLengthS / 60)} min` : t('notYet')));
    });
    host.replaceChildren(
      h('div.gallery', {},
        h('h1', {}, t('gallery')),
        h('div.gallery-opts', {},
          h('button.round', { type: 'button', onclick: () => { level = level % 5 + 1; list(); } }, '±'), levelLabel,
          h('button.round', { type: 'button', onclick: () => { seed = randomSeed(); list(); } }, '⟳'), seedLabel),
        ...rows),
    );
  }

  function open(id: MinigameId): void {
    const make = minigames[id];
    if (!make) return list();
    host.replaceChildren();
    const game = make(env);
    const unmount = game.mount(host, { cityId: 'nyc', difficulty: level, seed, locale: env.locale }, (r: MinigameResult) => {
      console.info('[metro minigame]', id, JSON.stringify(r));
      unmount();
      seed = randomSeed();
      list();
    });
  }

  const direct = params.get('mg') as MinigameId | null;
  if (direct && (minigameIdValues as readonly string[]).includes(direct)) open(direct);
  else list();
}

function clampInt(v: string | null, lo: number, hi: number, dflt: number): number {
  const n = v === null ? NaN : Number.parseInt(v, 10);
  return Number.isFinite(n) ? Math.min(hi, Math.max(lo, n)) : dflt;
}

function randomSeed(): number {
  return (Math.random() * 0xffffffff) >>> 0;
}
