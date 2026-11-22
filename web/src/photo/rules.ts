import type { TuningPhoto } from '../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../minigames/rules';
import type { Prng } from '../rules/prng';

/** specs/photo.md, version 1: framing a photo spot's view (P0, module `photo`). */
export interface PhotoSpot {
  id: string;
  /** Centre of the view (`look`) in dm. */
  x: number;
  y: number;
  /** Radius of the view (`subject_dm`). */
  r: number;
}

export interface PhotoConfig {
  /** Photo spots of the city in spots.pb order. */
  spots: PhotoSpot[];
  loosePct: number;
}

export type PhotoVerdict = '' | 'ok' | 'again' | 'cut' | 'loose';

export interface PhotoLast {
  spot: string;
  verdict: PhotoVerdict;
}

export interface PhotoState {
  /** Photographed spots in the order they were taken. */
  taken: string[];
  last: PhotoLast;
}

export type PhotoAction =
  | { by: 'player'; op: 'load'; taken: string[] }
  | { by: 'player'; op: 'shoot'; spot: string; cx: number; cy: number; hw: number; hh: number };

/** Config from tuning and the photo spots of the city. */
export function photoConfig(t: Pick<TuningPhoto, 'loosePct'>, spots: readonly PhotoSpot[]): PhotoConfig {
  return { spots: spots.map((s) => ({ ...s })), loosePct: t.loosePct };
}

/** floor(sqrt(n)) of a non-negative integer, exact. */
export function isqrt(n: number): number {
  let r = Math.floor(Math.sqrt(n));
  while (r * r > n) r--;
  while ((r + 1) * (r + 1) <= n) r++;
  return r;
}

/** The verdict of a frame (spec "Akce" shoot, steps 1–2; `again` / `ok` is decided by `taken`). */
export function frameVerdict(s: PhotoSpot, loosePct: number, cx: number, cy: number, hw: number, hh: number): 'cut' | 'loose' | 'fits' {
  const h = Math.min(hw, hh);
  const d = isqrt((cx - s.x) ** 2 + (cy - s.y) ** 2);
  if (d + s.r > h) return 'cut';
  if (h * 100 > s.r * loosePct) return 'loose';
  return 'fits';
}

const isInt = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v);
const noLast = (): PhotoLast => ({ spot: '', verdict: '' });

export class PhotoRules implements Rules<PhotoState, PhotoAction, RulesResult, PhotoConfig> {
  readonly id = 'photo';
  readonly specVersion = 1;
  private cfg: PhotoConfig | null = null;

  get config(): PhotoConfig {
    if (!this.cfg) throw new Error('photo: init first');
    return this.cfg;
  }

  init(config: PhotoConfig, _seed = 0): PhotoState {
    this.cfg = config;
    return { taken: [], last: noLast() };
  }

  legalActions(_s: PhotoState): PhotoAction[] {
    const out: PhotoAction[] = [{ by: 'player', op: 'load', taken: [] }];
    for (const p of this.config.spots) out.push({ by: 'player', op: 'shoot', spot: p.id, cx: p.x, cy: p.y, hw: p.r, hh: p.r });
    return out;
  }

  apply(state: PhotoState, a: PhotoAction): PhotoState {
    if (a.by !== 'player') throw new IllegalAction(this.id, a);
    const c = this.config;
    switch (a.op) {
      case 'load': {
        if (!Array.isArray(a.taken) || !a.taken.every((x) => typeof x === 'string')) throw new IllegalAction(this.id, a);
        const known = new Set(c.spots.map((p) => p.id));
        return { taken: [...new Set(a.taken.filter((x) => known.has(x)))], last: noLast() };
      }
      case 'shoot': {
        const p = typeof a.spot === 'string' ? c.spots.find((x) => x.id === a.spot) : undefined;
        if (!p || !isInt(a.cx) || !isInt(a.cy) || !isInt(a.hw) || !isInt(a.hh) || a.hw < 1 || a.hh < 1) throw new IllegalAction(this.id, a);
        const fit = frameVerdict(p, c.loosePct, a.cx, a.cy, a.hw, a.hh);
        const taken = [...state.taken];
        let verdict: PhotoVerdict;
        if (fit !== 'fits') verdict = fit;
        else if (taken.includes(p.id)) verdict = 'again';
        else {
          verdict = 'ok';
          taken.push(p.id);
        }
        return { taken, last: { spot: p.id, verdict } };
      }
      default:
        throw new IllegalAction(this.id, a);
    }
  }

  aiAction(_s: PhotoState, _level: number, _ai: Prng): PhotoAction {
    throw new Error('photo: no opponent');
  }

  result(_s: PhotoState): RulesResult | null {
    return null;
  }
}
