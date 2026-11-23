import type { ControlInput } from './drive/controls';

/**
 * Pause under overlays (specs/pause.md, F-034): one registry per client. An overlay registers when
 * it opens and releases when it closes; the main loop steps the world with `paused ? 0 : dt`.
 */

/**
 * Overlays that stop the game (specs/pause.md "Co hru zastaví"; `booth` = the booth offer card,
 * specs/booths.md; `travel` = the metro card and the line card of a move, specs/travel.md; `photo` =
 * the Camera framing mode, specs/photo.md; `shop` = the shop and bar card, specs/shops.md; `intro` =
 * the first run card, specs/firstrun.md).
 */
export const pausingOverlays = [
  'phone', 'garage', 'passport', 'about', 'postcard', 'dialogue', 'arrival', 'minigame', 'result', 'gallery', 'debug', 'bench', 'booth',
  'travel', 'photo', 'shop', 'intro',
] as const;
/** Short notices that do not wait for a tap (cash, fine, wanted, nav): they never pause. */
export type ToastKind = 'toast';
export type OverlayKind = (typeof pausingOverlays)[number] | ToastKind;

const pausing: ReadonlySet<string> = new Set(pausingOverlays);

/** Pure: true when at least one open overlay pauses the game. */
export function paused(open: Iterable<OverlayKind>): boolean {
  for (const k of open) if (pausing.has(k)) return true;
  return false;
}

/** Open overlays, counted per opening (two postcards in a row, a dialogue over a result, …). */
export class OverlayRegistry {
  private readonly open_ = new Map<number, OverlayKind>();
  private next = 1;

  /** Registers an open overlay; returns its release (idempotent). */
  open(kind: OverlayKind): () => void {
    const id = this.next++;
    this.open_.set(id, kind);
    return () => void this.open_.delete(id);
  }

  /** The open overlay kinds (with repeats). */
  get kinds(): OverlayKind[] {
    return [...this.open_.values()];
  }

  get paused(): boolean {
    return paused(this.open_.values());
  }

  isOpen(kind: OverlayKind): boolean {
    for (const k of this.open_.values()) if (k === kind) return true;
    return false;
  }

  clear(): void {
    this.open_.clear();
  }
}

/** The client-wide registry every overlay hooks into. */
export const overlays = new OverlayRegistry();

/**
 * Per-frame gate for the main loop: the simulation dt (0 while paused), the drive input zeroed
 * while paused and once more on resume, when `onResume` drops held pointers and keys.
 */
export class PauseGate {
  private was = false;

  constructor(readonly registry: OverlayRegistry = overlays) {}

  get paused(): boolean {
    return this.registry.paused;
  }

  frame(dt: number, input: ControlInput | null, onResume?: () => void): number {
    const p = this.registry.paused;
    if (p || this.was) input?.reset();
    if (!p && this.was) onResume?.();
    this.was = p;
    return p ? 0 : dt;
  }
}
