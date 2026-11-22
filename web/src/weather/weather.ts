import type { TuningWeather } from '../gen/tuning';
import { weatherConfig, weatherKinds, WeatherRules, type WeatherKind, type WeatherState } from './rules';

/**
 * The weather in the world (specs/weather.md P1), without DOM or GPU: the 1 s tick of the game
 * clock, the visual cross-fade and the grip multiplier.
 */
export class WeatherWorld {
  readonly rules = new WeatherRules();
  state: WeatherState;
  /** Visual weight 0..1 per kind; they always add up to 1. */
  readonly blend: Record<WeatherKind, number> = { clear: 1, rain: 0, fog: 0 };
  /** Called after a change of the kind (tick or set) with the new kind. */
  onChange: Array<(k: WeatherKind) => void> = [];
  private acc = 0;

  constructor(readonly t: TuningWeather, seed: number) {
    this.state = this.rules.init(weatherConfig(t), seed >>> 0);
  }

  get kind(): WeatherKind {
    return this.state.kind;
  }

  /** Grip multiplier of the player's car: rain_grip in rain, at once; otherwise 1. */
  get grip(): number {
    return this.state.kind === 'rain' ? this.t.rainGrip : 1;
  }

  /** Per frame with the game dt (0 while paused): one `tick` per whole game second. */
  update(stepDt: number): void {
    this.acc += Math.max(0, stepDt);
    while (this.acc >= 1) {
      this.acc -= 1;
      this.apply({ by: 'player', op: 'tick' });
    }
  }

  /** Debug and tests: `set` the kind (a new duration even for the same kind). */
  set(kind: WeatherKind): void {
    this.apply({ by: 'player', op: 'set', kind });
  }

  /**
   * Per frame with the frame dt: every weight moves linearly towards 1 (the current kind) or 0
   * over blend_s, so the old look fades out while the new fades in. blend_s ≤ 0 snaps.
   */
  fade(dt: number): void {
    const step = this.t.blendS > 0 ? Math.max(0, dt) / this.t.blendS : 1;
    for (const k of weatherKinds) {
      const target = k === this.state.kind ? 1 : 0;
      const w = this.blend[k];
      this.blend[k] = w < target ? Math.min(target, w + step) : Math.max(target, w - step);
    }
  }

  private apply(a: Parameters<WeatherRules['apply']>[1]): void {
    const before = this.state.kind;
    this.state = this.rules.apply(this.state, a);
    if (this.state.kind !== before) for (const f of this.onChange) f(this.state.kind);
  }
}

/** Toast key of a kind (i18n `weatherClear` / `weatherRain` / `weatherFog`). */
export function weatherToastKey(k: WeatherKind): 'weatherClear' | 'weatherRain' | 'weatherFog' {
  return k === 'rain' ? 'weatherRain' : k === 'fog' ? 'weatherFog' : 'weatherClear';
}

/** Fog alpha at a normalised distance from the screen centre (1 = half the diagonal). */
export function fogAlpha(t: TuningWeather, d: number): number {
  const e = Math.max(0, Math.min(1, (d - t.fogInner) / Math.max(1 - t.fogInner, 1e-6)));
  const s = e * e * (3 - 2 * e);
  return t.fogCenterAlpha + (t.fogEdgeAlpha - t.fogCenterAlpha) * s;
}

/** Wet road colour factor: 1 − wet_darken × rain weight. */
export function wetFactor(t: TuningWeather, rain: number): number {
  return 1 - t.wetDarken * Math.max(0, Math.min(1, rain));
}
