import { describe, expect, it } from 'vitest';

import { aiPrng } from '../src/minigames/rules';
import { PrsiRules, type PrsiConfig, type PrsiState } from '../src/minigames/prsi/rules';
import { points, SrdceRules, type SrdceConfig, type SrdceState } from '../src/minigames/srdce/rules';
import { Prng } from '../src/rules/prng';

const prsiCfg: PrsiConfig = { hand: 4, roundsToWin: 3, aiErrorPct: [40, 25, 12, 5, 0] };
const srdceCfg: SrdceConfig = { target: 50, maxDeals: 3, aiErrorPct: [40, 25, 12, 5, 0], starMargins: [15, 5] };

/** Mariáš card: suit 0–3, rank 0 = 7 … 7 = eso. */
const m = (suit: number, rank: number): number => suit * 8 + rank;

function prsiState(r: PrsiRules, over: Partial<PrsiState>): PrsiState {
  return { ...r.init(prsiCfg, 1), ...over };
}

describe('prsi rules (specs/minigames/prsi.md)', () => {
  it('deals hand cards each, turns one up, player starts round 1', () => {
    const r = new PrsiRules();
    const s = r.init(prsiCfg, 42);
    expect(s.player).toHaveLength(prsiCfg.hand);
    expect(s.ai).toHaveLength(prsiCfg.hand);
    expect(s.pile).toHaveLength(1);
    expect(s.deck).toHaveLength(32 - 2 * prsiCfg.hand - 1);
    expect(s.turn).toBe('player');
    expect(new Set([...s.deck, ...s.player, ...s.ai, ...s.pile]).size).toBe(32);
  });

  it('a svršek goes on anything and expands to four suits; draw last', () => {
    const r = new PrsiRules();
    const s = prsiState(r, { player: [m(2, 5), m(1, 1), m(0, 3)], pile: [m(0, 2)], suit: 0, sevens: 0, ace: false });
    expect(r.legalActions(s)).toEqual([
      { by: 'player', op: 'play', card: m(0, 3), suit: -1 },
      { by: 'player', op: 'play', card: m(2, 5), suit: 0 },
      { by: 'player', op: 'play', card: m(2, 5), suit: 1 },
      { by: 'player', op: 'play', card: m(2, 5), suit: 2 },
      { by: 'player', op: 'play', card: m(2, 5), suit: 3 },
      { by: 'player', op: 'draw' },
    ]);
  });

  it('sevens stack and the next side draws two per seven', () => {
    const r = new PrsiRules();
    let s = prsiState(r, { player: [m(1, 0), m(1, 1)], ai: [m(2, 0), m(3, 3)], pile: [m(1, 4)], suit: 1, sevens: 0, ace: false });
    s = r.apply(s, { by: 'player', op: 'play', card: m(1, 0), suit: -1 });
    expect(s.sevens).toBe(1);
    expect(r.legalActions(s)).toEqual([{ by: 'ai', op: 'play', card: m(2, 0), suit: -1 }, { by: 'ai', op: 'draw' }]);
    s = r.apply(s, { by: 'ai', op: 'play', card: m(2, 0), suit: -1 });
    expect(s.sevens).toBe(2);
    const before = s.player.length;
    s = r.apply(s, { by: 'player', op: 'draw' });
    expect(s.player.length).toBe(before + 4);
    expect([s.sevens, s.turn]).toEqual([0, 'ai']);
  });

  it('an ace makes the next side stand or answer with an ace', () => {
    const r = new PrsiRules();
    let s = prsiState(r, { player: [m(0, 7), m(1, 1)], ai: [m(3, 7), m(3, 3)], pile: [m(0, 4)], suit: 0, sevens: 0, ace: false });
    s = r.apply(s, { by: 'player', op: 'play', card: m(0, 7), suit: -1 });
    expect(r.legalActions(s)).toEqual([{ by: 'ai', op: 'play', card: m(3, 7), suit: -1 }, { by: 'ai', op: 'stand' }]);
    const stood = r.apply(s, { by: 'ai', op: 'stand' });
    expect([stood.ace, stood.turn]).toEqual([false, 'player']);
  });

  it('reshuffles the pile under the top card when the deck runs out', () => {
    const r = new PrsiRules();
    const s = prsiState(r, { deck: [], pile: [m(0, 1), m(0, 2), m(0, 3)], player: [m(3, 4)], suit: 0, sevens: 0, ace: false });
    const n = r.apply(s, { by: 'player', op: 'draw' });
    expect(n.pile).toEqual([m(0, 3)]);
    expect(n.deck.length + n.player.length).toBe(1 + 2);
    expect(n.rng).not.toBe(s.rng);
    // Nothing left to draw: the turn still passes.
    const empty = prsiState(r, { deck: [], pile: [m(0, 3)], player: [m(3, 4)], suit: 0, sevens: 0, ace: false });
    const e = r.apply(empty, { by: 'player', op: 'draw' });
    expect([e.player.length, e.turn, e.rng]).toEqual([1, 'ai', empty.rng]);
  });

  it('the last card wins the round even when it is a seven', () => {
    const r = new PrsiRules();
    const s = prsiState(r, { player: [m(0, 0)], pile: [m(0, 4)], suit: 0, sevens: 0, ace: false });
    const n = r.apply(s, { by: 'player', op: 'play', card: m(0, 0), suit: -1 });
    expect([n.playerWins, n.round, n.last, n.turn, n.sevens]).toEqual([1, 2, 'player', 'ai', n.sevens]);
  });

  it('AI draws r on every move, even with one legal action', () => {
    const r = new PrsiRules();
    const s = prsiState(r, { turn: 'ai', ai: [m(3, 3)], pile: [m(0, 1)], suit: 0, sevens: 0, ace: false });
    const ai = aiPrng(5);
    const ref = aiPrng(5);
    expect(r.aiAction(s, 5, ai)).toEqual({ by: 'ai', op: 'draw' });
    ref.nextInt(100);
    expect(ai.state).toBe(ref.state);
  });

  it('result: 3★ for a clean sweep', () => {
    const r = new PrsiRules();
    const s = prsiState(r, { over: true, playerWins: 3, aiWins: 0 });
    expect(r.result(s)).toEqual({ winner: 'player', stars: 3, score: 300, playerWins: 3, aiWins: 0 });
  });
});

function srdceState(r: SrdceRules, over: Partial<SrdceState>): SrdceState {
  return { ...r.init(srdceCfg, 1), ...over };
}

describe('srdce rules (specs/minigames/srdce.md)', () => {
  it('deals 13 each and the two of clubs leads', () => {
    const r = new SrdceRules();
    const s = r.init(srdceCfg, 9);
    expect(s.hands.map((h) => h.length)).toEqual([13, 13, 13, 13]);
    expect(s.hands[s.turn]).toContain(39);
    expect(r.legalCards(s)).toEqual([39]);
  });

  it('no points on the first trick unless nothing else', () => {
    const r = new SrdceRules();
    const s = srdceState(r, { turn: 1, leader: 0, trick: [39], tricks: 0, hands: [[], [10, 14, 0], [], []] });
    expect(r.legalCards(s)).toEqual([0]);
    const only = srdceState(r, { turn: 1, leader: 0, trick: [39], tricks: 0, hands: [[], [10, 14], [], []] });
    expect(r.legalCards(only)).toEqual([10, 14]);
  });

  it('hearts lead only when broken or the hand is all hearts', () => {
    const r = new SrdceRules();
    const s = srdceState(r, { turn: 0, trick: [], tricks: 3, broken: false, hands: [[2, 14, 20], [], [], []] });
    expect(r.legalCards(s)).toEqual([2]);
    expect(r.legalCards({ ...s, hands: [[14, 20], [], [], []] })).toEqual([14, 20]);
    expect(r.legalCards({ ...s, broken: true })).toEqual([2, 14, 20]);
  });

  it('the highest card of the led suit takes the points', () => {
    const r = new SrdceRules();
    const s = srdceState(r, { turn: 3, leader: 0, trick: [5, 12, 14], tricks: 4, hands: [[1], [2], [3], [10, 4]] });
    const n = r.apply(s, { by: 'ai', card: 4 });
    expect(n.lastTrick).toEqual({ cards: [5, 12, 14, 4], leader: 0, winner: 1 });
    expect(n.taken[1]).toBe(1);
    expect([n.turn, n.leader, n.tricks]).toEqual([1, 1, 5]);
  });

  it('shooting the moon gives the others 26', () => {
    const r = new SrdceRules();
    const s = srdceState(r, { turn: 3, leader: 0, trick: [25, 0, 1], tricks: 12, taken: [25, 0, 0, 0], hands: [[], [], [], [2]] });
    const n = r.apply(s, { by: 'ai', card: 2 });
    expect(n.scores).toEqual([0, 26, 26, 26]);
    expect(points(10)).toBe(13);
  });

  it('AI draws r on every card', () => {
    const r = new SrdceRules();
    const s = srdceState(r, { turn: 1, leader: 0, trick: [39], tricks: 0, hands: [[], [40], [], []] });
    const ai = aiPrng(3), ref = aiPrng(3);
    expect(r.aiAction(s, 5, ai)).toEqual({ by: 'ai', card: 40 });
    ref.nextInt(100);
    expect(ai.state).toBe(ref.state);
  });

  it('a full random game ends and the result is consistent', () => {
    const r = new SrdceRules();
    let s = r.init(srdceCfg, 77);
    const ai = aiPrng(77), p = new Prng(5);
    while (!r.result(s)) {
      const l = r.legalActions(s);
      s = r.apply(s, s.turn === 0 ? l[p.nextInt(l.length)]! : r.aiAction(s, 3, ai));
    }
    expect(s.over).toBe(true);
    expect(r.result(s)!.scores).toEqual(s.scores);
  });
});
