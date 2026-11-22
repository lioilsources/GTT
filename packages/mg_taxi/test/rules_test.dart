import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_taxi/mg_taxi.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  final tuning = Tuning.fromYaml(File('$repoRoot/content/tuning.yaml').readAsStringSync());
  final tt = tuning.minigames.taxi;
  final cfg = TaxiConfig.fromTuning(tt, ['a', 'b', 'c']);

  test('fare: meter, time bonus capped, late penalty capped, tip minus hits', () {
    final fast = taxiFare(cfg, 20000, 100000, 0);
    expect((fast.meter, fast.expectS), (46, 300));
    expect(fast.time, 46 * tt.bonusMaxPct ~/ 100);
    expect(fast.tip, 46 * tt.tipPct ~/ 100);
    final late = taxiFare(cfg, 20000, 310999, 2);
    expect((late.rideS, late.time), (310, -10));
    expect(late.tip, 46 * (tt.tipPct - 2 * tt.hitTipPct) ~/ 100);
    final crawl = taxiFare(cfg, 20000, 10000000, 99);
    expect(crawl.time, -(46 * tt.lateMaxPct ~/ 100));
    expect(crawl.tip, 0);
    expect(crawl.fare, greaterThanOrEqualTo(0));
  });

  test('stars from the fare thresholds', () {
    final s3 = tt.starFares[0], s2 = tt.starFares[1], s1 = tt.starFares[2];
    expect([0, s1 - 1, s1, s2, s3 - 1, s3, s3 * 2].map((f) => taxiStars(cfg, f)), [0, 0, 1, 2, 2, 3, 3]);
  });

  test('pickup picks an allowed destination, never the last one twice, dropoff pays', () {
    final r = TaxiRules();
    var s = r.start(cfg, 5);
    s = r.apply(s, const TaxiAction.pickup(0, ['b', 'c']));
    expect(['b', 'c'], contains(s.dest));
    expect(s.line, inInclusiveRange(0, tt.lines - 1));
    s = r.apply(s, const TaxiAction.dropoff(30000, 5000));
    expect(s.rides, 1);
    expect(s.fare, s.last.fare);
    for (var i = 0; i < 10; i++) {
      final prev = s.lastDest;
      s = r.apply(s, TaxiAction.pickup(s.clockMs, const ['b', 'c']));
      expect(s.dest, isNot(prev));
      s = r.apply(s, TaxiAction.dropoff(s.clockMs + 1000, 100));
    }
  });

  test('rejects illegal actions', () {
    final r = TaxiRules();
    final s = r.start(cfg, 1);
    expect(() => r.apply(s, const TaxiAction.dropoff(1, 1)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const TaxiAction.hit()), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const TaxiAction.pickup(0, ['nowhere'])), throwsA(isA<IllegalAction>()));
    final ride = r.apply(s, const TaxiAction.pickup(50, []));
    expect(() => r.apply(ride, const TaxiAction.dropoff(10, 1)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(ride, const TaxiAction.dropoff(60, -1)), throwsA(isA<IllegalAction>()));
    final over = r.apply(ride, const TaxiAction.timeout());
    expect(r.result(over)!.toJson(), {'winner': 'draw', 'stars': 0, 'score': 0, 'rides': 0});
    expect(() => r.apply(over, const TaxiAction.timeout()), throwsA(isA<IllegalAction>()));
    expect(r.result(s), isNull);
    expect(
      () => r.actionFromJson({'by': 'player', 'op': 'dropoff', 'atMs': 1.5, 'distDm': 1}),
      throwsA(isA<IllegalAction>()),
    );
  });

  // Ungated until parity.yaml marks F-027 done for Flutter: proves the port replays the web recording.
  test('vectors/taxi.json (ungated)', () => expect(checkVectors(TaxiRules()), isEmpty));
  test(
    'vectors/taxi.json',
    () => expect(checkVectors(TaxiRules()), isEmpty),
    skip: !flutterDone('vectors/taxi.json') ? 'pending in parity.yaml' : false,
  );
}
