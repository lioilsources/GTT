import './taxi.css';

import { minigameCatalog } from '../../gen/ids';
import type { MinigameContext, MinigameResult } from '../../gen/schema';
import type { Minigame, MinigameEnv } from '../api';
import { h } from '../dom';

/**
 * Taxi in the Gallery (specs/minigames/taxi.md "Galerie a ladění"): it needs the world, so the card
 * says so and its button reloads the client in world mode (`?mg=taxi`), which starts the shift at the
 * taxi stand. The world part lives in ./index.ts.
 */
export function taxi(env: MinigameEnv): Minigame {
  const { t } = env;
  return {
    meta: minigameCatalog.taxi,
    mount(host: HTMLElement, ctx: MinigameContext, onFinish: (r: MinigameResult) => void) {
      const card = h('div.mg-card.taxi-gallery', {},
        h('h2', {}, t('mg_taxi')),
        h('p', {}, t('taxiGallery')),
        h('button.mg-btn', { type: 'button', onclick: () => location.assign(`?mg=taxi&seed=${ctx.seed}`) }, t('taxiGalleryGo')),
        h('button.mg-btn.ghost', { type: 'button', onclick: () => onFinish({ stars: 0, score: 0, playedMs: 0, aborted: true }) }, t('back')));
      host.append(card);
      return () => card.remove();
    },
  };
}
