// Travel phone app of client W (specs/cities.md "Aplikace Cesty"): city list, passport percent,
// switching by reloading with ?city=<id>.
import { ASSET_BASE_URL } from '../config';
import type { MessageKey } from '../gen/i18n';
import { cityIdNames, cityIdValues, type CityId } from '../gen/ids';
import type { Tuning } from '../gen/tuning';
import type { SaveStore } from '../loop/store';
import { h } from '../minigames/dom';
import type { PassportTracker } from '../passport/tracker';
import { registerPhoneApp, type PhoneApi } from '../phone';
import { HttpPackSource } from '../world/citypack';
import { cityPassportPercent, switchCity } from './cities';

export interface TravelEnv {
  cityId: string;
  tuning: Tuning;
  t: (k: MessageKey, a?: Record<string, string | number>) => string;
  phone: PhoneApi;
  /** Live passport of the current city. */
  tracker: PassportTracker;
  store: SaveStore;
  /** Saves the current city (LoopApi.save). */
  save(): Promise<void>;
}

export function installTravel(env: TravelEnv): void {
  const { t } = env;
  // Percent of other cities, computed lazily the first time the app opens.
  const percents = new Map<CityId, Promise<number | null>>();
  const percentOf = (id: CityId): Promise<number | null> => {
    let p = percents.get(id);
    if (!p) {
      p = cityPassportPercent(id, env.tuning, env.store, (c) => HttpPackSource.open(ASSET_BASE_URL, c)).catch((e: unknown) => {
        console.warn(`travel: passport of ${id} failed`, e);
        percents.delete(id);
        return null;
      });
      percents.set(id, p);
    }
    return p;
  };
  let switching = false;

  registerPhoneApp('travel', (host) => {
    let alive = true;
    const rows = cityIdValues.map((id) => {
      const here = id === env.cityId;
      const pct = h('span.travel-pct', {});
      const setPct = (n: number | null): void => {
        if (alive && n !== null) pct.textContent = t('travelPassport', { pct: n });
      };
      if (here) setPct(env.tracker.result.percent);
      else void percentOf(id).then(setPct);
      return h('button.travel-row', {
        type: 'button',
        disabled: here || switching,
        onclick: () => {
          if (here || switching) return;
          switching = true;
          env.phone.phone.close();
          void switchCity(id, { save: env.save, navigate: (url) => location.assign(url), href: location.href });
        },
      },
      h('span.travel-name', {}, cityIdNames[id], here ? h('span.travel-here', {}, t('travelHere')) : null),
      pct);
    });
    host.append(h('div.travel', {}, h('div.travel-title', {}, t('travelTitle')), ...rows));
    return () => {
      alive = false;
    };
  });
}
