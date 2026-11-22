import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_cara/mg_cara.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const cfg = {
  'rounds': 7,
  'linePoints': 3,
  'roundPoints': 1,
  'scatter': [20, 28, 36, 44, 52],
  'aiScatter': [90, 70, 55, 40, 28],
  'aiAim': [90, 70, 55, 40, 28],
  'starMargins': [5, 3, 1],
};

/// No scatter: every coin lands where it was aimed.
final Map<String, Object?> exact = {
  ...cfg,
  'scatter': [0],
  'aiScatter': [0],
};

void main() {
  test('starts at round 1 with the player to toss', () {
    final s = CaraRules().init(cfg, 42);
    expect(s.toJson(), {
      'round': 1,
      'turn': 'player',
      'playerPts': 0,
      'aiPts': 0,
      'playerCoin': {'y': 0, 'burnt': false},
      'aiCoin': {'y': 0, 'burnt': false},
      'over': false,
      'rng': Prng(42).state,
    });
  });

  test('scatter and burnt coin', () {
    final r = CaraRules();
    final s = r.apply(r.init(cfg, 7), const CaraAction(-30, 3));
    final p = Prng(7);
    final y = -30 + p.nextInt(73) - 36;
    expect([s.playerCoin.y, s.playerCoin.burnt, s.rng, s.turn], [y, y > 0, p.state, 'ai']);
    final e = CaraRules();
    expect(e.apply(e.init(exact, 1), const CaraAction(1, 1)).playerCoin.burnt, isTrue);
    expect(e.apply(e.init(exact, 1), const CaraAction(0, 1)).playerCoin.burnt, isFalse);
  });

  test('line coins, closer coin, burnt coins, ties', () {
    final r = CaraRules();
    List<int> round(int py, int ay) {
      final s = r.apply(r.apply(r.init(exact, 1), CaraAction(py, 1)), CaraAction(ay, 1, by: 'ai'));
      return [s.playerPts, s.aiPts];
    }

    expect(round(0, -10), [3, 0]);
    expect(round(-1, 0), [0, 3]);
    expect(round(0, 0), [3, 3]);
    // A coin on the line voids the closer-coin point even for a burnt rival coin.
    expect(round(0, 5), [3, 0]);
    expect(round(-5, -10), [1, 0]);
    expect(round(-12, -3), [0, 1]);
    expect(round(4, -50), [0, 1]);
    expect(round(-50, 4), [1, 0]);
    expect(round(4, 9), [0, 0]);
    expect(round(-7, -7), [0, 0]);
  });

  test('turn order, level range, game over after the last round, ai aim', () {
    final r = CaraRules();
    var s = r.init(exact, 3);
    expect(() => r.apply(s, const CaraAction(0, 1, by: 'ai')), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const CaraAction(0, 2)), throwsA(isA<IllegalAction>()));
    expect(r.aiAction(s, 1, aiPrng(3)).toJson(), {'by': 'ai', 'y': -90, 'level': 1});
    for (var i = 0; i < 7; i++) {
      s = r.apply(s, const CaraAction(-5, 1));
      expect(() => r.apply(s, const CaraAction(-5, 1)), throwsA(isA<IllegalAction>()));
      s = r.apply(s, r.aiAction(s, 1, aiPrng(3)));
    }
    expect([s.over, s.round, s.playerPts, s.aiPts], [true, 8, 7, 0]);
    expect(r.result(s)!.toJson(), {'winner': 'player', 'stars': 3, 'score': 7, 'playerPts': 7, 'aiPts': 0});
    expect(() => r.apply(s, const CaraAction.timeout()), throwsA(isA<IllegalAction>()));
  });

  test('stars and timeout', () {
    final r = CaraRules();
    final b = r.init(cfg, 1).copyWith(over: true);
    expect([5, 4, 3, 1, 0, -2].map((m) => r.result(b.copyWith(playerPts: 6 + m, aiPts: 6))!.stars), [3, 2, 2, 1, 0, 0]);
    expect(r.result(b.copyWith(playerPts: 1, aiPts: 3))!.winner, 'ai');
    final s = r.apply(r.init(cfg, 5), const CaraAction.timeout());
    expect([s.over, r.result(s)!.winner, r.result(s)!.stars], [true, 'draw', 0]);
  });

  final vectors = File('$repoRoot/vectors/cara.json').existsSync();
  test(
    'vectors/cara.json',
    () => expect(checkVectors(CaraRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/cara.json') ? 'pending in parity.yaml' : false,
  );
}
