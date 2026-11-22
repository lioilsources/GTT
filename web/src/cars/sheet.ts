import { drawCarPreview } from '../garage/preview';
import type { Look } from '../garage/rules';
import type { MessageKey } from '../gen/i18n';
import type { CarSpec } from '../gen/schema';
import { tokens } from '../gen/tokens';
import type { Tuning } from '../gen/tuning';
import { h } from '../minigames/dom';
import { shapeKind } from './shape';
import { classKeys, saleOrder } from './ui';

/** Pixels per world metre in the sheet, so cars keep their relative size. */
const SHEET_PX_PER_M = 10;

/**
 * Debug contact sheet of every car (`?cars`, specs/cars.md "Kreslení"): each car twice with the
 * real drawing code (drawCarPreview → carPrims), as in the catalog and with a look (paint,
 * decal, rims, underglow cycling over the cars), grouped by class in the schema order.
 */
export function runCarSheet(host: HTMLElement, cars: ReadonlyMap<string, CarSpec>, tuning: Tuning,
  t: (k: MessageKey) => string): void {
  const margin = tuning.garage.glowMarginM;
  const cells = saleOrder(cars.values(), [], '').map((spec, i) => {
    const hl = (spec.length_m * tuning.carScale) / 2;
    const height = Math.round((2 * (hl + margin + 0.6) * SHEET_PX_PER_M) / 0.86);
    const look: Look = {
      paint: (i % tokens.colorGaragePaints.length) + 1,
      decal: (i % 3) + 1,
      wheels: (i % (tokens.colorGarageWheels.length - 1)) + 1,
      glow: (i % tokens.colorGarageGlow.length) + 1,
    };
    const canvases = [null, look].map((lk) => {
      const c = h('canvas', { width: 110, height, style: { width: '110px', height: `${height}px` } });
      requestAnimationFrame(() => drawCarPreview(c, spec, lk, tuning));
      return c;
    });
    const kind = shapeKind(spec.class, spec.length_m);
    return h('div', { 'data-car': spec.id, style: { display: 'inline-flex', flexDirection: 'column', alignItems: 'center', margin: '4px', verticalAlign: 'bottom' } },
      h('div', { style: { display: 'flex', alignItems: 'flex-end' } }, ...canvases),
      h('small', {}, spec.name),
      h('small', { style: { color: tokens.colorUiTextMuted } }, `${t(classKeys[spec.class])}${kind !== spec.class ? ` · ${kind}` : ''}`));
  });
  document.body.style.background = tokens.colorUiBackground;
  host.replaceChildren(h('div', { id: 'car-sheet', style: { color: tokens.colorUiText, padding: '8px', fontFamily: 'sans-serif' } }, ...cells));
}
