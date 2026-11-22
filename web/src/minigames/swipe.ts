/** Swipe handling shared by the flick and sport minigames: one pointer, dx right / dy down in CSS px. */
export interface SwipeHandlers {
  /** May a swipe start now (not paused, player's turn, nothing flying)? */
  canStart(): boolean;
  /** While dragging: the current swipe vector. */
  move(dx: number, dy: number): void;
  /** Released: `ok` is false for a cancelled pointer or a swipe shorter than `minPx` upwards. */
  release(dx: number, dy: number, ok: boolean): void;
}

export const MIN_SWIPE_PX = 12;

export function bindSwipe(el: Element, on: SwipeHandlers, minPx = MIN_SWIPE_PX): void {
  let drag: { id: number; x: number; y: number } | null = null;
  el.addEventListener('pointerdown', (ev) => {
    const e = ev as PointerEvent;
    if (drag || !on.canStart()) return;
    drag = { id: e.pointerId, x: e.clientX, y: e.clientY };
    (el as HTMLElement).setPointerCapture?.(e.pointerId);
  });
  el.addEventListener('pointermove', (ev) => {
    const e = ev as PointerEvent;
    if (!drag || e.pointerId !== drag.id) return;
    on.move(e.clientX - drag.x, e.clientY - drag.y);
  });
  const end = (ev: Event): void => {
    const e = ev as PointerEvent;
    if (!drag || e.pointerId !== drag.id) return;
    const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
    drag = null;
    on.release(dx, dy, e.type === 'pointerup' && dy < -minPx && on.canStart());
  };
  el.addEventListener('pointerup', end);
  el.addEventListener('pointercancel', end);
}

/** Ease-out tween over `ms`; calls `frame(k)` with k in 0..1 and `done` at the end. Returns a cancel. */
export function tween(ms: number, frame: (k: number) => void, done: () => void): () => void {
  let raf = 0;
  const t0 = performance.now();
  const step = (now: number): void => {
    const k = Math.min(1, (now - t0) / ms);
    frame(1 - (1 - k) * (1 - k));
    if (k < 1) raf = requestAnimationFrame(step);
    else done();
  };
  raf = requestAnimationFrame(step);
  return () => cancelAnimationFrame(raf);
}

/** One sequential timer that waits while the game is paused. */
export function pausableTimer(isPaused: () => boolean): { later(ms: number, fn: () => void): void; cancel(): void } {
  let id = 0;
  return {
    later(ms, fn) {
      window.clearTimeout(id);
      id = window.setTimeout(function tick() {
        if (isPaused()) {
          id = window.setTimeout(tick, 200);
          return;
        }
        fn();
      }, ms);
    },
    cancel: () => window.clearTimeout(id),
  };
}
