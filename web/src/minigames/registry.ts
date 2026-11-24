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
import { piskvorky } from './piskvorky/game';
import { ctyri } from './ctyri/game';
import { mlyn } from './mlyn/game';
import { reversi } from './reversi/game';
import { lode } from './lode/game';
import { posuvne } from './posuvne/game';
import { kviz } from './kviz/game';
import { prsi } from './prsi/game';
import { srdce } from './srdce/game';
import { kostky } from './kostky/game';
import { prase } from './prase/game';
import { kulecnik } from './kulecnik/game';
import { bowling } from './bowling/game';
import { minigolf } from './minigolf/game';
import { had } from './had/game';
import { cihly } from './cihly/game';
import { krtek } from './krtek/game';
import { hokej } from './hokej/game';
import { drift } from './drift/game';
import { sprint } from './sprint/game';
import { stickball } from './stickball/game';
import { doubledutch } from './doubledutch/game';
import { sachy } from './sachy/game';
import { gorodki } from './gorodki/game';
import { durak } from './durak/game';

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
  piskvorky,
  ctyri,
  mlyn,
  reversi,
  lode,
  posuvne,
  kviz,
  prsi,
  srdce,
  kostky,
  prase,
  kulecnik,
  bowling,
  minigolf,
  had,
  cihly,
  krtek,
  hokej,
  drift,
  sprint,
  stickball,
  doubledutch,
  sachy,
  gorodki,
  durak,
};
