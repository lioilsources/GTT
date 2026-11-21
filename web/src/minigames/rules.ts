import { Prng } from '../rules/prng';

/** JSON-shaped action: `by` is "player", "ai" or "timeout" (specs/minigames/README.md). */
export interface Action {
  by: 'player' | 'ai' | 'timeout';
  [k: string]: unknown;
}

/** Every result carries at least these fields; games add their own. */
export interface RulesResult {
  winner: 'player' | 'ai' | 'draw';
  stars: number;
  score: number;
}

/** The pure rules shape shared by both clients (DUALSTACK 5.4). States are plain JSON objects. */
export interface Rules<S extends object, A extends Action, R extends RulesResult, C = Record<string, unknown>> {
  readonly id: string;
  readonly specVersion: number;
  init(config: C, seed: number): S;
  legalActions(state: S): A[];
  /** Pure: returns a new state, throws on an illegal action. */
  apply(state: S, action: A): S;
  aiAction(state: S, level: number, ai: Prng): A;
  result(state: S): R | null;
}

/** The opponent's own random stream, one per game. */
export function aiPrng(seed: number): Prng {
  return new Prng((seed ^ 0x5bd1e995) >>> 0);
}

/** Rule-side randomness lives in the state as the PRNG's uint32 state. */
export function withRng<T>(rng: number, f: (r: Prng) => T): { value: T; rng: number } {
  const r = new Prng(rng);
  const value = f(r);
  return { value, rng: r.state };
}

export class IllegalAction extends Error {
  constructor(module: string, action: unknown) {
    super(`${module}: illegal action ${JSON.stringify(action)}`);
  }
}

/** Replays one vector case: AI steps given only as {by:"ai", level} are decided by aiAction. */
export function replay<S extends object, A extends Action, R extends RulesResult>(
  rules: Rules<S, A, R, never>,
  c: { config: Record<string, unknown>; seed: number; steps: Array<{ action: Record<string, unknown> }> },
): { states: S[]; result: R | null } {
  const ai = aiPrng(c.seed);
  let s = (rules as Rules<S, A, R, Record<string, unknown>>).init(c.config, c.seed);
  const states: S[] = [];
  for (const step of c.steps) {
    let a = step.action as A;
    if (a.by === 'ai' && Object.keys(a).every((k) => k === 'by' || k === 'level')) {
      a = rules.aiAction(s, a['level'] as number, ai);
    }
    s = rules.apply(s, a);
    states.push(s);
  }
  return { states, result: rules.result(s) };
}
