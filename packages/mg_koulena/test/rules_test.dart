import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_koulena/mg_koulena.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const cfg = {
  'series': 3,
  'balls': 9,
  'ringR': [80, 160, 240, 320, 400],
  'ringPoints': [50, 40, 30, 20, 10],
  'pockets': [-300, 360, 300, 360],
  'pocketR': 50,
  'pocketPoints': 100,
  'scatter': [40, 55, 70, 85, 100],
  'starScores': [700, 520, 360],
};

void main() {
  final c = KoulenaConfig.fromJson(cfg);

  test('starts at series 1, ball 0', () {
    final s = KoulenaRules().init(cfg, 42);
    expect(s.toJson(), {
      'series': 1,
      'ball': 0,
      'score': 0,
      'seriesScores': <int>[],
      'lastHit': {'x': 0, 'y': 0, 'points': 0},
      'over': false,
      'rng': Prng(42).state,
    });
  });

  test('ring boundaries and pocket priority', () {
    expect([koulenaPoints(c, 80, 0), koulenaPoints(c, 81, 0), koulenaPoints(c, 96, 128)], [50, 40, 40]);
    expect([koulenaPoints(c, -400, 0), koulenaPoints(c, 401, 0)], [10, 0]);
    expect([koulenaPoints(c, 350, 360), koulenaPoints(c, 351, 360), koulenaPoints(c, -300, 360)], [100, 0, 100]);
  });

  test('scatter draws x then y', () {
    final r = KoulenaRules();
    final s = r.apply(r.init(cfg, 7), const KoulenaAction(10, 20, 2));
    final p = Prng(7);
    final x = 10 + p.nextInt(111) - 55, y = 20 + p.nextInt(111) - 55;
    expect([s.lastHit.x, s.lastHit.y, s.rng], [x, y, p.state]);
  });

  test('series rollover, game over after 27 balls, illegal actions', () {
    final r = KoulenaRules();
    var s = r.init(cfg, 3);
    expect(() => r.apply(s, const KoulenaAction(0, 0, 6)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const KoulenaAction(0, 0, 1, by: 'ai')), throwsA(isA<IllegalAction>()));
    for (var i = 0; i < 9; i++) {
      s = r.apply(s, const KoulenaAction(0, 0, 1));
    }
    expect(s.series, 2);
    expect(s.ball, 0);
    expect(s.seriesScores, [s.score]);
    for (var i = 0; i < 18; i++) {
      s = r.apply(s, const KoulenaAction(0, 0, 1));
    }
    expect(s.over, isTrue);
    expect(s.seriesScores.fold(0, (a, b) => a + b), s.score);
    expect(() => r.apply(s, const KoulenaAction.timeout()), throwsA(isA<IllegalAction>()));
  });

  test('stars and timeout', () {
    final r = KoulenaRules();
    final b = r.init(cfg, 1).copyWith(over: true);
    expect([700, 699, 520, 360, 359].map((v) => r.result(b.copyWith(score: v))!.stars), [3, 2, 2, 1, 0]);
    expect(r.result(b.copyWith(score: 359))!.winner, 'ai');
    final s = r.apply(r.apply(r.init(cfg, 5), const KoulenaAction(0, 0, 5)), const KoulenaAction.timeout());
    expect([s.over, s.seriesScores.length, r.result(s)!.score], [true, 0, s.score]);
  });

  final vectors = File('$repoRoot/vectors/koulena.json').existsSync();
  test(
    'vectors/koulena.json',
    () => expect(checkVectors(KoulenaRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/koulena.json') ? 'pending in parity.yaml' : false,
  );
}
