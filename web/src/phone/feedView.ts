import type { MessageKey } from '../gen/i18n';
import type { TuningPhone } from '../gen/tuning';
import { art, artImage, usable } from '../art';
import { h } from '../minigames/dom';
import { FeedRules, type FeedCard, type FeedOp, type FeedState } from './feed';
import { driveMinutes, formatDistance } from './nav';
import type { TuningNav } from '../gen/tuning';

/**
 * The Feed app UI (specs/phone.md v5 "Gesta karty"): a vertical strip of pages (previous card,
 * current card, next card or feedDone) that follows the finger like TikTok; gestures map to
 * feed rules actions (specs/feed.md v2). Dragging only changes transforms, never the layout.
 */
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
  /** NPC character hosting a card of this spot (its bust replaces the silhouette, specs/art.md). */
  hostOf?: (spotId: string) => string | null;
}

// ---------- pure gesture maths (unit-tested)

export type FeedAxis = 'v' | 'h';
export interface FeedSample {
  /** ms */
  t: number;
  /** finger travel in the locked axis, px */
  p: number;
}

export const easeOutCubic = (u: number): number => 1 - (1 - u) ** 3;

/** Axis lock: none until the finger moves `lockPx` in either axis, then the larger component wins. */
export function lockAxis(dx: number, dy: number, lockPx: number): FeedAxis | null {
  if (Math.max(Math.abs(dx), Math.abs(dy)) < lockPx) return null;
  return Math.abs(dy) >= Math.abs(dx) ? 'v' : 'h';
}

/** Release velocity (px/s): travel from the oldest sample within `windowMs` of the last one to the last. */
export function releaseVelocity(samples: readonly FeedSample[], windowMs: number): number {
  const last = samples.at(-1);
  if (!last) return 0;
  const first = samples.find((x) => x.t >= last.t - windowMs)!;
  const dt = last.t - first.t;
  return dt > 0 ? ((last.p - first.p) * 1000) / dt : 0;
}

/** Strip offset for a vertical drag: 1:1 towards an existing page, rubber band otherwise. */
export function stripOffset(dy: number, hasPrev: boolean, hasNext: boolean, ph: TuningPhone): number {
  const exists = dy < 0 ? hasNext : dy > 0 ? hasPrev : true;
  return exists ? dy : dy * ph.feedRubber;
}

/** Vertical release: the action to commit (`next` up, `prev` down) or null to spring back. */
export function verticalRelease(
  dy: number, v: number, h: number, hasPrev: boolean, hasNext: boolean, ph: TuningPhone,
): 'next' | 'prev' | null {
  if (dy === 0 || !(dy < 0 ? hasNext : hasPrev)) return null;
  const along = dy < 0 ? -v : v;
  const far = Math.abs(dy) > (h * ph.feedCommitPct) / 100;
  return far || along > ph.feedFlickPxS ? (dy < 0 ? 'next' : 'prev') : null;
}

/** Sideways release: `accept` (right), `less` (left) or null to return. */
export function sideRelease(dx: number, v: number, ph: TuningPhone): 'accept' | 'less' | null {
  if (dx === 0) return null;
  const along = dx < 0 ? -v : v;
  return Math.abs(dx) > ph.swipePx || along > ph.feedFlickPxS ? (dx > 0 ? 'accept' : 'less') : null;
}

/** Card tilt (deg) around its bottom edge centre for a sideways drag over a `w` wide feed. */
export const tiltDeg = (dx: number, w: number, ph: TuningPhone): number => (w > 0 ? (ph.feedTiltDeg * dx) / w : 0);

/** Opacity of the sideways action hint. */
export const hintOpacity = (dx: number, ph: TuningPhone): number => Math.min(1, Math.abs(dx) / ph.swipePx);

// ---------- view

interface Drag {
  id: number;
  x0: number;
  y0: number;
  axis: FeedAxis | null;
  /** travel in the locked axis, px */
  d: number;
  samples: FeedSample[];
}

export function mountFeed(host: HTMLElement, env: FeedViewEnv): () => void {
  const { t } = env;
  const ph = env.phone;
  const root = h('div.feed', {});
  host.append(root);
  let lastTap = 0;
  /** A snap / spring-back / fly-off is running: new touches are ignored. */
  let busy = false;
  let raf = 0;
  let strip: HTMLElement = h('div.feed-strip', {});
  /** Current card (null on feedDone) and its two hints. */
  let cur: { el: HTMLElement; go: HTMLElement; less: HTMLElement } | null = null;
  let hasPrev = false;
  let hasNext = false;

  const act = (op: FeedOp): void => {
    const { rules, state } = env.deck();
    if (!rules.legalActions(state).some((a) => a.op === op)) return render();
    const next = rules.apply(state, { by: 'player', op });
    env.setState(next);
    if (op === 'accept') env.onAccept(next.accepted);
    else render();
  };

  function tween(from: number, to: number, apply: (v: number) => void, done?: () => void): void {
    busy = true;
    const ms = ph.feedSnapMs;
    const t0 = performance.now();
    const step = (now: number): void => {
      const u = ms > 0 ? Math.min(1, Math.max(0, (now - t0) / ms)) : 1;
      apply(from + (to - from) * easeOutCubic(u));
      if (u < 1) {
        raf = requestAnimationFrame(step);
        return;
      }
      raf = 0;
      busy = false;
      done?.();
    };
    raf = requestAnimationFrame(step);
  }

  const setStrip = (y: number): void => {
    strip.style.transform = y ? `translate3d(0, ${y}px, 0)` : '';
  };
  const setSide = (dx: number): void => {
    if (!cur) return;
    cur.el.style.transform = dx ? `translate3d(${dx}px, 0, 0) rotate(${tiltDeg(dx, root.clientWidth, ph)}deg)` : '';
    cur.go.style.opacity = dx > 0 ? String(hintOpacity(dx, ph)) : '0';
    cur.less.style.opacity = dx < 0 ? String(hintOpacity(dx, ph)) : '0';
  };

  function tag(text: string, cls = ''): HTMLElement {
    return h(`span.feed-tag${cls}` as 'span.x', {}, text);
  }

  /** Host bust (specs/art.md) anchored at the bottom, else the placeholder silhouette; both bob. */
  function hostEl(spot: string): HTMLElement {
    const silhouette = (): Node[] => [h('div.feed-host-head', {}), h('div.feed-host-body', {})];
    const id = env.hostOf?.(spot) ?? null;
    const path = id ? usable(art().bust(id)) : null;
    if (!path) return h('div.feed-host', {}, ...silhouette());
    const el = h('div.feed-host.art', {});
    el.append(artImage(path, 'feed-host-bust', () => {
      el.classList.remove('art');
      el.replaceChildren(...silhouette());
    }));
    return el;
  }

  function card(c: FeedCard, s: FeedState, at: number): HTMLElement {
    const d = formatDistance(c.distDm / 10, env.imperial, env.nav);
    const name = c.game === 'challenge' ? t('feedChallenge') : t(`mg_${c.game}` as MessageKey);
    const liked = s.liked.includes(c.spot);
    return h('div.feed-card', {},
      hostEl(c.spot),
      h('div.feed-line', {}, t(`feedHost${c.host + 1}` as MessageKey)),
      h('div.feed-name', {}, name, liked ? h('span.feed-liked', {}, ` ♥ ${t('feedLiked')}`) : null),
      h('div.feed-tags', {},
        tag(t(`engine_${c.engine}` as MessageKey)),
        c.local ? tag(t('feedLocal'), '.local') : null,
        tag([env.spotName(c.spot), c.district].filter(Boolean).join(' · ')),
        tag(`${t(d.key, d.args)} · ${t('feedDriveMin', { min: driveMinutes(c.driveS) })}`),
        tag(t('feedReward', { cash: c.reward })),
        tag(t('difficulty', { level: c.difficulty }))),
      // "Jedu" never starts a drag (specs/phone.md v5).
      h('button.feed-go', {
        type: 'button',
        onpointerdown: (e: Event) => e.stopPropagation(),
        onclick: (e: Event) => {
          e.stopPropagation();
          if (!busy && !drag && at === env.deck().state.at) act('accept');
        },
      }, t('feedGo')),
      h('div.feed-foot', {}, t('feedCount', { n: at + 1, total: s.deck.length }), ' · ', t('feedHint')));
  }

  const done = (): HTMLElement =>
    h('div.feed-done', {}, h('div.feed-done-title', {}, t('feedDone')), h('div', {}, t('feedDoneHint')));
  const page = (k: number, el: HTMLElement): HTMLElement => {
    const p = h('div.feed-page', {}, el);
    if (k) p.style.transform = `translate3d(0, ${k * 100}%, 0)`;
    return p;
  };

  /** Rebuilds the three neighbouring pages for the current state, strip centred at 0. */
  function render(): void {
    const { state } = env.deck();
    const c = state.deck[state.at];
    strip = h('div.feed-strip', {});
    cur = null;
    if (state.over || !c) {
      hasPrev = false;
      hasNext = false;
      strip.append(page(0, done()));
    } else {
      hasPrev = state.at > 0;
      hasNext = true;
      if (hasPrev) strip.append(page(-1, card(state.deck[state.at - 1]!, state, state.at - 1)));
      const el = card(c, state, state.at);
      const go = h('div.feed-hint.go', {}, t('feedGo'));
      const less = h('div.feed-hint.less', {}, t('feedLess'));
      el.append(go, less);
      cur = { el, go, less };
      strip.append(page(0, el));
      const n = state.deck[state.at + 1];
      strip.append(page(1, n ? card(n, state, state.at + 1) : done()));
    }
    root.replaceChildren(strip);
  }

  // ---------- gestures (one pointer at a time)
  let drag: Drag | null = null;

  const track = (e: PointerEvent): void => {
    if (!drag) return;
    const dx = e.clientX - drag.x0;
    const dy = e.clientY - drag.y0;
    if (!drag.axis) drag.axis = lockAxis(dx, dy, ph.feedAxisLockPx);
    if (!drag.axis) return;
    drag.d = drag.axis === 'v' ? dy : dx;
    const now = performance.now();
    drag.samples.push({ t: now, p: drag.d });
    while (drag.samples.length > 2 && drag.samples[1]!.t < now - ph.feedVelocityMs) drag.samples.shift();
    if (drag.axis === 'v') setStrip(stripOffset(drag.d, hasPrev, hasNext, ph));
    else setSide(drag.d);
  };

  root.addEventListener('pointerdown', (e) => {
    if (busy || drag || (e.target as HTMLElement).closest('button')) return;
    drag = { id: e.pointerId, x0: e.clientX, y0: e.clientY, axis: null, d: 0, samples: [] };
    try {
      root.setPointerCapture(e.pointerId);
    } catch {
      /* synthetic pointer without an active touch */
    }
  });
  root.addEventListener('pointermove', (e) => {
    if (drag && e.pointerId === drag.id) track(e);
  });
  root.addEventListener('pointercancel', (e) => {
    if (!drag || e.pointerId !== drag.id) return;
    const d = drag;
    drag = null;
    if (d.axis === 'v') tween(stripOffset(d.d, hasPrev, hasNext, ph), 0, setStrip);
    else if (d.axis === 'h') tween(d.d, 0, setSide);
  });
  root.addEventListener('pointerup', (e) => {
    if (!drag || e.pointerId !== drag.id) return;
    track(e);
    const d = drag;
    drag = null;
    if (!d.axis) {
      // A tap: two within double_tap_ms = like.
      const now = performance.now();
      if (cur && now - lastTap <= ph.doubleTapMs) {
        lastTap = 0;
        act('like');
      } else lastTap = now;
      return;
    }
    const v = releaseVelocity(d.samples, ph.feedVelocityMs);
    if (d.axis === 'v') {
      const from = stripOffset(d.d, hasPrev, hasNext, ph);
      const hgt = root.clientHeight;
      const op = verticalRelease(d.d, v, hgt, hasPrev, hasNext, ph);
      if (op) tween(from, op === 'next' ? -hgt : hgt, setStrip, () => act(op));
      else tween(from, 0, setStrip);
      return;
    }
    if (!cur) return;
    const op = sideRelease(d.d, v, ph);
    if (op) tween(d.d, (op === 'accept' ? 1 : -1) * root.clientWidth * 1.5, setSide, () => act(op));
    else tween(d.d, 0, setSide);
  });

  render();
  return () => {
    if (raf) cancelAnimationFrame(raf);
    root.remove();
  };
}
