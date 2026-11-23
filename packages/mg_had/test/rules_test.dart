import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_had/mg_had.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const cfg = {
  'level': 1,
  'w': 7,
  'h': 7,
  'startInterval': [3, 3, 2, 2, 2],
  'minInterval': [2, 2, 1, 1, 1],
  'speedupEvery': 2,
  'foodPoints': 10,
  'starScores': [30, 20, 10],
};

void main() {
  test('starts in the middle heading up with food placed', () {
    final r = HadRules();
    final s = r.init(cfg, 42);
    expect(s.toJson()['body'], [
      [3, 3],
      [3, 2],
      [3, 1],
    ]);
    expect([s.dir, s.next, s.t, s.interval], [0, 0, 0, 3]);
    expect(s.body.contains(s.food), isFalse);
    expect(s.rng, isNot(Prng(42).state));
  });

  test('reversal is ignored, the last turn wins, ticks move on the interval', () {
    final r = HadRules();
    var s = r.init(cfg, 1);
    expect(r.apply(s, const HadAction.turn(2)), same(s));
    s = r.apply(s, const HadAction.turn(1));
    s = r.apply(s, const HadAction.turn(3));
    expect(s.next, 3);
    s = r.apply(s, const HadAction.tick(2));
    expect([s.t, s.body.first], [2, (3, 3)]);
    s = r.apply(s, const HadAction.tick(1));
    expect([s.t, s.dir, s.body.first], [0, 3, (2, 3)]);
  });

  test('a wall ends the game without moving', () {
    final r = HadRules();
    var s = r.init(cfg, 1);
    s = r.apply(s, const HadAction.tick(100));
    expect(s.over, isTrue);
    expect(s.body.first, (3, 6));
    expect(() => r.apply(s, const HadAction.tick(1)), throwsA(isA<IllegalAction>()));
  });

  final vectors = File('$repoRoot/vectors/had.json').existsSync();
  test(
    'vectors/had.json',
    () => expect(checkVectors(HadRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/had.json') ? 'pending in parity.yaml' : false,
  );
}
