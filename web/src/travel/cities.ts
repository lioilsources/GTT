// Cities and switching between them (specs/cities.md): start city, last city, Travel URLs and
// passport percent of another city. Pure apart from the injected storage / pack source.
import { carIdValues, cityIdValues, type CityId } from '../gen/ids';
import type { Tuning, TuningPassport } from '../gen/tuning';
import { normalizeSave, saveConfig } from '../loop/save';
import type { SaveStore } from '../loop/store';
import { passportCity, PassportTracker, type PassportCity } from '../passport/tracker';
import { decodeLandmarks, decodeManifest, decodeSpots, type PackSource } from '../world/citypack';

/** localStorage key of the last played city (W, specs/cities.md "Výchozí město"). */
export const LAST_CITY_KEY = 'metropole:city';

/**
 * Start city: `?city=<id>` if known, else the last city if known, else the first known
 * (bundled) city.
 */
export function pickStartCity<T extends string>(param: string | null | undefined, last: string | null | undefined, known: readonly T[]): T {
  const has = (v: string | null | undefined): v is T => typeof v === 'string' && (known as readonly string[]).includes(v);
  if (has(param)) return param;
  if (has(last)) return last;
  return known[0]!;
}

/** The slice of Storage the last-city helpers use (localStorage in the browser, a fake in tests). */
export interface KeyValue {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
}

const browserStorage = (): KeyValue | null => {
  try {
    return typeof localStorage === 'undefined' ? null : localStorage;
  } catch {
    return null;
  }
};

/** Last city id, or null when missing, unknown or unreadable. */
export function readLastCity(storage: KeyValue | null = browserStorage()): CityId | null {
  try {
    const v = storage?.getItem(LAST_CITY_KEY) ?? null;
    return v !== null && (cityIdValues as readonly string[]).includes(v) ? (v as CityId) : null;
  } catch {
    return null;
  }
}

/** Remembers the city; called on every city start once its pack loaded. */
export function writeLastCity(cityId: string, storage: KeyValue | null = browserStorage()): void {
  try {
    storage?.setItem(LAST_CITY_KEY, cityId);
  } catch {
    // Storage full or blocked: the next start just falls back to the default city.
  }
}

/** The page URL for another city: `city` replaced, every other parameter kept. */
export function cityUrl(href: string, cityId: string): string {
  const u = new URL(href);
  u.searchParams.set('city', cityId);
  return u.toString();
}

export interface SwitchDeps {
  /** Saves the current city (same path as on pause, specs/save.md). */
  save(): Promise<void>;
  /** Loads the page at url (W: location.assign). */
  navigate(url: string): void;
  href: string;
}

/** Travel to another city: save the current one, then reload with `?city=<id>`. */
export async function switchCity(target: string, deps: SwitchDeps): Promise<void> {
  try {
    await deps.save();
  } catch (e) {
    console.warn('save before city switch failed', e);
  }
  deps.navigate(cityUrl(deps.href, target));
}

/** Passport percent of a city catalog with the given stamps (specs/passport.md rules). */
export function passportPercent(city: PassportCity, tuning: TuningPassport, stamps: readonly string[]): number {
  return new PassportTracker(city, tuning, stamps).result.percent;
}

/** The passport catalog of a pack from its small files only (no graph, no chunks). */
export async function loadPassportCity(src: PackSource): Promise<PassportCity> {
  const [m, l, s] = await Promise.all(['manifest.pb', 'landmarks.pb', 'spots.pb'].map((p) => src.read(p)));
  const manifest = await decodeManifest(m!);
  return passportCity({ landmarks: await decodeLandmarks(l!), districts: manifest.districts, spots: await decodeSpots(s!) });
}

/**
 * Passport percent of another city from its save (Travel list). A city without a save is 0 %
 * and needs no pack download.
 */
export async function cityPassportPercent(
  cityId: string,
  tuning: Tuning,
  store: SaveStore,
  openPack: (cityId: string) => Promise<PackSource>,
): Promise<number> {
  const raw = await store.read(cityId).catch(() => null);
  if (raw === null || raw === undefined) return 0;
  const stamps = normalizeSave(saveConfig(tuning, cityId, carIdValues), raw).stamps;
  if (stamps.length === 0) return 0;
  return passportPercent(await loadPassportCity(await openPack(cityId)), tuning.passport, stamps);
}
