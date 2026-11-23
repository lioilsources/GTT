import '../world.css';

import type { CarFleet } from '../../cars/fleet';
import type { DriveWorld } from '../../drive/driveWorld';
import type { MessageKey } from '../../gen/i18n';
import type { MinigameContext, MinigameResult } from '../../gen/schema';
import { tokens } from '../../gen/tokens';
import type { Tuning } from '../../gen/tuning';
import type { CameraRig } from '../../render/worldView';
import type { City } from '../../world/model';
import type { WorldMinigame } from '../api';
import { h } from '../dom';
import { WorldHits } from '../worldHits';
import { DriftSession, type DriftEvent } from './session';

type T = (k: MessageKey, a?: Record<string, string | number>) => string;

export interface DriftEnv {
  city: City;
  tuning: Tuning;
  t: T;
  drive: DriveWorld;
  fleet: CarFleet;
  rig: CameraRig;
  hud: HTMLElement;
}

export interface DriftApi extends WorldMinigame {
  /** Once per frame with the world dt (scaled like driving). */
  update(dt: number): void;
  /** The zone ring on the overlay canvas (CSS pixels). */
  draw(ctx: CanvasRenderingContext2D, w: number, h: number): void;
  /** The running session (debug, tests). */
  readonly session: DriftSession | null;
  /** Ends the session as given up (the HUD's end button). */
  quit(): void;
}

export const clockText = (s: number): string => {
  const n = Math.ceil(s);
  return `${Math.floor(n / 60)}:${String(n % 60).padStart(2, '0')}`;
};

/** Drift zone as a world minigame of client W: the player's own car, zone, samples, HUD, result. */
export function installDrift(env: DriftEnv): DriftApi {
  const { city, tuning, t, drive, fleet } = env;
  const dt0 = tuning.minigames.drift;

  // ---------- HUD
  const timer = h('div.pill', {});
  const score = h('div.pill', {});
  const chain = h('div.pill.chain', {});
  const endBtn = h('button.round', { type: 'button', title: t('driftEnd'), onclick: () => api.quit() }, '✕');
  const box = h('div.world-mg-hud', { id: 'drift-hud', hidden: true }, timer, score, chain, endBtn);
  const flash = h('div.pill.world-mg-flash', { id: 'drift-flash', hidden: true });
  env.hud.append(box);
  document.body.append(flash);
  let flashS = 0;
  const say = (text: string, cls: string): void => {
    flash.textContent = text;
    flash.className = `pill world-mg-flash ${cls}`;
    flash.hidden = false;
    flashS = tuning.nav.toastS;
  };

  let session: DriftSession | null = null;
  let hits: WorldHits | null = null;
  let done: ((r: MinigameResult) => void) | null = null;

  const finish = (aborted: boolean): void => {
    const s = session;
    if (!s) return;
    const r = s.end();
    session = null;
    hits?.dispose();
    hits = null;
    box.hidden = true;
    const cb = done;
    done = null;
    cb?.({ stars: aborted ? 0 : r.stars, score: aborted ? 0 : r.score, playedMs: s.ms, aborted });
  };

  // Boarding another car or leaving the garage ends the session (timeout, spec "Konec").
  fleet.on('carChanged', () => {
    if (session) finish(false);
  });

  const onEvent = (e: DriftEvent): void => {
    if (e.kind === 'bank') say(t('driftBank', { points: e.points }), 'bank');
    else finish(false);
  };

  const api: DriftApi = {
    get active() {
      return session !== null;
    },
    get session() {
      return session;
    },
    start(spotId: string, ctx: MinigameContext, onFinish: (r: MinigameResult) => void) {
      if (session) return;
      const spot = city.spots.items.find((s) => s.id === spotId);
      if (!spot) return;
      session = new DriftSession(dt0, ctx.difficulty, spot.parkX / 10, spot.parkY / 10);
      hits = new WorldHits(drive, dt0.hitMinMps);
      done = onFinish;
      box.hidden = false;
      api.update(0);
    },
    quit() {
      finish(true);
    },
    update(dt) {
      if (flashS > 0 && (flashS -= dt) <= 0) flash.hidden = true;
      const s = session;
      if (!s) return;
      const c = drive.car, v = c.body.getLinearVelocity();
      const crash = (atMs: number): boolean => hits?.take(atMs) ?? false;
      for (const e of s.update(dt, { x: c.x, y: c.y, heading: c.heading, vx: v.x, vy: v.y, layer: c.layer }, crash)) onEvent(e);
      if (!session) return;
      const st = s.state;
      timer.textContent = t('driftTime', { time: clockText(s.left) });
      timer.classList.toggle('low', s.left <= dt0.lowS);
      score.textContent = t('driftScore', { score: st.score });
      chain.textContent = s.inZone ? t('driftChain', { points: st.chain, mult: st.mult }) : t('driftOutside');
      chain.classList.toggle('low', !s.inZone);
    },
    draw(ctx, w, hgt) {
      const s = session;
      if (!s) return;
      const q = env.rig.toScreen(s.cx, s.cy, w, hgt, tuning);
      const r = (dt0.zoneM * w) / env.rig.viewWidth;
      ctx.fillStyle = tokens.colorDriftZoneFill;
      ctx.strokeStyle = tokens.colorDriftZone;
      ctx.lineWidth = 4;
      ctx.setLineDash([14, 10]);
      ctx.beginPath();
      ctx.arc(q.x, q.y, r, 0, 2 * Math.PI);
      ctx.fill();
      ctx.stroke();
      ctx.setLineDash([]);
    },
  };
  return api;
}
