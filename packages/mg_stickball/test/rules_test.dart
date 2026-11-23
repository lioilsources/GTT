import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_stickball/mg_stickball.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const cfg = {
  'level': 1,
  'maxOuts': 6,
  'strikesOut': 3,
  'ballsWalk': 4,
  'zonePct': [85, 80, 75, 70, 65],
  'flightMin': [900, 800, 700, 600, 520],
  'flightVar': [200, 250, 300, 350, 400],
  'perfectMs': 40,
  'goodMs': 80,
  'okMs': 130,
  'foulMs': 200,
  'catchPct': [10, 15, 20, 25, 30],
  'starRuns': [8, 5, 2],
};

const inZone = StickballAction.pitch(true, 1, 900);
const outZone = StickballAction.pitch(false, 1, 900);

void main() {
  StickballState bat(StickballRules r, StickballState s, [StickballAction p = inZone]) => r.apply(s, p);

  test('init and pitch', () {
    final r = StickballRules();
    final s = r.init(cfg, 42);
    expect(s.toJson(), {
      'phase': 'pitch',
      'outs': 0,
      'strikes': 0,
      'balls': 0,
      'bases': 0,
      'runs': 0,
      'hits': 0,
      'homers': 0,
      'pitch': {'zone': false, 'lane': 0, 'flightMs': 0},
      'last': '',
      'rng': Prng(42).state,
    });
    expect(r.legalActions(s), isEmpty);
    final b = bat(r, s);
    expect(
      [b.phase, b.pitch.toJson(), b.last],
      [
        'bat',
        inZone.toJson()
          ..remove('by')
          ..remove('op'),
        '',
      ],
    );
    expect(r.legalActions(b).length, 4);
  });

  test('grades: lane, zone, foul, strike', () {
    final r = StickballRules();
    final s = bat(r, r.init(cfg, 1));
    expect(r.apply(s, const StickballAction.swing(1, 40)).last, 'homer');
    expect(r.apply(s, const StickballAction.swing(1, -80)).last, 'double');
    expect(r.apply(s, const StickballAction.swing(2, 0)).last, 'double');
    final foul = r.apply(s, const StickballAction.swing(1, 200));
    expect([foul.last, foul.strikes, foul.phase], ['foul', 1, 'pitch']);
    final miss = r.apply(s, const StickballAction.swing(1, 201));
    expect([miss.last, miss.strikes], ['strike', 1]);
    // Lane two off with a foul: below zero -> strike.
    expect(r.apply(s, const StickballAction.swing(0, 150)).last, 'strike');
    // Out of the zone, right lane, perfect: double.
    final o = bat(r, r.init(cfg, 1), outZone);
    expect(r.apply(o, const StickballAction.swing(1, 0)).last, 'double');
    expect(r.apply(o, const StickballAction.take()).last, 'ball');
    expect(r.apply(s, const StickballAction.take()).last, 'strike');
  });

  test('catch roll only at grade 1', () {
    final r = StickballRules();
    final s = bat(r, r.init(cfg, 3));
    final n = Prng(3).nextInt(100);
    final a = r.apply(s, const StickballAction.swing(1, 100));
    expect(a.last, n < 10 ? 'catch' : 'single');
    expect(a.rng, isNot(s.rng));
    expect(r.apply(s, const StickballAction.swing(1, 0)).rng, s.rng);
  });

  test('foul with two strikes keeps the count; strikeout', () {
    final r = StickballRules();
    var s = r.init(cfg, 1);
    for (var i = 0; i < 2; i++) {
      s = r.apply(bat(r, s), const StickballAction.take());
    }
    expect(s.strikes, 2);
    s = r.apply(bat(r, s), const StickballAction.swing(1, 190));
    expect([s.strikes, s.last], [2, 'foul']);
    s = r.apply(bat(r, s), const StickballAction.take());
    expect([s.strikes, s.outs, s.last], [0, 1, 'strikeout']);
  });

  test('bases: walks force runs, grand slam', () {
    final r = StickballRules();
    var s = r.init(cfg, 1);
    for (var w = 0; w < 4; w++) {
      for (var i = 0; i < 4; i++) {
        s = r.apply(bat(r, s, outZone), const StickballAction.take());
      }
      expect(s.last, 'walk');
    }
    expect([s.bases, s.runs, s.balls], [7, 1, 0]);
    s = r.apply(bat(r, s), const StickballAction.swing(1, 0));
    expect([s.bases, s.runs, s.hits, s.homers], [0, 5, 1, 1]);
    // Walk with a runner on second only: batter to first, second stays.
    final b2 = r.apply(bat(r, s.copyWith(bases: 2, balls: 3), outZone), const StickballAction.take());
    expect(b2.bases, 3);
    // Double moves first to third.
    final d = r.apply(bat(r, s.copyWith(bases: 1)), const StickballAction.swing(1, 60));
    expect([d.bases, d.runs - s.runs], [6, 0]);
  });

  test('six outs end the game; stars; timeout; illegal', () {
    final r = StickballRules();
    var s = r.init(cfg, 1);
    for (var i = 0; i < 18; i++) {
      s = r.apply(bat(r, s), const StickballAction.take());
    }
    expect([s.outs, s.phase], [6, 'over']);
    expect(r.result(s)!.toJson(), {'winner': 'ai', 'stars': 0, 'score': 0, 'hits': 0, 'homers': 0});
    expect([8, 5, 2, 1].map((n) => r.result(s.copyWith(runs: n))!.stars), [3, 2, 1, 0]);
    expect(() => r.apply(s, const StickballAction.take()), throwsA(isA<IllegalAction>()));
    final t0 = r.apply(r.init(cfg, 1), const StickballAction.timeout());
    expect([t0.phase, r.result(t0)!.winner], ['over', 'ai']);
    final s0 = r.init(cfg, 1);
    expect(() => r.apply(s0, const StickballAction.take()), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(bat(r, s0), inZone), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s0, const StickballAction.pitch(true, 3, 900)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s0, const StickballAction.pitch(true, 1, 0)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(bat(r, s0), const StickballAction.swing(-1, 0)), throwsA(isA<IllegalAction>()));
    expect(
      () => r.apply(bat(r, s0), r.actionFromJson({'by': 'player', 'op': 'swing', 'lane': 1})),
      throwsA(isA<IllegalAction>()),
    );
    expect(() => r.aiAction(bat(r, s0), 1, aiPrng(1)), throwsStateError);
  });

  test('ai pitches from its own stream', () {
    final r = StickballRules();
    final s = r.init(cfg, 9);
    final ai = aiPrng(9), ref = aiPrng(9);
    for (var i = 0; i < 5; i++) {
      final a = r.aiAction(s, 3, ai);
      final zone = ref.nextInt(100) < 75, lane = ref.nextInt(3), fl = 700 + ref.nextInt(301);
      expect([a.zone, a.lane, a.flightMs], [zone, lane, fl]);
    }
  });

  test('lane by tap height', () {
    expect([0.0, 0.55, 0.65, 0.70, 0.84, 1.0].map((y) => stickballLaneAt(y * 100, 100)), [2, 2, 1, 1, 0, 0]);
  });

  final vectors = File('$repoRoot/vectors/stickball.json').existsSync();
  test(
    'vectors/stickball.json',
    () => expect(checkVectors(StickballRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/stickball.json') ? 'pending in parity.yaml' : false,
  );
}
