import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_bowling/mg_bowling.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  final tuning = Tuning.fromYaml(File('$repoRoot/content/tuning.yaml').readAsStringSync());
  BowlingConfig cfg(int level) => BowlingConfig.fromTuning(tuning.minigames.bowling, level);

  test('ten-pin scoring with strikes, spares and missing future rolls', () {
    expect(bowlingTotal(List.filled(12, 10)), 300);
    expect(bowlingTotal(List.filled(21, 5)), 150);
    expect(bowlingTotal([10, 3, 4]), 17 + 7);
    expect(bowlingTotal([7, 3, 2]), 12 + 2);
    expect(bowlingTotal([10]), 10);
    expect(bowlingTotal(List.filled(20, 0)), 0);
  });

  test('pins stand in a triangle, head pin in the middle', () {
    final c = cfg(1);
    expect(c.pinSpot(0), (x: c.laneW ~/ 2, y: c.headY));
    expect(c.pinSpot(6), (x: c.laneW ~/ 2 - 3 * c.pinDx, y: c.headY + 3 * c.pinDy));
    expect(c.pinSpot(9), (x: c.laneW ~/ 2 + 3 * c.pinDx, y: c.headY + 3 * c.pinDy));
  });

  test('rejects rolls off the line, out of power range or after the end', () {
    final r = BowlingRules();
    final s = r.start(cfg(3), 5);
    final c = r.config;
    expect(() => r.apply(s, BowlingAction.roll(c.ballR - 1, 0, 50)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, BowlingAction.roll(c.laneW - c.ballR + 1, 0, 50)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, BowlingAction.roll(c.ballR, 0, 0)), throwsA(isA<IllegalAction>()));
    final over = r.apply(s, const BowlingAction.timeout());
    expect(over.toJson()..remove('over'), s.toJson()..remove('over'));
    expect(() => r.apply(over, BowlingAction.roll(c.ballR, 0, 50)), throwsA(isA<IllegalAction>()));
    expect(r.result(over)!.toJson(), {'winner': 'ai', 'stars': 0, 'score': 0, 'rolls': <int>[]});
  });

  test('a gutter ball knocks nothing and draws two scatter numbers', () {
    final r = BowlingRules();
    final s = r.start(cfg(1), 9);
    final c = r.config;
    final a = BowlingAction.roll(c.ballR, -2000000, 100);
    final n = r.apply(s, a);
    expect(
      [n.frame, n.roll, n.lastKnocked, n.rolls],
      [
        1,
        2,
        0,
        [0],
      ],
    );
    final p = Prng(s.rng)
      ..nextInt(2 * c.scatter[0] + 1)
      ..nextInt(2 * c.scatter[0] + 1);
    expect(n.rng, p.state);
  });

  final vectors = File('$repoRoot/vectors/bowling.json').existsSync();
  test(
    'vectors/bowling.json',
    () => expect(checkVectors(BowlingRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/bowling.json') ? 'pending in parity.yaml' : false,
  );
}
