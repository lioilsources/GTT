import { minigameCatalog, minigameIdValues, type MinigameId } from '../gen/ids';
import type { MessageKey } from '../gen/i18n';
import type { MinigameResult } from '../gen/schema';
import type { DialogueSession } from '../dialogue/session';
import type { MinigameEnv } from './api';
import { overlays } from '../pause';
import { h } from './dom';
import { minigames } from './registry';

/**
 * Debug Gallery (METROPOLE_PLAN 9.2): every catalog minigame without driving.
 * `?gallery` lists them; `?mg=<id>&seed=<n>&level=<1-5>` opens one directly (DUALSTACK 6.6).
 */
export function runGallery(
  host: HTMLElement, env: MinigameEnv, params: URLSearchParams, npc: DialogueSession | null | undefined,
  /** The default start city (specs/cities.md "Co je po městech"). */
  cityId: string,
): void {
  const { t } = env;
  // The gallery runs without the world; it still counts as a pausing overlay (specs/pause.md).
  overlays.open('gallery');
  // NPC opponent for the result-screen line (specs/dialogue.md); ?opponent=<characterId>.
  const opponents = ['', ...(npc?.pack.characters.map((c) => c.id) ?? [])];
  let opponent = Math.max(0, opponents.indexOf(params.get('opponent') ?? ''));
  let level = clampInt(params.get('level'), 1, 5, 3);
  let seed = clampInt(params.get('seed'), 0, 0xffffffff, randomSeed());

  function list(): void {
    const seedLabel = h('span', {}, t('seed', { seed }));
    const levelLabel = h('span', {}, t('difficulty', { level }));
    const oppName = npc?.character(opponents[opponent]!)?.name;
    const oppLabel = h('span', {}, oppName ? t('npcOpponent', { name: oppName }) : t('npcNoOpponent'));
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
        npc ? h('div.gallery-opts', {},
          h('button.round', { type: 'button', onclick: () => { opponent = (opponent + 1) % opponents.length; list(); } }, '☺'), oppLabel,
          h('a', { href: '?skits' }, t('npcSkits'))) : null,
        ...rows),
    );
  }

  function open(id: MinigameId): void {
    const make = minigames[id];
    if (!make) return list();
    host.replaceChildren();
    const opponentId = opponents[opponent] || undefined;
    const game = make({ ...env, opponent: npc?.opponent(opponentId, seed, env.locale) });
    const ctx = { cityId, difficulty: level, seed, locale: env.locale, ...(opponentId ? { opponentId } : {}) };
    const unmount = game.mount(host, ctx, (r: MinigameResult) => {
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
