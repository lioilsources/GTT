import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_sipky/mg_sipky.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const cfg = {
  'start': 301,
  'maxRounds': 15,
  'playerScatter': 60,
  'aiScatter': [420, 300, 210, 150, 100],
  'starDarts': [18, 27],
};
const exact = {
  'start': 301,
  'maxRounds': 15,
  'playerScatter': 0,
  'aiScatter': [0, 0, 0, 0, 0],
  'starDarts': [18, 27],
};

void main() {
  test('board scoring and clockwise boundaries', () {
    int p(int x, int y) => sipkyScoreAt(x, y).points;
    expect(sipkyScoreAt(0, 0), (points: 50, mult: 2));
    expect(sipkyScoreAt(65, 0), (points: 25, mult: 1));
    expect(sipkyScoreAt(0, 1030), (points: 60, mult: 3));
    expect(sipkyScoreAt(0, 1660), (points: 40, mult: 2));
    expect(sipkyScoreAt(0, 1700), (points: 0, mult: 0));
    expect([p(0, 574), p(0, 989), p(0, 1070), p(160, 0)], [20, 20, 20, 6]);
    expect([p(500, 500), p(500, -500), p(-500, -500), p(-500, 500)], [4, 2, 16, 12]);
    expect([p(95, 600), p(96, 600), p(-95, 600), p(-96, 600)], [20, 1, 20, 5]);
  });

  test('AI targets', () {
    expect(
      [
        for (final z in [50, 20, 40, 57, 60, 61, 301, 25]) sipkyAiTarget(z),
      ],
      [(0, 0), (0, 574), (0, 1660), (-318, -980), (0, 1030), (0, 1030), (0, 1030), (-177, 546)],
    );
  });

  test('bust restores the turn start; exact finish wins', () {
    final r = SipkyRules();
    var s = r.init(exact, 3).copyWith(player: 70, turnStart: 70);
    s = r.apply(s, const SipkyAction.player(0, 574));
    expect(s.player, 50);
    s = r.apply(s, const SipkyAction.player(0, 1030));
    expect([s.player, s.turn, s.dart, s.playerDarts], [70, 'ai', 0, 2]);
    expect(() => r.apply(s, const SipkyAction.player(0, 0)), throwsA(isA<IllegalAction>()));
    final w = r.apply(
      r.init(exact, 3).copyWith(player: 40, turnStart: 40, playerDarts: 17, dart: 2),
      const SipkyAction.player(0, 1660),
    );
    expect(r.resultToJson(r.result(w)!), {
      'winner': 'player',
      'stars': 3,
      'score': 301,
      'player': 0,
      'ai': 301,
      'playerDarts': 18,
    });
  });

  test('max rounds ends the game', () {
    final r = SipkyRules();
    var s = r.init({...exact, 'maxRounds': 1}, 5);
    for (var i = 0; i < 3; i++) {
      s = r.apply(s, const SipkyAction.player(3000, 0));
    }
    for (var i = 0; i < 3; i++) {
      s = r.apply(s, r.aiAction(s, 5, aiPrng(5)));
    }
    expect([s.round, s.over, s.ai], [2, true, 121]);
    expect(r.result(s)!.winner, 'ai');
  });

  final vectors = File('$repoRoot/vectors/sipky.json').existsSync();
  test(
    'vectors/sipky.json',
    () => expect(checkVectors(SipkyRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/sipky.json') ? 'pending in parity.yaml' : false,
  );
}
