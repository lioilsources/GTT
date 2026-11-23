import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_srdce/mg_srdce.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const cfg = {
  'target': 50,
  'maxDeals': 3,
  'aiErrorPct': [40, 25, 12, 5, 0],
  'starMargins': [15, 5],
};

void main() {
  test('deal: 13 cards each, the two of clubs leads', () {
    final r = SrdceRules();
    final s = r.init(cfg, 3);
    expect([for (final h in s.hands) h.length], [13, 13, 13, 13]);
    expect({for (final h in s.hands) ...h}.length, 52);
    for (final h in s.hands) {
      expect(h, [...h]..sort());
    }
    expect(s.hands[s.leader], contains(twoOfClubs));
    expect(
      [s.turn, s.deal, s.tricks, s.broken, s.scores],
      [
        s.leader,
        1,
        0,
        false,
        [0, 0, 0, 0],
      ],
    );
    expect(s.lastTrick.toJson(), {'cards': <int>[], 'leader': -1, 'winner': -1});
    expect(r.legalCards(s), [twoOfClubs]);
  });

  test('legal cards: hearts lead, follow suit, first-trick discards', () {
    final r = SrdceRules();
    final b = r.init(cfg, 1);
    SrdceState at(List<int> hand, List<int> trick, {int tricks = 1, bool broken = false}) =>
        b.copyWith(hands: [hand, const [], const [], const []], trick: trick, turn: 0, tricks: tricks, broken: broken);
    // Lead: hearts only once broken or when the hand has only hearts.
    expect(r.legalCards(at([0, 14, 15], const [])), [0]);
    expect(r.legalCards(at([0, 14, 15], const [], broken: true)), [0, 14, 15]);
    expect(r.legalCards(at([14, 15], const [])), [14, 15]);
    // Follow the led suit.
    expect(r.legalCards(at([0, 5, 14, 40], const [27])), [0, 5, 14, 40]);
    expect(r.legalCards(at([0, 5, 14, 40], const [3])), [0, 5]);
    // No clubs in the first trick: no hearts or queen of spades while a clean card exists.
    expect(r.legalCards(at([10, 14, 30], const [39], tricks: 0)), [30]);
    expect(r.legalCards(at([10, 14], const [39], tricks: 0)), [10, 14]);
  });

  test('rejects illegal moves', () {
    final r = SrdceRules();
    final s = r.init(cfg, 1);
    final by = s.turn == 0 ? 'player' : 'ai';
    final wrong = s.turn == 0 ? 'ai' : 'player';
    expect(() => r.apply(s, SrdceAction(wrong, twoOfClubs)), throwsA(isA<IllegalAction>()));
    final other = s.hands[s.turn].firstWhere((c) => c != twoOfClubs);
    expect(() => r.apply(s, SrdceAction(by, other)), throwsA(isA<IllegalAction>()));
  });

  test('trick winner takes the points; the moon gives the others 26', () {
    final r = SrdceRules();
    final b = r.init(cfg, 1);
    // Seat 1 leads hearts 5; seat 3 plays the queen of spades; seat 0 wins with the heart ace.
    var s = b.copyWith(
      hands: [
        [25],
        [16],
        [17],
        [10],
      ],
      trick: const [],
      leader: 1,
      turn: 1,
      tricks: 12,
      broken: true,
      taken: [10, 0, 0, 0],
    );
    s = r.apply(s, const SrdceAction('ai', 16));
    s = r.apply(s, const SrdceAction('ai', 17));
    s = r.apply(s, const SrdceAction('ai', 10));
    s = r.apply(s, const SrdceAction('player', 25));
    // 10 + three hearts + 13 = 26 → moon; deal 2 starts, lastTrick is kept.
    expect(s.scores, [0, 26, 26, 26]);
    expect([s.deal, s.tricks, s.over], [2, 0, false]);
    expect(s.lastTrick.toJson(), {
      'cards': [16, 17, 10, 25],
      'leader': 1,
      'winner': 0,
    });
  });

  test('the last deal ends the game; stars by the margin to the best AI', () {
    final r = SrdceRules();
    final b = r.init(cfg, 1);
    final s = r.apply(
      b.copyWith(
        hands: [
          [0],
          [1],
          [2],
          [3],
        ],
        trick: const [],
        leader: 0,
        turn: 0,
        tricks: 12,
        deal: 3,
        scores: [10, 30, 20, 40],
        taken: [0, 0, 0, 0],
      ),
      const SrdceAction('player', 0),
    );
    final end = r.apply(
      r.apply(r.apply(s, const SrdceAction('ai', 1)), const SrdceAction('ai', 2)),
      const SrdceAction('ai', 3),
    );
    expect(
      [end.over, end.deal, end.tricks, end.leader, end.turn, end.hands],
      [
        true,
        3,
        13,
        3,
        3,
        [<int>[], <int>[], <int>[], <int>[]],
      ],
    );
    expect(r.result(end)!.toJson(), {
      'winner': 'player',
      'stars': 2,
      'score': 90,
      'scores': [10, 30, 20, 40],
    });
  });

  test('AI values: duck under the winner, dump the queen when void', () {
    final r = SrdceRules();
    final b = r.init(cfg, 1);
    SrdceState at(List<int> hand, List<int> trick) =>
        b.copyWith(hands: [const [], hand, const [], const []], trick: trick, turn: 1, tricks: 3, broken: true);
    // Following spades under the king: the highest card below it.
    expect(r.aiAction(at([3, 9, 12], const [11]), 5, aiPrng(1)).card, 9);
    // Void in the led suit: the queen of spades first, then high hearts.
    expect(r.aiAction(at([10, 25, 40], const [27]), 5, aiPrng(1)).card, 10);
    expect(r.aiAction(at([25, 40], const [27]), 5, aiPrng(1)).card, 25);
    // Leading: the lowest rank, hearts count five lower.
    expect(r.aiAction(at([5, 14, 30], const []), 5, aiPrng(1)).card, 30);
  });

  final vectors = File('$repoRoot/vectors/srdce.json').existsSync();
  test(
    'vectors/srdce.json',
    () => expect(checkVectors(SrdceRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/srdce.json') ? 'pending in parity.yaml' : false,
  );
}
