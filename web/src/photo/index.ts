// Photo spots and the Camera app of client W (specs/photo.md P1): camera icons, the "Foťák" button,
// the phone app, the framing mode (pause kind `photo`), shots and Passport stamps.
import './photo.css';

import type { CarsHud } from '../cars/ui';
import type { DriveWorld } from '../drive/driveWorld';
import type { MessageKey } from '../gen/i18n';
import { tokens } from '../gen/tokens';
import type { Tuning } from '../gen/tuning';
import type { LoopApi } from '../loop';
import { h } from '../minigames/dom';
import type { PassportTracker } from '../passport/tracker';
import { overlays } from '../pause';
import { registerPhoneApp, type PhoneApi } from '../phone';
import type { CameraRig } from '../render/worldView';
import type { City } from '../world/model';
import {
  frameToShot, photoBlocked, PhotoGlide, photoSpotAt, photoSpotsOf, photoViewWidth, PhotoWorld, rigForCentre,
  type PhotoPoint, type RigPose,
} from './photo';
import type { PhotoVerdict } from './rules';

export { PhotoWorld } from './photo';

type T = (k: MessageKey, a?: Record<string, string | number>) => string;

export interface PhotoEnv {
  city: City;
  tuning: Tuning;
  t: T;
  drive: DriveWorld;
  phone: PhoneApi;
  loop: LoopApi;
  carsHud: CarsHud;
  tracker: PassportTracker;
  /** Current wanted level (specs/police.md). */
  wanted: () => number;
  hud: HTMLElement;
  rig: CameraRig;
  /** Viewport in CSS pixels. */
  size: () => { w: number; h: number };
}

/** The photo feature as main.ts sees it (specs/photo.md). */
export interface PhotoFeature {
  /** Null when photo is off (no module). */
  readonly world: PhotoWorld | null;
  /** True while the Camera mode is open. */
  readonly active: boolean;
  /** HUD tick (~10×/s): the "Foťák" button. Call after the booths HUD and before the loop. */
  hud(dt: number): void;
  /** Per frame with the real dt: drives the camera rig while framing; false = the rig follows the car. */
  camera(dt: number): boolean;
  /** Camera icons, crosshair, frame and flash on the overlay canvas (CSS pixels). */
  draw(ctx: CanvasRenderingContext2D, w: number, h: number): void;
  /** Opens the Camera at the photo spot in reach (debug, tests); false when not offered. */
  open(): boolean;
  /** Shoots a frame between two screen corners (debug, tests); the verdict, null when not framing. */
  shoot(x0: number, y0: number, x1: number, y1: number): PhotoVerdict | null;
  close(): void;
}

const off: PhotoFeature = {
  world: null, active: false, hud() {}, camera: () => false, draw() {}, open: () => false, shoot: () => null, close() {},
};

const toastKey: Record<Exclude<PhotoVerdict, ''>, MessageKey> = {
  ok: 'photoTaken', again: 'photoAgain', cut: 'photoCut', loose: 'photoLoose',
};

export function installPhoto(env: PhotoEnv): PhotoFeature {
  const { city, tuning, t, drive, phone, loop, rig } = env;
  const pt = tuning.photo;
  if (!pt.enabled) return off;
  const points = photoSpotsOf(city.spots.items);
  const world = new PhotoWorld(points, tuning);
  world.loadStamps(env.tracker.stamps);

  // ---------- HUD: Camera button, toast
  const openBtn = h('button.round', { id: 'photo-open', type: 'button', hidden: true }, t('photoOpen'));
  const toast = h('div.pill', { id: 'photo-toast', hidden: true });
  env.hud.append(openBtn);
  document.body.append(toast);
  let toastS = 0;
  const showToast = (text: string): void => {
    toast.textContent = text;
    toast.hidden = false;
    toastS = tuning.nav.toastS;
  };

  // ---------- framing mode
  interface Mode {
    point: PhotoPoint;
    glide: PhotoGlide;
    drag: { id: number; x0: number; y0: number; x1: number; y1: number } | null;
    release: () => void;
    layer: HTMLElement;
  }
  let mode: Mode | null = null;
  /** The glide back to the car after closing (null = the rig follows the car). */
  let back: PhotoGlide | null = null;
  let flashS = 0;

  const blocked = (): ReturnType<typeof photoBlocked> => photoBlocked({ busy: loop.busy, inWorldGame: loop.inWorldGame, wanted: env.wanted() });
  const spotHere = (): PhotoPoint | null => {
    const c = drive.car;
    return photoSpotAt(points, c.x, c.y, c.speed, c.layer, tuning.loop);
  };
  // Priority: "Zvednout" (booth) > "Foťák" > "Hrát" (spec "U fotomísta").
  const prevLoop = loop.yieldTo, prevCars = env.carsHud.yieldTo;
  const canOpen = (): boolean => !mode && !phone.phone.isOpen && blocked() === null && !prevLoop?.() && spotHere() !== null;
  loop.yieldTo = () => !!prevLoop?.() || mode !== null || canOpen();
  env.carsHud.yieldTo = () => !!prevCars?.() || mode !== null || canOpen();

  const pose = (): RigPose => ({ x: rig.x, y: rig.y, heading: rig.heading, viewWidth: rig.viewWidth });
  const framing = (p: PhotoPoint, heading: number): RigPose => {
    const { w, h: hh } = env.size();
    const c = drive.car;
    const vw = photoViewWidth(tuning, p.subjectM);
    const at = rigForCentre((c.x + p.lookX) / 2, (c.y + p.lookY) / 2, heading, vw, w, hh, tuning);
    return { x: at.x, y: at.y, heading, viewWidth: vw };
  };

  const close = (): void => {
    if (!mode) return;
    const m = mode;
    mode = null;
    m.release();
    m.layer.remove();
    const from = pose();
    back = new PhotoGlide(from, () => ({ x: drive.car.x, y: drive.car.y, heading: from.heading, viewWidth: tuning.viewWidthM.slow }), pt.zoomS);
  };

  const shootFrame = (x0: number, y0: number, x1: number, y1: number): PhotoVerdict | null => {
    if (!mode) return null;
    const { w, h: hh } = env.size();
    const p = mode.point;
    const v = world.shoot(p.id, frameToShot(pose(), x0, y0, x1, y1, w, hh, tuning));
    mode.drag = null;
    if (!v) return v;
    if (v === 'ok' || v === 'again') flashS = pt.flashS;
    showToast(t(toastKey[v], { name: p.name }));
    if (v === 'ok') {
      env.tracker.photo(p.id);
      void loop.save();
      close();
    }
    return v;
  };

  const open = (p: PhotoPoint): void => {
    if (mode) return;
    phone.phone.close();
    back = null;
    const release = overlays.open('photo');
    const layer = h('div.photo-layer', {},
      h('div.pill.photo-hint', {}, t('photoHint', { name: p.name })),
      h('button.round.photo-back', { type: 'button', onclick: (e: Event) => {
        e.stopPropagation();
        close();
      } }, t('photoClose')));
    const from = pose();
    const m: Mode = { point: p, glide: new PhotoGlide(from, () => framing(p, from.heading), pt.zoomS), drag: null, release, layer };
    layer.addEventListener('pointerdown', (e) => {
      if (e.target !== layer) return;
      layer.setPointerCapture(e.pointerId);
      m.drag = { id: e.pointerId, x0: e.clientX, y0: e.clientY, x1: e.clientX, y1: e.clientY };
    });
    layer.addEventListener('pointermove', (e) => {
      if (m.drag?.id !== e.pointerId) return;
      m.drag.x1 = e.clientX;
      m.drag.y1 = e.clientY;
    });
    layer.addEventListener('pointerup', (e) => {
      const d = m.drag;
      if (d?.id !== e.pointerId) return;
      shootFrame(d.x0, d.y0, e.clientX, e.clientY);
    });
    layer.addEventListener('pointercancel', () => (m.drag = null));
    document.body.append(layer);
    mode = m;
    openBtn.hidden = true;
  };

  const tryOpen = (): boolean => {
    const p = canOpen() ? spotHere() : null;
    if (!p) return false;
    open(p);
    return true;
  };
  openBtn.addEventListener('click', () => void tryOpen());
  window.addEventListener('keydown', (e) => {
    if (e.code === 'Escape' && mode) close();
  });

  // ---------- Camera phone app (specs/phone.md slot `camera`)
  registerPhoneApp('camera', (host) => {
    const b = blocked();
    const p = b === null ? spotHere() : null;
    if (p) {
      // Open after the phone finished launching the app (the mode closes the phone).
      setTimeout(() => open(p), 0);
      return () => {};
    }
    host.append(h('div.photo-app', {}, h('p', {}, t(b === 'wanted' ? 'photoWanted' : 'photoNoSpot'))));
    return () => {};
  });
  phone.mapPoints.push(() => points.map((p) => ({ x: p.x, y: p.y, color: world.isTaken(p.id) ? tokens.colorPhotoSpotDone : tokens.colorPhotoSpot })));

  /** A small camera at the parking point: body, lens, viewfinder bump; upright on screen. */
  const drawIcon = (ctx: CanvasRenderingContext2D, x: number, y: number, s: number, color: string): void => {
    ctx.save();
    ctx.translate(x, y);
    ctx.fillStyle = color;
    ctx.strokeStyle = tokens.colorPhotoFrame;
    ctx.lineWidth = Math.max(1, s * 0.08);
    ctx.beginPath();
    ctx.roundRect(-s / 2, -s * 0.3, s, s * 0.65, s * 0.12);
    ctx.fill();
    ctx.stroke();
    ctx.fillRect(-s * 0.18, -s * 0.44, s * 0.36, s * 0.16);
    ctx.beginPath();
    ctx.arc(0, s * 0.03, s * 0.2, 0, 2 * Math.PI);
    ctx.stroke();
    ctx.restore();
  };

  return {
    world,
    get active() {
      return mode !== null;
    },
    hud(dt) {
      if (toastS > 0 && (toastS -= dt) <= 0) toast.hidden = true;
      openBtn.hidden = !canOpen();
    },
    camera(dt) {
      if (flashS > 0) flashS = Math.max(0, flashS - dt);
      const g = mode?.glide ?? back;
      if (!g) return false;
      g.step(dt);
      const p = g.pose();
      rig.x = p.x;
      rig.y = p.y;
      rig.heading = p.heading;
      rig.viewWidth = p.viewWidth;
      if (!mode && g.done) back = null;
      return true;
    },
    draw(ctx, w, hgt) {
      const ppm = w / rig.viewWidth;
      const s = Math.max(8, pt.spotIconM * ppm);
      for (const p of points) {
        const q = rig.toScreen(p.x, p.y, w, hgt, tuning);
        if (q.x < -s || q.y < -s || q.x > w + s || q.y > hgt + s) continue;
        drawIcon(ctx, q.x, q.y, s, world.isTaken(p.id) ? tokens.colorPhotoSpotDone : tokens.colorPhotoSpot);
      }
      if (mode) {
        // Crosshair on the look (photo.cross).
        const c = rig.toScreen(mode.point.lookX, mode.point.lookY, w, hgt, tuning);
        const r = pt.crossPx / 2;
        ctx.save();
        ctx.strokeStyle = tokens.colorPhotoCross;
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.arc(c.x, c.y, r * 0.6, 0, 2 * Math.PI);
        ctx.moveTo(c.x - r, c.y);
        ctx.lineTo(c.x + r, c.y);
        ctx.moveTo(c.x, c.y - r);
        ctx.lineTo(c.x, c.y + r);
        ctx.stroke();
        ctx.restore();
        const d = mode.drag;
        if (d) {
          const x = Math.min(d.x0, d.x1), y = Math.min(d.y0, d.y1), fw = Math.abs(d.x1 - d.x0), fh = Math.abs(d.y1 - d.y0);
          ctx.save();
          ctx.fillStyle = tokens.colorPhotoFrameShade;
          ctx.beginPath();
          ctx.rect(0, 0, w, hgt);
          ctx.rect(x, y, fw, fh);
          ctx.fill('evenodd');
          ctx.strokeStyle = tokens.colorPhotoFrame;
          ctx.lineWidth = 2;
          ctx.strokeRect(x, y, fw, fh);
          ctx.restore();
        }
      }
      if (flashS > 0) {
        // Real-time fade; the overlay is redrawn every frame even while paused.
        ctx.save();
        ctx.globalAlpha = Math.min(1, flashS / Math.max(pt.flashS, 1e-6));
        ctx.fillStyle = tokens.colorPhotoFlash;
        ctx.fillRect(0, 0, w, hgt);
        ctx.restore();
      }
    },
    open: tryOpen,
    shoot: shootFrame,
    close,
  };
}
