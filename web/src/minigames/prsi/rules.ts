import { Prng } from '../../rules/prng';
import type { TuningMinigamesPrsi } from '../../gen/tuning';
import { IllegalAction, type Rules, type RulesResult } from '../rules';

/** specs/minigames/prsi.md, version 1. */
export interface PrsiConfig {
  hand: number;
  roundsToWin: number;
  aiErrorPct: number[];
}

export type Side = 'player' | 'ai';

export interface PrsiState {
  deck: number[];
  player: number[];
  ai: number[];
  pile: number[];
  suit: number;
  sevens: number;
  ace: boolean;
  turn: Side;
  starter: Side;
  round: number;
  playerWins: number;
  aiWins: number;
  last: '' | Side;
  over: boolean;
  rng: number;
}

export type PrsiAction =
  | { by: Side; op: 'play'; card: number; suit: number }
  | { by: Side; op: 'draw' }
  | { by: Side; op: 'stand' }
  | { by: 'timeout' };

export interface PrsiResult extends RulesResult {
  playerWins: number;
  aiWins: number;
}

export function prsiConfig(t: TuningMinigamesPrsi): PrsiConfig {
  return { hand: t.hand, roundsToWin: t.roundsToWin, aiErrorPct: [...t.aiErrorPct] };
}

/** Card 0–31: suit = c div 8 (červené, zelené, kule, žaludy), rank = c mod 8 (7, 8, 9, 10, spodek, svršek, král, eso). */
export const suitOf = (c: number): number => Math.floor(c / 8);
export const rankOf = (c: number): number => c % 8;
export const SEVEN = 0;
export const QUEEN = 5;
export const ACE = 7;

const other = (s: Side): Side => (s === 'player' ? 'ai' : 'player');

/**
 * Draws up to n cards for `side`: an empty deck takes the pile without its top card, shuffled from
 * rng (no shuffle when there is nothing under the top card). Mutates the copies in `s`.
 */
function drawCards(s: PrsiState, side: Side, n: number): void {
  for (let k = 0; k < n; k++) {
    if (s.deck.length === 0 && s.pile.length > 1) {
      const top = s.pile[s.pile.length - 1]!;
      const r = new Prng(s.rng);
      s.deck = r.shuffle(s.pile.slice(0, -1));
      s.rng = r.state;
      s.pile = [top];
    }
    if (s.deck.length === 0) return;
    s[side].push(s.deck.shift()!);
  }
}

export class PrsiRules implements Rules<PrsiState, PrsiAction, PrsiResult, PrsiConfig> {
  readonly id = 'prsi';
  readonly specVersion = 1;
  private cfg: PrsiConfig | null = null;

  private get c(): PrsiConfig {
    if (!this.cfg) throw new Error('prsi: init first');
    return this.cfg;
  }

  init(config: PrsiConfig, seed: number): PrsiState {
    this.cfg = config;
    return this.deal({
      deck: [], player: [], ai: [], pile: [], suit: 0, sevens: 0, ace: false,
      turn: 'player', starter: 'player', round: 1, playerWins: 0, aiWins: 0, last: '', over: false,
      rng: new Prng(seed).state,
    });
  }

  /** New deal for s.round: shuffle, hand × (player, AI), turn up deck[0]. */
  private deal(s0: PrsiState): PrsiState {
    const r = new Prng(s0.rng);
    const deck = r.shuffle(Array.from({ length: 32 }, (_, i) => i));
    const s: PrsiState = { ...s0, deck, player: [], ai: [], pile: [], rng: r.state };
    for (let i = 0; i < this.c.hand; i++) {
      drawCards(s, 'player', 1);
      drawCards(s, 'ai', 1);
    }
    const up = s.deck.shift()!;
    s.pile = [up];
    s.suit = suitOf(up);
    s.sevens = rankOf(up) === SEVEN ? 1 : 0;
    s.ace = rankOf(up) === ACE;
    s.starter = s.round % 2 === 1 ? 'player' : 'ai';
    s.turn = s.starter;
    return s;
  }

  legalActions(s: PrsiState): PrsiAction[] {
    if (s.over) return [];
    const by = s.turn;
    const hand = [...s[by]].sort((a, b) => a - b);
    const out: PrsiAction[] = [];
    if (s.sevens > 0) {
      for (const c of hand) if (rankOf(c) === SEVEN) out.push({ by, op: 'play', card: c, suit: -1 });
      out.push({ by, op: 'draw' });
      return out;
    }
    if (s.ace) {
      for (const c of hand) if (rankOf(c) === ACE) out.push({ by, op: 'play', card: c, suit: -1 });
      out.push({ by, op: 'stand' });
      return out;
    }
    const topRank = rankOf(s.pile[s.pile.length - 1]!);
    for (const c of hand) {
      if (rankOf(c) === QUEEN) for (let su = 0; su < 4; su++) out.push({ by, op: 'play', card: c, suit: su });
      else if (rankOf(c) === topRank || suitOf(c) === s.suit) out.push({ by, op: 'play', card: c, suit: -1 });
    }
    out.push({ by, op: 'draw' });
    return out;
  }

  apply(s0: PrsiState, a: PrsiAction): PrsiState {
    if (s0.over) throw new IllegalAction(this.id, a);
    if (a.by === 'timeout') return { ...s0, over: true };
    const legal = this.legalActions(s0).some(
      (l) => l.by === a.by && l.op === a.op && (l.op !== 'play' || (a.op === 'play' && l.card === a.card && l.suit === a.suit)),
    );
    if (!legal) throw new IllegalAction(this.id, a);
    const side = s0.turn;
    const s: PrsiState = { ...s0, deck: [...s0.deck], player: [...s0.player], ai: [...s0.ai], pile: [...s0.pile] };
    if (a.op === 'play') {
      const hand = s[side];
      hand.splice(hand.indexOf(a.card), 1);
      s.pile.push(a.card);
      const rank = rankOf(a.card);
      s.suit = rank === QUEEN ? a.suit : suitOf(a.card);
      if (rank === SEVEN) {
        s.sevens += 1;
        s.ace = false;
      } else if (rank === ACE) {
        s.ace = true;
        s.sevens = 0;
      } else {
        s.sevens = 0;
        s.ace = false;
      }
      if (hand.length === 0) return this.endRound(s, side);
    } else if (a.op === 'draw') {
      const n = s.sevens > 0 ? 2 * s.sevens : 1;
      s.sevens = 0;
      drawCards(s, side, n);
    } else {
      s.ace = false;
    }
    s.turn = other(side);
    return s;
  }

  private endRound(s: PrsiState, winner: Side): PrsiState {
    if (winner === 'player') s.playerWins += 1;
    else s.aiWins += 1;
    s.last = winner;
    if (s.playerWins >= this.c.roundsToWin || s.aiWins >= this.c.roundsToWin) return { ...s, over: true };
    return this.deal({ ...s, round: s.round + 1 });
  }

  /** Heuristic value of a legal action for the AI (spec "AI"). */
  private value(s: PrsiState, a: PrsiAction, level: number): number {
    if (a.by === 'timeout' || a.op !== 'play') return 0;
    const h = [...s.ai];
    h.splice(h.indexOf(a.card), 1);
    const opp = s.player.length;
    const near = level >= 3 && opp <= 2;
    const rank = rankOf(a.card);
    const ofSuit = (su: number): number => h.filter((c) => suitOf(c) === su).length;
    if (rank === QUEEN) return 50 + 10 * ofSuit(a.suit);
    if (rank === SEVEN) return 100 + (near ? 30 : 0);
    if (rank === ACE) return 100 + (near ? 20 : 0);
    return 100 + 5 * ofSuit(suitOf(a.card));
  }

  aiAction(s: PrsiState, level: number, ai: Prng): PrsiAction {
    const legal = this.legalActions(s);
    if (s.turn !== 'ai' || legal.length === 0) throw new IllegalAction(this.id, { by: 'ai' });
    const err = this.c.aiErrorPct[level - 1] ?? 0;
    if (ai.nextInt(100) < err) return legal[ai.nextInt(legal.length)]!;
    let best = legal[0]!;
    let bv = this.value(s, best, level);
    for (const a of legal.slice(1)) {
      const v = this.value(s, a, level);
      if (v > bv) {
        best = a;
        bv = v;
      }
    }
    return best;
  }

  result(s: PrsiState): PrsiResult | null {
    if (!s.over) return null;
    const { playerWins: p, aiWins: a } = s;
    const winner = p > a ? 'player' : p < a ? 'ai' : 'draw';
    const stars = winner !== 'player' ? 0 : a === 0 ? 3 : a === 1 ? 2 : 1;
    return { winner, stars, score: 100 * p, playerWins: p, aiWins: a };
  }
}
