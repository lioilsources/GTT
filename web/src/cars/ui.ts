import type { MessageKey } from '../gen/i18n';
import { h } from '../minigames/dom';
import { overlays } from '../pause';
import type { CarFleet } from './fleet';
import type { ParkedCar } from './parked';

type T = (k: MessageKey, a?: Record<string, string | number>) => string;

const classKeys: Record<string, MessageKey> = {
  coupe: 'carClassCoupe',
  hatchback: 'carClassHatchback',
  muscle: 'carClassMuscle',
  taxi: 'carClassTaxi',
  pickup: 'carClassPickup',
  sedan: 'carClassSedan',
  micro: 'carClassMicro',
  supersport: 'carClassSupersport',
};

/**
 * HUD for cars (specs/cars.md): the car name pill, the context button ("Přesednout" / "Garáž")
 * and the garage list. Thin DOM over CarFleet; call `update()` from the HUD tick.
 */
export class CarsHud {
  private readonly name = h('div.pill', { id: 'car-name' });
  private readonly action = h('button.round', { id: 'car-action', type: 'button', hidden: true });
  private readonly sheet = h('div.mg-sheet', { id: 'garage', hidden: true });
  private mode: 'board' | 'garage' | null = null;
  private boardTarget: ParkedCar | null = null;
  private last = performance.now();
  /** Pause registration while the garage is open (specs/pause.md). */
  private release: (() => void) | null = null;
  /** A context button with priority ("Zvednout", specs/booths.md): while true, this one hides. */
  yieldTo: (() => boolean) | null = null;

  /** True while the garage list is open: the world does not step (specs/cars.md, specs/pause.md). */
  get busy(): boolean {
    return !this.sheet.hidden;
  }

  constructor(
    readonly fleet: CarFleet,
    readonly t: T,
    hud: HTMLElement,
    /** Called after the car changed (the view rebuilds the car mesh). */
    readonly onCarChanged: () => void,
  ) {
    hud.append(this.name, this.action);
    document.body.append(this.sheet);
    this.action.addEventListener('click', () => this.press());
  }

  private press(): void {
    if (this.mode === 'board') {
      const p = this.boardTarget;
      if (p && this.fleet.parked.includes(p)) {
        this.fleet.board(p);
        this.onCarChanged();
      }
    } else if (this.mode === 'garage') {
      this.openGarage();
    }
    this.update();
  }

  update(): void {
    this.name.textContent = this.fleet.spec.name;
    const now = performance.now();
    const a = this.fleet.action((now - this.last) / 1000);
    this.last = now;
    this.boardTarget = a?.kind === 'board' ? a.car : null;
    const mode = this.yieldTo?.() ? null : (a?.kind ?? null);
    if (mode !== this.mode) {
      this.mode = mode;
      this.action.hidden = mode === null;
      this.action.textContent = mode === 'board' ? this.t('boardCar') : mode === 'garage' ? this.t('garage') : '';
    }
  }

  private openGarage(): void {
    const f = this.fleet, t = this.t;
    const close = (): void => {
      this.sheet.hidden = true;
      this.sheet.replaceChildren();
      this.release?.();
      this.release = null;
    };
    const rows = f.owned.map((id) => {
      const spec = f.specs.get(id);
      if (!spec) return null;
      const ck = classKeys[spec.class];
      const driving = id === f.state.driving && !f.state.stolen;
      return h(
        driving ? 'button.mg-btn.ghost' : 'button.mg-btn',
        {
          type: 'button',
          disabled: !f.canSelect(id),
          onclick: () => {
            f.select(id);
            this.onCarChanged();
            close();
            this.update();
          },
        },
        `${spec.name}${ck ? ' · ' + t(ck) : ''} — ${driving ? t('garageDriving') : t('garageTakeOut')}`,
      );
    });
    // For sale (specs/economy.md "Nákup auta"): every car not owned, with its price.
    const buyable = new Set(f.buyable());
    const sale = [...f.specs.values()]
      .filter((s) => !f.owned.includes(s.id))
      .sort((a, b) => a.price - b.price || (a.id < b.id ? -1 : 1))
      .map((spec) => {
        const ck = classKeys[spec.class];
        return h('button.mg-btn.ghost', {
          type: 'button',
          disabled: !buyable.has(spec.id),
          onclick: () => {
            f.buy(spec.id);
            this.openGarage();
          },
        }, `${spec.name}${ck ? ' · ' + t(ck) : ''} — ${t('garageBuy', { price: spec.price })}`);
      });
    // Air tank of a hop car (specs/hop.md): refilled to full for free.
    const refill = f.canRefillHop()
      ? h('button.mg-btn', {
        type: 'button',
        onclick: () => {
          f.refillHop();
          this.openGarage();
        },
      }, t('hopRefill'))
      : null;
    this.sheet.replaceChildren(
      h('div.mg-card', {}, h('h2', {}, t('garageTitle')), refill, ...rows,
        sale.length ? h('h2', {}, t('garageForSale')) : null, ...sale,
        h('p', {}, t('cashHud', { cash: f.state.cash })),
        h('button.mg-btn.ghost', { type: 'button', onclick: close }, t('close'))),
    );
    this.sheet.hidden = false;
    this.release ??= overlays.open('garage');
  }
}
