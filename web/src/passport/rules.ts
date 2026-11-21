// Tourist passport rules (specs/passport.md): pure, integer, no DOM.
import { IllegalAction } from '../minigames/rules';

export const stampKinds = ['landmark', 'district', 'minigame', 'photo'] as const;
export type StampKind = (typeof stampKinds)[number];

export interface PassportConfig {
  landmarks: string[];
  districts: string[];
  minigames: string[];
  photos: string[];
  /** Points per kind, in stampKinds order (passport.weights). */
  weights: number[];
  starsForStamp: number;
  /** Saved stamps (Save.stamps); unknown ones are dropped. */
  stamps?: string[];
}

export interface PassportState {
  catalog: Record<StampKind, string[]>;
  weights: number[];
  starsForStamp: number;
  stamps: string[];
  points: number;
  total: number;
  last: string;
}

export interface PassportAction {
  by: 'player';
  op: 'visit';
  kind: StampKind;
  id: string;
  stars?: number;
  [k: string]: unknown;
}

export interface PassportResult {
  percent: number;
  points: number;
  total: number;
  stamps: number;
  of: number;
  kinds: Record<StampKind, [number, number]>;
}

export const stampId = (kind: StampKind, id: string): string => `${kind}:${id}`;

/** Stable district id from its display name (specs/passport.md "districtId"). */
export function districtId(name: string): string {
  return name
    .toLowerCase()
    .replace(/['’.]/g, '')
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

const unique = (xs: readonly string[]): string[] => [...new Set(xs)];

function kindOf(stamp: string): StampKind | null {
  const k = stamp.slice(0, stamp.indexOf(':'));
  return (stampKinds as readonly string[]).includes(k) ? (k as StampKind) : null;
}

export class PassportRules {
  readonly id = 'passport';
  readonly specVersion = 1;

  init(config: PassportConfig, _seed = 0): PassportState {
    const catalog: Record<StampKind, string[]> = {
      landmark: unique(config.landmarks),
      district: unique(config.districts),
      minigame: unique(config.minigames),
      photo: unique(config.photos),
    };
    const weights = [...config.weights];
    let total = 0;
    stampKinds.forEach((k, i) => (total += (weights[i] ?? 0) * catalog[k].length));
    const stamps: string[] = [];
    let points = 0;
    for (const s of config.stamps ?? []) {
      const k = kindOf(s);
      if (k === null || stamps.includes(s) || !catalog[k].includes(s.slice(k.length + 1))) continue;
      stamps.push(s);
      points += weights[stampKinds.indexOf(k)] ?? 0;
    }
    return { catalog, weights, starsForStamp: config.starsForStamp, stamps, points, total, last: '' };
  }

  legalActions(s: PassportState): PassportAction[] {
    const out: PassportAction[] = [];
    for (const kind of stampKinds) {
      for (const id of s.catalog[kind]) {
        if (s.stamps.includes(stampId(kind, id))) continue;
        out.push(kind === 'minigame' ? { by: 'player', op: 'visit', kind, id, stars: 3 } : { by: 'player', op: 'visit', kind, id });
      }
    }
    return out;
  }

  apply(s: PassportState, a: PassportAction): PassportState {
    const k = a.kind;
    if (a.by !== 'player' || a.op !== 'visit' || !(stampKinds as readonly string[]).includes(k) || !s.catalog[k].includes(a.id)) {
      throw new IllegalAction(this.id, a);
    }
    if (k === 'minigame') {
      const st = a.stars;
      if (typeof st !== 'number' || !Number.isInteger(st) || st < 0 || st > 3) throw new IllegalAction(this.id, a);
      if (st < s.starsForStamp) return { ...s, last: '' };
    }
    const stamp = stampId(k, a.id);
    if (s.stamps.includes(stamp)) return { ...s, last: '' };
    return {
      ...s,
      stamps: [...s.stamps, stamp],
      points: s.points + (s.weights[stampKinds.indexOf(k)] ?? 0),
      last: stamp,
    };
  }

  aiAction(): PassportAction {
    throw new Error('passport: no opponent');
  }

  result(s: PassportState): PassportResult {
    const kinds = {} as Record<StampKind, [number, number]>;
    let of = 0;
    for (const k of stampKinds) {
      const got = s.stamps.filter((x) => kindOf(x) === k).length;
      kinds[k] = [got, s.catalog[k].length];
      of += s.catalog[k].length;
    }
    return {
      percent: s.total === 0 ? 0 : Math.floor((100 * s.points) / s.total),
      points: s.points,
      total: s.total,
      stamps: s.stamps.length,
      of,
      kinds,
    };
  }
}
