import type { DriveWorld } from '../drive/driveWorld';
import { hopCharges } from '../drive/hop';
import type { MessageKey } from '../gen/i18n';
import { h } from '../minigames/dom';
import { overlays } from '../pause';

type T = (k: MessageKey, a?: Record<string, string | number>) => string;

/**
 * HUD button "Skok" with the air-tank indicator (specs/hop.md "Ovládání"): only in a car with
 * `hop`, grey when the hop cannot start, "tank empty" feedback when pressed with no charge left.
 */
export class HopHud {
  readonly button: HTMLButtonElement;
  private readonly pips = h('span.hop-pips');
  private readonly toast = h('div.pill', { id: 'hop-toast', hidden: true });
  private toastTimer = 0;
  private shown = -1;

  constructor(
    readonly drive: DriveWorld,
    readonly t: T,
    hud: HTMLElement,
    /** How long the "tank empty" note stays (s). */
    readonly toastS: number,
  ) {
    this.button = h('button.round', { id: 'hop', type: 'button', hidden: true, onclick: () => this.press() },
      h('span.hop-label', {}, t('hopButton')), this.pips) as HTMLButtonElement;
    hud.append(this.button, this.toast);
    this.update(0);
  }

  /** Button or key J. */
  press(): void {
    if (overlays.paused) return;
    const d = this.drive;
    if (d.tryHop()) {
      this.update(0);
      return;
    }
    if (hopCharges(d.spec) !== null && d.hop.charges <= 0) {
      this.toast.textContent = this.t('hopEmpty');
      this.toast.hidden = false;
      this.toastTimer = this.toastS;
    }
  }

  /** HUD tick with the real time since the last call. */
  update(dt: number): void {
    const d = this.drive;
    const full = hopCharges(d.spec);
    this.button.hidden = full === null;
    if (this.toastTimer > 0 && (this.toastTimer -= dt) <= 0) this.toast.hidden = true;
    if (full === null) return;
    this.button.classList.toggle('off', !d.canHop);
    const key = full * 1000 + d.hop.charges;
    if (key === this.shown) return;
    this.shown = key;
    this.pips.replaceChildren(...Array.from({ length: full }, (_, i) => h('span', { className: i < d.hop.charges ? 'on' : '' })));
  }
}
