import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_prase/mg_prase.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const cfg = {
  'target': 100,
  'maxRounds': 15,
  'aiHoldAt': [10, 15, 18, 20, 20],
  'aiErrorPct': [35, 20, 10, 5, 0],
  'starMargins': [40, 15],
};

void main() {
  test('starts 0 : 0 with the player rolling', () {
    final r = PraseRules();
    final s = r.init(cfg, 42);
    expect(s.toJson(), {
      'player': 0,
      'ai': 0,
      'turn': 'player',
      'turnScore': 0,
      'die': 0,
      'bust': false,
      'round': 1,
      'over': false,
      'rng': 42,
    });
    expect(r.legalActions(s), [const PraseAction.roll('player')]);
    expect(r.legalActions(s.copyWith(turnScore: 3)), [
      const PraseAction.roll('player'),
      const PraseAction.hold('player'),
    ]);
  });

  test('rejects illegal moves', () {
    final r = PraseRules();
    final s = r.init(cfg, 1);
    expect(() => r.apply(s, const PraseAction.roll('ai')), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const PraseAction.hold('player')), throwsA(isA<IllegalAction>()));
    final over = r.apply(s, const PraseAction.timeout());
    expect(() => r.apply(over, const PraseAction.roll('player')), throwsA(isA<IllegalAction>()));
  });

  test('hold passes the turn; the round counts after the AI and caps the game', () {
    final r = PraseRules();
    var s = r.init(cfg, 1).copyWith(turnScore: 12, die: 5);
    s = r.apply(s, const PraseAction.hold('player'));
    expect([s.player, s.turn, s.turnScore, s.round, s.die], [12, 'ai', 0, 1, 5]);
    s = r.apply(s.copyWith(turnScore: 7, round: 15), const PraseAction.hold('ai'));
    expect([s.ai, s.turn, s.round, s.over], [7, 'player', 16, true]);
    expect(r.result(s)!.toJson(), {'winner': 'player', 'stars': 1, 'score': 12, 'player': 12, 'ai': 7});
  });

  test('reaching the target keeps turn, round, die and bust', () {
    final r = PraseRules();
    final s = r.apply(
      r.init(cfg, 1).copyWith(player: 90, turnScore: 10, die: 6, round: 4),
      const PraseAction.hold('player'),
    );
    expect([s.player, s.turnScore, s.turn, s.round, s.die, s.over], [100, 0, 'player', 4, 6, true]);
  });

  test('a one busts the turn and stays shown', () {
    final r = PraseRules();
    var s = r.init(cfg, 1);
    for (var i = 0; i < 200 && !s.bust; i++) {
      s = r.apply(s.copyWith(turn: 'player', turnScore: 0), const PraseAction.roll('player'));
    }
    expect([s.die, s.bust, s.turnScore, s.turn], [1, true, 0, 'ai']);
  });

  test('AI order: target, last round, chase, holdAt', () {
    final r = PraseRules();
    final b = r.init(cfg, 1).copyWith(turn: 'ai');
    String d(int level, {int t = 0, int ai = 0, int player = 0, int round = 1}) =>
        r.aiAction(b.copyWith(turnScore: t, ai: ai, player: player, round: round), level, aiPrng(9)).op;
    expect(d(5), 'roll');
    expect(d(5, t: 5, ai: 95), 'hold');
    expect(d(5, t: 5, ai: 30, player: 30, round: 15), 'hold');
    expect(d(5, t: 25, ai: 30, player: 60, round: 15), 'roll');
    expect(d(5, t: 25, player: 85), 'roll');
    expect(d(5, t: 20), 'hold');
    expect(d(5, t: 19), 'roll');
  });

  final vectors = File('$repoRoot/vectors/prase.json').existsSync();
  test(
    'vectors/prase.json',
    () => expect(checkVectors(PraseRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/prase.json') ? 'pending in parity.yaml' : false,
  );
}
