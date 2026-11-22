import type { MinigameId } from '../gen/ids';
import type { Minigame, MinigameEnv } from './api';
import { sirky } from './sirky/game';
import { oko } from './oko/game';
import { dama } from './dama/game';
import { desetitisic } from './desetitisic/game';
import { sipky } from './sipky/game';
import { koulena } from './koulena/game';
import { strelnice } from './strelnice/game';
import { taxi } from './taxi/game';
import { kulicky } from './kulicky/game';
import { cara } from './cara/game';
import { nohejbal } from './nohejbal/game';

/** Minigames this client implements; the Gallery greys out the rest. */
export const minigames: Partial<Record<MinigameId, (env: MinigameEnv) => Minigame>> = {
  sirky,
  oko,
  dama,
  desetitisic,
  sipky,
  koulena,
  strelnice,
  taxi,
  kulicky,
  cara,
  nohejbal,
};
