import type { Locale, MessageKey } from '../gen/i18n';
import type { MinigameContext, MinigameMeta, MinigameResult } from '../gen/schema';
import type { Tuning } from '../gen/tuning';

/** The web side of the minigame contract (specs/minigames/README.md, DUALSTACK 6.5). */
export interface Minigame {
  meta: MinigameMeta;
  /** Mounts the game into `host`; returns unmount. `onFinish` is called once. */
  mount(host: HTMLElement, ctx: MinigameContext, onFinish: (r: MinigameResult) => void): () => void;
}

/** What a game needs from the app besides the contract context. */
export interface MinigameEnv {
  tuning: Tuning;
  locale: Locale;
  t: (k: MessageKey, a?: Record<string, string | number>) => string;
}
