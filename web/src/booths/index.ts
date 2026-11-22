import './booths.css';

import type { CarsHud } from '../cars/ui';
import type { DriveWorld } from '../drive/driveWorld';
import type { MessageKey } from '../gen/i18n';
import { minigameCatalog } from '../gen/ids';
import type { NpcPack } from '../gen/schema';
import { tokens } from '../gen/tokens';
import type { Tuning } from '../gen/tuning';
import type { LoopApi } from '../loop';
import { art, artImage, usable } from '../art';
import { h } from '../minigames/dom';
import { overlays } from '../pause';
import type { PhoneApi } from '../phone';
import { edgeArrow } from '../phone/nav';
import type { CameraRig } from '../render/worldView';
import type { City } from '../world/model';
import { boothGames, boothHost, boothInReach, boothsOf, BoothWorld, nearBooths, type Booth } from './booths';
import type { BoothOffer } from './rules';

export { BoothWorld } from './booths';

type T = (k: MessageKey, a?: Record<string, string | number>) => string;

/** The booths feature as main.ts sees it (specs/booths.md). */
export interface BoothsFeature {
  /** Null when booths are off or the city has none (no module). */
  readonly world: BoothWorld | null;
  /** Per frame: `stepDt` = game dt (0 while paused), `dt` = real frame dt (pulse, toast). */
  update(stepDt: number, dt: number): void;
  /** HUD tick (~10×/s): the "Zvednout" button. Call before the cars HUD and the loop. */
  hud(): void;
  /** Booths, ring pulse and the edge arrow on the overlay canvas (CSS pixels). */
  draw(ctx: CanvasRenderingContext2D, w: number, h: number): void;
  /** Drops the offer (city switch). */
  clear(): void;
  /** Opens the offer of the ringing booth as if "Zvednout" was pressed (debug, tests). */
  answer(): BoothOffer | null;
}

export interface BoothsEnv {
  city: City;
  tuning: Tuning;
  t: T;
  drive: DriveWorld;
  phone: PhoneApi;
  loop: LoopApi;
  carsHud: CarsHud;
  /** Current wanted level (specs/police.md). */
  wanted: () => number;
  npcPack: NpcPack | null;
  hud: HTMLElement;
  rig: CameraRig;
  seed?: number;
}

const off: BoothsFeature = { world: null, update() {}, hud() {}, draw() {}, clear() {}, answer: () => null };

/** Ringing booths of client W: tick, reach, "Zvednout", the offer card, bonus and drawing. */
export function installBooths(env: BoothsEnv): BoothsFeature {
  const { city, tuning, t, drive, phone, loop } = env;
  const bt = tuning.booths;
  const spots = city.spots.items;
  const booths = boothsOf(spots);
  if (!bt.enabled || booths.length === 0) return off;
  const world = new BoothWorld(booths, tuning, boothGames(spots, minigameCatalog), env.seed ?? (Math.random() * 0x100000000) >>> 0);
  const spotById = new Map(spots.map((s) => [s.id, s]));
  const chars = env.npcPack?.characters ?? [];

  // ---------- HUD: answer button, ringing toast, offer card
  const answerBtn = h('button.round', { id: 'booth-answer', type: 'button', hidden: true }, t('boothAnswer'));
  const toast = h('div.pill', { id: 'booth-toast', hidden: true });
  env.hud.append(answerBtn, toast);
  let toastS = 0;
  world.onRing.push(() => {
    toast.textContent = t('boothRinging');
    toast.hidden = false;
    toastS = tuning.nav.toastS;
  });
  let closeCard: (() => void) | null = null;

  /** Ringing is suppressed during navigation, a minigame, Taxi and while wanted (spec "Dosah"). */
  const quiet = (): boolean => phone.nav.active || loop.busy || loop.inWorldGame || env.wanted() > 0;
  const near = (): number[] => (quiet() ? [] : nearBooths(booths, drive.car.x, drive.car.y, bt.ringMinM, bt.ringMaxM));
  /** "Zvednout": the same conditions as "Hrát" at a spot (specs/loop.md). */
  const canAnswer = (): boolean => {
    const b = world.ringing, c = drive.car;
    if (!b || closeCard || loop.busy || phone.phone.isOpen || phone.nav.active || loop.inWorldGame) return false;
    return boothInReach(b, c.x, c.y, c.speed, c.layer, tuning.loop);
  };
  loop.yieldTo = canAnswer;
  env.carsHud.yieldTo = canAnswer;

  const openCard = (booth: Booth, offer: BoothOffer): void => {
    const spot = spotById.get(offer.spot);
    const hi = boothHost(booth.id, chars.length);
    const host = hi >= 0 ? chars[hi]!.name : booth.name;
    const game = spot?.minigame ? t(`mg_${spot.minigame}` as MessageKey) : offer.spot;
    const release = overlays.open('booth');
    const close = (): void => {
      release();
      sheet.remove();
      closeCard = null;
    };
    // Host bust (specs/art.md) above the call; without the file the card stays as before.
    const bust = hi >= 0 ? usable(art().bust(chars[hi]!.id)) : null;
    const hostPic = bust ? h('div.booth-host', {}) : null;
    if (hostPic && bust) hostPic.append(artImage(bust, 'booth-host-bust', () => hostPic.remove()));
    const sheet = h('div.mg-sheet.booth-offer', {},
      h('div.mg-card', {},
        hostPic,
        h('h2', {}, booth.name),
        h('p', {}, t('boothCall', { host, game, place: spot?.name ?? offer.spot, bonus: offer.bonus })),
        h('button.mg-btn', { type: 'button', onclick: () => {
          close();
          // "Jedu" = an accepted feed card: route, driveDm = route length, feed.difficulty_base.
          phone.acceptSpot(offer.spot, tuning.feed.difficultyBase);
        } }, t('boothGo')),
        h('button.mg-btn.ghost', { type: 'button', onclick: () => {
          close();
          world.clear();
        } }, t('boothSkip'))));
    document.body.append(sheet);
    closeCard = close;
  };
  const answer = (): BoothOffer | null => {
    const b = world.ringing;
    if (!b) return null;
    const offer = world.answer(world.state.ringing);
    if (offer) openCard(b, offer);
    answerBtn.hidden = true;
    return offer;
  };
  answerBtn.addEventListener('click', () => {
    if (canAnswer()) answer();
  });

  // ---------- bonus and clears (spec "Bonus")
  loop.book.bonus = (spot, stars, aborted) => world.finish(spot, stars, aborted);
  phone.onAccept.push(() => world.clear());
  phone.mapPoints.push(() => {
    const b = world.ringing;
    return b ? [{ x: b.x, y: b.y, color: tokens.colorBoothRing }] : [];
  });

  let clock = 0;
  return {
    world,
    update(stepDt, dt) {
      world.update(stepDt, near);
      clock += dt;
      if (toastS > 0 && (toastS -= dt) <= 0) toast.hidden = true;
      if (!world.ringing && !answerBtn.hidden) answerBtn.hidden = true;
    },
    hud() {
      answerBtn.hidden = !canAnswer();
    },
    draw(ctx, w, hgt) {
      const rig = env.rig;
      const ppm = w / rig.viewWidth;
      const ring = world.ringing;
      for (const b of booths) {
        const p = rig.toScreen(b.x, b.y, w, hgt, tuning);
        const bw = bt.boothWM * ppm, bl = bt.boothLM * ppm;
        if (p.x < -bl || p.y < -bl || p.x > w + bl || p.y > hgt + bl) continue;
        ctx.save();
        ctx.translate(p.x, p.y);
        ctx.rotate(rig.screenAngle(b.heading));
        ctx.fillStyle = tokens.colorBoothBody;
        ctx.fillRect(-bl / 2, -bw / 2, bl, bw);
        ctx.strokeStyle = tokens.colorBoothRoof;
        ctx.lineWidth = Math.max(1, bw / 5);
        ctx.strokeRect(-bl / 2, -bw / 2, bl, bw);
        ctx.restore();
      }
      if (!ring) return;
      const p = rig.toScreen(ring.x, ring.y, w, hgt, tuning);
      // Pulse: a ring growing to the answer reach (loop.spot_radius_m) once per ring_pulse_s.
      const phase = bt.ringPulseS > 0 ? (clock % bt.ringPulseS) / bt.ringPulseS : 0;
      ctx.save();
      ctx.globalAlpha = 1 - phase;
      ctx.strokeStyle = tokens.colorBoothRing;
      ctx.lineWidth = Math.max(2, bt.boothWM * ppm * 0.25);
      ctx.beginPath();
      ctx.arc(p.x, p.y, Math.max(1, tuning.loop.spotRadiusM * ppm * phase), 0, 2 * Math.PI);
      ctx.stroke();
      ctx.restore();
      // Edge arrow towards an off-screen ringing booth (as navigation, specs/phone.md).
      const a = edgeArrow(p.x, p.y, w, hgt, tuning.nav.arrowMarginPx, w * tuning.carAnchor.x, hgt * tuning.carAnchor.y);
      if (!a) return;
      const s = tuning.nav.arrowPx;
      ctx.save();
      ctx.translate(a.x, a.y);
      ctx.rotate(a.angle);
      ctx.fillStyle = tokens.colorBoothRing;
      ctx.beginPath();
      ctx.moveTo(s, 0);
      ctx.lineTo(-s * 0.7, s * 0.8);
      ctx.lineTo(-s * 0.3, 0);
      ctx.lineTo(-s * 0.7, -s * 0.8);
      ctx.closePath();
      ctx.fill();
      ctx.restore();
    },
    clear: () => world.clear(),
    answer,
  };
}
