import type { Prng } from '../rules/prng';
import type { TuningPolice } from '../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../minigames/rules';

/** specs/police.md, version 1: wanted level, escape and capture in integer ticks (P0, module `police`). */
export type OffenceKind = 'crash' | 'hitrun' | 'sidewalk' | 'theft';

/** Alphabetical: the order of legalActions and of the `cool` keys. */
export const OFFENCE_KINDS: readonly OffenceKind[] = ['crash', 'hitrun', 'sidewalk', 'theft'];

export type OffenceMap = Record<OffenceKind, number>;

export interface PoliceConfig {
  maxLevel: number;
  escapeTicks: number;
  captureTicks: number;
  hitRunTicks: number;
  cooldownTicks: number;
  levels: OffenceMap;
  fines: number[];
}

export interface PoliceState {
  level: number;
  unseen: number;
  capture: number;
  hitRun: number;
  hitRunSeen: boolean;
  cool: OffenceMap;
  offences: number;
  last: string;
  busted: number;
  fined: number;
}

export type PoliceAction =
  | { by: 'player'; op: 'offence'; kind: OffenceKind; seen: boolean }
  | { by: 'player'; op: 'tick'; seen: boolean; near: boolean; away: boolean };

export type PoliceResult = RulesResult;

const ticks = (s: number, hz: number): number => Math.round(s * hz);

/** Config from tuning: seconds become integer ticks at police.tick_hz. */
export function policeConfig(t: TuningPolice): PoliceConfig {
  const o = t.offenceLevel;
  return {
    maxLevel: t.maxLevel,
    escapeTicks: ticks(t.escapeS, t.tickHz),
    captureTicks: ticks(t.captureS, t.tickHz),
    hitRunTicks: ticks(t.hitRunS, t.tickHz),
    cooldownTicks: ticks(t.cooldownS, t.tickHz),
    levels: { crash: o.crash, hitrun: o.hitrun, sidewalk: o.sidewalk, theft: o.theft },
    fines: [...t.fines],
  };
}

/** Fine when busted at `level` (specs/police.md): fines[min(level, len − 1)]. */
export function fine(level: number, fines: readonly number[]): number {
  if (fines.length === 0) return 0;
  return fines[Math.max(0, Math.min(level, fines.length - 1))]!;
}

const zeroCool = (v: number): OffenceMap => ({ crash: v, hitrun: v, sidewalk: v, theft: v });

export class PoliceRules implements Rules<PoliceState, PoliceAction, PoliceResult, PoliceConfig> {
  readonly id = 'police';
  readonly specVersion = 1;
  private cfg: PoliceConfig | null = null;

  get config(): PoliceConfig {
    if (!this.cfg) throw new Error('police: init first');
    return this.cfg;
  }

  init(config: PoliceConfig, _seed: number): PoliceState {
    this.cfg = config;
    return { level: 0, unseen: 0, capture: 0, hitRun: 0, hitRunSeen: false, cool: zeroCool(0), offences: 0, last: '', busted: 0, fined: 0 };
  }

  legalActions(_s: PoliceState): PoliceAction[] {
    const out: PoliceAction[] = [];
    for (const kind of OFFENCE_KINDS) for (const seen of [false, true]) out.push({ by: 'player', op: 'offence', kind, seen });
    for (let b = 0; b < 8; b++) out.push({ by: 'player', op: 'tick', seen: (b & 4) !== 0, near: (b & 2) !== 0, away: (b & 1) !== 0 });
    return out;
  }

  /** Counts a seen offence that is not cooling down (spec "Započtení přestupku"); mutates s. */
  private commit(s: PoliceState, kind: OffenceKind, seen: boolean): void {
    const c = this.config;
    if (!seen || s.cool[kind] > 0) return;
    s.level = Math.min(c.maxLevel, Math.max(c.levels[kind], s.level > 0 ? s.level + 1 : 0));
    s.offences++;
    s.last = kind;
    s.cool[kind] = c.cooldownTicks;
    s.unseen = 0;
  }

  apply(state: PoliceState, a: PoliceAction): PoliceState {
    if (a.by !== 'player' || typeof a.seen !== 'boolean') throw new IllegalAction(this.id, a);
    const c = this.config;
    const s: PoliceState = { ...state, cool: { ...state.cool } };
    if (a.op === 'offence') {
      if (!OFFENCE_KINDS.includes(a.kind)) throw new IllegalAction(this.id, a);
      if (a.kind === 'crash') {
        s.hitRunSeen = (s.hitRun > 0 && s.hitRunSeen) || a.seen;
        s.hitRun = c.hitRunTicks;
      }
      this.commit(s, a.kind, a.seen);
      return s;
    }
    if (a.op !== 'tick' || typeof a.near !== 'boolean' || typeof a.away !== 'boolean') throw new IllegalAction(this.id, a);
    for (const k of OFFENCE_KINDS) s.cool[k] = Math.max(0, s.cool[k] - 1);
    if (s.hitRun > 0) {
      if (a.away) {
        const seen = a.seen || s.hitRunSeen;
        s.hitRun = 0;
        s.hitRunSeen = false;
        this.commit(s, 'hitrun', seen);
      } else {
        s.hitRun--;
        if (s.hitRun === 0) s.hitRunSeen = false;
      }
    }
    if (s.level === 0) {
      s.unseen = 0;
      s.capture = 0;
      return s;
    }
    s.capture = a.near ? s.capture + 1 : 0;
    if (s.capture >= c.captureTicks) {
      s.fined += fine(s.level, c.fines);
      s.busted++;
      s.level = 0;
      s.unseen = 0;
      s.capture = 0;
      s.hitRun = 0;
      s.hitRunSeen = false;
      s.cool = zeroCool(c.cooldownTicks);
      return s;
    }
    s.unseen = a.seen ? 0 : s.unseen + 1;
    if (s.unseen >= c.escapeTicks) {
      s.level--;
      s.unseen = 0;
    }
    return s;
  }

  aiAction(_s: PoliceState, _level: number, _ai: Prng): PoliceAction {
    throw new Error('police: no opponent');
  }

  result(_s: PoliceState): PoliceResult | null {
    return null;
  }
}
