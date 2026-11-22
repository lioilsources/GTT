import './phone.css';

import { routeGraphFromPb } from '../drive/gps';
import type { DriveWorld } from '../drive/driveWorld';
import type { MessageKey } from '../gen/i18n';
import { minigameCatalog } from '../gen/ids';
import { tokens } from '../gen/tokens';
import type { Tuning } from '../gen/tuning';
import type { CameraRig } from '../render/worldView';
import { h } from '../minigames/dom';
import type { City } from '../world/model';
import { buildCandidates, feedConfig, FeedRules, type FeedState } from './feed';
import { mountFeed } from './feedView';
import { mountMap } from './mapView';
import { edgeArrow, edgeLengthsDm, feedDistDm, formatDistance, navGoal, navStart, Navigator, type NavTarget } from './nav';
import { Phone, registerPhoneApp } from './phone';

export { registerPhoneApp } from './phone';

export interface PhoneEnv {
  city: City;
  drive: DriveWorld;
  tuning: Tuning;
  t: (k: MessageKey, a?: Record<string, string | number>) => string;
  rig: CameraRig;
  /** Parent for the phone, HUD pill and toast (above the canvases). */
  parent: HTMLElement;
  /** Container of the round HUD buttons. */
  buttons: HTMLElement;
  params: URLSearchParams;
  /** Landmarks the player has discovered (passport stamps), for the feed's landmark bonus. */
  discovered?: () => ReadonlySet<string>;
}

/** The feed state the save keeps (specs/save.md `feed`). */
export interface FeedSave {
  prefs: Record<string, number>;
  visits: Record<string, number>;
  districts: string[];
}

/** The card the player accepted; the loop reads its distance and difficulty on arrival. */
export interface AcceptedCard {
  spot: string;
  distDm: number;
  difficulty: number;
}

export interface PhoneApi {
  /** Once per frame with the real dt. */
  update(dt: number): void;
  /** Route line and edge arrow on the overlay canvas (CSS pixels). */
  draw(ctx: CanvasRenderingContext2D, w: number, h: number): void;
  navigate(spotId: string): boolean;
  /**
   * Navigation to any target (a world minigame's passenger or destination). Silent: on arrival
   * the route just ends (no toast, no visit, no onArrived).
   */
  navigateTo(target: NavTarget, silent: boolean): boolean;
  cancelNav(): void;
  /** arrived(spotId): the minigame launch hook for a later feature. */
  onArrived: Array<(spotId: string) => void>;
  /** The last accepted feed card (cleared by the loop once used). */
  accepted: AcceptedCard | null;
  /**
   * Accepts a spot like a feed card (a booth offer, specs/booths.md): route to the spot,
   * `distDm` = route length as on feed cards, the given difficulty. Does not call onAccept.
   */
  acceptSpot(spotId: string, difficulty: number): boolean;
  /** Called when the player accepts a feed card (spot id). */
  onAccept: Array<(spotId: string) => void>;
  /** Extra points on the Map app (metres, colour), e.g. a ringing booth. */
  mapPoints: Array<() => Array<{ x: number; y: number; color: string }>>;
  feedSave(): FeedSave;
  feedRestore(f: FeedSave): void;
  phone: Phone;
  nav: Navigator;
}

export function installPhone(env: PhoneEnv): PhoneApi {
  const { city, drive, tuning, t } = env;
  const g = city.graph;
  const rg = routeGraphFromPb(city.graphPb, tuning.route.classCost);
  const lens = edgeLengthsDm(city.graphPb);
  const nav = new Navigator(g, rg, tuning.route, tuning.nav);
  const spotById = new Map(city.spots.items.map((s) => [s.id, s]));
  const target = (id: string): NavTarget => {
    const s = spotById.get(id)!;
    return { id: s.id, name: s.name, edge: s.edge, parkX: s.parkX, parkY: s.parkY };
  };

  // ---------- feed session (specs/feed.md "Po balíčku")
  const rules = new FeedRules();
  let deck: { rules: FeedRules; state: FeedState } | null = null;
  let prefs: Record<string, number> = {};
  const visits = new Map<string, number>();
  const visitedDistricts = new Set<string>();
  let driven = 0, arrivedSinceDeal = false;
  let lastX = drive.car.x, lastY = drive.car.y;
  let firstSeed = env.params.has('feedSeed') ? Number.parseInt(env.params.get('feedSeed')!, 10) >>> 0 : null;

  /** Integer road distance from the car to a spot, as on feed cards (specs/feed.md). */
  const distTo = (id: string, start: ReturnType<typeof navStart>): number => {
    const c = drive.car;
    return feedDistDm(rg, lens, start, navGoal(g, target(id)), c.x, c.y, target(id), tuning.feed.straightPct);
  };
  const deal = (): void => {
    const c = drive.car;
    const start = navStart(g, drive.layers.hit, c.x, c.y, c.heading, tuning.nav.searchM);
    const candidates = buildCandidates({
      cityId: city.id,
      spots: city.spots.items.map((s) => ({ id: s.id, minigame: s.minigame, x: s.x, y: s.y })),
      catalog: minigameCatalog,
      districtAt: (x, y) => city.districtAt(x / 10, y / 10) ?? '',
      landmarks: city.landmarks.items.map((l) => ({ id: l.id, x: l.x, y: l.y })),
      discovered: env.discovered?.() ?? new Set(),
      visits,
      landmarkRadiusDm: tuning.feed.landmarkRadiusDm,
      distDm: (id) => distTo(id, start),
    });
    const seed = firstSeed ?? (Math.random() * 0x100000000) >>> 0;
    firstSeed = null;
    deck = { rules, state: rules.init(feedConfig(tuning.feed, candidates, prefs, [...visitedDistricts]), seed) };
    driven = 0;
    arrivedSinceDeal = false;
  };
  const currentDeck = (): { rules: FeedRules; state: FeedState } => {
    if (!deck || (deck.state.over && (driven >= tuning.feed.redealM || arrivedSinceDeal))) deal();
    return deck!;
  };

  // ---------- phone
  const phone = new Phone(env.parent, tuning.phone, t);
  const phoneBtn = h('button.round', { type: 'button', title: t('phone'), onclick: () => phone.toggle() }, '☎');
  env.buttons.append(phoneBtn);

  registerPhoneApp('feed', (host) =>
    mountFeed(host, {
      t,
      phone: tuning.phone,
      nav: tuning.nav,
      imperial: city.imperial,
      deck: currentDeck,
      setState: (s) => {
        deck!.state = s;
        prefs = s.prefs;
      },
      spotName: (id) => spotById.get(id)?.name ?? id,
      onAccept: (id) => {
        const card = deck?.state.deck.find((c) => c.spot === id);
        api.accepted = card ? { spot: id, distDm: card.distDm, difficulty: card.difficulty } : null;
        phone.close();
        navigate(id);
        for (const f of api.onAccept) f(id);
      },
    }),
  );
  registerPhoneApp('map', (host) =>
    mountMap(host, {
      graph: g,
      spots: city.spots,
      area: city.area,
      phone: tuning.phone,
      player: () => drive.car,
      route: () => nav.ahead(),
      target: () => nav.target?.id ?? null,
      extra: () => api.mapPoints.flatMap((f) => f()),
    }),
  );

  // ---------- navigation HUD
  const pillText = h('span', {});
  const cancel = h('button.route-cancel', { type: 'button', title: t('routeCancel'), onclick: () => stopNav() }, '✕');
  const pill = h('div.pill.route-pill', { hidden: true }, pillText, cancel);
  const toast = h('div.pill.route-toast', { hidden: true });
  env.parent.append(pill, toast);
  let toastTimer = 0;
  const showToast = (text: string): void => {
    toast.textContent = text;
    toast.hidden = false;
    toastTimer = tuning.nav.toastS;
  };
  let silent = false;
  const stopNav = (): void => {
    nav.cancel();
    pill.hidden = true;
    silent = false;
  };

  function navigateTo(tg: NavTarget, quiet: boolean): boolean {
    const c = drive.car;
    const ok = nav.start(tg, c.x, c.y, c.heading, drive.layers.hit);
    silent = quiet;
    if (!ok && !quiet) showToast(t('noRoute'));
    pill.hidden = false;
    return ok;
  }

  function navigate(id: string): boolean {
    if (!spotById.has(id)) return false;
    return navigateTo(target(id), false);
  }

  const api: PhoneApi = {
    phone,
    nav,
    onArrived: [],
    accepted: null,
    onAccept: [],
    mapPoints: [],
    acceptSpot(id, difficulty) {
      if (!spotById.has(id)) return false;
      const c = drive.car;
      const distDm = distTo(id, navStart(g, drive.layers.hit, c.x, c.y, c.heading, tuning.nav.searchM));
      api.accepted = { spot: id, distDm, difficulty };
      phone.close();
      return navigate(id);
    },
    feedSave: () => ({ prefs: { ...prefs }, visits: Object.fromEntries(visits), districts: [...visitedDistricts] }),
    feedRestore(f) {
      prefs = { ...f.prefs };
      visits.clear();
      for (const [k, v] of Object.entries(f.visits)) visits.set(k, v);
      visitedDistricts.clear();
      for (const d of f.districts) visitedDistricts.add(d);
      deck = null;
    },
    navigate,
    navigateTo,
    cancelNav: stopNav,
    update(dt) {
      const c = drive.car;
      driven += Math.hypot(c.x - lastX, c.y - lastY);
      lastX = c.x;
      lastY = c.y;
      if (toastTimer > 0 && (toastTimer -= dt) <= 0) toast.hidden = true;
      if (!nav.active) return;
      const ev = nav.update(c.x, c.y, c.heading, drive.layers.hit, dt);
      if (ev === 'arrived' && silent) {
        stopNav();
        return;
      }
      if (ev === 'arrived') {
        const id = nav.target!.id;
        stopNav();
        visits.set(id, (visits.get(id) ?? 0) + 1);
        const s = spotById.get(id)!;
        const d = city.districtAt(s.x / 10, s.y / 10);
        if (d) visitedDistricts.add(d);
        arrivedSinceDeal = true;
        showToast(t('arrived'));
        for (const f of api.onArrived) f(id);
        return;
      }
      const d = formatDistance(nav.remaining, city.imperial, tuning.nav);
      pillText.textContent = t('routeTo', { place: nav.target!.name, distance: t(d.key, d.args) });
    },
    draw(ctx, w, hgt) {
      if (!nav.active) return;
      const rig = env.rig;
      const pts = nav.ahead();
      if (pts.length >= 4) {
        ctx.strokeStyle = tokens.colorUiRoute;
        ctx.lineWidth = (tuning.route.lineWidthM * w) / rig.viewWidth;
        ctx.lineCap = ctx.lineJoin = 'round';
        ctx.beginPath();
        for (let i = 0; i + 1 < pts.length; i += 2) {
          const p = rig.toScreen(pts[i]!, pts[i + 1]!, w, hgt, tuning);
          if (i === 0) ctx.moveTo(p.x, p.y);
          else ctx.lineTo(p.x, p.y);
        }
        ctx.stroke();
      }
      const p = rig.toScreen(nav.parkX, nav.parkY, w, hgt, tuning);
      const a = edgeArrow(p.x, p.y, w, hgt, tuning.nav.arrowMarginPx, w * tuning.carAnchor.x, hgt * tuning.carAnchor.y);
      if (!a) return;
      const s = tuning.nav.arrowPx;
      ctx.save();
      ctx.translate(a.x, a.y);
      ctx.rotate(a.angle);
      ctx.fillStyle = tokens.colorUiRouteArrow;
      ctx.beginPath();
      ctx.moveTo(s, 0);
      ctx.lineTo(-s * 0.7, s * 0.8);
      ctx.lineTo(-s * 0.3, 0);
      ctx.lineTo(-s * 0.7, -s * 0.8);
      ctx.closePath();
      ctx.fill();
      ctx.restore();
    },
  };

  // ?goto=<spotId> starts navigation right away (specs/phone.md "Ladění").
  const go = env.params.get('goto');
  if (go) navigate(go);
  return api;
}
