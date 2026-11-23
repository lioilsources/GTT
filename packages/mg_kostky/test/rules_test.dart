import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_kostky/mg_kostky.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const cfg = {
  'bonusAt': 63,
  'bonus': 35,
  'aiErrorPct': [40, 25, 12, 5, 0],
  'starMargins': [60, 20],
};

void main() {
  test('category values (spec table and edge cases)', () {
    expect(
      [
        for (var c = 0; c < 13; c++) catValue(c, [3, 3, 3, 5, 5]),
      ],
      [
        0, 0, 9, 0, 10, 0, 19, 0, 25, 0, 0, 0, 19, //
      ],
    );
    expect(
      [
        for (var c = 0; c < 13; c++) catValue(c, [6, 6, 6, 6, 6]),
      ],
      [
        0, 0, 0, 0, 0, 30, 30, 30, 0, 0, 0, 50, 30, //
      ],
    );
    expect(catValue(9, [1, 3, 4, 5, 6]), 30);
    expect(catValue(10, [1, 3, 4, 5, 6]), 0);
    expect(catValue(10, [6, 2, 3, 5, 4]), 40);
    expect(catValue(9, [6, 2, 3, 5, 4]), 30);
    final c = KostkyConfig.fromJson(cfg);
    expect(tableTotal([3, 6, 9, 12, 15, 18, -1, -1, -1, -1, -1, -1, 5], c), 63 + 35 + 5);
    expect(tableTotal([3, 6, 9, 12, 15, 17, ...List.filled(7, -1)], c), 62);
  });

  test('legal actions by roll count', () {
    final r = KostkyRules();
    final s = r.init(cfg, 1);
    expect(r.legalActions(s), [const KostkyAction.roll('player', [])]);
    final one = r.apply(s, const KostkyAction.roll('player', []));
    final l = r.legalActions(one);
    expect(l.length, 31 + 13);
    expect(l[3], const KostkyAction.roll('player', [0, 1]));
    expect(l[31], const KostkyAction.score('player', 0));
    final three = one.copyWith(rolls: 3);
    expect(r.legalActions(three).length, 13);
  });

  test('rejects illegal moves', () {
    final r = KostkyRules();
    final s = r.init(cfg, 1);
    expect(() => r.apply(s, const KostkyAction.roll('player', [0])), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const KostkyAction.score('player', 0)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const KostkyAction.roll('ai', [])), throwsA(isA<IllegalAction>()));
    final one = r.apply(s, const KostkyAction.roll('player', []));
    expect(() => r.apply(one, const KostkyAction.roll('player', [0, 1, 2, 3, 4])), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(one, const KostkyAction.roll('player', [2, 1])), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(one, const KostkyAction.roll('player', [5])), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(one, const KostkyAction.score('player', 13)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(one.copyWith(rolls: 3), const KostkyAction.roll('player', [])), throwsA(isA<IllegalAction>()));
  });

  test('held dice stay, scoring passes the turn and the last AI write ends the game', () {
    final r = KostkyRules();
    var s = r.init(cfg, 7);
    s = r.apply(s, const KostkyAction.roll('player', []));
    final first = s.dice;
    s = r.apply(s, const KostkyAction.roll('player', [0, 2]));
    expect([s.dice[0], s.dice[2], s.rolls], [first[0], first[2], 2]);
    s = r.apply(s, const KostkyAction.score('player', 12));
    expect([s.turn, s.rolls, s.dice, s.round], ['ai', 0, <int>[], 1]);
    final last = s.copyWith(ai: [...List.filled(12, 0), -1], dice: [1, 2, 3, 4, 6], rolls: 1);
    final end = r.apply(last, const KostkyAction.score('ai', 12));
    expect([end.over, end.round, end.turn, end.dice, end.rolls], [true, 2, 'player', <int>[], 0]);
  });

  test('AI keeps the most frequent value, a run at level 3+, and scores combos', () {
    final r = KostkyRules();
    final free = List.filled(13, -1);
    expect(r.aiKeep([2, 5, 2, 5, 1], free, 5), [1, 3]);
    expect(r.aiKeep([4, 4, 1, 4, 6], free, 1), [0, 1, 3]);
    expect(r.aiKeep([2, 3, 4, 4, 6], free, 3), [0, 1, 2]);
    expect(r.aiKeep([2, 3, 4, 4, 6], free, 2), [2, 3]);
    expect(r.aiKeep([1, 2, 3, 5, 6], free, 3), [0, 1, 2]);
    final s = r.init(cfg, 1).copyWith(turn: 'ai', rolls: 1, dice: [3, 3, 5, 5, 5]);
    expect(r.aiAction(s, 5, aiPrng(1)), const KostkyAction.score('ai', 8));
    final t = r.aiAction(s.copyWith(rolls: 3, dice: [1, 1, 2, 2, 6]), 5, aiPrng(1));
    expect(t, const KostkyAction.score('ai', 12));
  });

  final vectors = File('$repoRoot/vectors/kostky.json').existsSync();
  test(
    'vectors/kostky.json',
    () => expect(checkVectors(KostkyRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/kostky.json') ? 'pending in parity.yaml' : false,
  );
}
