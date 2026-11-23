import type { MessageKey } from '../gen/i18n';
import type { TuningPhone } from '../gen/tuning';
import { h } from '../minigames/dom';
import { overlays } from '../pause';

/** In-game phone shell (specs/phone.md "Telefon"): bottom sheet, home grid, app slots. */

export const phoneAppIds = ['feed', 'map', 'taxi', 'garage', 'passport', 'camera', 'contacts', 'wallet', 'travel', 'settings'] as const;
export type PhoneAppId = (typeof phoneAppIds)[number];

const icons: Record<PhoneAppId, string> = {
  feed: '▤', map: '⌖', taxi: '⇢', garage: '⌂', passport: '✪', camera: '◉', contacts: '☺', wallet: '¤', travel: '✈', settings: '⚙',
};

/** Mounts an app screen into host; returns unmount. */
export type PhoneMount = (host: HTMLElement) => () => void;

const mounts: Partial<Record<PhoneAppId, PhoneMount>> = {};

/** The slot other features use to bring their app to life (greyed until registered). */
export function registerPhoneApp(id: PhoneAppId, mount: PhoneMount): void {
  mounts[id] = mount;
}

export class Phone {
  readonly root: HTMLElement;
  private readonly screen: HTMLElement;
  private readonly title: HTMLElement;
  private readonly backBtn: HTMLButtonElement;
  private unmount: (() => void) | null = null;
  private app: PhoneAppId | null = null;
  isOpen = false;
  /** Release of the pause registration while open (specs/pause.md). */
  private release: (() => void) | null = null;
  onChange: (open: boolean) => void = () => {};
  /** Actions under the home grid (the phone is the pause menu: "Na silnici", specs/flow.md). */
  readonly homeActions: HTMLElement[] = [];

  constructor(
    parent: HTMLElement,
    tuning: TuningPhone,
    private readonly t: (k: MessageKey, a?: Record<string, string | number>) => string,
  ) {
    this.title = h('div.phone-title', {}, t('phone'));
    this.backBtn = h('button.phone-btn', { type: 'button', onclick: () => this.home() }, '‹');
    const closeBtn = h('button.phone-btn', { type: 'button', onclick: () => this.close() }, '✕');
    const bar = h('div.phone-bar', {}, this.backBtn, this.title, closeBtn);
    this.screen = h('div.phone-screen', {});
    this.root = h('div.phone', { hidden: true, style: { height: `${tuning.heightPct}%` } }, h('div.phone-handle', {}), bar, this.screen);
    parent.append(this.root);
    this.swipe(bar, (dy) => dy > tuning.pullPx && this.close());
    // Bottom-edge grab zone: swipe up opens the phone.
    const grab = h('div.phone-grab', { style: { height: `${tuning.edgePx}px` } });
    parent.append(grab);
    this.swipe(grab, (dy) => dy < -tuning.pullPx && this.open());
    window.addEventListener('keydown', (e) => {
      if (e.code === 'Escape' && this.isOpen) this.close();
    });
  }

  private swipe(el: HTMLElement, done: (dy: number) => void): void {
    let y0: number | null = null;
    el.addEventListener('pointerdown', (e) => {
      y0 = e.clientY;
      el.setPointerCapture(e.pointerId);
    });
    el.addEventListener('pointerup', (e) => {
      if (y0 !== null) done(e.clientY - y0);
      y0 = null;
    });
    el.addEventListener('pointercancel', () => (y0 = null));
  }

  open(app?: PhoneAppId): void {
    if (!this.isOpen) {
      this.isOpen = true;
      this.release = overlays.open('phone');
      this.root.hidden = false;
      this.onChange(true);
    }
    if (app) this.launch(app);
    else if (!this.app) this.home();
  }

  close(): void {
    if (!this.isOpen) return;
    this.isOpen = false;
    this.release?.();
    this.release = null;
    this.root.hidden = true;
    this.onChange(false);
  }

  toggle(): void {
    if (this.isOpen) this.close();
    else this.open();
  }

  home(): void {
    this.unmount?.();
    this.unmount = null;
    this.app = null;
    this.title.textContent = this.t('phone');
    this.backBtn.style.visibility = 'hidden';
    const grid = h('div.phone-home', {},
      ...phoneAppIds.map((id) =>
        h('button.phone-app', { type: 'button', disabled: !mounts[id], onclick: () => this.launch(id) },
          h('span.phone-icon', {}, icons[id]),
          h('span.phone-label', {}, this.t(`app_${id}` as MessageKey)))));
    this.screen.replaceChildren(grid, ...(this.homeActions.length > 0 ? [h('div.phone-actions', {}, ...this.homeActions)] : []));
  }

  launch(id: PhoneAppId): void {
    const mount = mounts[id];
    if (!mount) return;
    this.unmount?.();
    this.app = id;
    this.title.textContent = this.t(`app_${id}` as MessageKey);
    this.backBtn.style.visibility = 'visible';
    this.screen.replaceChildren();
    this.unmount = mount(this.screen);
  }
}
