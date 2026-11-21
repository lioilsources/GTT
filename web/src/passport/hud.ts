// Hooks the passport into the driving HUD of client W: a HUD button (bottom right), postcards on discovery,
// About the maps from the attribution line. main.ts calls installPassport once.
import type { TuningPassport } from '../gen/tuning';
import type { City } from '../world/model';
import { passportCity, PassportTracker } from './tracker';
import { mountAbout, mountPassport, mountPostcard, showStampToast, type PassportEnv } from './ui';

export interface PassportHud {
  tracker: PassportTracker;
  /** Call in the HUD tick with the car position (m). */
  update(x: number, y: number): void;
  openPassport(): void;
  openAbout(): void;
}

export function installPassport(
  city: City,
  tuning: TuningPassport,
  env: PassportEnv,
  hud: { root: HTMLElement; about: HTMLElement },
  saved: readonly string[] = [],
): PassportHud {
  const tracker = new PassportTracker(passportCity(city), tuning, saved);
  const host = document.body;
  let closePostcard: (() => void) | null = null;
  let closeScreen: (() => void) | null = null;

  const showPostcard = (lm: PassportTracker['landmarks'][number], autoS: number): void => {
    closePostcard?.();
    closePostcard = mountPostcard(host, env, lm, autoS, () => (closePostcard = null));
  };
  const openAbout = (): void => {
    closeScreen?.();
    const m = city.manifest;
    closeScreen = mountAbout(host, env, { overtureRelease: m.overtureRelease, builtAt: m.builtAt }, () => {
      closeScreen?.();
      closeScreen = null;
    });
  };
  const openPassport = (): void => {
    closeScreen?.();
    closeScreen = mountPassport(host, env, tracker, {
      cityName: city.manifest.name,
      onClose: () => {
        closeScreen?.();
        closeScreen = null;
      },
      onAbout: openAbout,
      onPostcard: (lm) => showPostcard(lm, 0),
    });
  };

  tracker.onStamp((e) => {
    if (e.kind === 'landmark') showPostcard(e.landmark, tuning.postcardS);
    else if (e.kind === 'district') showStampToast(host, env, e.name, tuning.postcardS);
  });

  const btn = document.createElement('button');
  btn.className = 'round';
  btn.type = 'button';
  btn.id = 'btn-passport';
  btn.textContent = '✪';
  btn.title = env.t('passport');
  btn.addEventListener('click', openPassport);
  hud.root.append(btn);
  hud.about.style.pointerEvents = 'auto';
  hud.about.style.cursor = 'pointer';
  hud.about.title = env.t('aboutTitle');
  hud.about.addEventListener('click', openAbout);

  return {
    tracker,
    update: (x, y) => void tracker.update(x, y, city.districtAt(x, y)),
    openPassport,
    openAbout,
  };
}
