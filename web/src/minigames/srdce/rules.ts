import { Prng } from '../../rules/prng';
import type { TuningMinigamesSrdce } from '../../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../rules';

/** specs/minigames/srdce.md, version 1. */
export interface SrdceConfig {
  target: number;
  maxDeals: number;
  aiErrorPct: number[];
  starMargins: number[];
}

export interface SrdceTrick {
  cards: number[];
  leader: number;
  winner: number;
}

export interface SrdceState {
  hands: number[][];
  trick: number[];
  leader: number;
  turn: number;
  taken: number[];
  scores: number[];
  deal: number;
  tricks: number;
  broken: boolean;
  lastTrick: SrdceTrick;
  over: boolean;
  rng: number;
}

export type SrdceAction = { by: 'player' | 'ai'; card: number } | { by: 'timeout' };

export interface SrdceResult extends RulesResult {
  scores: number[];
}

export function srdceConfig(t: TuningMinigamesSrdce): SrdceConfig {
  return { target: t.target, maxDeals: t.maxDeals, aiErrorPct: [...t.aiErrorPct], starMargins: [...t.starMargins] };
}

/** Card 0–51 as in Oko bere: rank = c mod 13 (0 = 2 … 12 = A), suit = c div 13 (♠ ♥ ♦ ♣). */
export const rankOf = (c: number): number => c % 13;
export const suitOf = (c: number): number => Math.floor(c / 13);
export const HEARTS = 1;
export const TWO_OF_CLUBS = 39;
export const QUEEN_OF_SPADES = 10;
export const points = (c: number): number => (c === QUEEN_OF_SPADES ? 13 : suitOf(c) === HEARTS ? 1 : 0);

const byOf = (seat: number): 'player' | 'ai' => (seat === 0 ? 'player' : 'ai');

export class SrdceRules implements Rules<SrdceState, SrdceAction, SrdceResult, SrdceConfig> {
  readonly id = 'srdce';
  readonly specVersion = 1;
  private cfg: SrdceConfig | null = null;

  private get c(): SrdceConfig {
    if (!this.cfg) throw new Error('srdce: init first');
    return this.cfg;
  }

  init(config: SrdceConfig, seed: number): SrdceState {
    this.cfg = config;
    return this.newDeal({
      hands: [], trick: [], leader: 0, turn: 0, taken: [], scores: [0, 0, 0, 0], deal: 1, tricks: 0,
      broken: false, lastTrick: { cards: [], leader: -1, winner: -1 }, over: false, rng: new Prng(seed).state,
    });
  }

  private newDeal(s: SrdceState): SrdceState {
    const r = new Prng(s.rng);
    const deck = r.shuffle(Array.from({ length: 52 }, (_, i) => i));
    const hands: number[][] = [[], [], [], []];
    deck.forEach((c, i) => hands[i % 4]!.push(c));
    hands.forEach((h) => h.sort((a, b) => a - b));
    const leader = hands.findIndex((h) => h.includes(TWO_OF_CLUBS));
    return { ...s, hands, taken: [0, 0, 0, 0], trick: [], tricks: 0, broken: false, leader, turn: leader, rng: r.state };
  }

  /** Legal cards of the seat on turn, ascending. */
  legalCards(s: SrdceState): number[] {
    if (s.over) return [];
    const hand = s.hands[s.turn]!;
    if (s.trick.length === 0) {
      if (s.tricks === 0) return hand.includes(TWO_OF_CLUBS) ? [TWO_OF_CLUBS] : [];
      if (s.broken || hand.every((c) => suitOf(c) === HEARTS)) return [...hand];
      return hand.filter((c) => suitOf(c) !== HEARTS);
    }
    const led = suitOf(s.trick[0]!);
    const follow = hand.filter((c) => suitOf(c) === led);
    if (follow.length > 0) return follow;
    if (s.tricks === 0) {
      const clean = hand.filter((c) => points(c) === 0);
      if (clean.length > 0) return clean;
    }
    return [...hand];
  }

  legalActions(s: SrdceState): SrdceAction[] {
    const by = byOf(s.turn);
    return this.legalCards(s).map((card) => ({ by, card }));
  }

  apply(s0: SrdceState, a: SrdceAction): SrdceState {
    if (s0.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s0, over: true };
    if (a.by !== byOf(s0.turn) || !this.legalCards(s0).includes(a.card)) throw new IllegalAction(this.id, a);
    const hands = s0.hands.map((h, i) => (i === s0.turn ? h.filter((c) => c !== a.card) : [...h]));
    const trick = [...s0.trick, a.card];
    const s: SrdceState = { ...s0, hands, trick, broken: s0.broken || suitOf(a.card) === HEARTS };
    if (trick.length < 4) return { ...s, turn: (s0.turn + 1) % 4 };
    const led = suitOf(trick[0]!);
    let wi = 0;
    for (let i = 1; i < 4; i++) {
      const c = trick[i]!;
      if (suitOf(c) === led && rankOf(c) > rankOf(trick[wi]!)) wi = i;
    }
    const winner = (s0.leader + wi) % 4;
    const taken = [...s0.taken];
    taken[winner]! += trick.reduce((t, c) => t + points(c), 0);
    const n: SrdceState = {
      ...s, taken, trick: [], tricks: s0.tricks + 1, leader: winner, turn: winner,
      lastTrick: { cards: trick, leader: s0.leader, winner },
    };
    return n.tricks === 13 ? this.endDeal(n) : n;
  }

  private endDeal(s: SrdceState): SrdceState {
    const moon = s.taken.indexOf(26);
    const scores = s.scores.map((v, i) => v + (moon >= 0 ? (i === moon ? 0 : 26) : s.taken[i]!));
    const n = { ...s, scores };
    if (scores.some((v) => v >= this.c.target) || s.deal >= this.c.maxDeals) return { ...n, over: true };
    return this.newDeal({ ...n, deal: s.deal + 1 });
  }

  private value(s: SrdceState, c: number, level: number): number {
    const rank = rankOf(c);
    if (s.trick.length === 0) return -rank - (suitOf(c) === HEARTS ? 5 : 0);
    const led = suitOf(s.trick[0]!);
    if (suitOf(c) === led) {
      if (level <= 2) return -rank;
      const w = Math.max(...s.trick.filter((x) => suitOf(x) === led).map(rankOf));
      if (rank < w) return 1000 + rank;
      if (c === QUEEN_OF_SPADES) return -1000;
      const pts = s.trick.reduce((t, x) => t + points(x), 0);
      if (s.trick.length === 3 && pts === 0) return 500 + rank;
      return 100 - rank;
    }
    if (level <= 2) return rank;
    if (c === QUEEN_OF_SPADES) return 3000;
    if (suitOf(c) === HEARTS) return 2000 + rank;
    return 1000 + rank;
  }

  aiAction(s: SrdceState, level: number, ai: Prng): SrdceAction {
    const legal = this.legalCards(s);
    if (s.over || s.turn === 0 || legal.length === 0) throw new IllegalAction(this.id, { by: 'ai' });
    const err = this.c.aiErrorPct[level - 1] ?? 0;
    if (ai.nextInt(100) < err) return { by: 'ai', card: legal[ai.nextInt(legal.length)]! };
    let best = legal[0]!;
    let bv = this.value(s, best, level);
    for (const c of legal.slice(1)) {
      const v = this.value(s, c, level);
      if (v > bv) {
        best = c;
        bv = v;
      }
    }
    return { by: 'ai', card: best };
  }

  result(s: SrdceState): SrdceResult | null {
    if (!s.over) return null;
    const me = s.scores[0]!;
    const best = Math.min(s.scores[1]!, s.scores[2]!, s.scores[3]!);
    const winner = me < best ? 'player' : me === best ? 'draw' : 'ai';
    const m = this.c.starMargins;
    const stars = winner !== 'player' ? 0 : best - me >= m[0]! ? 3 : best - me >= m[1]! ? 2 : 1;
    return { winner, stars, score: Math.max(0, 100 - me), scores: [...s.scores] };
  }
}
