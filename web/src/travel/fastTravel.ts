// Fast travel of client W (specs/travel.md P1): station unlocking, the "Metro" button and card,
// the Taxi phone app, the line card and the move.
import './fast.css';

import type { CarFleet } from '../cars/fleet';
import type { DriveWorld } from '../drive/driveWorld';
import type { MessageKey } from '../gen/i18n';
import { minigameCatalog } from '../gen/ids';
import { tokens } from '../gen/tokens';
import type { Tuning } from '../gen/tuning';
import type { LoopApi } from '../loop';
import { h } from '../minigames/dom';
import { overlays } from '../pause';
import { registerPhoneApp, type PhoneApi } from '../phone';
import type { CameraRig } from '../render/worldView';
import type { City } from '../world/model';
import { moveTo, stationsOf, taxiChoices, taxiTargets, travelOffered, TravelWorld, type MoveWorld, type TravelPoint } from './fast';

type T = (k: MessageKey, a?: Record<string, string | number>) => string;

export interface FastTravelEnv {
  city: City;
  tuning: Tuning;
  t: T;
  drive: DriveWorld;
  fleet: CarFleet;
  phone: PhoneApi;
  loop: LoopApi;
  /** Current wanted level (specs/police.md). */
  wanted: () => number;
  /** Roadblock reset of the police (null without police). */
  police: { clearRoadblock(): void } | null;
  peds: { clear(): void } | null;
  hud: HTMLElement;
  rig: CameraRig;
  /** After the move: the view rebuilds the car mesh and snaps the camera. */
  onMoved(): void;
}

export interface FastTravelFeature {
  /** Null when travel is off (no module). */
  readonly world: TravelWorld | null;
  /** HUD tick (~10×/s): unlocking by passing, the "Metro" button. */
  hud(dt: number): void;
  /** Station entrances on the overlay canvas (CSS pixels). */
  draw(ctx: CanvasRenderingContext2D, w: number, h: number): void;
  /** Opens the metro card at the station in reach (debug, tests); false when not offered. */
  openMetro(): boolean;
  /** Takes a taxi to the target id (debug, tests); false when not offered or not affordable. */
  taxi(id: string): boolean;
}

const off: FastTravelFeature = { world: null, hud() {}, draw() {}, openMetro: () => false, taxi: () => false };

export function installFastTravel(env: FastTravelEnv): FastTravelFeature {
  const { city, tuning, t, drive, fleet, phone, loop } = env;
  const tr = tuning.travel;
  if (!tr.enabled) return off;
  const stations = stationsOf(city.spots.items);
  const world = new TravelWorld(stations, tuning, { get: () => fleet.state.cash, set: (c) => fleet.setCash(c) });
  world.load(loop.savedStations);
  loop.stations = () => [...world.unlocked];
  const targets = taxiTargets(city.spots.items, minigameCatalog, city.graph, city.landmarks.items, tuning.minigames.taxi.destSearchM);
  const move: MoveWorld = { drive, peds: env.peds, police: env.police };

  // ---------- HUD: metro button, unlock toast
  const metroBtn = h('button.round', { id: 'travel-metro', type: 'button', hidden: true }, t('travelMetro'));
  const toast = h('div.pill', { id: 'travel-toast', hidden: true });
  env.hud.append(metroBtn, toast);
  let toastS = 0;
  let closeCard: (() => void) | null = null;
  let cutting = false;

  const offered = (): boolean => !cutting && travelOffered({ busy: loop.busy, inWorldGame: loop.inWorldGame, wanted: env.wanted() });
  const stationHere = (): TravelPoint | null => {
    const c = drive.car;
    if (!offered() || closeCard || phone.phone.isOpen) return null;
    return world.stationAt(c.x, c.y, c.speed, c.layer, tuning.loop);
  };

  /** The line card over the world for travel.cut_s, the move under it (spec "Přesun"). */
  const travel = (p: TravelPoint, icon: string): void => {
    cutting = true;
    phone.phone.close();
    const release = overlays.open('travel');
    const card = h('div.travel-cut', {},
      h('div.travel-cut-icon', {}, icon),
      h('div.travel-cut-line', {}),
      h('div', {}, t('travelTo', { name: p.name })));
    document.body.append(card);
    moveTo(move, p);
    env.onMoved();
    void loop.save();
    setTimeout(() => {
      card.remove();
      release();
      cutting = false;
      // The accepted card and the navigation stay; the route is recomputed from the new place.
      const tg = phone.nav.active ? phone.nav.target : null;
      if (tg) phone.navigateTo(tg, false);
    }, tr.cutS * 1000);
  };

  const openCard = (from: TravelPoint): void => {
    const release = overlays.open('travel');
    const close = (): void => {
      release();
      sheet.remove();
      closeCard = null;
    };
    const rows = world.metroChoices(from.id).map((ch) =>
      h('button.mg-btn', {
        type: 'button',
        disabled: !ch.affordable,
        onclick: () => {
          if (world.metro(from.id, ch.point.id) === null) return;
          close();
          travel(ch.point, 'M');
        },
      }, t('travelFare', { name: ch.point.name, fare: ch.fare })));
    const sheet = h('div.mg-sheet.travel-card', {},
      h('div.mg-card', {},
        h('h2', {}, from.name),
        ...rows,
        world.anyLocked ? h('p.travel-hint', {}, t('travelLocked')) : null,
        h('button.mg-btn.ghost', { type: 'button', onclick: close }, t('travelClose'))));
    document.body.append(sheet);
    closeCard = close;
  };
  const openMetro = (): boolean => {
    const s = stationHere();
    if (!s) return false;
    openCard(s);
    metroBtn.hidden = true;
    return true;
  };
  metroBtn.addEventListener('click', () => void openMetro());

  // ---------- Taxi phone app (specs/phone.md v4)
  const taxi = (id: string): boolean => {
    if (!offered()) return false;
    const c = drive.car;
    const ch = taxiChoices(targets, c.x, c.y, fleet.state.cash, world.config).find((x) => x.point.id === id);
    if (!ch || !ch.affordable || world.taxi(ch.distDm) === null) return false;
    travel(ch.point, '⇢');
    return true;
  };
  registerPhoneApp('taxi', (host) => {
    if (env.wanted() > 0) {
      host.append(h('div.taxi-app', {}, h('p', {}, t('travelWanted'))));
      return () => {};
    }
    const c = drive.car;
    const can = offered();
    const rows = taxiChoices(targets, c.x, c.y, fleet.state.cash, world.config).map((ch) =>
      h('button.travel-row', { type: 'button', disabled: !can || !ch.affordable, onclick: () => void taxi(ch.point.id) },
        h('span.travel-name', {}, t('travelFare', { name: ch.point.name, fare: ch.fare }))));
    host.append(h('div.taxi-app', {}, ...rows));
    return () => {};
  });
  phone.mapPoints.push(() => world.unlocked.map((id) => {
    const s = world.station(id)!;
    return { x: s.x, y: s.y, color: tokens.colorTravelEntry };
  }));

  return {
    world,
    hud(dt) {
      if (toastS > 0 && (toastS -= dt) <= 0) toast.hidden = true;
      const c = drive.car;
      const fresh = world.pass(c.x, c.y, c.layer, tr.unlockM);
      if (fresh.length > 0) {
        toast.textContent = t('travelUnlocked', { name: fresh[fresh.length - 1]!.name });
        toast.hidden = false;
        toastS = tuning.nav.toastS;
        void loop.save();
      }
      metroBtn.hidden = stationHere() === null;
    },
    draw(ctx, w, hgt) {
      if (stations.length === 0) return;
      const rig = env.rig;
      const ppm = w / rig.viewWidth;
      const ew = tr.entryWM * ppm, el = tr.entryLM * ppm;
      for (const s of stations) {
        const p = rig.toScreen(s.x, s.y, w, hgt, tuning);
        if (p.x < -el || p.y < -el || p.x > w + el || p.y > hgt + el) continue;
        ctx.save();
        ctx.translate(p.x, p.y);
        ctx.rotate(rig.screenAngle(s.heading));
        ctx.fillStyle = world.isUnlocked(s.id) ? tokens.colorTravelEntry : tokens.colorTravelEntryLocked;
        ctx.fillRect(-el / 2, -ew / 2, el, ew);
        ctx.restore();
      }
    },
    openMetro,
    taxi,
  };
}
