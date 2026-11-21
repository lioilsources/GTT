import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_desetitisic/mg_desetitisic.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const cfg = {
  'target': 5000,
  'maxRounds': 10,
  'aiBankAt': [250, 300, 350, 400, 450],
  'aiErrorPct': [40, 25, 10, 5, 0],
  'starMargins': [1500, 500],
};

void main() {
  test('scoring uses the best decomposition (spec edge cases)', () {
    expect(scoreSelection([1]), 100);
    expect(scoreSelection([5]), 50);
    expect(scoreSelection([1, 1, 1]), 1000);
    expect(scoreSelection([1, 1, 1, 1]), 1100);
    expect(scoreSelection([2, 2, 2, 2, 2, 2]), 400);
    expect(scoreSelection([5, 5, 5, 5]), 550);
    expect(scoreSelection([6, 5, 4, 3, 2, 1]), 1500);
    expect(scoreSelection([]), isNull);
    expect(scoreSelection([1, 2]), isNull);
    expect(scoreSelection([2, 2, 2, 2]), isNull);
    expect(selections([2, 3, 4, 6, 6]), isEmpty);
    expect(selections([1, 2, 5]), [
      [0],
      [2],
      [0, 2],
    ]);
  });

  test('starts with the player rolling six dice', () {
    final r = DesetitisicRules();
    final s = r.init(cfg, 42);
    expect(s.toJson(), {
      'player': 0,
      'ai': 0,
      'turn': 'player',
      'phase': 'roll',
      'roll': <int>[],
      'dice': 6,
      'turnScore': 0,
      'round': 1,
      'lastBust': false,
      'over': false,
      'rng': 42,
    });
    expect(r.legalActions(s), [const DesetitisicAction.roll('player')]);
  });

  test('rejects illegal moves', () {
    final r = DesetitisicRules();
    final s = r.init(cfg, 1);
    expect(() => r.apply(s, const DesetitisicAction.roll('ai')), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const DesetitisicAction.bank('player')), throwsA(isA<IllegalAction>()));
    final k = s.copyWith(phase: 'keep', roll: [1, 2, 3, 3, 5, 6]);
    expect(() => r.apply(k, const DesetitisicAction.keep('player', [1])), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(k, const DesetitisicAction.keep('player', [4, 0])), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(k, const DesetitisicAction.keep('player', [])), throwsA(isA<IllegalAction>()));
  });

  test('keep, hot dice, bank and the round after the AI', () {
    final r = DesetitisicRules();
    var s = r.init(cfg, 1).copyWith(phase: 'keep', roll: [1, 5], dice: 2, turnScore: 300);
    s = r.apply(s, const DesetitisicAction.keep('player', [0, 1]));
    expect([s.turnScore, s.dice, s.phase], [450, 6, 'decide']);
    s = r.apply(s, const DesetitisicAction.bank('player'));
    expect([s.player, s.turn, s.phase, s.turnScore, s.round], [450, 'ai', 'roll', 0, 1]);
    s = r.apply(s.copyWith(phase: 'decide', turnScore: 300), const DesetitisicAction.bank('ai'));
    expect([s.ai, s.turn, s.round, s.over], [300, 'player', 2, false]);
  });

  test('target and max rounds end the game; stars by lead', () {
    final r = DesetitisicRules();
    final b = r.init(cfg, 1);
    final t = r.apply(
      b.copyWith(player: 4800, phase: 'decide', turnScore: 200),
      const DesetitisicAction.bank('player'),
    );
    expect([t.over, t.phase], [true, 'over']);
    expect(r.result(t)!.toJson(), {'winner': 'player', 'stars': 3, 'score': 5000, 'player': 5000, 'ai': 0});
    final m = r.apply(
      b.copyWith(round: 10, turn: 'ai', phase: 'decide', turnScore: 100, player: 900, ai: 700),
      const DesetitisicAction.bank('ai'),
    );
    expect([m.round, m.over, r.result(m)!.stars], [11, true, 1]);
    int stars(int p, int a) => r.result(b.copyWith(over: true, phase: 'over', player: p, ai: a))!.stars;
    expect([stars(3000, 1500), stars(3000, 2500), stars(3000, 2550), stars(2000, 2500)], [3, 2, 1, 0]);
  });

  test('AI bank rule', () {
    final r = DesetitisicRules();
    final ai = aiPrng(1);
    String d(int score, int dice, [int total = 0]) => r
        .aiAction(r.init(cfg, 1).copyWith(turn: 'ai', phase: 'decide', turnScore: score, dice: dice, ai: total), 3, ai)
        .op;
    expect(
      [d(350, 3), d(300, 3), d(200, 2), d(150, 1), d(1500, 6), d(1500, 6, 3600)],
      ['bank', 'roll', 'bank', 'roll', 'roll', 'bank'],
    );
  });

  final vectors = File('$repoRoot/vectors/desetitisic.json').existsSync();
  test(
    'vectors/desetitisic.json',
    () => expect(checkVectors(DesetitisicRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/desetitisic.json') ? 'pending in parity.yaml' : false,
  );
}
