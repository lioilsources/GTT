// Weather of client W (specs/weather.md P1): the 1 s game tick, grip in rain, the rain / fog pass,
// wet roads, the HUD icon and the toast on a change, and `?weather=clear|rain|fog`.
import './weather.css';

import type { DriveWorld } from '../drive/driveWorld';
import type { MessageKey } from '../gen/i18n';
import type { Tuning } from '../gen/tuning';
import { h } from '../minigames/dom';
import { WeatherView } from '../render/weatherView';
import type { WorldView } from '../render/worldView';
import { isWeatherKind, weatherActive, type WeatherKind } from './rules';
import { WeatherWorld, weatherToastKey, wetFactor } from './weather';

export { WeatherWorld } from './weather';

type T = (k: MessageKey, a?: Record<string, string | number>) => string;

export interface WeatherEnv {
  cityId: string;
  tuning: Tuning;
  t: T;
  drive: DriveWorld;
  view: WorldView;
  hud: HTMLElement;
  params: URLSearchParams;
  /** Random seed of `init` (specs/weather.md "Start a uložení": not saved, random per start). */
  seed?: number;
}

/** The weather feature as main.ts sees it. */
export interface WeatherFeature {
  /** Null when the weather is off in this city (no module: always clear, no icon, no toasts). */
  readonly world: WeatherWorld | null;
  /** Per frame: `stepDt` = game dt (0 while paused, ticks), `dt` = frame dt (blend, rain, toast). */
  update(stepDt: number, dt: number): void;
  /** Debug and tests: `set` a kind. */
  set(kind: WeatherKind): void;
}

// Icons in color.weather.icon (currentColor): sun, drop, waves.
const ICONS: Record<WeatherKind, string> = {
  clear: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="4.5" fill="currentColor"/><path d="M12 2v2.5M12 19.5V22M2 12h2.5M19.5 12H22M4.9 4.9l1.8 1.8M17.3 17.3l1.8 1.8M4.9 19.1l1.8-1.8M17.3 6.7l1.8-1.8"/></svg>',
  rain: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 2.5C9 7 6 10.4 6 14.2a6 6 0 0 0 12 0C18 10.4 15 7 12 2.5z"/></svg>',
  fog: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M3 8c3-2 6 2 9 0s6 2 9 0M3 13c3-2 6 2 9 0s6 2 9 0M3 18c3-2 6 2 9 0s6 2 9 0"/></svg>',
};

export function installWeather(env: WeatherEnv): WeatherFeature {
  const { tuning, t, drive, view } = env;
  const wt = tuning.weather;
  if (!weatherActive(wt, env.cityId)) {
    drive.gripScale = 1;
    return { world: null, update() {}, set() {} };
  }
  const world = new WeatherWorld(wt, env.seed ?? (Math.random() * 0xffffffff) >>> 0);
  const layer = new WeatherView(view.scene, wt);

  const icon = h('div.pill', { id: 'weather-icon' });
  const toast = h('div.pill', { id: 'weather-toast', hidden: true });
  env.hud.append(icon);
  document.body.append(toast);
  const showIcon = (k: WeatherKind): void => {
    icon.innerHTML = ICONS[k];
    icon.title = t(weatherToastKey(k));
    icon.setAttribute('aria-label', icon.title);
  };
  showIcon(world.kind);
  let toastS = 0;
  world.onChange.push((k) => {
    showIcon(k);
    toast.textContent = t(weatherToastKey(k));
    toast.hidden = false;
    toastS = tuning.nav.toastS;
  });

  // ?weather=clear|rain|fog: one `set` right after `init` (specs/weather.md "Ladění").
  const q = env.params.get('weather');
  if (isWeatherKind(q)) world.set(q);

  return {
    world,
    update(stepDt, dt) {
      world.update(stepDt);
      // Grip switches at once with the kind; only the look blends.
      drive.gripScale = world.grip;
      world.fade(dt);
      const b = world.blend;
      view.setWet(wetFactor(wt, b.rain));
      const eng = view.engine;
      layer.update(b.rain, b.fog, dt, eng.getRenderWidth(), eng.getRenderHeight(), 1 / eng.getHardwareScalingLevel());
      if (toastS > 0 && (toastS -= dt) <= 0) toast.hidden = true;
    },
    set: (k) => world.set(k),
  };
}
