import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_sirky/mg_sirky.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const cfg = {
  'start': 15,
  'minStart': 12,
  'maxStart': 25,
  'maxTake': 3,
  'roundsToWin': 5,
  'aiErrorPct': [60, 45, 30, 15, 0],
};

void main() {
  test('starts with the player and 15 matches', () {
    final r = SirkyRules();
    final s = r.init(cfg, 42);
    expect(s.left, 15);
    expect(s.turn, 'player');
    expect(r.legalActions(s).map((a) => a.take), [1, 2, 3]);
  });

  test('rejects illegal moves', () {
    final r = SirkyRules();
    final s = r.init(cfg, 1);
    expect(() => r.apply(s, const SirkyAction('ai', 1)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const SirkyAction('player', 4)), throwsA(isA<IllegalAction>()));
  });

  test('stars follow the opponent round count', () {
    final r = SirkyRules();
    final b = r.init(cfg, 1);
    int stars(int ai, [int player = 5]) => r.result(b.copyWith(over: true, player: player, ai: ai))!.stars;
    expect([stars(0), stars(2), stars(3), stars(4), stars(5, 2)], [3, 3, 2, 1, 0]);
  });

  final vectors = File('$repoRoot/vectors/sirky.json').existsSync();
  test(
    'vectors/sirky.json',
    () => expect(checkVectors(SirkyRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/sirky.json') ? 'pending in parity.yaml' : false,
  );
}
