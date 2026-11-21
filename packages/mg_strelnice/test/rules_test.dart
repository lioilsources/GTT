import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_strelnice/mg_strelnice.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const cfg = {
  'rounds': 3,
  'roundTicks': 2700,
  'targets': 36,
  'width': 1000,
  'lanes': [250, 500, 750],
  'kinds': [40, 9, 50, 60, 6, 20, 80, 4, 10],
  'kindPct': [15, 55],
  'magazine': 6,
  'reloadTicks': 45,
  'starScores': [1500, 1000, 600],
};

Target tgt({int lane = 0, int kind = 1, int spawn = 0, int dir = 1}) =>
    Target(lane: lane, kind: kind, spawn: spawn, dir: dir);

void main() {
  test('targets are generated in lane → roll → spawn order', () {
    final r = StrelniceRules();
    final s = r.init(cfg, 42);
    expect(s.targets, hasLength(36));
    expect(s.ammo, 6);
    final p = Prng(42);
    const spacing = 2700 * 9 ~/ 360;
    for (var i = 0; i < 36; i++) {
      final lane = p.nextInt(3), roll = p.nextInt(100), spawn = i * spacing + p.nextInt(spacing);
      expect(s.targets[i].toJson(), {
        'lane': lane,
        'kind': roll < 15 ? 0 : (roll < 55 ? 1 : 2),
        'spawn': spawn,
        'dir': lane.isEven ? 1 : -1,
        'hit': false,
      });
    }
    expect(s.rng, p.state);
  });

  test('positions and on-field edges', () {
    final r = StrelniceRules()..init(cfg, 1);
    final c = r.config;
    expect(targetPos(tgt(spawn: 10), 10, c), (x: -60, y: 250));
    expect(onField(tgt(spawn: 10), 9, c), isFalse);
    final edge = tgt(kind: 2);
    expect(onField(edge, 290, c), isTrue);
    expect(onField(edge, 291, c), isFalse);
    final left = tgt(lane: 1, kind: 0, dir: -1);
    expect(targetPos(left, 0, c), (x: 1040, y: 500));
    expect(onField(left, 120, c), isTrue);
    expect(onField(left, 121, c), isFalse);
  });

  test('overlapping targets: the lowest index is hit', () {
    final r = StrelniceRules();
    final s = r
        .init(cfg, 1)
        .copyWith(tick: 50, targets: [tgt(kind: 2), tgt(kind: 0, spawn: 25), tgt(kind: 1, spawn: 15)]);
    final n = r.apply(s, const StrelniceAction.shoot(150, 250));
    expect(n.targets.map((t) => t.hit), [true, false, false]);
    final m = r.apply(n, const StrelniceAction.shoot(150, 250));
    expect(m.targets.map((t) => t.hit), [true, true, false]);
    expect([m.score, m.hits, m.shots, m.ammo], [60, 2, 2, 4]);
  });

  test('reload: empty magazine, no-op shots, refill', () {
    final r = StrelniceRules();
    var s = r.init(cfg, 3);
    for (var i = 0; i < 6; i++) {
      s = r.apply(s, const StrelniceAction.shoot(0, 0));
    }
    expect([s.ammo, s.reload], [0, 45]);
    expect(identical(r.apply(s, const StrelniceAction.shoot(0, 0)), s), isTrue);
    s = r.apply(s, const StrelniceAction.tick(45));
    expect([s.ammo, s.reload, s.tick], [6, 0, 45]);
  });

  test('rollover, over after the last round, stars', () {
    final r = StrelniceRules();
    var s = r.init(cfg, 9);
    final first = s.targets;
    s = r.apply(s, const StrelniceAction.tick(2700));
    expect([s.round, s.tick], [2, 0]);
    expect(s.targets.map((t) => t.toJson()), isNot(first.map((t) => t.toJson())));
    s = r.apply(s, const StrelniceAction.tick(2700));
    expect([s.round, s.tick, s.over], [3, 0, false]);
    s = r.apply(s, const StrelniceAction.tick(10000));
    expect([s.round, s.tick, s.over], [3, 2700, true]);
    expect(() => r.apply(s, const StrelniceAction.tick(1)), throwsA(isA<IllegalAction>()));
    int stars(int score) => r.result(s.copyWith(score: score))!.stars;
    expect([0, 599, 600, 1000, 1500].map(stars), [0, 0, 1, 2, 3]);
    expect(r.result(s)!.winner, 'ai');
  });

  test('rejects illegal actions', () {
    final r = StrelniceRules();
    final s = r.init(cfg, 1);
    expect(() => r.apply(s, const StrelniceAction.tick(0)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const StrelniceAction.raw('ai', 'tick', n: 1)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const StrelniceAction.raw('player', 'jump')), throwsA(isA<IllegalAction>()));
  });

  final vectors = File('$repoRoot/vectors/strelnice.json').existsSync();
  test(
    'vectors/strelnice.json',
    () => expect(checkVectors(StrelniceRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/strelnice.json') ? 'pending in parity.yaml' : false,
  );
}
