import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_drift/mg_drift.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';
import 'package:shared_gen/shared_gen.dart';

const cfg = {
  'level': 3,
  'minSlipMrad': 250,
  'maxSlipMrad': 800,
  'minSpeedCms': 800,
  'maxSpeedCms': 2500,
  'ptsDiv': 1000,
  'maxDtMs': 250,
  'graceMs': 600,
  'multStepMs': 2000,
  'maxMult': 5,
  'starScores': [40000, 20000, 8000],
  'levelPct': [60, 80, 100, 120, 140],
};

void main() {
  final tuning = Tuning.fromYaml(File('$repoRoot/content/tuning.yaml').readAsStringSync());
  final td = tuning.minigames.drift;

  test('samples build a chain, banked after the grace time', () {
    final r = DriftRules();
    var s = r.init(cfg, 1);
    expect(s.toJson(), const DriftState().toJson());
    // First sample: dt = atMs, clipped to maxDtMs.
    s = r.apply(s, const DriftAction.sample(400, 900, 3000, true));
    expect(
      [s.chain, s.chainMs, s.mult, s.lastDriftMs, s.clockMs],
      [250 * 800 ~/ 1000 * 2500 ~/ 1000, 250, 1, 400, 400],
    );
    for (var t = 500; t <= 2400; t += 100) {
      s = r.apply(s, DriftAction.sample(t, 300, 1000, true));
    }
    expect([s.chainMs, s.mult], [2250, 2]);
    final chain = s.chain;
    s = r.apply(s, const DriftAction.sample(3000, 0, 0, true));
    expect([s.score, s.chain], [0, chain]);
    s = r.apply(s, const DriftAction.sample(3001, 0, 0, false));
    expect(
      [s.score, s.best, s.drifts, s.chain, s.chainMs, s.mult, s.lastDriftMs],
      [chain * 2, chain * 2, 1, 0, 0, 1, 2400],
    );
  });

  test('chain 0 is never banked; a hit drops the chain', () {
    final r = DriftRules();
    var s = r.init(cfg, 1);
    s = r.apply(s, const DriftAction.sample(100, 249, 3000, true));
    s = r.apply(s, const DriftAction.sample(5000, 0, 0, false));
    expect([s.drifts, s.score], [0, 0]);
    s = r.apply(s, const DriftAction.sample(5100, 800, 2500, true));
    expect(s.chain, 100 * 800 ~/ 1000 * 2500 ~/ 1000);
    s = r.apply(s, const DriftAction.hit(5150));
    expect([s.chain, s.chainMs, s.mult, s.hits, s.clockMs, s.lastDriftMs, s.drifts], [0, 0, 1, 1, 5150, 5100, 0]);
    s = r.apply(s, const DriftAction.timeout());
    expect(r.result(s)!.toJson(), {'winner': 'draw', 'stars': 0, 'score': 0, 'best': 0, 'drifts': 0, 'hits': 1});
  });

  test('timeout banks the open chain; star thresholds by level', () {
    final r = DriftRules();
    var s = r.init({...cfg, 'level': 1}, 1);
    s = r.apply(s, const DriftAction.sample(250, 800, 2500, true));
    s = r.apply(s, const DriftAction.timeout());
    expect([s.phase, s.score, s.drifts], ['over', 500, 1]);
    expect(r.config.thresholds, [24000, 12000, 4800]);
    final over = r.init(cfg, 1);
    expect([40000, 39999, 20000, 8000, 7999].map((x) => r.result(over.copyWith(phase: 'over', score: x))!.stars), [
      3,
      2,
      2,
      1,
      0,
    ]);
  });

  test('illegal actions', () {
    final r = DriftRules();
    final s = r.apply(r.init(cfg, 1), const DriftAction.sample(100, 0, 0, false));
    expect(() => r.apply(s, const DriftAction.sample(99, 0, 0, false)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const DriftAction.hit(50)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const DriftAction.sample(200, -1, 0, false)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const DriftAction.sample(200, 0, -1, false)), throwsA(isA<IllegalAction>()));
    expect(
      () => r.actionFromJson({'by': 'player', 'op': 'sample', 'atMs': 1, 'slipMrad': 1, 'speedCms': 1}),
      throwsA(isA<IllegalAction>()),
    );
    expect(() => r.actionFromJson({'by': 'player', 'op': 'hit', 'atMs': 1.5}), throwsA(isA<IllegalAction>()));
    expect(() => r.actionFromJson({'by': 'ai', 'op': 'hit', 'atMs': 1}), throwsA(isA<IllegalAction>()));
    expect(() => r.actionFromJson({'by': 'player', 'op': 'jump', 'atMs': 1}), throwsA(isA<IllegalAction>()));
    expect(r.legalActions(s).map((a) => a.toJson()), [
      {'by': 'player', 'op': 'sample', 'atMs': 100, 'slipMrad': 0, 'speedCms': 0, 'inZone': false},
      {'by': 'timeout'},
    ]);
    final over = r.apply(s, const DriftAction.timeout());
    expect(r.legalActions(over), isEmpty);
    expect(() => r.apply(over, const DriftAction.timeout()), throwsA(isA<IllegalAction>()));
    expect(() => r.aiAction(s, 1, Prng(1)), throwsUnsupportedError);
  });

  test('slip angle: |atan2(lateral, forward)|, 0 below 0.5 m/s, up to π reversing', () {
    DriftPose p(double h, double vx, double vy) => (x: 0, y: 0, heading: h, vx: vx, vy: vy, layer: 0);
    expect(slipMrad(p(0, 10, 0)), 0);
    expect(slipMrad(p(0, 10, 10)), 785);
    expect(slipMrad(p(math.pi / 2, 10, 10)), 785);
    expect(slipMrad(p(0, -10, 0.0001)), 3141);
    expect(slipMrad(p(0, 0.3, 0.3)), 0);
  });

  test('session: one sample per frame, hit before the sample, the end frame sends only timeout', () {
    final s = DriftSession(td, 3, 0, 0);
    DriftPose car({double x = 0, int layer = 0}) => (x: x, y: 0, heading: 0, vx: 20, vy: 10, layer: layer);
    final period = 1 / td.sampleHz;
    expect(s.update(period * 0.6, car()), isEmpty);
    expect(s.log, isEmpty);
    s.update(period * 0.6, car(), (_) => true);
    expect(s.log.map((a) => a.op), ['hit', 'sample']);
    expect(s.log[0].atMs, s.log[1].atMs);
    expect(s.log[1].atMs, (period * 1.2 * 1000).floor());
    // A long frame still sends one sample.
    s.update(period * 3.5, car());
    expect(s.log.length, 3);
    s.update(period, car(x: td.zoneM + 1));
    expect([s.log.last.inZone, s.inZone], [false, false]);
    s.update(period, car(layer: 1));
    expect(s.log.last.inZone, false);
    s.update(period, car(x: td.zoneM));
    expect(s.log.last.inZone, true);
    final n = s.log.length;
    final ev = s.update(td.sessionS.toDouble(), car(), (_) => true);
    expect(s.log.length, n + 1);
    expect(s.log.last.by, 'timeout');
    expect(ev.last, isA<DriftOver>());
    expect(s.update(1, car()), isEmpty);
  });

  test('session: a drift in the zone scores and banks after the grace time', () {
    final s = DriftSession(td, 3, 100, 100);
    final period = 1 / td.sampleHz;
    final events = <DriftEvent>[];
    for (var i = 0; i < 30; i++) {
      events.addAll(s.update(period, (x: 100, y: 100, heading: 0, vx: 15, vy: 10, layer: 0)));
    }
    expect(s.state.chain, greaterThan(0));
    for (var i = 0; i < 10; i++) {
      events.addAll(s.update(period, (x: 100, y: 100, heading: 0, vx: 0, vy: 0, layer: 0)));
    }
    expect(events.whereType<DriftBank>().length, 1);
    expect(s.state.drifts, 1);
    final r = s.end();
    expect([r.score, r.drifts], [s.state.score, 1]);
  });

  final vectors = File('$repoRoot/vectors/drift.json').existsSync();
  test(
    'vectors/drift.json',
    () => expect(checkVectors(DriftRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/drift.json') ? 'pending in parity.yaml' : false,
  );
}
