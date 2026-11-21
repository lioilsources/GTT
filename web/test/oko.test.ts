import { describe, expect, it } from 'vitest';

import { handTotal, isNatural, OkoRules, type OkoAction, type OkoConfig, type OkoState } from '../src/minigames/oko/rules';
import { replay } from '../src/minigames/rules';

const cfg: OkoConfig = { roundsToWin: 5, dealerStand: 17 };
// card(rank, suit): rank 0 = 2 … 8 = 10, 9 J, 10 Q, 11 K, 12 A.
const card = (rank: number, suit = 0): number => suit * 13 + rank;
const A = 12, K = 11, TEN = 8;
const v = (n: number, suit = 0): number => card(n - 2, suit); // pip card by value 2–10
const HIT: OkoAction = { by: 'player', op: 'hit' };
const STAND: OkoAction = { by: 'player', op: 'stand' };

/** A fresh state with the given hands and the rest of the deck on top. */
function table(r: OkoRules, player: number[], dealer: number[], top: number[] = []): OkoState {
  const s = r.init(cfg, 7);
  const used = new Set([...player, ...dealer, ...top]);
  return { ...s, playerWins: 0, dealerWins: 0, round: 1, player, dealer, deck: [...top, ...Array.from({ length: 52 }, (_, i) => i).filter((c) => !used.has(c))], phase: 'play' };
}

describe('oko rules (specs/minigames/oko.md)', () => {
  it('counts aces as 11, then 1, repeatedly', () => {
    expect(handTotal([card(A), card(A, 1), v(9)])).toBe(21);
    expect(handTotal([card(A), card(A, 1)])).toBe(12);
    expect(handTotal([card(A), v(5)])).toBe(16);
    expect(handTotal([card(A), v(5), v(10)])).toBe(16);
    expect(handTotal([card(K), card(9), v(5)])).toBe(25);
    expect(isNatural([card(A), card(K)])).toBe(true);
    expect(isNatural([v(7), v(7, 1), v(7, 2)])).toBe(false);
  });

  it('deals two cards each from a shuffled deck and offers hit / stand', () => {
    const r = new OkoRules();
    const s = r.init(cfg, 42);
    expect(s.player.length + s.dealer.length + s.deck.length).toBe(52);
    expect(new Set([...s.player, ...s.dealer, ...s.deck]).size).toBe(52);
    if (s.round === 1) expect(r.legalActions(s)).toEqual([HIT, STAND]);
    expect(() => r.apply(s, { by: 'ai', op: 'hit' } as unknown as OkoAction)).toThrow();
  });

  it('a natural is decided right at the deal', () => {
    const r = new OkoRules();
    let found = false;
    for (let seed = 1; seed < 2000 && !found; seed++) {
      const s = r.init(cfg, seed);
      if (s.round === 2 && s.last.outcome === 'win') {
        expect(isNatural(s.last.player)).toBe(true);
        expect(isNatural(s.last.dealer)).toBe(false);
        expect(s.playerWins).toBe(1);
        found = true;
      }
    }
    expect(found).toBe(true);
  });

  it('busting loses the round at once, the banker does not draw', () => {
    const r = new OkoRules();
    const s = r.apply(table(r, [card(K), v(6)], [v(7), v(9)], [v(9, 1)]), HIT);
    expect(s.dealerWins).toBe(1);
    expect(s.round).toBe(2);
    expect(s.last).toEqual({ player: [card(K), v(6), v(9, 1)], dealer: [v(7), v(9)], outcome: 'lose' });
  });

  it('hitting to 21 stands automatically', () => {
    const r = new OkoRules();
    const s = r.apply(table(r, [v(5), v(6)], [card(TEN), v(7)], [card(K)]), HIT);
    expect(s.last.outcome).toBe('win');
    expect(s.last.dealer).toEqual([card(TEN), v(7)]);
  });

  it('the banker draws on soft 16 and stands on soft 17', () => {
    const r = new OkoRules();
    const a = r.apply(table(r, [card(K), v(8)], [card(A), v(5)], [card(A, 1), v(9)]), STAND);
    expect(a.last.dealer).toEqual([card(A), v(5), card(A, 1)]);
    expect(a.last.outcome).toBe('win');
    const b = r.apply(table(r, [card(K), v(7)], [card(A), v(6)], [v(2)]), STAND);
    expect(b.last.dealer).toEqual([card(A), v(6)]);
    expect(b.last.outcome).toBe('push');
    expect([b.playerWins, b.dealerWins]).toEqual([0, 0]);
  });

  it('banker bust wins, the higher total wins', () => {
    const r = new OkoRules();
    expect(r.apply(table(r, [v(10), v(2)], [v(10, 1), v(6)], [card(K)]), STAND).last.outcome).toBe('win');
    expect(r.apply(table(r, [v(10), v(2)], [v(10, 1), v(8)]), STAND).last.outcome).toBe('lose');
  });

  it('the game ends at rounds_to_win with the hands kept; stars like Sirky', () => {
    const r = new OkoRules();
    const s = r.apply({ ...table(r, [card(K), v(8)], [v(10, 1), v(7)]), playerWins: 4, dealerWins: 3 }, STAND);
    expect(s).toMatchObject({ over: true, phase: 'over', playerWins: 5, player: [card(K), v(8)] });
    expect(r.legalActions(s)).toEqual([]);
    expect(r.result(s)).toEqual({ winner: 'player', stars: 2, score: 500, playerWins: 5, dealerWins: 3 });
    const base = r.init(cfg, 1);
    const stars = (d: number, p = 5) => r.result({ ...base, over: true, phase: 'over', playerWins: p, dealerWins: d })!.stars;
    expect([stars(0), stars(2), stars(3), stars(4), stars(5, 2)]).toEqual([3, 3, 2, 1, 0]);
  });

  it('timeout ends the game; a tie is a draw', () => {
    const r = new OkoRules();
    const s = r.apply({ ...r.init(cfg, 3), playerWins: 2, dealerWins: 2 }, { by: 'timeout' });
    expect(s).toMatchObject({ over: true, phase: 'over' });
    expect(r.result(s)).toMatchObject({ winner: 'draw', stars: 0, score: 200 });
  });

  it('a whole game terminates and replays to the same states', () => {
    const r = new OkoRules();
    let s = r.init(cfg, 99);
    const steps: Array<{ action: Record<string, unknown> }> = [];
    while (!s.over && steps.length < 500) {
      const a = handTotal(s.player) < 17 ? HIT : STAND;
      steps.push({ action: a as Record<string, unknown> });
      s = r.apply(s, a);
    }
    expect(s.over).toBe(true);
    expect(Math.max(s.playerWins, s.dealerWins)).toBe(5);
    const again = replay(new OkoRules() as never, { config: cfg as never, seed: 99, steps });
    expect(again.states.at(-1)).toEqual(s);
    expect(again.result).toEqual(r.result(s));
  });
});
