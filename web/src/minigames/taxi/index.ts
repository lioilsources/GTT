import './taxi.css';

import type { CarFleet } from '../../cars/fleet';
import { routeGraphFromPb } from '../../drive/gps';
import type { DriveWorld } from '../../drive/driveWorld';
import type { MessageKey } from '../../gen/i18n';
import type { CarSpec, MinigameContext, MinigameResult } from '../../gen/schema';
import { tokens } from '../../gen/tokens';
import type { Tuning } from '../../gen/tuning';
import type { PhoneApi } from '../../phone';
import { edgeLengthsDm, type NavTarget } from '../../phone/nav';
import type { CameraRig } from '../../render/worldView';
import type { City } from '../../world/model';
import type { WorldMinigame } from '../api';
import { h } from '../dom';
import { taxiDests, TaxiShift, type TaxiEvent } from './shift';

type T = (k: MessageKey, a?: Record<string, string | number>) => string;

export interface TaxiEnv {
  city: City;
  tuning: Tuning;
  t: T;
  drive: DriveWorld;
  fleet: CarFleet;
  phone: PhoneApi;
  rig: CameraRig;
  /** Car specs by id (the taxi_metro body for the shift). */
  cars: ReadonlyMap<string, CarSpec>;
  hud: HTMLElement;
  /** Called after the driven body changed (the view rebuilds the car mesh). */
  onCarChanged(): void;
}

export interface TaxiApi extends WorldMinigame {
  /** Once per frame with the world dt (scaled like driving). */
  update(dt: number): void;
  /** Passenger marker on the overlay canvas (CSS pixels). */
  draw(ctx: CanvasRenderingContext2D, w: number, h: number): void;
  /** The running shift (debug, tests). */
  readonly shift: TaxiShift | null;
  /** Ends the shift as given up (the HUD's end button). */
  quit(): void;
}

/** The taxi car of the shift (specs/minigames/taxi.md "Start"). */
export const TAXI_CAR = 'taxi_metro';

const clockText = (s: number): string => {
  const n = Math.ceil(s);
  return `${Math.floor(n / 60)}:${String(n % 60).padStart(2, '0')}`;
};

/** Taxi as a world minigame of client W: car swap, passengers, navigation, HUD, result. */
export function installTaxi(env: TaxiEnv): TaxiApi {
  const { city, tuning, t, drive, fleet, phone } = env;
  const tt = tuning.minigames.taxi;
  const g = city.graph;
  const world = {
    graph: g,
    route: routeGraphFromPb(city.graphPb, tuning.route.classCost),
    lensDm: edgeLengthsDm(city.graphPb),
    straightPct: tuning.feed.straightPct,
    searchM: tuning.nav.searchM,
  };
  const dests = taxiDests(g, city.landmarks.items, tt.destSearchM);

  // ---------- HUD
  const timer = h('div.pill', {});
  const fare = h('div.pill', {});
  const endBtn = h('button.round', { type: 'button', title: t('taxiEnd'), onclick: () => api.quit() }, '✕');
  const box = h('div', { id: 'taxi-hud', hidden: true }, timer, fare, endBtn);
  const line = h('div.pill', { id: 'taxi-line', hidden: true });
  env.hud.append(box);
  document.body.append(line);
  let lineS = 0;
  const say = (text: string, s = tt.lineS): void => {
    line.textContent = text;
    line.hidden = false;
    lineS = s;
  };

  let shift: TaxiShift | null = null;
  let done: ((r: MinigameResult) => void) | null = null;
  let prevSpec: CarSpec | null = null;
  let navFor: NavTarget | null = null;
  let renav = 0;
  let swapping = false;

  const navigate = (target: NavTarget | null, name: string): void => {
    navFor = target;
    renav = 0;
    if (target) phone.navigateTo({ ...target, name }, true);
    else phone.cancelNav();
  };

  const finish = (aborted: boolean, giveBack: boolean): void => {
    const s = shift;
    if (!s) return;
    const r = s.end();
    shift = null;
    box.hidden = true;
    navigate(null, '');
    if (giveBack && prevSpec) {
      const c = drive.car;
      swapping = true;
      drive.replaceCar(prevSpec, c.x, c.y, c.heading);
      swapping = false;
      env.onCarChanged();
    }
    prevSpec = null;
    const cb = done;
    done = null;
    cb?.({ stars: aborted ? 0 : r.stars, score: r.score, playedMs: s.ms, aborted });
  };

  // Boarding another car or leaving the garage during the shift ends it (no car given back).
  fleet.on('carChanged', () => {
    if (shift && !swapping) finish(false, false);
  });
  drive.traffic?.onHit(() => shift?.hit());

  const onEvent = (e: TaxiEvent): void => {
    switch (e.kind) {
      case 'spawn':
        navigate(e.passenger.target, t('taxiPassenger'));
        break;
      case 'pickup':
        say(t(`taxiLine${e.line + 1}` as MessageKey, { place: e.dest.name }));
        navigate(e.dest, e.dest.name);
        break;
      case 'dropoff':
        say(t('taxiPaid', { fare: e.ride.fare }), tuning.nav.toastS);
        navigate(null, '');
        break;
      case 'over':
        finish(false, true);
        break;
    }
  };

  const api: TaxiApi = {
    get active() {
      return shift !== null;
    },
    get shift() {
      return shift;
    },
    start(_spotId: string, ctx: MinigameContext, onFinish: (r: MinigameResult) => void) {
      if (shift) return;
      const spec = env.cars.get(TAXI_CAR);
      if (!spec) return;
      shift = new TaxiShift(world, tt, dests, ctx.seed);
      done = onFinish;
      prevSpec = drive.spec;
      if (drive.spec.id !== TAXI_CAR) {
        const c = drive.car;
        swapping = true;
        drive.replaceCar(spec, c.x, c.y, c.heading);
        swapping = false;
        env.onCarChanged();
      }
      box.hidden = false;
      say(t('taxiStart'));
      api.update(0);
    },
    quit() {
      finish(true, true);
    },
    update(dt) {
      if (lineS > 0 && (lineS -= dt) <= 0) line.hidden = true;
      const s = shift;
      if (!s) return;
      const c = drive.car;
      for (const e of s.update(dt, c, drive.layers.hit)) onEvent(e);
      if (!shift) return;
      // Navigation cancelled (✕ on the pill) or ended short of the target: bring it back.
      const tg = s.target;
      if (tg && !phone.nav.active) {
        const far = Math.hypot(tg.parkX / 10 - c.x, tg.parkY / 10 - c.y) > tt.dropRadiusM;
        if (far && (renav += dt) >= tt.renavS) navigate(tg, tg === s.dest ? s.dest.name : t('taxiPassenger'));
      } else if (tg && navFor !== tg) {
        navigate(tg, tg === s.dest ? s.dest!.name : t('taxiPassenger'));
      }
      timer.textContent = t('taxiTime', { time: clockText(s.left) });
      timer.classList.toggle('low', s.left <= tt.lowS);
      fare.textContent = t('taxiFare', { fare: s.state.fare });
    },
    draw(ctx, w, hgt) {
      const p = shift?.passenger;
      if (!p) return;
      const q = env.rig.toScreen(p.x, p.y, w, hgt, tuning);
      const r = Math.max(tt.passengerPx, (tt.passengerM * w) / env.rig.viewWidth);
      ctx.fillStyle = tokens.colorTaxiPassenger;
      ctx.strokeStyle = tokens.colorTaxiPassengerRing;
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.arc(q.x, q.y, r, 0, 2 * Math.PI);
      ctx.fill();
      ctx.stroke();
    },
  };
  return api;
}
