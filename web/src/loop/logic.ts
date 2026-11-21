// Loop glue (specs/loop.md): pure helpers and the loop book (best results, plays, cash, stamps).
// No DOM, no Babylon.
import type { BestResult, MinigameResult } from '../gen/schema';
import type { Tuning, TuningFeed, TuningLoop } from '../gen/tuning';
import { fnv1a } from '../passport/postcard';
import { economyConfig, EconomyRules, type EconomyAction, type EconomyLast, type EconomyState } from './economy';

/** Difficulty of the minigame at a spot (specs/loop.md "Kontext minihry"). */
export function loopDifficulty(cardDifficulty: number | null, plays: number, feed: TuningFeed): number {
  const d = cardDifficulty ?? Math.min(feed.difficultyMax, feed.difficultyBase + plays);
  return Math.min(5, Math.max(1, d));
}

/** NPC opponent index for a spot: fnv1a(spotId) mod count, -1 without characters. */
export function opponentIndex(spotId: string, count: number): number {
  return count <= 0 ? -1 : fnv1a(spotId) % count;
}

/** True when (stars, score) beats the stored best (or there is none). */
export function betterBest(old: BestResult | undefined, stars: number, score: number): boolean {
  return !old || stars > old.stars || (stars === old.stars && score > old.score);
}

export interface LoopSpot {
  id: string;
  minigame: string;
  /** Parking point, metres. */
  x: number;
  y: number;
}

/** The nearest spot with a minigame within loop.spot_radius_m while the car stands (layer 0). */
export function spotInReach(spots: readonly LoopSpot[], x: number, y: number, speed: number, layer: number, t: TuningLoop): LoopSpot | null {
  if (speed > t.stopSpeedMps || layer !== 0) return null;
  return nearestSpot(spots, x, y, t.spotRadiusM);
}

export function nearestSpot(spots: readonly LoopSpot[], x: number, y: number, radius: number): LoopSpot | null {
  let best: LoopSpot | null = null;
  let bd = radius * radius;
  for (const s of spots) {
    if (!s.minigame) continue;
    const d = (s.x - x) ** 2 + (s.y - y) ** 2;
    if (d <= bd) {
      bd = d;
      best = s;
    }
  }
  return best;
}

/** Where the loop reads and writes the state it does not own (cash: cars state, stamps: passport). */
export interface LoopPorts {
  getCash(): number;
  setCash(cash: number): void;
  /** Passport minigame(id, stars); true when a new stamp was added. */
  stamp(minigame: string, stars: number): boolean;
}

export interface LoopInput {
  spot: string;
  minigame: string;
  engine: string;
  result: MinigameResult;
  /** distDm of the accepted feed card that led here, 0 without one. */
  driveDm: number;
}

/** Everything the result screen shows (specs/loop.md "Výsledek smyčky"). */
export interface LoopOutcome {
  spot: string;
  minigame: string;
  stars: number;
  score: number;
  aborted: boolean;
  cash: EconomyLast;
  /** Cash after the reward. */
  total: number;
  firstTime: boolean;
  newBest: boolean;
  stamp: boolean;
  hasStamp: boolean;
}

/** Best results, plays per spot and the economy of one session. */
export class LoopBook {
  readonly economy = new EconomyRules();
  eco: EconomyState;
  best: Record<string, BestResult> = {};
  plays: Record<string, number> = {};

  constructor(readonly tuning: Tuning, readonly ports: LoopPorts) {
    this.eco = this.economy.init(economyConfig(tuning, ports.getCash()));
  }

  restore(best: Record<string, BestResult>, plays: Record<string, number>): void {
    this.best = { ...best };
    this.plays = { ...plays };
  }

  /** One economy action on the cash held by the cars state. */
  pay(a: EconomyAction): EconomyLast {
    this.eco = this.economy.apply({ ...this.eco, cash: this.ports.getCash() }, a);
    this.ports.setCash(this.eco.cash);
    return this.eco.last;
  }

  tow(): EconomyLast {
    return this.pay({ by: 'player', op: 'tow' });
  }

  /** Police fine hook (the police feature calls this). */
  fine(amount: number): EconomyLast {
    return this.pay({ by: 'player', op: 'fine', amount: Math.max(0, Math.floor(amount)) });
  }

  finish(inp: LoopInput, hasStamp: (id: string) => boolean): LoopOutcome {
    const r = inp.result;
    const stars = r.aborted ? 0 : r.stars;
    const old = this.best[inp.minigame];
    const firstTime = !old || old.stars < 1;
    const cash = this.pay({
      by: 'player', op: 'reward', engine: inp.engine, stars, score: r.score, first: firstTime, driveDm: inp.driveDm, aborted: r.aborted,
    });
    const stamp = r.aborted ? false : this.ports.stamp(inp.minigame, stars);
    const newBest = !r.aborted && betterBest(old, stars, r.score);
    if (newBest) this.best = { ...this.best, [inp.minigame]: { stars, score: r.score } };
    if (!r.aborted) this.plays = { ...this.plays, [inp.spot]: (this.plays[inp.spot] ?? 0) + 1 };
    const o: LoopOutcome = {
      spot: inp.spot, minigame: inp.minigame, stars, score: r.score, aborted: r.aborted, cash, total: this.eco.cash,
      firstTime: firstTime && cash.first > 0, newBest, stamp, hasStamp: hasStamp(inp.minigame),
    };
    return o;
  }
}
