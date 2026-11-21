import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_oko/mg_oko.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const cfg = {'roundsToWin': 5, 'dealerStand': 17};

// card(rank, suit): rank 0 = 2 … 8 = 10, 9 J, 10 Q, 11 K, 12 A; v(n) = pip card of value n.
int card(int rank, [int suit = 0]) => suit * 13 + rank;
int v(int n, [int suit = 0]) => card(n - 2, suit);
const ace = 12, king = 11;

/// A fresh state with the given hands and the rest of the deck on top.
OkoState table(OkoRules r, List<int> player, List<int> dealer, [List<int> top = const []]) {
  final used = {...player, ...dealer, ...top};
  return r
      .init(cfg, 7)
      .copyWith(
        playerWins: 0,
        dealerWins: 0,
        round: 1,
        phase: 'play',
        player: player,
        dealer: dealer,
        deck: [
          ...top,
          for (var i = 0; i < 52; i++)
            if (!used.contains(i)) i,
        ],
      );
}

void main() {
  test('aces count 11, then 1, repeatedly', () {
    expect(handTotal([card(ace), card(ace, 1), v(9)]), 21);
    expect(handTotal([card(ace), card(ace, 1)]), 12);
    expect(handTotal([card(ace), v(5)]), 16);
    expect(handTotal([card(ace), v(5), v(10)]), 16);
    expect(isNatural([card(ace), card(king)]), isTrue);
  });

  test('deals from a full shuffled deck and offers hit / stand', () {
    final r = OkoRules();
    final s = r.init(cfg, 42);
    expect({...s.player, ...s.dealer, ...s.deck}.length, 52);
    if (s.round == 1) expect(r.legalActions(s), [OkoAction.hit, OkoAction.stand]);
    expect(() => r.apply(s, const OkoAction('ai', 'hit')), throwsA(isA<IllegalAction>()));
  });

  test('a natural is decided at the deal', () {
    final r = OkoRules();
    var found = false;
    for (var seed = 1; seed < 2000 && !found; seed++) {
      final s = r.init(cfg, seed);
      if (s.round == 2 && s.last.outcome == 'win') {
        expect(isNatural(s.last.player), isTrue);
        expect(s.playerWins, 1);
        found = true;
      }
    }
    expect(found, isTrue);
  });

  test('bust loses at once; hitting to 21 stands', () {
    final r = OkoRules();
    final a = r.apply(table(r, [card(king), v(6)], [v(7), v(9)], [v(9, 1)]), OkoAction.hit);
    expect(a.last.toJson(), {
      'player': [card(king), v(6), v(9, 1)],
      'dealer': [v(7), v(9)],
      'outcome': 'lose',
    });
    expect(a.dealerWins, 1);
    final b = r.apply(table(r, [v(5), v(6)], [v(10), v(7)], [card(king)]), OkoAction.hit);
    expect(b.last.outcome, 'win');
    expect(b.last.dealer, [v(10), v(7)]);
  });

  test('banker draws on soft 16, stands on soft 17', () {
    final r = OkoRules();
    final a = r.apply(table(r, [card(king), v(8)], [card(ace), v(5)], [card(ace, 1), v(9)]), OkoAction.stand);
    expect(a.last.dealer, [card(ace), v(5), card(ace, 1)]);
    expect(a.last.outcome, 'win');
    final b = r.apply(table(r, [card(king), v(7)], [card(ace), v(6)], [v(2)]), OkoAction.stand);
    expect(b.last.dealer, [card(ace), v(6)]);
    expect(b.last.outcome, 'push');
    expect([b.playerWins, b.dealerWins], [0, 0]);
  });

  test('stars and timeout draw', () {
    final r = OkoRules();
    final b = r.init(cfg, 1);
    int stars(int d, [int p = 5]) =>
        r.result(b.copyWith(over: true, phase: 'over', playerWins: p, dealerWins: d))!.stars;
    expect([stars(0), stars(2), stars(3), stars(4), stars(5, 2)], [3, 3, 2, 1, 0]);
    final t = r.apply(r.init(cfg, 3).copyWith(playerWins: 2, dealerWins: 2), const OkoAction.timeout());
    expect(r.result(t)!.toJson(), {'winner': 'draw', 'stars': 0, 'score': 200, 'playerWins': 2, 'dealerWins': 2});
  });

  test('a whole game terminates', () {
    final r = OkoRules();
    var s = r.init(cfg, 99);
    var n = 0;
    while (!s.over && n++ < 500) {
      s = r.apply(s, handTotal(s.player) < 17 ? OkoAction.hit : OkoAction.stand);
    }
    expect(s.over, isTrue);
    expect(s.playerWins == 5 || s.dealerWins == 5, isTrue);
  });

  final vectors = File('$repoRoot/vectors/oko.json').existsSync();
  test(
    'vectors/oko.json',
    () => expect(checkVectors(OkoRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/oko.json') ? 'pending in parity.yaml' : false,
  );
}
