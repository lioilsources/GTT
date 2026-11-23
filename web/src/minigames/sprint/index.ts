import '../world.css';

import type { CarFleet } from '../../cars/fleet';
import { routeGraphFromPb } from '../../drive/gps';
import type { DriveWorld } from '../../drive/driveWorld';
import type { MessageKey } from '../../gen/i18n';
import type { MinigameContext, MinigameResult } from '../../gen/schema';
import { tokens } from '../../gen/tokens';
import type { Tuning } from '../../gen/tuning';
import type { PhoneApi } from '../../phone';
import { edgeLengthsDm, type NavTarget } from '../../phone/nav';
import type { CameraRig } from '../../render/worldView';
import { drunkInput } from '../../shops/shops';
import type { City } from '../../world/model';
import type { WorldMinigame } from '../api';
import { h } from '../dom';
import { clockText } from '../drift';
import { taxiDests } from '../taxi/shift';
import { WorldHits } from '../worldHits';
import { SprintRace, type SprintEvent, type SprintGate } from './race';

type T = (k: MessageKey, a?: Record<string, string | number>) => string;

export interface SprintEnv {
  city: City;
  tuning: Tuning;
  t: T;
  drive: DriveWorld;
  fleet: CarFleet;
  phone: PhoneApi;
  rig: CameraRig;
  hud: HTMLElement;
  /** Called after the car body was rebuilt at the start line (the view rebuilds the car mesh). */
  onCarChanged(): void;
}

export interface SprintApi extends WorldMinigame {
  /** Once per frame with the world dt (scaled like driving). */
  update(dt: number): void;
  /** During the countdown: overrides the player's input so the car stands (call after the controls). */
  brake(): void;
  /** Gates and the finish on the overlay canvas (CSS pixels). */
  draw(ctx: CanvasRenderingContext2D, w: number, h: number): void;
  /** The running race (debug, tests). */
  readonly race: SprintRace | null;
  /** Ends the race as given up (the HUD's end button). */
  quit(): void;
}

/** Signed seconds with one decimal: "+1.2 s" behind par, "−0.8 s" ahead. */
export function splitText(deltaMs: number): string {
  const s = Math.abs(deltaMs) / 1000;
  return `${deltaMs > 0 ? '+' : deltaMs < 0 ? '−' : '±'}${s.toFixed(1)} s`;
}

/** Sprint A→B as a world minigame of client W: start line, gates, navigation, HUD, result. */
export function installSprint(env: SprintEnv): SprintApi {
  const { city, tuning, t, drive, fleet, phone } = env;
  const st = tuning.minigames.sprint;
  const g = city.graph;
  const world = { graph: g, route: routeGraphFromPb(city.graphPb, tuning.route.classCost), lensDm: edgeLengthsDm(city.graphPb), searchM: tuning.nav.searchM };
  const dests = taxiDests(g, city.landmarks.items, st.destSearchM);

  // ---------- HUD
  const timer = h('div.pill', {});
  const par = h('div.pill', {});
  const cp = h('div.pill', {});
  const endBtn = h('button.round', { type: 'button', title: t('sprintEnd'), onclick: () => api.quit() }, '✕');
  const box = h('div.world-mg-hud', { id: 'sprint-hud', hidden: true }, timer, par, cp, endBtn);
  const flash = h('div.pill.world-mg-flash', { id: 'sprint-flash', hidden: true });
  env.hud.append(box);
  document.body.append(flash);
  let flashS = 0;
  const say = (text: string, cls = '', s = tuning.nav.toastS): void => {
    flash.textContent = text;
    flash.className = `pill world-mg-flash ${cls}`;
    flash.hidden = false;
    flashS = s;
  };

  let race: SprintRace | null = null;
  let hits: WorldHits | null = null;
  let done: ((r: MinigameResult) => void) | null = null;
  let navFor: NavTarget | null = null;
  let renav = 0;
  let spawning = false;

  const navigate = (target: NavTarget | null): void => {
    navFor = target;
    renav = 0;
    if (target) phone.navigateTo({ ...target, name: target.name || t('sprintCp', { n: (race?.state.passed ?? 0) + 1, total: race?.state.cps ?? 0 }) }, true);
    else phone.cancelNav();
  };

  const finish = (aborted: boolean): void => {
    const r0 = race;
    if (!r0) return;
    const r = r0.end();
    race = null;
    hits?.dispose();
    hits = null;
    box.hidden = true;
    navigate(null);
    const cb = done;
    done = null;
    cb?.({ stars: aborted ? 0 : r.stars, score: aborted ? 0 : r.score, playedMs: r0.ms, aborted });
  };

  // Boarding another car or leaving the garage ends the race (timeout).
  fleet.on('carChanged', () => {
    if (race && !spawning) finish(false);
  });

  const onEvent = (e: SprintEvent): void => {
    switch (e.kind) {
      case 'picked':
        say(t('sprintTo', { place: e.dest.name }), '', st.countdownS);
        navFor = null;
        break;
      case 'go':
        say(t('sprintGo'), 'bank');
        if (race?.next) navigate(race.next.target);
        break;
      case 'cp': {
        const d = e.splitMs - e.parAtMs;
        say(t('sprintSplit', { delta: splitText(d) }), d <= 0 ? 'bank' : 'low');
        if (race?.next) navigate(race.next.target);
        break;
      }
      case 'over':
        finish(false);
        break;
    }
  };

  const api: SprintApi = {
    get active() {
      return race !== null;
    },
    get race() {
      return race;
    },
    start(spotId: string, ctx: MinigameContext, onFinish: (r: MinigameResult) => void) {
      if (race) return;
      const spot = city.spots.items.find((s) => s.id === spotId);
      if (!spot) return;
      // The car stands on the start line (the spot's parking point).
      spawning = true;
      drive.spawn(spot.parkX / 10, spot.parkY / 10, spot.parkHeading);
      spawning = false;
      env.onCarChanged();
      race = new SprintRace(world, st, dests, ctx.difficulty, ctx.seed);
      hits = new WorldHits(drive, st.hitMinMps);
      done = onFinish;
      box.hidden = false;
      const c = drive.car;
      for (const e of race.begin({ hit: drive.layers.hit, x: c.x, y: c.y, heading: c.heading })) onEvent(e);
      api.update(0);
    },
    quit() {
      finish(true);
    },
    brake() {
      if (race && race.state.phase === 'ready') drunkInput(drive.input, drive.car.forwardSpeed, tuning.drive.brakeMinMps);
    },
    update(dt) {
      if (flashS > 0 && (flashS -= dt) <= 0) flash.hidden = true;
      const r = race;
      if (!r) return;
      const c = drive.car;
      const crash = (atMs: number): boolean => hits?.take(atMs) ?? false;
      for (const e of r.update(dt, { x: c.x, y: c.y, heading: c.heading, layer: c.layer }, crash)) onEvent(e);
      if (!race) return;
      const s = r.state;
      if (s.phase === 'ready') {
        if (r.plan) say(`${t('sprintTo', { place: r.plan.dest.name })} · ${Math.ceil(r.countdown)}`, '', 0.5);
      }
      // Navigation cancelled (✕ on the pill) or ended short of the gate: bring it back.
      const tg = s.phase === 'run' ? r.next?.target ?? null : null;
      if (tg && !phone.nav.active) {
        if ((renav += dt) >= tuning.minigames.taxi.renavS) navigate(tg);
      } else if (tg && navFor !== tg) navigate(tg);
      timer.textContent = t('sprintTime', { time: clockText(Math.max(0, r.raceS)) });
      par.textContent = t('sprintPar', { time: clockText(s.parMs / 1000) });
      cp.textContent = t('sprintCp', { n: s.passed, total: s.cps });
    },
    draw(ctx, w, hgt) {
      const r = race;
      const p = r?.plan;
      if (!r || !p) return;
      const k = w / env.rig.viewWidth;
      const next = r.next;
      const gate = (q: SprintGate, color: string): void => {
        const a = env.rig.toScreen(q.x - q.dirY * q.halfWidth, q.y + q.dirX * q.halfWidth, w, hgt, tuning);
        const b = env.rig.toScreen(q.x + q.dirY * q.halfWidth, q.y - q.dirX * q.halfWidth, w, hgt, tuning);
        ctx.strokeStyle = color;
        ctx.lineWidth = Math.max(4, 1.5 * k);
        ctx.lineCap = 'round';
        ctx.beginPath();
        ctx.moveTo(a.x, a.y);
        ctx.lineTo(b.x, b.y);
        ctx.stroke();
      };
      for (let i = r.state.passed; i < p.gates.length; i++) gate(p.gates[i]!, p.gates[i] === next ? tokens.colorSprintNext : tokens.colorSprintGate);
      // Finish: a chequered square on the destination point.
      const f = env.rig.toScreen(p.finish.x, p.finish.y, w, hgt, tuning);
      const side = Math.max(16, p.finish.halfWidth * 2 * k), n = 4, cell = side / n;
      for (let i = 0; i < n; i++) {
        for (let j = 0; j < n; j++) {
          ctx.fillStyle = (i + j) % 2 ? tokens.colorSprintFinishDark : tokens.colorSprintFinish;
          ctx.fillRect(f.x - side / 2 + i * cell, f.y - side / 2 + j * cell, cell, cell);
        }
      }
    },
  };
  return api;
}
