import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_doubledutch/mg_doubledutch.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const cfg = {
  'level': 3,
  'beats': 60,
  'introBeats': 4,
  'startGapMs': [700, 640, 580, 520, 470],
  'minGapMs': [520, 470, 420, 380, 340],
  'speedupEvery': 8,
  'speedupMs': 20,
  'trickPct': [0, 10, 15, 20, 25],
  'perfectMs': 45,
  'goodMs': 90,
  'okMs': 140,
  'maxTrips': 3,
  'perfectPts': 100,
  'goodPts': 60,
  'okPts': 30,
  'trickMult': 2,
  'comboStep': 10,
  'maxMult': 4,
  'starPct': [85, 65, 40],
};

Map<String, Object?> withCfg(Map<String, Object?> o) => {...cfg, ...o};

void main() {
  test('chart: intro beats plain, one generator draws per later beat', () {
    final r = DoubledutchRules();
    final s = r.init(cfg, 11);
    final p = Prng(11);
    final kinds = [for (var i = 0; i < 60; i++) i < 4 ? 0 : (p.nextInt(100) < 15 ? 1 : 0)];
    expect([s.kinds, s.rng, s.next, s.over], [kinds, p.state, 0, false]);
    // Level 1 has no tricks but still draws.
    final s1 = r.init(withCfg({'level': 1}), 11);
    final p1 = Prng(11);
    for (var i = 4; i < 60; i++) {
      p1.nextInt(100);
    }
    expect([s1.kinds.every((k) => k == 0), s1.rng], [true, p1.state]);
  });

  test('gaps speed up to the minimum; beat times from the lead-in', () {
    final c = DoubledutchConfig.fromJson(cfg);
    expect([c.gap(1), c.gap(7), c.gap(8), c.gap(16), c.gap(59)], [580, 580, 560, 540, 440]);
    final fast = DoubledutchConfig.fromJson(withCfg({'level': 5}));
    expect(fast.gap(59), 340);
    final t = c.beatTimes(1500);
    expect([t[0], t[1], t[8]], [1500, 2080, 1500 + 7 * 580 + 560]);
  });

  test('windows, multiplier after the combo, trips end the game', () {
    final r = DoubledutchRules();
    var s = r.init(withCfg({'level': 1, 'comboStep': 2}), 1);
    s = r.apply(s, const DoubledutchAction.hit(0, 45));
    expect([s.score, s.perfect, s.combo], [100, 1, 1]);
    s = r.apply(s, const DoubledutchAction.hit(0, -90)); // combo 2 → mult 2
    expect([s.score, s.good, s.combo], [100 + 120, 1, 2]);
    s = r.apply(s, const DoubledutchAction.hit(0, 140));
    expect([s.score, s.ok], [220 + 60, 1]);
    s = r.apply(s, const DoubledutchAction.hit(0, 141));
    expect([s.score, s.trips, s.misses, s.combo, s.bestCombo, s.next], [280, 1, 1, 0, 3, 4]);
    s = r.apply(s, const DoubledutchAction.hit(1, 0)); // wrong input
    s = r.apply(s, const DoubledutchAction.miss());
    expect([s.trips, s.over], [3, true]);
    final res = r.result(s)!;
    expect(res.toJson()['winner'], 'ai');
    expect(() => r.apply(s, const DoubledutchAction.miss()), throwsA(isA<IllegalAction>()));
  });

  test('illegal input, missing errMs; timeout only ends; no ai', () {
    final r = DoubledutchRules();
    final s = r.init(cfg, 2);
    for (final j in [
      {'by': 'player', 'op': 'hit', 'input': 2, 'errMs': 0},
      {'by': 'player', 'op': 'hit', 'input': 0},
      {'by': 'player', 'op': 'hit', 'input': 0, 'errMs': 1.5},
      {'by': 'player', 'op': 'jump'},
      {'by': 'ai', 'op': 'miss'},
    ]) {
      expect(() => r.apply(s, r.actionFromJson(j)), throwsA(isA<IllegalAction>()), reason: '$j');
    }
    final t = r.apply(s, const DoubledutchAction.timeout());
    expect(
      [t.over, t.next, r.result(t)!.toJson()],
      [
        true,
        0,
        {'winner': 'ai', 'stars': 0, 'score': 0, 'pct': 0, 'bestCombo': 0, 'misses': 0},
      ],
    );
    expect(r.legalActions(t), isEmpty);
    expect(r.legalActions(s).map((a) => a.toJson()), [
      {'by': 'player', 'op': 'hit', 'input': s.kinds[0], 'errMs': 0},
      {'by': 'player', 'op': 'miss'},
    ]);
    expect(() => r.aiAction(s, 1, aiPrng(2)), throwsStateError);
  });

  test('all perfect is 100 % and three stars; pct floors', () {
    final r = DoubledutchRules();
    var s = r.init(cfg, 3);
    while (!s.over) {
      s = r.apply(s, DoubledutchAction.hit(s.kinds[s.next], 0));
    }
    final res = r.result(s)!;
    expect([res.pct, res.stars, res.score, res.bestCombo], [100, 3, r.config.maxScore(s.kinds), 60]);
    final half = r.result(s.copyWith(score: res.score ~/ 3))!;
    expect(half.pct, res.score ~/ 3 * 100 ~/ res.score);
  });

  test('inputErr: from ok_ms before the beat, floored', () {
    expect(inputErr([1000, 1600], 0, 859.9, 140), isNull);
    expect(inputErr([1000, 1600], 0, 860, 140), -140);
    expect(inputErr([1000, 1600], 1, 1650.7, 140), 50);
    expect(inputErr([1000], 1, 5000, 140), isNull);
  });

  final vectors = File('$repoRoot/vectors/doubledutch.json').existsSync();
  test(
    'vectors/doubledutch.json',
    () => expect(checkVectors(DoubledutchRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/doubledutch.json') ? 'pending in parity.yaml' : false,
  );
}
