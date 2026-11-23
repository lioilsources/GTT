import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_krtek/mg_krtek.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const cfg = {
  'level': 2,
  'holes': 4,
  'gameTicks': 40,
  'firstSpawn': 3,
  'spawnEvery': [6, 5, 4, 4, 3],
  'upTicks': [14, 12, 10, 9, 8],
  'goldPct': 20,
  'bombPct': [0, 10, 15, 20, 25],
  'points': 10,
  'goldPoints': 30,
  'bombPenalty': 20,
  'starScores': [100, 60, 30],
};

void main() {
  test('first mole on tick firstSpawn, it hides after upTicks and counts as a miss', () {
    final r = KrtekRules();
    var s = r.init(cfg, 5);
    s = r.apply(s, const KrtekAction.tick(2));
    expect(s.holes.every((h) => h.kind == ''), isTrue);
    s = r.apply(s, const KrtekAction.tick(1));
    final i = s.holes.indexWhere((h) => h.kind != '');
    expect([s.holes[i].left, s.nextSpawn, s.rng == Prng(5).state], [12, 5, false]);
    final kind = s.holes[i].kind;
    // 12 more ticks: the spawned one hides (others may spawn meanwhile).
    s = r.apply(s, const KrtekAction.tick(12));
    expect(s.misses, kind == 'bomb' ? 0 : greaterThanOrEqualTo(1));
  });

  test('hits score, bombs cost but never below zero, empty holes do nothing', () {
    final r = KrtekRules();
    final s = r.init(cfg, 1);
    KrtekState with_(String kind, int score) =>
        s.copyWith(holes: [MoleHole(kind, 5), ...s.holes.skip(1)], score: score);
    expect(r.apply(with_('mole', 0), const KrtekAction.hit(0)).toJson()['score'], 10);
    expect(r.apply(with_('gold', 0), const KrtekAction.hit(0)).hits, 1);
    final bomb = r.apply(with_('bomb', 5), const KrtekAction.hit(0));
    expect([bomb.score, bomb.hits, bomb.holes[0].kind, bomb.holes[0].left], [0, 0, '', 0]);
    expect(r.apply(s, const KrtekAction.hit(3)).toJson(), s.toJson());
    expect(() => r.apply(s, const KrtekAction.hit(4)), throwsA(isA<IllegalAction>()));
  });

  test('the clock ends the game and drops leftover ticks', () {
    final r = KrtekRules();
    final s = r.apply(r.init(cfg, 1), const KrtekAction.tick(1000));
    expect([s.tick, s.over], [40, true]);
  });

  final vectors = File('$repoRoot/vectors/krtek.json').existsSync();
  test(
    'vectors/krtek.json',
    () => expect(checkVectors(KrtekRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/krtek.json') ? 'pending in parity.yaml' : false,
  );
}
