import { replay } from '../minigames/rules';
import { SirkyRules } from '../minigames/sirky/rules';
import { OkoRules } from '../minigames/oko/rules';
import { DamaRules } from '../minigames/dama/rules';
import { DesetitisicRules } from '../minigames/desetitisic/rules';
import { SipkyRules } from '../minigames/sipky/rules';
import { KoulenaRules } from '../minigames/koulena/rules';
import { StrelniceRules } from '../minigames/strelnice/rules';
import { TaxiRules } from '../minigames/taxi/rules';
import { KulickyRules } from '../minigames/kulicky/rules';
import { CaraRules } from '../minigames/cara/rules';
import { NohejbalRules } from '../minigames/nohejbal/rules';
import { PiskvorkyRules } from '../minigames/piskvorky/rules';
import { CtyriRules } from '../minigames/ctyri/rules';
import { MlynRules } from '../minigames/mlyn/rules';
import { ReversiRules } from '../minigames/reversi/rules';
import { LodeRules } from '../minigames/lode/rules';
import { PosuvneRules } from '../minigames/posuvne/rules';
import { KvizRules } from '../minigames/kviz/rules';
import { PrsiRules } from '../minigames/prsi/rules';
import { SrdceRules } from '../minigames/srdce/rules';
import { KostkyRules } from '../minigames/kostky/rules';
import { PraseRules } from '../minigames/prase/rules';
import { RouteRules } from '../drive/gps';
import { FeedRules } from '../phone/feed';
import { PassportRules } from '../passport/rules';
import { DialogueRules } from '../dialogue/rules';
import { CarsRules } from '../cars/rules';
import { PoliceRules } from '../police/rules';
import { BoothsRules } from '../booths/rules';
import { EconomyRules } from '../loop/economy';
import { SaveRules } from '../loop/save';
import { TravelRules } from '../travel/rules';
import { PhotoRules } from '../photo/rules';
import { ShopsRules } from '../shops/rules';
import { WeatherRules } from '../weather/rules';
import { GarageRules } from '../garage/rules';
import { Prng } from './prng';

/** One step of a P0 vector: an action and the state after it (DUALSTACK 5.4). */
export interface VectorStep {
  action: Record<string, unknown>;
  state: Record<string, unknown>;
}

export interface VectorCase {
  name: string;
  config: Record<string, unknown>;
  seed: number;
  steps: VectorStep[];
  result: unknown;
}

export interface VectorFile {
  module: string;
  specVersion: number;
  cases: VectorCase[];
}

/** Replays a case and returns the states this client produces, one per step. */
export type Replayer = (c: VectorCase) => Array<Record<string, unknown>>;

type AnyRules = Parameters<typeof replay>[0];

/** Minigame rules modules by vector module id (specs/minigames/README.md "Vektory"). */
export const rulesModules: Record<string, () => AnyRules> = {
  route: () => new RouteRules() as unknown as AnyRules,
  feed: () => new FeedRules() as unknown as AnyRules,
  sirky: () => new SirkyRules() as unknown as AnyRules,
  oko: () => new OkoRules() as unknown as AnyRules,
  dama: () => new DamaRules() as unknown as AnyRules,
  desetitisic: () => new DesetitisicRules() as unknown as AnyRules,
  sipky: () => new SipkyRules() as unknown as AnyRules,
  koulena: () => new KoulenaRules() as unknown as AnyRules,
  strelnice: () => new StrelniceRules() as unknown as AnyRules,
  taxi: () => new TaxiRules() as unknown as AnyRules,
  kulicky: () => new KulickyRules() as unknown as AnyRules,
  cara: () => new CaraRules() as unknown as AnyRules,
  nohejbal: () => new NohejbalRules() as unknown as AnyRules,
  piskvorky: () => new PiskvorkyRules() as unknown as AnyRules,
  ctyri: () => new CtyriRules() as unknown as AnyRules,
  mlyn: () => new MlynRules() as unknown as AnyRules,
  reversi: () => new ReversiRules() as unknown as AnyRules,
  lode: () => new LodeRules() as unknown as AnyRules,
  posuvne: () => new PosuvneRules() as unknown as AnyRules,
  kviz: () => new KvizRules() as unknown as AnyRules,
  prsi: () => new PrsiRules() as unknown as AnyRules,
  srdce: () => new SrdceRules() as unknown as AnyRules,
  kostky: () => new KostkyRules() as unknown as AnyRules,
  prase: () => new PraseRules() as unknown as AnyRules,
  passport: () => new PassportRules() as unknown as AnyRules,
  dialogue: () => new DialogueRules() as unknown as AnyRules,
  cars: () => new CarsRules() as unknown as AnyRules,
  police: () => new PoliceRules() as unknown as AnyRules,
  booths: () => new BoothsRules() as unknown as AnyRules,
  economy: () => new EconomyRules() as unknown as AnyRules,
  save: () => new SaveRules() as unknown as AnyRules,
  travel: () => new TravelRules() as unknown as AnyRules,
  photo: () => new PhotoRules() as unknown as AnyRules,
  shops: () => new ShopsRules() as unknown as AnyRules,
  weather: () => new WeatherRules() as unknown as AnyRules,
  garage: () => new GarageRules() as unknown as AnyRules,
};

/** Final result of a rules case (compared with case.result). */
export function replayResult(module: string, c: VectorCase): unknown {
  const make = rulesModules[module];
  return make ? replay(make(), c).result : undefined;
}

const rulesReplayer = (make: () => AnyRules): Replayer => (c) =>
  replay(make(), c).states as unknown as Array<Record<string, unknown>>;

export const replayers: Record<string, Replayer> = {
  ...Object.fromEntries(Object.entries(rulesModules).map(([k, make]) => [k, rulesReplayer(make)])),
  prng: (c) => {
    const r = new Prng(c.seed);
    return c.steps.map(({ action }) => {
      switch (action['op']) {
        case 'nextU32':
          return { value: r.nextU32(), x: r.state };
        case 'nextInt':
          return { value: r.nextInt(action['n'] as number), x: r.state };
        case 'shuffle':
          return { value: r.shuffle([...(action['items'] as number[])]), x: r.state };
        default:
          throw new Error(`prng: unknown op ${String(action['op'])}`);
      }
    });
  },
};

/** Canonical JSON (sorted keys) so state comparison never depends on key order. */
export function canonical(v: unknown): string {
  if (Array.isArray(v)) return `[${v.map(canonical).join(',')}]`;
  if (v !== null && typeof v === 'object') {
    const o = v as Record<string, unknown>;
    return `{${Object.keys(o)
      .sort()
      .map((k) => `${JSON.stringify(k)}:${canonical(o[k])}`)
      .join(',')}}`;
  }
  return JSON.stringify(v);
}
