import { Prng } from '../../rules/prng';
import type { TuningMinigamesOko } from '../../gen/tuning';
import { IllegalAction, withRng, type Rules, type RulesResult } from '../rules';

/** specs/minigames/oko.md, version 1. */
export interface OkoConfig {
  roundsToWin: number;
  dealerStand: number;
}

export type Outcome = 'win' | 'lose' | 'push';

export interface OkoLast {
  player: number[];
  dealer: number[];
  outcome: Outcome | '';
}

export interface OkoState {
  deck: number[];
  player: number[];
  dealer: number[];
  playerWins: number;
  dealerWins: number;
  round: number;
  phase: 'play' | 'over';
  last: OkoLast;
  over: boolean;
  rng: number;
}

export type OkoAction = { by: 'player'; op: 'hit' | 'stand' } | { by: 'timeout' };

export interface OkoResult extends RulesResult {
  playerWins: number;
  dealerWins: number;
}

export function okoConfig(t: TuningMinigamesOko): OkoConfig {
  return { roundsToWin: t.roundsToWin, dealerStand: t.dealerStand };
}

/** Card 0–51: rank = c mod 13 (0 = 2 … 8 = 10, 9 J, 10 Q, 11 K, 12 A), suit = c div 13 (♠ ♥ ♦ ♣). */
export const rankOf = (c: number): number => c % 13;
export const suitOf = (c: number): number => Math.floor(c / 13);

/** Aces count 11, then drop 10 per ace while the total is over 21. */
export function handTotal(cards: readonly number[]): number {
  let sum = 0;
  let aces = 0;
  for (const c of cards) {
    const r = rankOf(c);
    if (r === 12) {
      sum += 11;
      aces++;
    } else sum += r <= 8 ? r + 2 : 10;
  }
  while (sum > 21 && aces > 0) {
    sum -= 10;
    aces--;
  }
  return sum;
}

/** Oko: 21 from two cards. */
export const isNatural = (cards: readonly number[]): boolean => cards.length === 2 && handTotal(cards) === 21;

const HIT: OkoAction = { by: 'player', op: 'hit' };
const STAND: OkoAction = { by: 'player', op: 'stand' };

export class OkoRules implements Rules<OkoState, OkoAction, OkoResult, OkoConfig> {
  readonly id = 'oko';
  readonly specVersion = 1;
  private cfg: OkoConfig | null = null;

  init(config: OkoConfig, seed: number): OkoState {
    this.cfg = config;
    const s: OkoState = {
      deck: [],
      player: [],
      dealer: [],
      playerWins: 0,
      dealerWins: 0,
      round: 1,
      phase: 'play',
      last: { player: [], dealer: [], outcome: '' },
      over: false,
      rng: new Prng(seed).state,
    };
    return this.deal(s);
  }

  private get c(): OkoConfig {
    if (!this.cfg) throw new Error('oko: init first');
    return this.cfg;
  }

  /** Shuffles a fresh deck from rng, deals player, banker, player, banker, then checks naturals. */
  private deal(s: OkoState): OkoState {
    const { value: deck, rng } = withRng(s.rng, (r) => r.shuffle(Array.from({ length: 52 }, (_, i) => i)));
    const player = [deck[0]!, deck[2]!];
    const dealer = [deck[1]!, deck[3]!];
    const n: OkoState = { ...s, deck: deck.slice(4), player, dealer, phase: 'play', rng };
    const pn = isNatural(player), dn = isNatural(dealer);
    if (pn && dn) return this.settle(n, 'push');
    if (pn) return this.settle(n, 'win');
    if (dn) return this.settle(n, 'lose');
    return n;
  }

  /** Scores a finished round; ends the game or deals the next round. */
  private settle(s: OkoState, outcome: Outcome): OkoState {
    const n: OkoState = {
      ...s,
      playerWins: s.playerWins + (outcome === 'win' ? 1 : 0),
      dealerWins: s.dealerWins + (outcome === 'lose' ? 1 : 0),
      last: { player: [...s.player], dealer: [...s.dealer], outcome },
    };
    if (n.playerWins >= this.c.roundsToWin || n.dealerWins >= this.c.roundsToWin) {
      return { ...n, over: true, phase: 'over' };
    }
    return this.deal({ ...n, round: s.round + 1 });
  }

  /** The banker draws below dealerStand (soft totals included), then the hands are compared. */
  private stand(s: OkoState): OkoState {
    const deck = [...s.deck];
    const dealer = [...s.dealer];
    while (handTotal(dealer) < this.c.dealerStand) dealer.push(deck.shift()!);
    const n = { ...s, deck, dealer };
    const p = handTotal(s.player), d = handTotal(dealer);
    return this.settle(n, d > 21 || p > d ? 'win' : p < d ? 'lose' : 'push');
  }

  legalActions(s: OkoState): OkoAction[] {
    return s.phase === 'play' && !s.over ? [HIT, STAND] : [];
  }

  apply(s: OkoState, a: OkoAction): OkoState {
    if (s.over || s.phase !== 'play') throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s, over: true, phase: 'over' };
    if (a.by !== 'player') throw new IllegalAction(this.id, a);
    if (a.op === 'stand') return this.stand(s);
    if (a.op !== 'hit') throw new IllegalAction(this.id, a);
    const n = { ...s, deck: s.deck.slice(1), player: [...s.player, s.deck[0]!] };
    const total = handTotal(n.player);
    if (total > 21) return this.settle(n, 'lose');
    if (total === 21) return this.stand(n);
    return n;
  }

  /** The banker has no decisions; the contract still wants an AI move: the first legal action. */
  aiAction(s: OkoState, _level: number, _ai: Prng): OkoAction {
    const a = this.legalActions(s)[0];
    if (!a) throw new IllegalAction(this.id, { by: 'ai' });
    return a;
  }

  result(s: OkoState): OkoResult | null {
    if (!s.over) return null;
    const { playerWins: p, dealerWins: d } = s;
    const winner = p > d ? 'player' : p < d ? 'ai' : 'draw';
    const stars = winner !== 'player' ? 0 : d <= 2 ? 3 : d === 3 ? 2 : d === 4 ? 1 : 0;
    return { winner, stars, score: 100 * p, playerWins: p, dealerWins: d };
  }
}
