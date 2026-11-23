import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_lode/mg_lode.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const cfg = {
  'fleet': [5, 4, 3, 3, 2],
  'shuffles': 3,
  'aiErrorPct': [50, 30, 15, 5, 0],
  'fastShots': 45,
  'okShots': 70,
};

void main() {
  test('fleets are dealt in fleet order without touching ships', () {
    final r = LodeRules();
    final s = r.init(cfg, 7);
    for (final fleet in [s.pShips, s.aShips]) {
      expect([for (final sh in fleet) sh.length], [5, 4, 3, 3, 2]);
      for (var a = 0; a < fleet.length; a++) {
        for (var b = a + 1; b < fleet.length; b++) {
          for (final p in fleet[a]) {
            for (final q in fleet[b]) {
              expect(((p % 10) - (q % 10)).abs() > 1 || ((p ~/ 10) - (q ~/ 10)).abs() > 1, isTrue);
            }
          }
        }
      }
    }
  });

  test('shuffle only before the first shot; a hit fires again, water passes', () {
    final r = LodeRules();
    var s = r.init(cfg, 7);
    expect(r.legalActions(s).first, const LodeAction.shuffle());
    s = r.apply(s, const LodeAction.shuffle());
    expect(s.shuffles, 2);
    final hitCell = s.aShips.first.first;
    final h = r.apply(s, LodeAction.shot('player', hitCell));
    expect(h.aShots[hitCell], 'x');
    expect(h.turn, 'player');
    expect(h.shots, 1);
    expect(r.canShuffle(h), isFalse);
    expect(() => r.apply(h, const LodeAction.shuffle()), throwsA(isA<IllegalAction>()));
    final water = [for (var i = 0; i < 100; i++) i].firstWhere((i) => !h.aShips.any((sh) => sh.contains(i)));
    expect(r.apply(h, LodeAction.shot('player', water)).turn, 'ai');
  });

  test('a run of two hits is extended at both ends', () {
    final shots = List.filled(100, '.');
    shots[44] = 'x';
    shots[45] = 'x';
    expect(
      targetCandidates([
        [43, 44, 45, 46],
      ], shots.join()),
      [43, 46],
    );
    shots[43] = 'o';
    expect(
      targetCandidates([
        [44, 45, 46],
      ], shots.join()),
      [46],
    );
  });

  test('timeout compares hits', () {
    final r = LodeRules();
    final s = r.init(cfg, 7);
    final n = r.apply(r.apply(s, LodeAction.shot('player', s.aShips.first.first)), const LodeAction.timeout());
    expect(r.result(n)!.toJson(), {'winner': 'player', 'stars': 3, 'score': 990, 'shots': 1});
  });

  final vectors = File('$repoRoot/vectors/lode.json').existsSync();
  test(
    'vectors/lode.json',
    () => expect(checkVectors(LodeRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/lode.json') ? 'pending in parity.yaml' : false,
  );
}
