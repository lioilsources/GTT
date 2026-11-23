import { svg } from './dom';

/** Pip positions on a 0..1 face, per value (shared by the dice minigames). */
export const PIPS: Record<number, Array<[number, number]>> = {
  1: [[0.5, 0.5]],
  2: [[0.27, 0.27], [0.73, 0.73]],
  3: [[0.27, 0.27], [0.5, 0.5], [0.73, 0.73]],
  4: [[0.27, 0.27], [0.73, 0.27], [0.27, 0.73], [0.73, 0.73]],
  5: [[0.27, 0.27], [0.73, 0.27], [0.5, 0.5], [0.27, 0.73], [0.73, 0.73]],
  6: [[0.27, 0.25], [0.73, 0.25], [0.27, 0.5], [0.73, 0.5], [0.27, 0.75], [0.73, 0.75]],
};

/** One die as an SVG group (`deset-die` styles); value 0 draws a blank face. */
export function dieFace(x: number, y: number, size: number, value: number, cls: string[] = []): SVGGElement {
  const g = svg('g', { class: ['deset-die', ...cls].join(' ') });
  g.append(svg('rect', { x, y, width: size, height: size, rx: size / 5, class: 'face' }));
  for (const [px, py] of PIPS[value] ?? []) {
    g.append(svg('circle', { cx: x + px * size, cy: y + py * size, r: size / 10, class: 'pip' }));
  }
  return g;
}
