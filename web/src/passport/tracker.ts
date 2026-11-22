// Passport while driving (specs/passport.md "Objevování za jízdy", P1): catalog from city data,
// landmark and district discovery. Pure: no DOM, no Babylon.
import { messages, type MessageKey } from '../gen/i18n';
import type { TuningPassport } from '../gen/tuning';
import { districtId, PassportRules, stampId, type PassportResult, type PassportState, type StampKind } from './rules';

/** The parts of a citypack the passport needs (plain data, so tests need no pack). */
export interface PassportCity {
  landmarks: Array<{ id: string; name: string; x: number; y: number; heightM: number; hero: boolean }>;
  /** District names in pack order (duplicates allowed). */
  districts: string[];
  /** Minigame ids of spots, in spot order ('' = no minigame). */
  spotMinigames: string[];
  /** Photo spots (`kind = photo`) in spot order (specs/photo.md); none = empty catalog. */
  photos?: Array<{ id: string; name: string }>;
}

export interface PassportLandmark {
  id: string;
  name: string;
  /** Label anchor in metres. */
  x: number;
  y: number;
  heightM: number;
}

export const postcardTitleKey = (id: string): MessageKey => `lm_${id}_title` as MessageKey;
export const postcardTextKey = (id: string): MessageKey => `lm_${id}_text` as MessageKey;
export const hasPostcard = (id: string): boolean => postcardTitleKey(id) in messages.en;

export type StampEvent =
  | { kind: 'landmark'; id: string; landmark: PassportLandmark }
  | { kind: 'district'; id: string; name: string }
  | { kind: 'minigame' | 'photo'; id: string };

/** Holds the passport state for one city; the save feature reads `stamps` and passes them back in. */
export class PassportTracker {
  readonly rules = new PassportRules();
  readonly landmarks: PassportLandmark[];
  /** District id → first display name. */
  readonly districtNames = new Map<string, string>();
  /** Photo spot id → name. */
  readonly photoNames = new Map<string, string>();
  state: PassportState;
  private readonly listeners: Array<(e: StampEvent) => void> = [];

  constructor(city: PassportCity, private readonly tuning: TuningPassport, saved: readonly string[] = []) {
    this.landmarks = city.landmarks
      .filter((l) => l.hero && hasPostcard(l.id))
      .map((l) => ({ id: l.id, name: l.name, x: l.x / 10, y: l.y / 10, heightM: l.heightM }));
    for (const n of city.districts) {
      const id = districtId(n);
      if (id !== '' && !this.districtNames.has(id)) this.districtNames.set(id, n);
    }
    for (const p of city.photos ?? []) if (!this.photoNames.has(p.id)) this.photoNames.set(p.id, p.name);
    this.state = this.rules.init({
      landmarks: this.landmarks.map((l) => l.id),
      districts: [...this.districtNames.keys()],
      minigames: city.spotMinigames.filter((m) => m !== ''),
      photos: [...this.photoNames.keys()],
      weights: tuning.weights,
      starsForStamp: tuning.starsForStamp,
      stamps: [...saved],
    });
  }

  /** Save.stamps out. */
  get stamps(): string[] {
    return [...this.state.stamps];
  }

  /** Loads saved stamps (specs/save.md); unknown ones are dropped by the rules. */
  restore(stamps: readonly string[]): void {
    const c = this.state.catalog;
    this.state = this.rules.init({
      landmarks: c.landmark,
      districts: c.district,
      minigames: c.minigame,
      photos: c.photo,
      weights: this.tuning.weights,
      starsForStamp: this.tuning.starsForStamp,
      stamps: [...stamps],
    });
  }

  get result(): PassportResult {
    return this.rules.result(this.state);
  }

  has(kind: StampKind, id: string): boolean {
    return this.state.stamps.includes(stampId(kind, id));
  }

  onStamp(f: (e: StampEvent) => void): void {
    this.listeners.push(f);
  }

  /** Called ~10× a second with the car position (m) and the district name under it. */
  update(x: number, y: number, district: string | null): StampEvent[] {
    const out: StampEvent[] = [];
    const r2 = this.tuning.discoverRadiusM ** 2;
    const lm = this.landmarks.find((l) => !this.has('landmark', l.id) && (l.x - x) ** 2 + (l.y - y) ** 2 <= r2);
    if (lm && this.visit('landmark', lm.id)) out.push({ kind: 'landmark', id: lm.id, landmark: lm });
    if (district) {
      const id = districtId(district);
      if (this.state.catalog.district.includes(id) && this.visit('district', id)) {
        out.push({ kind: 'district', id, name: this.districtNames.get(id) ?? district });
      }
    }
    for (const e of out) for (const f of this.listeners) f(e);
    return out;
  }

  /** A finished minigame (MinigameResult.stars); stamps at passport.stars_for_stamp. */
  minigame(id: string, stars: number): boolean {
    if (!this.state.catalog.minigame.includes(id)) return false;
    const ok = this.visit('minigame', id, stars);
    if (ok) for (const f of this.listeners) f({ kind: 'minigame', id });
    return ok;
  }

  /** A Camera shot with verdict `ok` (specs/photo.md): `visit photo`; true when the stamp is new. */
  photo(id: string): boolean {
    if (!this.state.catalog.photo.includes(id)) return false;
    const ok = this.visit('photo', id);
    if (ok) for (const f of this.listeners) f({ kind: 'photo', id });
    return ok;
  }

  private visit(kind: StampKind, id: string, stars?: number): boolean {
    this.state = this.rules.apply(this.state, { by: 'player', op: 'visit', kind, id, ...(stars === undefined ? {} : { stars }) });
    return this.state.last !== '';
  }
}

/** Plain passport data from a loaded City. */
export function passportCity(c: {
  landmarks: { items: Array<{ id: string; name: string; x: number; y: number; heightM: number; hero: boolean }> };
  districts: Array<{ name: string }>;
  spots: { items: Array<{ minigame: string; kind?: string; id?: string; name?: string }> };
}): PassportCity {
  return {
    landmarks: c.landmarks.items.map((l) => ({ id: l.id, name: l.name, x: l.x, y: l.y, heightM: l.heightM, hero: l.hero })),
    districts: c.districts.map((d) => d.name),
    spotMinigames: c.spots.items.map((s) => s.minigame),
    photos: c.spots.items.filter((s) => s.kind === 'photo' && s.id).map((s) => ({ id: s.id!, name: s.name ?? s.id! })),
  };
}
