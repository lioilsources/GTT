import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_kulicky/mg_kulicky.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const cfg = {
  'rounds': 5,
  'holeR': 25,
  'holePoints': 3,
  'closerPoints': 1,
  'scatter': [30, 40, 50, 60, 70],
  'aiScatter': [110, 90, 70, 55, 40],
  'starMargins': [6, 3, 1],
};

/// No scatter: every shot lands where it was aimed.
final Map<String, Object?> exact = {
  ...cfg,
  'scatter': [0],
  'aiScatter': [0],
};

void main() {
  test('starts at round 1 with the player to shoot', () {
    final s = KulickyRules().init(cfg, 42);
    expect(s.toJson(), {
      'round': 1,
      'turn': 'player',
      'playerPts': 0,
      'aiPts': 0,
      'playerShot': {'x': 0, 'y': 0, 'inHole': false},
      'aiShot': {'x': 0, 'y': 0, 'inHole': false},
      'over': false,
      'rng': Prng(42).state,
    });
  });

  test('scatter draws x then y, hole boundary', () {
    final r = KulickyRules();
    final s = r.apply(r.init(cfg, 7), const KulickyAction(10, 20, 2));
    final p = Prng(7);
    final x = 10 + p.nextInt(81) - 40, y = 20 + p.nextInt(81) - 40;
    expect(
      [s.playerShot.x, s.playerShot.y, s.playerShot.inHole, s.rng, s.turn],
      [x, y, x * x + y * y <= 625, p.state, 'ai'],
    );
    final e = KulickyRules();
    expect(e.apply(e.init(exact, 1), const KulickyAction(15, 20, 1)).playerShot.inHole, isTrue);
    expect(e.apply(e.init(exact, 1), const KulickyAction(15, 21, 1)).playerShot.inHole, isFalse);
  });

  test('hole points, closer point, equal distance', () {
    final r = KulickyRules();
    KulickyState round(int px, int py, int ax, int ay) {
      final s = r.apply(r.init(exact, 1), KulickyAction(px, py, 1));
      return r.apply(s, KulickyAction(ax, ay, 1, by: 'ai'));
    }

    expect([round(0, 0, 0, 0).playerPts, round(0, 0, 0, 0).aiPts], [3, 3]);
    expect([round(0, 0, 100, 0).playerPts, round(0, 0, 100, 0).aiPts], [3, 0]);
    expect([round(40, 0, 50, 0).playerPts, round(40, 0, 50, 0).aiPts], [1, 0]);
    expect([round(60, 0, 0, -50).playerPts, round(60, 0, 0, -50).aiPts], [0, 1]);
    expect([round(30, 40, 50, 0).playerPts, round(30, 40, 50, 0).aiPts], [0, 0]);
    final s = round(40, 0, 50, 0);
    expect([s.round, s.turn, s.over], [2, 'player', false]);
  });

  test('turn order, level range, game over after the last round', () {
    final r = KulickyRules();
    var s = r.init(exact, 3);
    expect(() => r.apply(s, const KulickyAction(0, 0, 1, by: 'ai')), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const KulickyAction(0, 0, 2)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const KulickyAction(0, 0, 0)), throwsA(isA<IllegalAction>()));
    for (var i = 0; i < 5; i++) {
      s = r.apply(s, const KulickyAction(0, 0, 1));
      expect(() => r.apply(s, const KulickyAction(0, 0, 1)), throwsA(isA<IllegalAction>()));
      expect(r.result(s), isNull);
      s = r.apply(s, r.aiAction(s, 1, aiPrng(3)));
    }
    expect([s.over, s.round, s.playerPts, s.aiPts], [true, 6, 15, 15]);
    expect(() => r.apply(s, const KulickyAction.timeout()), throwsA(isA<IllegalAction>()));
  });

  test('stars by the lead, winner by its sign, timeout', () {
    final r = KulickyRules();
    final b = r.init(cfg, 1).copyWith(over: true);
    KulickyState at(int p, int a) => b.copyWith(playerPts: p, aiPts: a);
    expect([at(9, 3), at(8, 3), at(6, 3), at(4, 3), at(3, 3), at(2, 3)].map((s) => r.result(s)!.stars), [
      3,
      2,
      2,
      1,
      0,
      0,
    ]);
    expect([at(4, 3), at(3, 3), at(2, 3)].map((s) => r.result(s)!.winner), ['player', 'draw', 'ai']);
    expect(r.result(at(4, 3))!.toJson(), {'winner': 'player', 'stars': 1, 'score': 4, 'playerPts': 4, 'aiPts': 3});
    final s = r.apply(r.apply(r.init(cfg, 5), const KulickyAction(0, 0, 1)), const KulickyAction.timeout());
    expect([s.over, s.round, s.playerPts, r.result(s)!.winner], [true, 1, 0, 'draw']);
  });

  final vectors = File('$repoRoot/vectors/kulicky.json').existsSync();
  test(
    'vectors/kulicky.json',
    () => expect(checkVectors(KulickyRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/kulicky.json') ? 'pending in parity.yaml' : false,
  );
}
