import type { TuningWeather } from '../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../minigames/rules';
import { Prng } from '../rules/prng';

/** specs/weather.md, version 1: the weather cycle in whole game seconds (P0, module `weather`). */
export type WeatherKind = 'clear' | 'rain' | 'fog';

/** The fixed kind order of weights, the draw and `legalActions`. */
export const weatherKinds: readonly WeatherKind[] = ['clear', 'rain', 'fog'];

export interface WeatherConfig {
  /** Integer weights ≥ 0 in the order clear, rain, fog. */
  weights: [number, number, number];
  minS: number;
  maxS: number;
}

export interface WeatherState {
  kind: WeatherKind;
  left: number;
  changes: number;
  rng: number;
}

export type WeatherAction =
  | { by: 'player'; op: 'tick' }
  | { by: 'player'; op: 'set'; kind: WeatherKind };

/** Config from tuning (`weather.weight_*`, `min_s`, `max_s`). */
export function weatherConfig(t: TuningWeather): WeatherConfig {
  return { weights: [t.weightClear, t.weightRain, t.weightFog], minS: t.minS, maxS: t.maxS };
}

/** `weather.enabled` and `weather.cities.<city>`; an unknown city has no weather. */
export function weatherActive(t: TuningWeather, cityId: string): boolean {
  const cities = t.cities as unknown as Record<string, boolean | undefined>;
  return t.enabled && Object.prototype.hasOwnProperty.call(cities, cityId) && cities[cityId] === true;
}

export function isWeatherKind(v: unknown): v is WeatherKind {
  return typeof v === 'string' && (weatherKinds as readonly string[]).includes(v);
}

export class WeatherRules implements Rules<WeatherState, WeatherAction, RulesResult, WeatherConfig> {
  readonly id = 'weather';
  readonly specVersion = 1;
  private cfg: WeatherConfig | null = null;

  get config(): WeatherConfig {
    if (!this.cfg) throw new Error('weather: init first');
    return this.cfg;
  }

  /** gap() = minS + rng.nextInt(maxS − minS + 1). */
  private gap(r: Prng): number {
    const c = this.config;
    return c.minS + r.nextInt(c.maxS - c.minS + 1);
  }

  init(config: WeatherConfig, seed: number): WeatherState {
    this.cfg = config;
    const r = new Prng(seed);
    const left = this.gap(r);
    return { kind: 'clear', left, changes: 0, rng: r.state };
  }

  legalActions(_s: WeatherState): WeatherAction[] {
    return [{ by: 'player', op: 'tick' }, ...weatherKinds.map((kind) => ({ by: 'player' as const, op: 'set' as const, kind }))];
  }

  apply(state: WeatherState, a: WeatherAction): WeatherState {
    if (a.by !== 'player') throw new IllegalAction(this.id, a);
    const s: WeatherState = { ...state };
    switch (a.op) {
      case 'tick': {
        s.left -= 1;
        if (s.left > 0) break;
        const r = new Prng(s.rng);
        const w = this.config.weights;
        let total = 0;
        for (let i = 0; i < weatherKinds.length; i++) if (weatherKinds[i] !== s.kind) total += w[i]!;
        if (total > 0) {
          let x = r.nextInt(total);
          for (let i = 0; i < weatherKinds.length; i++) {
            const k = weatherKinds[i]!;
            if (k === s.kind) continue;
            if (x < w[i]!) {
              s.kind = k;
              break;
            }
            x -= w[i]!;
          }
        }
        s.left = this.gap(r);
        s.changes += 1;
        s.rng = r.state;
        break;
      }
      case 'set': {
        if (!isWeatherKind(a.kind)) throw new IllegalAction(this.id, a);
        const r = new Prng(s.rng);
        s.kind = a.kind;
        s.left = this.gap(r);
        s.changes += 1;
        s.rng = r.state;
        break;
      }
      default:
        throw new IllegalAction(this.id, a);
    }
    return s;
  }

  aiAction(): WeatherAction {
    throw new Error('weather: no opponent');
  }

  result(_s: WeatherState): RulesResult | null {
    return null;
  }
}
