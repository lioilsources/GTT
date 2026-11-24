import { Prng } from '../../rules/prng';
import type { TuningMinigamesDurak } from '../../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../rules';

/** specs/minigames/durak.md, version 1: podkidnoy durak, 36 cards. */
export interface DurakConfig {
  hand: number;
  opponents: number[];
  aiErrorPct: number[];
  level: number;
}

export interface DurakPair {
  a: number;
  d: number;
}

export interface DurakState {
  n: number;
  hands: number[][];
  stock: number[];
  trump: number;
  trumpCard: number;
  table: DurakPair[];
  attacker: number;
  defender: number;
  thrower: number;
  passes: number;
  limit: number;
  finished: number[];
  over: boolean;
  durak: number;
  byCount: boolean;
  rng: number;
}

type By = 'player' | 'ai';
export type DurakAction =
  | { by: By; op: 'play' | 'beat'; card: number }
  | { by: By; op: 'take' | 'pass' }
  | { by: 'timeout' };

export interface DurakResult extends RulesResult {
  byCount: boolean;
  place: number;
  durak: number;
}

export function durakConfig(t: TuningMinigamesDurak, level: number): DurakConfig {
  return { hand: t.hand, opponents: [...t.opponents], aiErrorPct: [...t.aiErrorPct], level };
}

/** Card 0–35: rank = c mod 9 (0 = 6 … 8 = A), suit = c div 9 (♠ ♥ ♦ ♣). */
export const rankOf = (c: number): number => c % 9;
export const suitOf = (c: number): number => Math.floor(c / 9);
/** The Oko bere card index (52-card face) of a durak card, for drawing. */
export const face = (c: number): number => suitOf(c) * 13 + rankOf(c) + 4;

export function beats(a: number, b: number, trump: number): boolean {
  if (suitOf(a) === suitOf(b)) return rankOf(a) > rankOf(b);
  return suitOf(a) === trump && suitOf(b) !== trump;
}

const price = (c: number, trump: number): number => (suitOf(c) === trump ? 9 : 0) + rankOf(c);
const byOf = (seat: number): By => (seat === 0 ? 'player' : 'ai');

export class DurakRules implements Rules<DurakState, DurakAction, DurakResult, DurakConfig> {
  readonly id = 'durak';
  readonly specVersion = 1;
  private cfg: DurakConfig | null = null;

  private get c(): DurakConfig {
    if (!this.cfg) throw new Error('durak: init first');
    return this.cfg;
  }

  init(config: DurakConfig, seed: number): DurakState {
    this.cfg = config;
    const lv = Math.min(Math.max(config.level, 1), 5);
    const n = (config.opponents[lv - 1] ?? 1) + 1;
    const r = new Prng(seed);
    const deck = r.shuffle(Array.from({ length: 36 }, (_, i) => i));
    const hands: number[][] = Array.from({ length: n }, () => []);
    for (let k = 0; k < config.hand * n; k++) hands[k % n]!.push(deck[k]!);
    hands.forEach((hd) => hd.sort((a, b) => a - b));
    const stock = deck.slice(config.hand * n);
    const trumpCard = stock[stock.length - 1]!;
    const trump = suitOf(trumpCard);
    let attacker = 0, low = 99;
    hands.forEach((hd, i) => {
      for (const c of hd) if (suitOf(c) === trump && rankOf(c) < low) {
        low = rankOf(c);
        attacker = i;
      }
    });
    return {
      n, hands, stock, trump, trumpCard, table: [], attacker, defender: (attacker + 1) % n, thrower: attacker,
      passes: 0, limit: 0, finished: [], over: false, durak: -1, byCount: false, rng: r.state,
    };
  }

  /** The seat to act: the defender while a card lies unbeaten, else the thrower. */
  turn(s: DurakState): number {
    return s.table.some((p) => p.d < 0) ? s.defender : s.thrower;
  }

  /** Throwers in order from the attacker: seats in play except the defender. */
  private throwers(s: DurakState): number[] {
    const out: number[] = [];
    for (let k = 0; k < s.n; k++) {
      const i = (s.attacker + k) % s.n;
      if (i !== s.defender && !s.finished.includes(i)) out.push(i);
    }
    return out;
  }

  private canPlay(s: DurakState, c: number): boolean {
    if (s.table.length === 0) return true;
    if (s.table.length >= s.limit) return false;
    const r = rankOf(c);
    return s.table.some((p) => rankOf(p.a) === r || (p.d >= 0 && rankOf(p.d) === r));
  }

  legalActions(s: DurakState): DurakAction[] {
    if (s.over) return [];
    const seat = this.turn(s);
    const by = byOf(seat);
    const hand = s.hands[seat]!;
    if (seat === s.defender && s.table.some((p) => p.d < 0)) {
      const a = s.table.find((p) => p.d < 0)!.a;
      return [...hand.filter((c) => beats(c, a, s.trump)).map((card) => ({ by, op: 'beat' as const, card })), { by, op: 'take' }];
    }
    const plays: DurakAction[] = hand.filter((c) => this.canPlay(s, c)).map((card) => ({ by, op: 'play' as const, card }));
    return s.table.length === 0 ? plays : [...plays, { by, op: 'pass' }];
  }

  apply(s: DurakState, a: DurakAction): DurakState {
    if (s.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s, over: true, byCount: true };
    const legal = this.legalActions(s);
    if (!legal.some((l) => l.by === a.by && l.op === a.op && ('card' in l ? 'card' in a && a.card === l.card : !('card' in a)))) {
      throw new IllegalAction(this.id, a);
    }
    const seat = this.turn(s);
    const hands = s.hands.map((hd) => [...hd]);
    if (a.op === 'play') {
      hands[seat] = hands[seat]!.filter((c) => c !== a.card);
      const limit = s.table.length === 0 ? Math.min(6, s.hands[s.defender]!.length) : s.limit;
      return { ...s, hands, table: [...s.table, { a: a.card, d: -1 }], limit, passes: 0 };
    }
    if (a.op === 'beat') {
      hands[seat] = hands[seat]!.filter((c) => c !== a.card);
      const table = s.table.map((p) => (p.d < 0 ? { a: p.a, d: a.card } : p));
      return { ...s, hands, table, thrower: s.attacker, passes: 0 };
    }
    if (a.op === 'take') {
      for (const p of s.table) {
        hands[seat]!.push(p.a);
        if (p.d >= 0) hands[seat]!.push(p.d);
      }
      hands[seat]!.sort((x, y) => x - y);
      return this.endRound({ ...s, hands }, true);
    }
    const th = this.throwers(s);
    const passes = s.passes + 1;
    if (passes >= th.length) return this.endRound({ ...s, passes }, false);
    const at = th.indexOf(s.thrower);
    return { ...s, passes, thrower: th[(at + 1) % th.length]! };
  }

  private endRound(s: DurakState, took: boolean): DurakState {
    const order = [...this.throwers(s), s.defender];
    const hands = s.hands.map((hd) => [...hd]);
    const stock = [...s.stock];
    for (const i of order) {
      while (hands[i]!.length < this.c.hand && stock.length) hands[i]!.push(stock.shift()!);
      hands[i]!.sort((x, y) => x - y);
    }
    const finished = [...s.finished];
    if (stock.length === 0) for (const i of order) if (hands[i]!.length === 0 && !finished.includes(i)) finished.push(i);
    const base: DurakState = { ...s, hands, stock, table: [], passes: 0, limit: 0, finished };
    const live = Array.from({ length: s.n }, (_, i) => i).filter((i) => !finished.includes(i));
    if (live.length <= 1) return { ...base, over: true, durak: live.length ? live[0]! : -1 };
    const next = (from: number): number => {
      for (let k = 1; k <= s.n; k++) {
        const i = (from + k) % s.n;
        if (!finished.includes(i)) return i;
      }
      return from;
    };
    const attacker = !took && !finished.includes(s.defender) ? s.defender : next(s.defender);
    return { ...base, attacker, defender: next(attacker), thrower: attacker };
  }

  aiAction(s: DurakState, level: number, ai: Prng): DurakAction {
    if (s.over) throw new IllegalAction(this.id, { by: 'ai' });
    const c = this.c;
    const legal = this.legalActions(s);
    const lv = Math.min(Math.max(level, 1), 5);
    if (ai.nextInt(100) < (c.aiErrorPct[lv - 1] ?? 0)) return legal[ai.nextInt(legal.length)]!;
    const cheapest = (cards: number[]): number => {
      let best = cards[0]!;
      for (const x of cards) if (price(x, s.trump) < price(best, s.trump)) best = x;
      return best;
    };
    const cardsOf = (op: string): number[] =>
      legal.filter((l) => 'card' in l && l.op === op).map((l) => (l as { card: number }).card);
    const by = legal[0]!.by as By;
    const beatCards = cardsOf('beat');
    if (legal.some((l) => 'op' in l && l.op === 'take')) {
      return beatCards.length ? { by, op: 'beat', card: cheapest(beatCards) } : { by, op: 'take' };
    }
    const plays = cardsOf('play');
    if (s.table.length === 0) return { by, op: 'play', card: cheapest(plays) };
    const ok = plays.filter((x) => suitOf(x) !== s.trump || s.stock.length === 0);
    return ok.length ? { by, op: 'play', card: cheapest(ok) } : { by, op: 'pass' };
  }

  result(s: DurakState): DurakResult | null {
    if (!s.over) return null;
    const place = s.finished.indexOf(0) + 1;
    let winner: 'player' | 'ai' | 'draw';
    let stars: number;
    if (s.byCount) {
      const mine = s.hands[0]!.length;
      const ok = place > 0 || Array.from({ length: s.n }, (_, i) => i)
        .filter((i) => i > 0 && !s.finished.includes(i))
        .every((i) => s.hands[i]!.length > mine);
      winner = ok ? 'player' : 'ai';
      stars = ok ? 1 : 0;
    } else if (s.durak === 0) {
      winner = 'ai';
      stars = 0;
    } else if (place === 1) {
      winner = 'player';
      stars = 3;
    } else if (s.durak < 0) {
      winner = 'draw';
      stars = 1;
    } else {
      winner = 'player';
      stars = 2;
    }
    return { winner, stars, score: stars * 100, byCount: s.byCount, place, durak: s.durak };
  }
}
