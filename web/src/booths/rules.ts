import { Prng } from '../rules/prng';
import type { TuningBooths } from '../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../minigames/rules';

/** specs/booths.md, version 1: ringing phone booths in whole game seconds (P0, module `booths`). */
export interface BoothsConfig {
  booths: number;
  gapMin: number;
  gapMax: number;
  retry: number;
  ringS: number;
  bonus: number;
  /** Spot ids with a catalog minigame, in spot order (the feed's candidates). */
  games: string[];
}

export interface BoothOffer {
  spot: string;
  bonus: number;
}

export interface BoothsState {
  ringing: number;
  left: number;
  next: number;
  answered: number;
  missed: number;
  offer: BoothOffer;
  paid: number;
  last: number;
  rng: number;
}

export type BoothsAction =
  | { by: 'player'; op: 'tick'; near: number[] }
  | { by: 'player'; op: 'answer'; booth: number }
  | { by: 'player'; op: 'finish'; spot: string; stars: number; aborted: boolean }
  | { by: 'player'; op: 'clear' };

export type BoothsResult = RulesResult;

/** Config from tuning, the number of booths and the minigame spots of the city. */
export function boothsConfig(t: TuningBooths, booths: number, games: readonly string[]): BoothsConfig {
  return { booths, gapMin: t.gapMinS, gapMax: t.gapMaxS, retry: t.retryS, ringS: t.ringS, bonus: t.bonus, games: [...games] };
}

const noOffer = (): BoothOffer => ({ spot: '', bonus: 0 });
const isInt = (v: unknown): v is number => typeof v === 'number' && Number.isInteger(v);

export class BoothsRules implements Rules<BoothsState, BoothsAction, BoothsResult, BoothsConfig> {
  readonly id = 'booths';
  readonly specVersion = 1;
  private cfg: BoothsConfig | null = null;

  get config(): BoothsConfig {
    if (!this.cfg) throw new Error('booths: init first');
    return this.cfg;
  }

  /** gap() = gapMin + rng.nextInt(gapMax − gapMin + 1). */
  private gap(r: Prng): number {
    const c = this.config;
    return c.gapMin + r.nextInt(c.gapMax - c.gapMin + 1);
  }

  init(config: BoothsConfig, seed: number): BoothsState {
    this.cfg = config;
    const r = new Prng(seed);
    const next = this.gap(r);
    return { ringing: -1, left: 0, next, answered: 0, missed: 0, offer: noOffer(), paid: 0, last: 0, rng: r.state };
  }

  legalActions(s: BoothsState): BoothsAction[] {
    const out: BoothsAction[] = [{ by: 'player', op: 'clear' }, { by: 'player', op: 'tick', near: [] }];
    if (s.ringing >= 0) out.push({ by: 'player', op: 'answer', booth: s.ringing });
    return out;
  }

  /** `near`: ascending, no duplicates, every index in [0, booths). */
  private validNear(near: unknown): near is number[] {
    if (!Array.isArray(near)) return false;
    let prev = -1;
    for (const b of near) {
      if (!isInt(b) || b <= prev || b >= this.config.booths) return false;
      prev = b;
    }
    return true;
  }

  apply(state: BoothsState, a: BoothsAction): BoothsState {
    if (a.by !== 'player') throw new IllegalAction(this.id, a);
    const c = this.config;
    const s: BoothsState = { ...state, offer: { ...state.offer }, last: 0 };
    const r = new Prng(s.rng);
    switch (a.op) {
      case 'tick': {
        if (!this.validNear(a.near)) throw new IllegalAction(this.id, a);
        if (s.ringing >= 0) {
          s.left--;
          if (s.left === 0) {
            s.ringing = -1;
            s.missed++;
            s.next = this.gap(r);
          }
          break;
        }
        s.next--;
        if (s.next > 0) break;
        if (a.near.length === 0 || c.games.length === 0) {
          s.next = c.retry;
          break;
        }
        s.ringing = a.near[r.nextInt(a.near.length)]!;
        s.left = c.ringS;
        break;
      }
      case 'answer': {
        if (!isInt(a.booth) || s.ringing < 0 || a.booth !== s.ringing) throw new IllegalAction(this.id, a);
        s.offer = { spot: c.games[r.nextInt(c.games.length)]!, bonus: c.bonus };
        s.ringing = -1;
        s.left = 0;
        s.answered++;
        s.next = this.gap(r);
        break;
      }
      case 'finish': {
        if (typeof a.spot !== 'string' || !isInt(a.stars) || a.stars < 0 || a.stars > 3 || typeof a.aborted !== 'boolean') {
          throw new IllegalAction(this.id, a);
        }
        if (s.offer.spot !== '' && a.spot === s.offer.spot) {
          if (a.stars >= 1 && !a.aborted) {
            s.last = s.offer.bonus;
            s.paid += s.last;
          }
          s.offer = noOffer();
        }
        break;
      }
      case 'clear':
        s.offer = noOffer();
        break;
      default:
        throw new IllegalAction(this.id, a);
    }
    s.rng = r.state;
    return s;
  }

  aiAction(_s: BoothsState, _level: number, _ai: Prng): BoothsAction {
    throw new Error('booths: no opponent');
  }

  result(_s: BoothsState): BoothsResult | null {
    return null;
  }
}
