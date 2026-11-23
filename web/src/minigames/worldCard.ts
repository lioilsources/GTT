import type { MessageKey } from '../gen/i18n';
import { minigameCatalog, type MinigameId } from '../gen/ids';
import type { MinigameContext, MinigameResult } from '../gen/schema';
import type { Minigame, MinigameEnv } from './api';
import { h } from './dom';

/**
 * Gallery card of a world minigame (engine `drive`, like Taxi): it needs the city, so the card says
 * so and its button reloads the client in world mode (`?mg=<id>`), which starts it at its spot.
 */
export function worldCard(id: MinigameId, text: MessageKey, go: MessageKey): (env: MinigameEnv) => Minigame {
  return (env: MinigameEnv): Minigame => ({
    meta: minigameCatalog[id],
    mount(host: HTMLElement, ctx: MinigameContext, onFinish: (r: MinigameResult) => void) {
      const { t } = env;
      const card = h('div.mg-card.world-gallery', {},
        h('h2', {}, t(`mg_${id}` as MessageKey)),
        h('p', {}, t(text)),
        h('button.mg-btn', { type: 'button', onclick: () => location.assign(`?mg=${id}&seed=${ctx.seed}`) }, t(go)),
        h('button.mg-btn.ghost', { type: 'button', onclick: () => onFinish({ stars: 0, score: 0, playedMs: 0, aborted: true }) }, t('back')));
      host.append(card);
      return () => card.remove();
    },
  });
}
