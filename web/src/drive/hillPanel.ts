import type { Tuning } from '../gen/tuning';
import { h } from '../minigames/dom';

/**
 * Hill tuning panel (specs/bench.md v2 "Ladění kopců"): with ?debug, sliders over the client-side
 * keys of content/tuning.yaml that the hills depend on. Every key is read each step or frame, so a
 * change shows at once. Labels are the YAML keys on purpose (what gets pasted back into the repo),
 * like the F tuning panel. Pack-side numbers (terrain.exaggeration, max_grade, shade_strength) are
 * not here: they need a new citypack.
 */
export interface HillKey {
  key: string;
  min: number;
  max: number;
  get(t: Tuning): number;
  set(t: Tuning, v: number): void;
}

export const HILL_KEYS: readonly HillKey[] = [
  { key: 'slope_physics.gravity', min: 5, max: 40, get: (t) => t.slopePhysics.gravity, set: (t, v) => (t.slopePhysics.gravity = v) },
  { key: 'slope_physics.slope_force_scale', min: 0, max: 1.5, get: (t) => t.slopePhysics.slopeForceScale, set: (t, v) => (t.slopePhysics.slopeForceScale = v) },
  { key: 'slope_physics.suspension_travel', min: 0.1, max: 2, get: (t) => t.slopePhysics.suspensionTravel, set: (t, v) => (t.slopePhysics.suspensionTravel = v) },
  { key: 'slope_physics.hard_landing', min: 2, max: 30, get: (t) => t.slopePhysics.hardLanding, set: (t, v) => (t.slopePhysics.hardLanding = v) },
  { key: 'speed_mps.cruise', min: 5, max: 60, get: (t) => t.speedMps.cruise, set: (t, v) => (t.speedMps.cruise = v) },
  { key: 'camera.topdown.height_m', min: 80, max: 600, get: (t) => t.camera.topdown.heightM, set: (t, v) => (t.camera.topdown.heightM = v) },
  { key: 'camera.heading_follow_rate', min: 0.5, max: 15, get: (t) => t.camera.headingFollowRate, set: (t, v) => (t.camera.headingFollowRate = v) },
  { key: 'view_width_m.slow', min: 25, max: 150, get: (t) => t.viewWidthM.slow, set: (t, v) => (t.viewWidthM.slow = v) },
  { key: 'view_width_m.fast', min: 40, max: 250, get: (t) => t.viewWidthM.fast, set: (t, v) => (t.viewWidthM.fast = v) },
];

/** YAML lines (`a.b: 1.25`) of the panel keys, floats always with a decimal point (CLAUDE.md). */
export function hillYaml(t: Tuning): string {
  return HILL_KEYS.map((k) => {
    const v = Math.round(k.get(t) * 1000) / 1000;
    return `${k.key}: ${Number.isInteger(v) ? v.toFixed(1) : String(v)}`;
  }).join('\n');
}

export function hillPanel(t: Tuning, label: { title: string; copy: string; copied: string }): { button: HTMLElement; panel: HTMLElement } {
  const rows = HILL_KEYS.map((k) => {
    const out = h('span.hill-value', {}, String(k.get(t)));
    const input = h('input', {
      type: 'range', min: String(k.min), max: String(k.max), step: String((k.max - k.min) / 200), value: String(k.get(t)),
      oninput: () => {
        k.set(t, Number(input.value));
        out.textContent = String(Math.round(k.get(t) * 1000) / 1000);
      },
    });
    return h('label.hill-row', {}, h('span', {}, k.key), input, out);
  });
  const copy = h('button.round', { type: 'button' }, label.copy);
  copy.onclick = () => void navigator.clipboard?.writeText(hillYaml(t)).then(() => (copy.textContent = label.copied));
  const panel = h('div.hill-panel', { hidden: true }, ...rows, copy);
  const button = h('button.round', { type: 'button', title: label.title, onclick: () => (panel.hidden = !panel.hidden) }, label.title);
  return { button, panel };
}
