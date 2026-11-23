import type { MessageKey } from '../gen/i18n';
import type { TuningControls } from '../gen/tuning';
import type { ControlSchemeId } from './controls';

/**
 * The boost hint (specs/controls.md v2 "Nápověda boostu"): a toast on the first drive and again
 * after a stretch of cruise without boost, at most `boost_hint_max` times per device. Pure logic;
 * `shown` is what the client persists.
 */
export class BoostHint {
  private cruise = 0;

  constructor(readonly t: TuningControls, public shown: number) {}

  /** One frame of game time (0 while paused): 'show' = show the toast, 'used' = boost found. */
  step(dt: number, speed: number, boost: boolean): 'show' | 'used' | null {
    const max = this.t.boostHintMax;
    if (boost) {
      if (this.shown >= max) return null;
      this.shown = max;
      return 'used';
    }
    if (this.shown >= max || dt <= 0) return null;
    if (this.shown > 0) {
      if (Math.abs(speed) >= this.t.boostHintMinSpeedMps) this.cruise += dt;
      if (this.cruise < this.t.boostHintAfterS) return null;
    }
    this.shown += 1;
    this.cruise = 0;
    return 'show';
  }
}

/** The hint text for the active scheme; `keyboard` = a device with a fine pointer. */
export function boostHintKey(scheme: ControlSchemeId, keyboard: boolean): MessageKey {
  if (keyboard) return 'boostHintKeys';
  return scheme === 'a' ? 'boostHintA' : scheme === 'b' ? 'boostHintB' : 'boostHintC';
}

export const BOOST_HINT_KEY = 'metropole:boostHint';

export interface HintStore {
  getItem(k: string): string | null;
  setItem(k: string, v: string): void;
}

/** The persisted count; 0 without storage or with a bad value. */
export function readBoostHint(store: HintStore | null): number {
  try {
    const n = Number.parseInt(store?.getItem(BOOST_HINT_KEY) ?? '', 10);
    return Number.isFinite(n) && n > 0 ? n : 0;
  } catch {
    return 0;
  }
}

export function writeBoostHint(store: HintStore | null, shown: number): void {
  try {
    store?.setItem(BOOST_HINT_KEY, String(shown));
  } catch {
    // Storage blocked: the hint may show again next start.
  }
}
