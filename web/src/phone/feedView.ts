import type { MessageKey } from '../gen/i18n';
import type { TuningPhone } from '../gen/tuning';
import { h } from '../minigames/dom';
import { FeedRules, type FeedCard, type FeedOp, type FeedState } from './feed';
import { driveMinutes, formatDistance } from './nav';
import type { TuningNav } from '../gen/tuning';

/** The Feed app UI (specs/phone.md "Feed"): one full-screen card, gestures map to feed rules actions. */
export interface FeedViewEnv {
  t: (k: MessageKey, a?: Record<string, string | number>) => string;
  phone: TuningPhone;
  nav: TuningNav;
  imperial: boolean;
  /** Current deck (dealt on demand by the session). */
  deck: () => { rules: FeedRules; state: FeedState };
  setState: (s: FeedState) => void;
  spotName: (id: string) => string;
  onAccept: (spotId: string) => void;
}

export function mountFeed(host: HTMLElement, env: FeedViewEnv): () => void {
  const { t } = env;
  const root = h('div.feed', {});
  host.append(root);
  let lastTap = 0;

  const act = (op: FeedOp): void => {
    const { rules, state } = env.deck();
    if (!rules.legalActions(state).some((a) => a.op === op)) return;
    const next = rules.apply(state, { by: 'player', op });
    env.setState(next);
    if (op === 'accept') env.onAccept(next.accepted);
    else render();
  };

  function tag(text: string, cls = ''): HTMLElement {
    return h(`span.feed-tag${cls}` as 'span.x', {}, text);
  }

  function card(c: FeedCard, s: FeedState): HTMLElement {
    const d = formatDistance(c.distDm / 10, env.imperial, env.nav);
    const name = c.game === 'challenge' ? t('feedChallenge') : t(`mg_${c.game}` as MessageKey);
    const liked = s.liked.includes(c.spot);
    const el = h('div.feed-card', {},
      h('div.feed-host', {}, h('div.feed-host-head', {}), h('div.feed-host-body', {})),
      h('div.feed-line', {}, t(`feedHost${c.host + 1}` as MessageKey)),
      h('div.feed-name', {}, name, liked ? h('span.feed-liked', {}, ` ♥ ${t('feedLiked')}`) : null),
      h('div.feed-tags', {},
        tag(t(`engine_${c.engine}` as MessageKey)),
        c.local ? tag(t('feedLocal'), '.local') : null,
        tag([env.spotName(c.spot), c.district].filter(Boolean).join(' · ')),
        tag(`${t(d.key, d.args)} · ${t('feedDriveMin', { min: driveMinutes(c.driveS) })}`),
        tag(t('feedReward', { cash: c.reward })),
        tag(t('difficulty', { level: c.difficulty }))),
      h('button.feed-go', { type: 'button', onclick: (e: Event) => { e.stopPropagation(); act('accept'); } }, t('feedGo')),
      h('div.feed-foot', {}, t('feedCount', { n: s.at + 1, total: s.deck.length }), ' · ', t('feedHint')));
    let x0 = 0, y0 = 0, down = false;
    el.addEventListener('pointerdown', (e) => {
      if ((e.target as HTMLElement).closest('button')) return;
      down = true;
      x0 = e.clientX;
      y0 = e.clientY;
      el.setPointerCapture(e.pointerId);
    });
    el.addEventListener('pointermove', (e) => {
      if (down) el.style.transform = `translate(${(e.clientX - x0) * 0.5}px, ${Math.min(0, e.clientY - y0) * 0.5}px)`;
    });
    el.addEventListener('pointercancel', () => {
      down = false;
      el.style.transform = '';
    });
    el.addEventListener('pointerup', (e) => {
      if (!down) return;
      down = false;
      el.style.transform = '';
      const dx = e.clientX - x0, dy = e.clientY - y0, sw = env.phone.swipePx;
      if (-dy > sw && -dy > Math.abs(dx)) return act('next');
      if (dx > sw) return act('accept');
      if (dx < -sw) return act('less');
      if (Math.abs(dx) < 10 && Math.abs(dy) < 10) {
        const now = performance.now();
        if (now - lastTap <= env.phone.doubleTapMs) {
          lastTap = 0;
          act('like');
        } else lastTap = now;
      }
    });
    return el;
  }

  function render(): void {
    const { state } = env.deck();
    const c = state.deck[state.at];
    if (state.over || !c) {
      root.replaceChildren(h('div.feed-done', {}, h('div.feed-done-title', {}, t('feedDone')), h('div', {}, t('feedDoneHint'))));
      return;
    }
    root.replaceChildren(card(c, state));
  }

  render();
  return () => root.remove();
}
