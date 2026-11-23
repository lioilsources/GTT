import './police.css';

import { art, artIcon } from '../art';
import type { MessageKey } from '../gen/i18n';
import { h } from '../minigames/dom';
import type { Police } from './police';
import type { OffenceKind } from './rules';

type T = (k: MessageKey, a?: Record<string, string | number>) => string;

const reasonKeys: Record<OffenceKind, MessageKey> = {
  crash: 'policeReason_crash',
  hitrun: 'policeReason_hitrun',
  sidewalk: 'policeReason_sidewalk',
  theft: 'policeReason_theft',
};

/**
 * Police HUD (specs/police.md "Kreslení a HUD"): wanted badges top centre, a short reason toast,
 * the roadblock toast and the "busted" card. Thin DOM over the Police events.
 */
export class PoliceHud {
  private readonly stars = h('div', { id: 'police-stars', hidden: true });
  private readonly toast = h('div', { id: 'police-toast', hidden: true });
  private readonly card = h('div', { id: 'police-busted', hidden: true });
  private toastTimer = 0;
  private cardTimer = 0;

  constructor(
    readonly police: Police,
    readonly t: T,
    hud: HTMLElement,
  ) {
    const max = police.tuning.police.maxLevel;
    // ui/wanted_star.png (specs/art.md v3): the glyph as a mask, empty ones faded; else the shape.
    const star = art().uiIcon('wanted_star');
    for (let i = 0; i < max; i++) {
      const el = h('span.police-star');
      if (star) {
        el.classList.add('art');
        el.append(artIcon(star, 'police-star-art', () => el.classList.remove('art')));
      }
      this.stars.append(el);
    }
    hud.append(this.stars, this.toast, this.card);
    police.on('offence', (e) => this.say(t(reasonKeys[e.kind])));
    police.onWantedChanged((e) => {
      this.render(e.level);
      if (e.reason === 'escape' && e.level === 0) this.say(t('policeEscaped'));
    });
    police.onFined((e) => this.busted(e.amount));
    police.on('roadblock', () => this.say(t('policeRoadblock')));
  }

  private render(level: number): void {
    this.stars.hidden = level === 0;
    this.stars.setAttribute('aria-label', this.t('policeWanted', { level }));
    this.stars.childNodes.forEach((n, i) => (n as HTMLElement).classList.toggle('on', i < level));
  }

  private say(text: string): void {
    this.toast.textContent = text;
    this.toast.hidden = false;
    this.toast.classList.remove('in');
    void this.toast.offsetWidth;
    this.toast.classList.add('in');
    this.toastTimer = this.police.tuning.police.toastS;
  }

  private busted(amount: number): void {
    this.card.replaceChildren(h('div.police-busted-title', {}, this.t('policeBusted')), h('div.police-busted-fine', {}, this.t('policeFine', { amount })));
    this.card.hidden = false;
    this.card.classList.remove('in');
    void this.card.offsetWidth;
    this.card.classList.add('in');
    this.cardTimer = this.police.tuning.police.bustedS;
    this.toast.hidden = true;
  }

  /** Per frame with the real dt (timers of the toast and the card). */
  update(dt: number): void {
    if (this.toastTimer > 0 && (this.toastTimer -= dt) <= 0) this.toast.hidden = true;
    if (this.cardTimer > 0 && (this.cardTimer -= dt) <= 0) this.card.hidden = true;
  }
}
