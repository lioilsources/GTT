// Passport UI for client W (specs/passport.md): postcard card, Passport screen, About the maps.
// Each is a DOM component with mount → unmount, so the phone app can host it later.
import type { MessageKey } from '../gen/i18n';
import { art, artImage, usable } from '../art';
import { h, svg } from '../minigames/dom';
import { overlays } from '../pause';
import { POSTCARD_H, POSTCARD_W, postcardShapes } from './postcard';
import { stampKinds, type StampKind } from './rules';
import { postcardTextKey, postcardTitleKey, type PassportLandmark, type PassportTracker } from './tracker';
import './passport.css';

export interface PassportEnv {
  t(key: MessageKey, args?: Record<string, string | number>): string;
  /** City id for generated postcards (`postcards/<city>/<id>.png`, specs/art.md); none = placeholder. */
  city?: string;
}

/** The generated postcard of a landmark when the index has it, else null. */
function postcardArt(env: PassportEnv, id: string): string | null {
  return env.city ? usable(art().postcard(env.city, id)) : null;
}

/** Postcard picture: the generated 4 : 5 image (contain to card width) or the placeholder 3 : 2 SVG. */
export function postcardPic(env: PassportEnv, lm: Pick<PassportLandmark, 'id' | 'heightM'>): Element {
  const path = postcardArt(env, lm.id);
  if (!path) return postcardSvg(lm);
  const img = artImage(path, 'pp-pic pp-art', () => slot.replaceChildren(postcardSvg(lm)));
  img.width = 1080;
  img.height = 1350;
  const slot = h('div.pp-pic-slot', {}, img);
  return slot;
}

/** The placeholder picture as an inline SVG. */
export function postcardSvg(lm: Pick<PassportLandmark, 'id' | 'heightM'>): SVGSVGElement {
  const root = svg('svg', { viewBox: `0 0 ${POSTCARD_W} ${POSTCARD_H}`, class: 'pp-pic' });
  for (const s of postcardShapes(lm.id, lm.heightM)) {
    if (s.t === 'rect') root.append(svg('rect', { x: s.x, y: s.y, width: s.w, height: s.h, fill: s.fill }));
    else if (s.t === 'circle') root.append(svg('circle', { cx: s.x, cy: s.y, r: s.r, fill: s.fill }));
    else root.append(svg('polygon', { points: s.pts.join(' '), fill: s.fill }));
  }
  return root;
}

/** The postcard card; slides in from below, closes on tap or after `autoCloseS` (0 = never). */
export function mountPostcard(
  host: HTMLElement,
  env: PassportEnv,
  lm: PassportLandmark,
  autoCloseS: number,
  onClose?: () => void,
): () => void {
  const card = h(
    'div.pp-postcard',
    { role: 'dialog' },
    postcardPic(env, lm),
    h('div.pp-postcard-title', {}, env.t(postcardTitleKey(lm.id))),
    h('div.pp-postcard-text', {}, env.t(postcardTextKey(lm.id))),
    h('div.pp-postcard-stamp', {}, env.t('postcardStamped')),
  );
  host.append(card);
  requestAnimationFrame(() => card.classList.add('in'));
  // The game stands until the card closes or auto-closes (specs/pause.md).
  const release = overlays.open('postcard');
  let timer = 0;
  const close = (): void => {
    window.clearTimeout(timer);
    release();
    card.remove();
    onClose?.();
  };
  card.addEventListener('click', close);
  if (autoCloseS > 0) timer = window.setTimeout(close, autoCloseS * 1000);
  return close;
}

/** Short "Stamp: <name>" label for districts and minigames. */
export function showStampToast(host: HTMLElement, env: PassportEnv, name: string, seconds: number): void {
  const el = h('div.pp-toast.pill', {}, env.t('passportStampNew', { name }));
  host.append(el);
  window.setTimeout(() => el.remove(), seconds * 1000);
}

const sectionKey: Record<StampKind, MessageKey> = {
  landmark: 'passportLandmarks',
  district: 'passportDistricts',
  minigame: 'passportMinigames',
  photo: 'passportPhotos',
};

export interface PassportScreenOpts {
  cityName: string;
  onClose(): void;
  onAbout(): void;
  onPostcard(lm: PassportLandmark): void;
}

/** The Passport screen: completion % and a stamp grid per kind. */
export function mountPassport(host: HTMLElement, env: PassportEnv, tracker: PassportTracker, o: PassportScreenOpts): () => void {
  const { t } = env;
  const r = tracker.result;
  const name = (kind: StampKind, id: string): string => {
    if (kind === 'landmark') return t(postcardTitleKey(id));
    if (kind === 'district') return tracker.districtNames.get(id) ?? id;
    if (kind === 'minigame') return t(`mg_${id}` as MessageKey);
    return tracker.photoNames.get(id) ?? id;
  };
  const bar = h('div.pp-progress', {}, h('span', { style: { width: `${r.percent}%` } }));
  const sections = stampKinds.map((kind) => {
    const ids = tracker.state.catalog[kind];
    const [got, of] = r.kinds[kind];
    const grid = h('div.pp-grid');
    for (const id of ids) {
      const owned = tracker.has(kind, id);
      const lm = kind === 'landmark' ? tracker.landmarks.find((l) => l.id === id) : undefined;
      // An owned landmark with a generated postcard shows its thumbnail (cover square) as the mark.
      const thumb = owned && lm ? postcardArt(env, lm.id) : null;
      const mark = h('span.pp-stamp-mark', {}, owned ? '★' : '');
      if (thumb) {
        mark.className = 'pp-stamp-mark pp-thumb';
        mark.textContent = '';
        mark.append(artImage(thumb, 'art-fill', () => {
          mark.className = 'pp-stamp-mark';
          mark.textContent = '★';
        }));
      }
      grid.append(
        h(
          'button.pp-stamp',
          {
            type: 'button',
            className: `pp-stamp${owned ? ' got' : ''}`,
            disabled: !(owned && lm),
            onclick: () => lm && o.onPostcard(lm),
          },
          mark,
          h('span.pp-stamp-name', {}, name(kind, id)),
        ),
      );
    }
    return h(
      'section.pp-section',
      {},
      h('h2', {}, t(sectionKey[kind]), h('span.pp-count', {}, t('passportCount', { got, of }))),
      ids.length ? grid : h('p.pp-muted', {}, t('passportPhotosLater')),
    );
  });
  const root = h(
    'div.pp-screen',
    {},
    h(
      'div.pp-head',
      {},
      h('button.round', { type: 'button', title: t('close'), onclick: o.onClose }, '✕'),
      h('h1', {}, t('passport')),
    ),
    h('div.pp-body', {}, h('p.pp-percent', {}, t('passportProgress', { city: o.cityName, percent: r.percent })), bar, ...sections,
      h('button.pp-link', { type: 'button', onclick: o.onAbout }, t('aboutTitle'))),
  );
  host.append(root);
  const release = overlays.open('passport');
  return () => {
    release();
    root.remove();
  };
}

export interface AboutInfo {
  overtureRelease: string;
  builtAt: string;
}

/** About the maps (M1-S12): data sources and licences. */
export function mountAbout(host: HTMLElement, env: PassportEnv, info: AboutInfo, onClose: () => void): () => void {
  const { t } = env;
  const url = t('aboutRepoUrl');
  const p = (k: MessageKey, a?: Record<string, string | number>): HTMLElement => h('p', {}, t(k, a));
  const root = h(
    'div.pp-screen.pp-about',
    {},
    h('div.pp-head', {}, h('button.round', { type: 'button', title: t('close'), onclick: onClose }, '✕'), h('h1', {}, t('aboutTitle'))),
    h(
      'div.pp-body',
      {},
      p('aboutIntro'),
      p('aboutOsm'),
      p('aboutOverture', { release: info.overtureRelease }),
      p('aboutOverturePlaces'),
      p('aboutCityData'),
      p('aboutShareAlike'),
      p('aboutPostcards'),
      info.builtAt ? h('p.pp-muted', {}, t('aboutPack', { built: info.builtAt })) : null,
      h('p', {}, h('a', { href: url, target: '_blank', rel: 'noopener' }, `${t('aboutSource')}: ${url}`)),
    ),
  );
  host.append(root);
  const release = overlays.open('about');
  return () => {
    release();
    root.remove();
  };
}
