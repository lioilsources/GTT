import { replay } from '../minigames/rules';
import { SirkyRules } from '../minigames/sirky/rules';
import { OkoRules } from '../minigames/oko/rules';
import { DamaRules } from '../minigames/dama/rules';
import { DesetitisicRules } from '../minigames/desetitisic/rules';
import { SipkyRules } from '../minigames/sipky/rules';
import { KoulenaRules } from '../minigames/koulena/rules';
import { StrelniceRules } from '../minigames/strelnice/rules';
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
  sirky: () => new SirkyRules() as unknown as AnyRules,
  oko: () => new OkoRules() as unknown as AnyRules,
  dama: () => new DamaRules() as unknown as AnyRules,
  desetitisic: () => new DesetitisicRules() as unknown as AnyRules,
  sipky: () => new SipkyRules() as unknown as AnyRules,
  koulena: () => new KoulenaRules() as unknown as AnyRules,
  strelnice: () => new StrelniceRules() as unknown as AnyRules,
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
