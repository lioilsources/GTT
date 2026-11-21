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

export const replayers: Record<string, Replayer> = {
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
