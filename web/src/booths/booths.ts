// Ringing booths in the world (specs/booths.md P1): booth list, reach, the 1 s game tick. No DOM, no Babylon.
import type { MinigameMeta } from '../gen/schema';
import type { Tuning, TuningLoop } from '../gen/tuning';
import { opponentIndex } from '../loop/logic';
import { boothsConfig, BoothsRules, type BoothOffer, type BoothsState } from './rules';

/** A booth: spot `kind: booth`, parking point in metres. */
export interface Booth {
  id: string;
  name: string;
  x: number;
  y: number;
  heading: number;
}

interface SpotLike {
  id: string;
  kind: string;
  name: string;
  parkX: number;
  parkY: number;
  parkHeading: number;
  minigame: string;
}

/** Booths in spots.pb order; index b = order among `kind = booth` spots. */
export function boothsOf(spots: readonly SpotLike[]): Booth[] {
  return spots.filter((s) => s.kind === 'booth').map((s) => ({ id: s.id, name: s.name, x: s.parkX / 10, y: s.parkY / 10, heading: s.parkHeading }));
}

/** Spot ids with a catalog minigame, in spot order (the feed's candidates, specs/feed.md). */
export function boothGames(spots: readonly SpotLike[], catalog: Readonly<Record<string, MinigameMeta | undefined>>): string[] {
  return spots.filter((s) => s.minigame !== '' && catalog[s.minigame] !== undefined).map((s) => s.id);
}

/** Indices of booths with ring_min_m ≤ distance(player, parking point) ≤ ring_max_m, ascending. */
export function nearBooths(booths: readonly Booth[], x: number, y: number, minM: number, maxM: number): number[] {
  const out: number[] = [];
  booths.forEach((b, i) => {
    const d2 = (b.x - x) ** 2 + (b.y - y) ** 2;
    if (d2 >= minM * minM && d2 <= maxM * maxM) out.push(i);
  });
  return out;
}

/** Same conditions as "Hrát" at a spot (specs/loop.md): standing, layer 0, parking point in reach. */
export function boothInReach(b: Booth, x: number, y: number, speed: number, layer: number, t: TuningLoop): boolean {
  return speed <= t.stopSpeedMps && layer === 0 && (b.x - x) ** 2 + (b.y - y) ** 2 <= t.spotRadiusM ** 2;
}

/** Host of a booth call: characters[fnv1a(boothId) mod n], −1 without characters (as the loop opponent). */
export const boothHost = opponentIndex;

/** The booths module of one session: state, game clock and its events. */
export class BoothWorld {
  readonly rules = new BoothsRules();
  state: BoothsState;
  /** Game seconds not yet ticked. */
  private acc = 0;
  /** Called when a booth starts ringing (HUD toast). */
  onRing: Array<(b: Booth) => void> = [];

  constructor(readonly booths: readonly Booth[], tuning: Tuning, games: readonly string[], seed: number) {
    this.state = this.rules.init(boothsConfig(tuning.booths, booths.length, games), seed);
  }

  get ringing(): Booth | null {
    return this.state.ringing >= 0 ? (this.booths[this.state.ringing] ?? null) : null;
  }

  get offer(): BoothOffer | null {
    return this.state.offer.spot !== '' ? this.state.offer : null;
  }

  /**
   * Advances the game clock by `stepDt` (0 while paused) and ticks once per whole second;
   * `near()` gives the booths in reach at that tick (empty while ringing is suppressed).
   */
  update(stepDt: number, near: () => number[]): void {
    this.acc += Math.max(0, stepDt);
    while (this.acc >= 1) {
      this.acc -= 1;
      const was = this.state.ringing;
      this.state = this.rules.apply(this.state, { by: 'player', op: 'tick', near: near() });
      const b = this.ringing;
      if (was < 0 && b) for (const f of this.onRing) f(b);
    }
  }

  /** Picks up the ringing booth; returns the offer, null when it no longer rings. */
  answer(booth: number): BoothOffer | null {
    if (this.state.ringing < 0 || booth !== this.state.ringing) return null;
    this.state = this.rules.apply(this.state, { by: 'player', op: 'answer', booth });
    return this.offer;
  }

  /** Loop result on a spot; returns the bonus (`last`). */
  finish(spot: string, stars: number, aborted: boolean): number {
    const s = Math.max(0, Math.min(3, Math.floor(stars)));
    this.state = this.rules.apply(this.state, { by: 'player', op: 'finish', spot, stars: s, aborted });
    return this.state.last;
  }

  clear(): void {
    this.state = this.rules.apply(this.state, { by: 'player', op: 'clear' });
  }
}
