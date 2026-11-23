// Tuning and cosmetics of client W (specs/garage.md P1): the Tuning and Vzhled tabs of the garage
// list, the live look preview, the read-only Garage phone app, the body rebuilt from the upgrades
// and the looks handed to the renderer.
import './garage.css';

import type { CarFleet } from '../cars/fleet';
import type { CarsHud } from '../cars/ui';
import type { MessageKey } from '../gen/i18n';
import { tokens } from '../gen/tokens';
import type { Tuning } from '../gen/tuning';
import type { LoopApi } from '../loop';
import { h } from '../minigames/dom';
import { registerPhoneApp } from '../phone';
import type { WorldView } from '../render/worldView';
import type { ShopsFeature } from '../shops';
import { GarageWorld } from './garage';
import { lookPaint, lookSmoke } from './looks';
import { drawCarPreview } from './preview';
import { lookParts, type GarageSlot, type Look, type LookPart } from './rules';

export { GarageWorld } from './garage';
export { tunedSpec } from './rules';

type T = (k: MessageKey, a?: Record<string, string | number>) => string;

export interface GarageEnv {
  tuning: Tuning;
  t: T;
  fleet: CarFleet;
  carsHud: CarsHud;
  loop: LoopApi;
  view: WorldView;
  shops: ShopsFeature;
}

export interface GarageFeature {
  readonly world: GarageWorld;
  /** The car the Tuning and Vzhled tabs show (an own car). */
  selected: string;
  /** Opens the garage list on a tab (debug, screenshots). */
  open(tab?: 'cars' | 'tuning' | 'looks' | 'shelf'): void;
}

const slotKeys: Record<GarageSlot, { name: MessageKey; effect: MessageKey }> = {
  engine: { name: 'garageSlotEngine', effect: 'garageEffectEngine' },
  tyres: { name: 'garageSlotTyres', effect: 'garageEffectTyres' },
  brakes: { name: 'garageSlotBrakes', effect: 'garageEffectBrakes' },
  weight: { name: 'garageSlotWeight', effect: 'garageEffectWeight' },
  drift: { name: 'garageSlotDrift', effect: 'garageEffectDrift' },
};
const partKeys: Record<LookPart, MessageKey> = {
  paint: 'garagePartPaint', decal: 'garagePartDecal', wheels: 'garagePartWheels', glow: 'garagePartGlow', smoke: 'garagePartSmoke',
};
/** Labels of the decal and wheel choices in choice order (specs/garage.md v2 "Vzhled"). */
export const decalKeys: MessageKey[] = ['garageDecalNone', 'garageDecalStripes', 'garageDecalFlames', 'garageDecalChecker',
  'garageDecalStars', 'garageDecalLightning', 'garageDecalWaves', 'garageDecalCamo', 'garageDecalHalftone'];
export const wheelKeys: MessageKey[] = ['garageWheelsStock', 'garageWheelsSport', 'garageWheelsWhite',
  'garageWheelsFiveSpoke', 'garageWheelsMesh', 'garageWheelsTurbine', 'garageWheelsOffroad'];

/** Percent gained by the next level of a slot (garageEffect<Slot>). */
export function effectPct(tuning: Tuning, slot: GarageSlot): number {
  const g = tuning.garage;
  const step = { engine: g.enginePowerStep, tyres: g.tyresStep, brakes: g.brakesStep, weight: g.weightMassStep, drift: g.driftStep }[slot];
  return Math.round(step * 100);
}

export function installGarage(env: GarageEnv): GarageFeature {
  const { tuning, t, fleet, carsHud, loop, view } = env;
  const g = tuning.garage;
  const world = new GarageWorld(tuning, fleet.specs.values(), { get: () => fleet.state.cash, set: (c) => fleet.setCash(c) });
  world.load(loop.savedGarage.upgrades, loop.savedGarage.looks);
  loop.garage = () => ({ upgrades: world.state.upgrades, looks: world.state.looks });

  // Upgrades only for own cars (fleet.drivenSpec); looks of the driven own car and own parked cars.
  fleet.levelsOf = (car) => world.levels(car);
  view.looks = {
    driven: () => (fleet.drivingOwn ? world.look(fleet.state.driving) : null),
    parked: (p) => (p.owner === 'player' ? world.look(p.carId) : null),
  };
  // Start: the saved car with its upgrades (the loop restored the catalog body).
  fleet.rebuild();
  view.looksChanged();
  // Leaving the garage: the same place, at rest, with the new levels (spec "Účinek na jízdu").
  carsHud.onClose.push(() => {
    fleet.rebuild();
    view.looksChanged();
  });

  const toast = h('div.pill', { id: 'garage-toast', hidden: true });
  document.body.append(toast);
  let toastTimer: ReturnType<typeof setTimeout> | null = null;
  const showToast = (text: string): void => {
    toast.textContent = text;
    toast.hidden = false;
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(() => (toast.hidden = true), tuning.nav.toastS * 1000);
  };
  const bought = (): void => {
    showToast(t('garageBought'));
    void loop.save();
  };

  const feature: GarageFeature = {
    world,
    selected: '',
    open: (tab) => carsHud.openGarage(tab),
  };
  /** The car the tabs show: the chosen one while owned, else the driven own car, else the first. */
  const current = (): string => {
    const owned = fleet.owned;
    if (owned.includes(feature.selected)) return feature.selected;
    return fleet.drivingOwn ? fleet.state.driving : (owned[0] ?? fleet.state.driving);
  };
  const carPicker = (refresh: () => void): HTMLElement | null => {
    if (fleet.owned.length < 2) return null;
    const cur = current();
    return h('div.garage-cars', {}, ...fleet.owned.map((id) => h(id === cur ? 'button.garage-chip.on' : 'button.garage-chip', {
      type: 'button',
      onclick: () => {
        feature.selected = id;
        pending = {};
        refresh();
      },
    }, fleet.specs.get(id)?.name ?? id)));
  };
  const pips = (lvl: number): HTMLElement =>
    h('div.garage-level', {}, ...Array.from({ length: g.maxLevel }, (_, i) => h(i < lvl ? 'span.on' : 'span', {})));

  // ---------- Tuning
  const tuningTab = (refresh: () => void): HTMLElement => {
    const car = current();
    const spec = fleet.specs.get(car);
    const slots = world.slots(car) as GarageSlot[];
    const rows = slots.map((slot) => {
      const lvl = world.level(car, slot), price = world.upgradePrice(car, slot);
      const k = slotKeys[slot];
      let action: HTMLElement;
      if (price === null) action = h('p.garage-muted', {}, t('garageMaxed'));
      else {
        const ok = world.canUpgrade(car, slot);
        action = h('div', {},
          h('button.mg-btn', {
            type: 'button',
            disabled: !ok,
            'data-slot': slot,
            onclick: () => {
              if (world.upgrade(car, slot) === null) return;
              bought();
              refresh();
            },
          }, t('garageUpgrade', { price })),
          ok ? null : h('p.garage-muted', {}, t('garageNoCash')));
      }
      return h('div.garage-row', {},
        h('div.garage-row-head', {}, h('strong', {}, t(k.name)), pips(lvl)),
        price === null ? null : h('p.garage-effect', {}, t(k.effect, { pct: effectPct(tuning, slot) })),
        action);
    });
    return h('div', {}, carPicker(refresh), h('h2', {}, spec?.name ?? car),
      ...(rows.length ? rows : [h('p.garage-muted', {}, t('garageNoSlots'))]));
  };

  // ---------- Vzhled
  /** Choices picked in the tab but not bought yet (live preview). */
  let pending: Look = {};
  const swatch = (part: LookPart, v: number, car: string): string | null => {
    const spec = fleet.specs.get(car)!;
    switch (part) {
      case 'paint': return lookPaint(spec, { paint: v });
      case 'glow': return v === 0 ? null : (tokens.colorGarageGlow[v - 1] ?? null);
      // Stock smoke has no colour of its own (kouř se v1 nekreslí): an empty ring like stock glow.
      case 'smoke': return v === 0 ? null : lookSmoke({ smoke: v });
      default: return null;
    }
  };
  const looksTab = (refresh: () => void): HTMLElement => {
    const car = current();
    const spec = fleet.specs.get(car)!;
    const have = world.look(car);
    const shown: Look = { ...have, ...pending };
    const canvas = h('canvas.garage-preview', { width: 200, height: 240 });
    requestAnimationFrame(() => drawCarPreview(canvas, spec, shown, tuning));
    const rows = lookParts.map((part) => {
      const cur = have[part] ?? 0, sel = shown[part] ?? 0;
      const n = world.choices(part);
      const opts = Array.from({ length: n }, (_, v) => {
        const cls = `${v === sel ? '.on' : ''}${v === cur ? '.current' : ''}`;
        const pick = (): void => {
          pending = { ...pending, [part]: v };
          refresh();
        };
        if (part === 'decal' || part === 'wheels') {
          const label = t((part === 'decal' ? decalKeys : wheelKeys)[v] ?? 'garageStock');
          return h(`button.garage-opt${cls}` as 'button', { type: 'button', 'data-part': part, 'data-value': v, onclick: pick }, label);
        }
        const col = swatch(part, v, car);
        return h(`button.garage-dot${cls}${col ? '' : '.none'}` as 'button', {
          type: 'button', 'data-part': part, 'data-value': v, title: v === 0 ? t('garageStock') : '', onclick: pick,
          style: col ? { background: col } : {},
        });
      });
      let foot: HTMLElement | null = null;
      if (sel === cur) foot = h('p.garage-muted', {}, t('garageCurrent'));
      else {
        const price = world.lookPrice(part, sel), ok = world.canLook(car, part, sel);
        foot = h('div.garage-buy', {},
          h('span', {}, price === 0 ? t('garageFree') : t('cashHud', { cash: price })),
          h('button.mg-btn', {
            type: 'button',
            disabled: !ok,
            'data-buy': part,
            onclick: () => {
              if (world.setLook(car, part, sel) === null) return;
              const { [part]: _, ...rest } = pending;
              pending = rest;
              view.looksChanged();
              bought();
              refresh();
            },
          }, t('garageLookBuy', { price })),
          ok ? null : h('p.garage-muted', {}, t('garageNoCash')));
      }
      return h('div.garage-row', {}, h('strong', {}, t(partKeys[part])), h('div.garage-opts', {}, ...opts), foot);
    });
    return h('div', {}, carPicker(refresh), h('h2', {}, spec.name), canvas, ...rows);
  };

  if (g.enabled) {
    carsHud.tabs.push(
      { id: 'tuning', label: 'garageTabTuning', order: 1, render: tuningTab },
      { id: 'looks', label: 'garageTabLooks', order: 2, render: looksTab },
    );
  }
  carsHud.onClose.push(() => {
    pending = {};
  });

  // ---------- phone: own cars with levels and looks, read-only, and the shelf
  registerPhoneApp('garage', (host) => {
    const cars = fleet.owned.map((id) => {
      const spec = fleet.specs.get(id);
      if (!spec) return null;
      const canvas = h('canvas.garage-thumb', { width: 72, height: 96 });
      requestAnimationFrame(() => drawCarPreview(canvas, spec, world.look(id), tuning));
      const slots = world.slots(id) as GarageSlot[];
      return h('div.garage-app-car', {}, canvas,
        h('div.garage-app-info', {}, h('strong', {}, spec.name),
          ...(slots.length
            ? slots.map((s) => h('div.garage-row-head', {}, h('span', {}, t(slotKeys[s].name)), pips(world.level(id, s))))
            : [h('p.garage-muted', {}, t('garageNoSlots'))])));
    });
    host.append(h('div.shop-app', {}, h('div.garage-app', {}, ...cars), env.shops.shelf()));
    return () => {};
  });
  return feature;
}
