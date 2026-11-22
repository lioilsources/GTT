// Shops and bars of client W (specs/shops.md P1): shop icons, the "Koupit" / "Bar" button, the shop
// and bar cards (pause kind `shop`), beers and the drunk HUD, the souvenir shelf in the Garage.
import './shops.css';

import type { CarFleet } from '../cars/fleet';
import type { CarsHud } from '../cars/ui';
import { startSkit } from '../dialogue';
import type { DriveWorld } from '../drive/driveWorld';
import type { Locale, MessageKey } from '../gen/i18n';
import { minigameCatalog } from '../gen/ids';
import type { NpcPack } from '../gen/schema';
import { tokens } from '../gen/tokens';
import type { Tuning } from '../gen/tuning';
import type { LoopApi } from '../loop';
import { art, artImage, usable } from '../art';
import { h } from '../minigames/dom';
import { overlays } from '../pause';
import { registerPhoneApp, type PhoneApi } from '../phone';
import type { CameraRig } from '../render/worldView';
import type { City } from '../world/model';
import { barGames, drunkInput, shopHost, shopInReach, shopsActive, shopsOf, ShopsWorld, type Shop } from './shops';
import type { ShopKind } from './rules';

export { ShopsWorld } from './shops';

type T = (k: MessageKey, a?: Record<string, string | number>) => string;

export interface ShopsEnv {
  city: City;
  tuning: Tuning;
  locale: Locale;
  t: T;
  drive: DriveWorld;
  fleet: CarFleet;
  phone: PhoneApi;
  loop: LoopApi;
  carsHud: CarsHud;
  npcPack: NpcPack | null;
  hud: HTMLElement;
  rig: CameraRig;
}

/** The shops feature as main.ts sees it (specs/shops.md). */
export interface ShopsFeature {
  /** Null when shops are off in this city or it has none (no module). */
  readonly world: ShopsWorld | null;
  /** True while too many beers: main.ts replaces the drive input with `brake()`. */
  readonly drunk: boolean;
  /** Per frame with the game dt (0 while paused): the 1 s tick. */
  update(stepDt: number, dt: number): void;
  /** HUD tick (~10×/s): the "Koupit" / "Bar" button, beers and the drunk bar. Call after the photo HUD. */
  hud(): void;
  /** Drunk: overrides the player's input so the car brakes to a stop. */
  brake(): void;
  /** Shop icons on the overlay canvas (CSS pixels). */
  draw(ctx: CanvasRenderingContext2D, w: number, h: number): void;
  /** Opens the card of the shop in reach, or of `id` (debug, tests); false when not offered. */
  open(id?: string): boolean;
  close(): void;
}

const kindColor: Record<ShopKind, string> = {
  food: tokens.colorShopsFood, souvenir: tokens.colorShopsSouvenir, bar: tokens.colorShopsBar,
};

export function installShops(env: ShopsEnv): ShopsFeature {
  const { city, tuning, t, drive, fleet, phone, loop } = env;
  const st = tuning.shops;
  const shops = shopsOf(city.spots.items);
  const nameOf = new Map(shops.map((s) => [s.id, s.name]));
  const active = shopsActive(st, city.id, shops);
  const world = active ? new ShopsWorld(shops, tuning, { get: () => fleet.state.cash, set: (c) => fleet.setCash(c) }) : null;
  if (world) {
    world.load(loop.savedSouvenirs);
    loop.souvenirs = () => [...world.owned];
  }

  // ---------- the shelf (Garage app and the garage list); stays even with the module off
  const shelf = (): HTMLElement => {
    const owned = world ? world.owned : loop.savedSouvenirs;
    const items = owned.map((id) => {
      const path = usable(art().souvenir(id));
      const icon = h('div.shop-shelf-icon', {});
      if (path) icon.append(artImage(path, 'shop-shelf-img', () => icon.classList.remove('has-art')));
      if (path) icon.classList.add('has-art');
      return h('div.shop-shelf-item', {}, icon, h('div.shop-shelf-name', {}, nameOf.get(id) ?? id));
    });
    return h('div.shop-shelf', {},
      h('h2', {}, t('shopShelf')),
      items.length ? h('div.shop-shelf-grid', {}, ...items) : h('p.shop-muted', {}, t('shopShelfEmpty')));
  };
  registerPhoneApp('garage', (host) => {
    host.append(h('div.shop-app', {}, shelf()));
    return () => {};
  });
  env.carsHud.extras.push(shelf);
  if (!world) {
    return { world: null, drunk: false, update() {}, hud() {}, brake() {}, draw() {}, open: () => false, close() {} };
  }

  // Bars with their own minigame play it from the bar card, not from "Hrát".
  for (const s of shops) if (s.kind === 'bar' && s.minigame !== '') loop.noPlay.add(s.id);
  // Cash (spec "Hotovost"): the snack bonus after the economy reward, then `finish` (sobering up).
  loop.book.shops = { reward: (amount) => world.reward(amount), finish: (stars, aborted) => world.finish(stars, aborted) };
  const games = barGames(shops, minigameCatalog);
  const chars = env.npcPack?.characters ?? [];

  // ---------- HUD: context button, beers, drunk bar, toast
  const openBtn = h('button.round', { id: 'shop-open', type: 'button', hidden: true });
  const beersPill = h('div.pill', { id: 'shop-beers', hidden: true });
  const drunkBar = h('div', { id: 'shop-drunk', hidden: true }, t('shopsDrunk'));
  const toast = h('div.pill', { id: 'shop-toast', hidden: true });
  env.hud.append(openBtn, beersPill, drunkBar);
  document.body.append(toast);
  let toastS = 0;
  const showToast = (text: string): void => {
    toast.textContent = text;
    toast.hidden = false;
    toastS = tuning.nav.toastS;
  };
  world.onSober.push(() => showToast(t('shopsSober')));

  let card: { shop: Shop; close: () => void; render: () => void } | null = null;
  /** The same conditions as "Hrát" at a spot (specs/loop.md); never during a minigame or Taxi. */
  const shopHere = (): Shop | null => {
    if (card || loop.busy || loop.inWorldGame || phone.phone.isOpen || phone.nav.active) return null;
    const c = drive.car;
    return shopInReach(shops, c.x, c.y, c.speed, c.layer, tuning.loop);
  };
  // Priority: Zvednout > Foťák > Bar / Koupit > Hrát > Přesednout (spec "Ve světě").
  const prevLoop = loop.yieldTo, prevCars = env.carsHud.yieldTo;
  const canOpen = (): boolean => !prevLoop?.() && shopHere() !== null;
  loop.yieldTo = () => !!prevLoop?.() || card !== null || canOpen();
  env.carsHud.yieldTo = () => !!prevCars?.() || card !== null || canOpen();

  const openCard = (shop: Shop): void => {
    const release = overlays.open('shop');
    const sheet = h('div.mg-sheet.shop-card', {});
    const hi = shopHost(shop.id, chars.length);
    const host = hi >= 0 ? chars[hi]! : null;
    // Host bust (specs/art.md) and the skit under it, both kept across re-renders.
    const bust = host ? usable(art().bust(host.id)) : null;
    const hostPic = bust ? h('div.shop-host', {}) : null;
    if (hostPic && bust) hostPic.append(artImage(bust, 'shop-host-bust', () => hostPic.remove()));
    const skit = h('div.shop-skit', {});
    const close = (): void => {
      release();
      sheet.remove();
      card = null;
    };
    const buyBtn = (label: string, id: string): HTMLElement[] => {
      const ok = world.canBuy(id);
      const btn: HTMLElement = h('button.mg-btn', { type: 'button', disabled: !ok, onclick: () => buy(id) }, label);
      return ok ? [btn] : [btn, h('p.shop-muted', {}, t('shopNoCash'))];
    };
    const render = (): void => {
      const price = world.price(shop.id);
      const rows: Array<HTMLElement | null> = [];
      if (shop.kind === 'bar') {
        rows.push(h('p.shop-what', {}, `${t('shopBeer')} · ${t('cashHud', { cash: price })}`), ...buyBtn(t('shopBeer'), shop.id));
        for (const g of games) {
          rows.push(h('button.mg-btn', { type: 'button', onclick: () => {
            close();
            loop.start(shop.id, g);
          } }, t('shopPlay', { game: t(`mg_${g}` as MessageKey) })));
        }
      } else {
        rows.push(h('p.shop-what', {}, shop.kind === 'food' ? t('shopSnack', { pct: st.snackPct }) : shop.name));
        rows.push(h('p.shop-price', {}, t('cashHud', { cash: price })));
        if (shop.kind === 'souvenir' && world.owned.includes(shop.id)) rows.push(h('p.shop-owned', {}, t('shopOwned')));
        else rows.push(...buyBtn(t('shopBuy'), shop.id));
      }
      const beers = world.state.beers;
      sheet.replaceChildren(h('div.mg-card', {},
        hostPic,
        skit,
        h('h2', { style: { color: kindColor[shop.kind] } }, shop.name),
        ...rows,
        beers > 0 ? h('p.shop-muted', {}, t('shopBeers', { n: beers })) : null,
        h('p.shop-muted', {}, t('cashHud', { cash: fleet.state.cash })),
        h('button.mg-btn.ghost', { type: 'button', onclick: close }, t('shopBack'))));
    };
    const buy = (id: string): void => {
      if (world.buy(id) === null) return;
      if (shop.kind === 'food') showToast(t('shopSnack', { pct: st.snackPct }));
      else if (shop.kind === 'souvenir') {
        showToast(t('shopOwned'));
        void loop.save();
      } else showToast(world.drunk ? t('shopsDrunk') : t('shopBeers', { n: world.state.beers }));
      render();
    };
    render();
    document.body.append(sheet);
    card = { shop, close, render };
    if (host) startSkit(skit, { locale: env.locale, t }, host.id, shop.kind === 'bar' ? 'bar' : 'shop');
    openBtn.hidden = true;
  };

  const open = (id?: string): boolean => {
    const s = id ? (shops.find((x) => x.id === id) ?? null) : canOpen() ? shopHere() : null;
    if (!s || card) return false;
    phone.phone.close();
    openCard(s);
    return true;
  };
  openBtn.addEventListener('click', () => void open());
  window.addEventListener('keydown', (e) => {
    if (e.code === 'Escape' && card) card.close();
  });
  phone.mapPoints.push(() => shops.map((s) => ({ x: s.x, y: s.y, color: kindColor[s.kind] })));

  let shown: Shop | null = null;
  return {
    world,
    get drunk() {
      return world.drunk;
    },
    update(stepDt, dt) {
      world.update(stepDt);
      if (toastS > 0 && (toastS -= dt) <= 0) toast.hidden = true;
    },
    hud() {
      const s = canOpen() ? shopHere() : null;
      if (s !== shown) {
        shown = s;
        openBtn.hidden = s === null;
        if (s) {
          openBtn.textContent = t(s.kind === 'bar' ? 'barOpen' : 'shopOpen');
          openBtn.style.background = kindColor[s.kind];
        }
      }
      const beers = world.state.beers;
      drunkBar.hidden = !world.drunk;
      beersPill.hidden = world.drunk || beers === 0;
      if (!beersPill.hidden) beersPill.textContent = t('shopBeers', { n: beers });
    },
    brake() {
      if (world.drunk) drunkInput(drive.input, drive.car.forwardSpeed, tuning.drive.brakeMinMps);
    },
    draw(ctx, w, hgt) {
      const rig = env.rig;
      const r = Math.max(4, (st.iconM * w) / rig.viewWidth / 2);
      for (const s of shops) {
        const p = rig.toScreen(s.x, s.y, w, hgt, tuning);
        if (p.x < -r || p.y < -r || p.x > w + r || p.y > hgt + r) continue;
        ctx.save();
        ctx.fillStyle = kindColor[s.kind];
        ctx.strokeStyle = tokens.colorUiStreetLabel;
        ctx.lineWidth = Math.max(1, r * 0.18);
        ctx.beginPath();
        ctx.arc(p.x, p.y, r, 0, 2 * Math.PI);
        ctx.fill();
        ctx.stroke();
        ctx.restore();
      }
    },
    open,
    close: () => card?.close(),
  };
}
