import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_nohejbal/mg_nohejbal.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const cfg = {
  'halfWidth': 450,
  'depth': 900,
  'winPoints': 10,
  'winBy': 2,
  'maxPoints': 15,
  'scatter': [40, 55, 70, 85, 100],
  'aiScatter': [160, 130, 100, 80, 60],
  'aiReach': [380, 420, 460, 500, 540],
  'playerReach': 380,
  'aiMargin': [220, 180, 140, 110, 80],
  'starMargins': [6, 3, 1],
};

/// No scatter: every ball lands where it was aimed.
final Map<String, Object?> exact = {
  ...cfg,
  'scatter': [0],
  'aiScatter': [0],
};

void main() {
  final c = NohejbalConfig.fromJson(cfg);

  test('starts with the player serving', () {
    final s = NohejbalRules().init(cfg, 42);
    expect(s.toJson(), {
      'playerPts': 0,
      'aiPts': 0,
      'turn': 'player',
      'server': 'player',
      'rally': 0,
      'lastShot': {'by': '', 'x': 0, 'y': 0, 'in': false, 'reached': false},
      'over': false,
      'rng': Prng(42).state,
    });
  });

  test('scatter draws x then y', () {
    final r = NohejbalRules();
    final s = r.apply(r.init(cfg, 7), const NohejbalAction(10, 300, 2));
    final p = Prng(7);
    final x = 10 + p.nextInt(111) - 55, y = 300 + p.nextInt(111) - 55;
    expect([s.lastShot.x, s.lastShot.y, s.lastShot.inCourt, s.rng], [x, y, true, p.state]);
  });

  test('out, out of reach, returned; server and rally', () {
    final r = NohejbalRules();
    final s0 = r.init(exact, 1);
    final out = r.apply(s0, const NohejbalAction(451, 450, 1));
    expect([out.aiPts, out.server, out.turn, out.rally, out.lastShot.inCourt], [1, 'ai', 'ai', 0, false]);
    expect(r.apply(s0, const NohejbalAction(0, -1, 1)).aiPts, 1);
    expect(r.apply(s0, const NohejbalAction(0, 901, 1)).aiPts, 1);
    final ace = r.apply(s0, const NohejbalAction(450, 900, 1));
    expect([ace.playerPts, ace.server, ace.lastShot.inCourt, ace.lastShot.reached], [1, 'player', true, false]);
    // Reach boundary: 380 from the centre (0, 450) for level 1.
    final back = r.apply(s0, const NohejbalAction(0, 830, 1));
    expect([back.turn, back.rally, back.lastShot.reached, back.playerPts + back.aiPts], ['ai', 1, true, 0]);
    expect(r.apply(s0, const NohejbalAction(0, 831, 1)).playerPts, 1);
    final ret = r.apply(back, const NohejbalAction(100, 450, 1, by: 'ai'));
    expect([ret.turn, ret.rally, ret.lastShot.by, ret.lastShot.reached], ['player', 2, 'ai', true]);
    final miss = r.apply(back, const NohejbalAction(-400, 100, 1, by: 'ai'));
    expect([miss.aiPts, miss.server, miss.turn, miss.rally], [1, 'ai', 'ai', 0]);
  });

  test('end: win by two, max points', () {
    expect(
      [nohejbalOver(c, 10, 8), nohejbalOver(c, 10, 9), nohejbalOver(c, 12, 10), nohejbalOver(c, 9, 11)],
      [true, false, true, true],
    );
    expect([nohejbalOver(c, 15, 14), nohejbalOver(c, 14, 15), nohejbalOver(c, 14, 13)], [true, true, false]);
    final r = NohejbalRules();
    var s = r.init(exact, 1);
    for (var i = 0; i < 10; i++) {
      s = r.apply(s, const NohejbalAction(450, 900, 1));
    }
    expect([s.over, s.playerPts], [true, 10]);
    expect(r.result(s)!.toJson(), {'winner': 'player', 'stars': 3, 'score': 10, 'playerPts': 10, 'aiPts': 0});
    expect(() => r.apply(s, const NohejbalAction(0, 0, 1)), throwsA(isA<IllegalAction>()));
  });

  test('illegal actions', () {
    final r = NohejbalRules();
    final s = r.init(cfg, 1);
    expect(() => r.apply(s, const NohejbalAction(0, 0, 1, by: 'ai')), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const NohejbalAction(0, 0, 6)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const NohejbalAction(0, 0, 0)), throwsA(isA<IllegalAction>()));
  });

  test('ai aims at a corner with its own stream', () {
    final r = NohejbalRules();
    final s = r.init(cfg, 9);
    final ai = aiPrng(9), ref = aiPrng(9);
    for (var i = 0; i < 8; i++) {
      final a = r.aiAction(s, 2, ai);
      final k = ref.nextInt(4);
      expect([a.by, a.x, a.y, a.level], ['ai', k.isEven ? -270 : 270, k < 2 ? 180 : 720, 2]);
    }
    expect(s.rng, Prng(9).state);
  });

  test('stars and timeout', () {
    final r = NohejbalRules();
    final b = r.init(cfg, 1).copyWith(over: true);
    expect([6, 5, 3, 1, 0, -1].map((m) => r.result(b.copyWith(playerPts: 8 + m, aiPts: 8))!.stars), [3, 2, 2, 1, 0, 0]);
    final s = r.apply(r.init(cfg, 5), const NohejbalAction.timeout());
    expect([s.over, r.result(s)!.winner], [true, 'draw']);
    expect(r.result(b.copyWith(playerPts: 3, aiPts: 10))!.winner, 'ai');
  });

  final vectors = File('$repoRoot/vectors/nohejbal.json').existsSync();
  test(
    'vectors/nohejbal.json',
    () => expect(checkVectors(NohejbalRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/nohejbal.json') ? 'pending in parity.yaml' : false,
  );
}
