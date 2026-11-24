import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_gorodki/mg_gorodki.dart';
import 'package:rules_core/vector_test_support.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
  final cfg = GorodkiConfig.fromTuning(tuning.minigames.gorodki, 1);
  final mid = cfg.gorodW ~/ 2;

  test('figure 1 from the middle of the front line; a hard straight throw knocks pieces out', () {
    final r = GorodkiRules();
    final s = r.start(cfg, 1);
    expect([s.fig, s.bats, s.polukon, s.px[0], s.py[0]], [1, cfg.bats[0], false, mid - 15000, cfg.gorodY0 + 20000]);
    final hit = r.apply(s, GorodkiAction.hurl(mid, mid, 100));
    expect(hit.lastOut, greaterThan(0));
    expect(hit.polukon, isTrue);
    final miss = r.apply(s, GorodkiAction.hurl(0, -200000, 100));
    expect([miss.lastOut, miss.polukon, miss.throws], [0, false, 1]);
    expect(() => r.apply(s, GorodkiAction.hurl(-1, mid, 50)), throwsA(anything));
  });

  test('clearing a figure lays the next one; the last bat ends the game', () {
    final r = GorodkiRules();
    final s = r.start(cfg, 1);
    final one = s.copyWith(
      up: [true, false, false, false, false],
      px: [mid, 0, 0, 0, 0],
      py: [cfg.gorodY0 + 10000, 0, 0, 0, 0],
    );
    final n = r.apply(one, GorodkiAction.hurl(mid, mid, 100));
    expect([n.fig, n.cleared, n.polukon, n.up], [2, 1, false, List.filled(5, true)]);
    final last = r.apply(s.copyWith(bats: 1), GorodkiAction.hurl(0, -200000, 10));
    expect(last.over, isTrue);
    expect(r.result(last)!.stars, 0);
  });

  final vectors = File('$repoRoot/vectors/gorodki.json').existsSync();
  test(
    'vectors/gorodki.json',
    () => expect(checkVectors(GorodkiRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/gorodki.json') ? 'pending in parity.yaml' : false,
  );
}
