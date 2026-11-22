import type { MessageKey } from '../gen/i18n';
import { h } from '../minigames/dom';
import { overlays } from '../pause';
import type { LoopOutcome } from './logic';

type T = (k: MessageKey, a?: Record<string, string | number>) => string;

/** The loop result card over the paused world (specs/loop.md "Výsledek smyčky"). */
export function mountLoopResult(
  parent: HTMLElement,
  t: T,
  o: LoopOutcome,
  on: { drive(): void; feed(): void },
): () => void {
  const name = t(`mg_${o.minigame}` as MessageKey);
  const stars = h('div.mg-stars', {}, ...[0, 1, 2].map((i) => h('span', { className: i < o.stars ? 'on' : 'off' }, '★')));
  const c = o.cash;
  const parts: Array<[MessageKey, number]> = [['loopBase', c.base], ['loopTrip', c.trip], ['loopBand', c.band], ['loopFirst', c.first]];
  const sheet = h('div.mg-sheet.loop-result', {},
    h('div.mg-card', {},
      h('h2', {}, t('loopTitle')),
      h('p.loop-game', {}, name),
      stars,
      h('p', {}, t('scoreValue', { score: o.score })),
      o.aborted ? h('p.loop-muted', {}, t('loopAborted')) : h('p.loop-cash', {}, t('loopCash', { cash: c.amount + o.booth + o.snack })),
      ...parts.filter(([, v]) => v > 0).map(([k, v]) => h('p.loop-part', {}, t(k, { cash: v }))),
      o.booth > 0 ? h('p.loop-part.loop-booth', {}, t('loopBooth', { cash: o.booth })) : null,
      o.snack > 0 ? h('p.loop-part.loop-snack', {}, t('loopSnack', { cash: o.snack })) : null,
      o.stamp ? h('p.loop-stamp', {}, t('loopStamp', { name })) : !o.hasStamp ? h('p.loop-muted', {}, t('loopStampHint')) : null,
      o.newBest && o.stars > 0 ? h('p.loop-best', {}, t('loopBest')) : null,
      h('p.loop-muted', {}, t('cashHud', { cash: o.total })),
      h('button.mg-btn', { type: 'button', onclick: () => { close(); on.drive(); } }, t('loopDrive')),
      h('button.mg-btn.ghost', { type: 'button', onclick: () => { close(); on.feed(); } }, t('loopFeed'))),
  );
  parent.append(sheet);
  const release = overlays.open('result');
  const close = (): void => {
    release();
    sheet.remove();
  };
  return close;
}
