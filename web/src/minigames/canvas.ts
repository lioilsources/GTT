import type { ShellApi } from './shell';

/**
 * Canvas helpers for the batch C minigames (kulecnik, bowling, minigolf, had, cihly, krtek, hokej):
 * a world rectangle (x right, y up, game units) fitted into a canvas, and a fixed-rate tick loop.
 */

/** Where the world rectangle [x0, x1] × [y0, y1] sits in the canvas (CSS px, y flipped). */
export interface View {
  k: number;
  ox: number;
  oy: number;
  x0: number;
  y1: number;
}

/** Fits the world rectangle into the canvas, centred, with `pad` CSS px around it. */
export function fit(canvas: HTMLCanvasElement, x0: number, y0: number, x1: number, y1: number, pad = 0): View {
  const w = canvas.clientWidth, h = canvas.clientHeight;
  const k = Math.max(1e-9, Math.min((w - 2 * pad) / (x1 - x0), (h - 2 * pad) / (y1 - y0)));
  return { k, ox: (w - (x1 - x0) * k) / 2, oy: (h - (y1 - y0) * k) / 2, x0, y1 };
}

/** Resizes the backing store to the device pixel ratio and returns a cleared 2D context in CSS px. */
export function begin(canvas: HTMLCanvasElement): CanvasRenderingContext2D | null {
  const dpr = window.devicePixelRatio || 1;
  const cw = Math.round(canvas.clientWidth * dpr), ch = Math.round(canvas.clientHeight * dpr);
  if (canvas.width !== cw || canvas.height !== ch) {
    canvas.width = cw;
    canvas.height = ch;
  }
  const g = canvas.getContext('2d');
  if (!g) return null;
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  g.clearRect(0, 0, canvas.clientWidth, canvas.clientHeight);
  return g;
}

export const sx = (v: View, x: number): number => v.ox + (x - v.x0) * v.k;
export const sy = (v: View, y: number): number => v.oy + (v.y1 - y) * v.k;

/** Pointer position → world coordinates (not rounded). */
export function toWorld(canvas: HTMLCanvasElement, v: View, e: { clientX: number; clientY: number }): { x: number; y: number } {
  const r = canvas.getBoundingClientRect();
  return { x: v.x0 + (e.clientX - r.left - v.ox) / v.k, y: v.y1 - (e.clientY - r.top - v.oy) / v.k };
}

export function disc(g: CanvasRenderingContext2D, x: number, y: number, r: number, fill: string, stroke?: string, lw = 1): void {
  g.beginPath();
  g.arc(x, y, Math.max(r, 0.5), 0, Math.PI * 2);
  g.fillStyle = fill;
  g.fill();
  if (stroke) {
    g.lineWidth = lw;
    g.strokeStyle = stroke;
    g.stroke();
  }
}

export function roundRect(g: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void {
  g.beginPath();
  g.roundRect(x, y, w, h, Math.min(r, w / 2, h / 2));
}

/** Longest real-time step fed to a simulation per frame (tab switches, hiccups). */
export const MAX_FRAME_MS = 250;

/**
 * requestAnimationFrame loop: while running and not paused, `ticks(n)` gets the whole ticks at `hz`
 * elapsed since the last frame; `draw` runs every frame.
 */
export function tickLoop(api: ShellApi, hz: number, running: () => boolean, ticks: (n: number) => void, draw: (now: number) => void): () => void {
  let raf = 0;
  let last = -1;
  let acc = 0;
  const frame = (now: number): void => {
    raf = requestAnimationFrame(frame);
    if (api.paused || !running()) {
      last = -1;
    } else {
      if (last >= 0) acc += Math.min(now - last, MAX_FRAME_MS);
      last = now;
      const n = Math.floor((acc * hz) / 1000);
      if (n > 0) {
        acc -= (n * 1000) / hz;
        ticks(n);
      }
    }
    draw(now);
  };
  raf = requestAnimationFrame(frame);
  return () => cancelAnimationFrame(raf);
}

/** Plays recorded simulation frames, one per animation frame, waiting while paused. */
export function playback<F>(api: ShellApi, frames: F[], show: (f: F) => void, done: () => void): () => void {
  let raf = 0;
  let i = 0;
  const step = (): void => {
    if (!api.paused) {
      if (i >= frames.length) {
        done();
        return;
      }
      show(frames[i++]!);
    }
    raf = requestAnimationFrame(step);
  };
  raf = requestAnimationFrame(step);
  return () => cancelAnimationFrame(raf);
}

/** A short floating message over the game body (foul, strike, goal…). */
export function toast(host: HTMLElement, text: string, ms = 1200): void {
  const el = document.createElement('div');
  el.className = 'mgc-toast';
  el.textContent = text;
  host.append(el);
  window.setTimeout(() => el.remove(), ms);
}

/** Pointer capture that tolerates pointers the browser does not track (synthetic events). */
export function capture(el: Element, id: number): void {
  try {
    el.setPointerCapture(id);
  } catch {
    // not an active pointer
  }
}

/** One-pointer drag: dx right / dy down in CSS px from where the finger went down. */
export interface DragHandlers {
  canStart(e: PointerEvent): boolean;
  move(dx: number, dy: number, e: PointerEvent): void;
  /** `ok` is false for a cancelled pointer. */
  release(dx: number, dy: number, ok: boolean): void;
}

export function bindDrag(el: HTMLElement, on: DragHandlers): void {
  let drag: { id: number; x: number; y: number } | null = null;
  el.addEventListener('pointerdown', (e) => {
    if (drag || !on.canStart(e)) return;
    e.preventDefault();
    drag = { id: e.pointerId, x: e.clientX, y: e.clientY };
    capture(el, e.pointerId);
    on.move(0, 0, e);
  });
  el.addEventListener('pointermove', (e) => {
    if (!drag || e.pointerId !== drag.id) return;
    on.move(e.clientX - drag.x, e.clientY - drag.y, e);
  });
  const end = (e: PointerEvent): void => {
    if (!drag || e.pointerId !== drag.id) return;
    const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
    drag = null;
    on.release(dx, dy, e.type === 'pointerup');
  };
  el.addEventListener('pointerup', end);
  el.addEventListener('pointercancel', end);
}

/** Drag length → power 1–100 (`full` CSS px = 100); below `minPx` there is no shot (0). */
export function dragPower(dx: number, dy: number, full: number, minPx = 10): number {
  const len = Math.hypot(dx, dy);
  if (len < minPx) return 0;
  return Math.max(1, Math.min(100, Math.round((len / full) * 100)));
}
