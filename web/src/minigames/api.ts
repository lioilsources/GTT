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
  /** The NPC opponent (MinigameContext.opponentId) resolved by the launcher; its line shows on the result screen. */
  opponent?: MinigameOpponent;
}

/**
 * A minigame played in the running world (engine `drive`, e.g. Taxi, specs/minigames/taxi.md):
 * the loop starts it at its spot instead of mounting a full-screen game; the world keeps running.
 */
export interface WorldMinigame {
  readonly active: boolean;
  /** Starts at the spot; `onFinish` is called once when it ends (the loop shows its result). */
  start(spotId: string, ctx: MinigameContext, onFinish: (r: MinigameResult) => void): void;
}

/** An NPC opponent as the shell needs it (specs/dialogue.md "Hláška soupeře"). */
export interface MinigameOpponent {
  id: string;
  name: string;
  /** Index into tokens colorNpcPortraits (placeholder portrait). */
  portrait: number;
  /** The quip for the player's outcome, in the env locale. */
  line(winner: 'player' | 'ai' | 'draw'): string;
}
