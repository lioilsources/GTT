import './cars.css';
import { drawCarPreview } from '../garage/preview';
import type { MessageKey } from '../gen/i18n';
import type { CarSpec } from '../gen/schema';
import { h } from '../minigames/dom';
import { overlays } from '../pause';
import type { CarFleet } from './fleet';
import type { ParkedCar } from './parked';

type T = (k: MessageKey, a?: Record<string, string | number>) => string;

export interface GarageTab {
  id: string;
  label: MessageKey;
  order: number;
  render(refresh: () => void): HTMLElement | null;
}

/** i18n key of every class, in the schema order (`mini` … `special`, schema/car.schema.json). */
export const classKeys: Record<CarSpec['class'], MessageKey> = {
  mini: 'carClassMini',
  hatchback: 'carClassHatchback',
  sedan: 'carClassSedan',
  kombi: 'carClassKombi',
  coupe: 'carClassCoupe',
  muscle: 'carClassMuscle',
  supersport: 'carClassSupersport',
  veteran: 'carClassVeteran',
  offroad: 'carClassOffroad',
  pickup: 'carClassPickup',
  van: 'carClassVan',
  taxi: 'carClassTaxi',
  limo: 'carClassLimo',
  bus: 'carClassBus',
  micro: 'carClassMicro',
  special: 'carClassSpecial',
};
const classOrder = Object.keys(classKeys);

/**
 * Cars for sale in list order (specs/cars.md "Garáž", v2): every car not owned, those with the
 * current city in `tags` first, then by class in the schema order, price and id.
 */
export function saleOrder(specs: Iterable<CarSpec>, owned: readonly string[], cityId: string): CarSpec[] {
  const here = (s: CarSpec): number => (s.tags.includes(cityId) ? 0 : 1);
  return [...specs]
    .filter((s) => !owned.includes(s.id))
    .sort((a, b) => here(a) - here(b) || classOrder.indexOf(a.class) - classOrder.indexOf(b.class)
      || a.price - b.price || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
}

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
  /**
   * Tabs of the garage list after "Auta" (specs/garage.md "Garáž"): Tuning and Vzhled from the
   * garage, Polička from the shops; shown in `order`. `render` gets a re-render callback.
   */
  readonly tabs: GarageTab[] = [];
  /** Called when the garage list closes (the garage rebuilds the car from its upgrades). */
  readonly onClose: Array<() => void> = [];
  private tab = 'cars';

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

  /** Closes the garage list (no-op when closed); listeners in `onClose` run once. */
  closeGarage(): void {
    if (this.sheet.hidden) return;
    this.sheet.hidden = true;
    this.sheet.replaceChildren();
    this.release?.();
    this.release = null;
    this.tab = 'cars';
    for (const fn of this.onClose) fn();
  }

  /** Opens the garage list on [tab] (default the last one shown, "Auta" when it was closed). */
  openGarage(tab: string = this.tab): void {
    const t = this.t;
    const tabs = [{ id: 'cars', label: 'garageTabCars' as MessageKey, order: 0, render: () => this.carsTab() }, ...this.tabs]
      .sort((a, b) => a.order - b.order);
    this.tab = tabs.some((x) => x.id === tab) ? tab : 'cars';
    const refresh = (): void => this.openGarage(this.tab);
    const bar = tabs.length > 1
      ? h('div.garage-tabs', {}, ...tabs.map((x) => h(x.id === this.tab ? 'button.garage-tab.on' : 'button.garage-tab', {
        type: 'button',
        'data-tab': x.id,
        onclick: () => this.openGarage(x.id),
      }, t(x.label))))
      : null;
    const body = tabs.find((x) => x.id === this.tab)!.render(refresh);
    this.sheet.replaceChildren(
      h('div.mg-card.garage-card', {}, bar, body,
        h('p', {}, t('cashHud', { cash: this.fleet.state.cash })),
        h('button.mg-btn.ghost', { type: 'button', onclick: () => this.closeGarage() }, t('close'))),
    );
    this.sheet.hidden = false;
    this.release ??= overlays.open('garage');
  }

  /** "Auta": own cars to drive out with, cars for sale, the hop refill (specs/cars.md). */
  private carsTab(): HTMLElement {
    const f = this.fleet, t = this.t;
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
            this.closeGarage();
            this.update();
          },
        },
        `${spec.name}${ck ? ' · ' + t(ck) : ''} — ${driving ? t('garageDriving') : t('garageTakeOut')}`,
      );
    });
    // For sale (specs/economy.md "Nákup auta"): every car not owned, with its price.
    // Sorted by city, class, price and id, each with its class and a small preview (specs/cars.md "Garáž").
    const buyable = new Set(f.buyable());
    const sale = saleOrder(f.specs.values(), f.owned, f.drive.city.id).map((spec) => {
      const canvas = h('canvas.garage-sale-thumb', { width: 40, height: 56 });
      requestAnimationFrame(() => drawCarPreview(canvas, spec, null, f.tuning));
      return h('button.mg-btn.ghost.garage-sale', {
        type: 'button',
        'data-car': spec.id,
        disabled: !buyable.has(spec.id),
        onclick: () => {
          f.buy(spec.id);
          this.openGarage();
        },
      }, canvas, h('span.garage-sale-info', {},
        h('strong', {}, spec.name), h('span', {}, t(classKeys[spec.class]))),
      h('span.garage-sale-price', {}, t('garageBuy', { price: spec.price })));
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
    return h('div', {}, h('h2', {}, t('garageTitle')), refill, ...rows,
      sale.length ? h('h2', {}, t('garageForSale')) : null, ...sale);
  }
}
