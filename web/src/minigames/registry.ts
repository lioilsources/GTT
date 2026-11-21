import type { MinigameId } from '../gen/ids';
import type { Minigame, MinigameEnv } from './api';
import { sirky } from './sirky/game';

/** Minigames this client implements; the Gallery greys out the rest. */
export const minigames: Partial<Record<MinigameId, (env: MinigameEnv) => Minigame>> = {
  sirky,
};
