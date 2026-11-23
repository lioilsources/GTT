import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_sprint/mg_sprint.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const cfg = {
  'dests': ['a', 'b', 'c', 'd'],
  'level': 3,
  'parBaseMs': 5000,
  'parDmPerS': [90, 110, 130, 150, 170],
  'hitPenaltyMs': 2000,
  'starPct': [100, 120, 145],
};

void main() {
  test('pick draws from the allowed subset in config order', () {
    final r = SprintRules();
    final s0 = r.init(cfg, 7);
    expect(s0.toJson(), {
      'rng': Prng(7).state,
      'phase': 'pick',
      'dest': '',
      'distDm': 0,
      'cps': 0,
      'parMs': 0,
      'goMs': 0,
      'clockMs': 0,
      'passed': 0,
      'splits': <int>[],
      'hits': 0,
      'finished': false,
      'timeMs': 0,
    });
    final p = Prng(7);
    final all = r.apply(s0, const SprintAction.pick([]));
    expect(
      [all.dest, all.phase, all.rng],
      [
        ['a', 'b', 'c', 'd'][p.nextInt(4)],
        'ready',
        p.state,
      ],
    );
    final q = Prng(7);
    final sub = r.apply(s0, const SprintAction.pick(['d', 'b']));
    expect(sub.dest, ['b', 'd'][q.nextInt(2)]);
    expect(r.apply(s0, const SprintAction.pick(['c'])).dest, 'c');
    expect(() => r.apply(s0, const SprintAction.pick(['x'])), throwsA(isA<IllegalAction>()));
  });

  test('empty pool ends without a draw', () {
    final r = SprintRules();
    final s = r.apply(r.init({...cfg, 'dests': <String>[]}, 3), const SprintAction.pick([]));
    expect([s.phase, s.rng, s.dest, s.finished], ['over', Prng(3).state, '', false]);
    expect(r.result(s)!.toJson(), {
      'winner': 'draw',
      'stars': 0,
      'score': 0,
      'timeMs': 0,
      'parMs': 0,
      'dest': '',
      'hits': 0,
    });
  });

  test('go, checkpoints in order, hits, finish and stars', () {
    final r = SprintRules();
    var s = r.apply(r.init(cfg, 1), const SprintAction.pick([]));
    s = r.apply(s, const SprintAction.go(3000, 13000, 2));
    expect([s.phase, s.goMs, s.parMs], ['run', 3000, 5000 + 13000 * 1000 ~/ 130]);
    expect(() => r.apply(s, const SprintAction.cp(4000, 1)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const SprintAction.finish(4000)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const SprintAction.cp(2999, 0)), throwsA(isA<IllegalAction>()));
    s = r.apply(s, const SprintAction.cp(20000, 0));
    s = r.apply(s, const SprintAction.hit(30000));
    s = r.apply(s, const SprintAction.cp(40000, 1));
    expect(
      [s.splits, s.hits, s.passed],
      [
        [17000, 37000],
        1,
        2,
      ],
    );
    expect(() => r.apply(s, const SprintAction.cp(41000, 2)), throwsA(isA<IllegalAction>()));
    s = r.apply(s, const SprintAction.finish(90000));
    expect([s.phase, s.finished, s.timeMs], ['over', true, 87000 + 2000]);
    final res = r.result(s)!;
    // par 105000: 89000 ≤ 100 % → 3 stars; score = (210000 − 89000) ÷ 100.
    expect(res.toJson(), {
      'winner': 'player',
      'stars': 3,
      'score': 1210,
      'timeMs': 89000,
      'parMs': 105000,
      'dest': s.dest,
      'hits': 1,
    });
    final c = r.config;
    expect([105000, 105001, 126000, 126001, 152250, 152251].map((t) => c.stars(t, 105000)), [3, 2, 2, 1, 1, 0]);
  });

  test('cps 0 finishes at once; timeout keeps finished false; legal actions', () {
    final r = SprintRules();
    final ready = r.apply(r.init(cfg, 1), const SprintAction.pick([]));
    final run = r.apply(ready, const SprintAction.go(0, 0, 0));
    expect(r.legalActions(run).map((a) => a.op), ['hit', 'finish', '']);
    expect(r.apply(run, const SprintAction.finish(0)).finished, true);
    final out = r.apply(run, const SprintAction.timeout());
    expect([out.phase, out.finished, r.result(out)!.stars, r.result(out)!.score], ['over', false, 0, 0]);
    expect(r.legalActions(out), isEmpty);
    expect(r.legalActions(r.init(cfg, 1)).map((a) => a.toJson()), [
      {'by': 'player', 'op': 'pick', 'allow': <String>[]},
      {'by': 'timeout'},
    ]);
    expect(r.legalActions(ready).map((a) => a.op), ['go', '']);
    final cps = r.apply(ready, const SprintAction.go(0, 5000, 1));
    expect(r.legalActions(cps).map((a) => a.op), ['cp', 'hit', '']);
    expect(() => r.apply(ready, const SprintAction.go(0, -1, 0)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(ready, const SprintAction.hit(0)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(run, const SprintAction.pick([])), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(out, const SprintAction.timeout()), throwsA(isA<IllegalAction>()));
    expect(
      () => r.actionFromJson({'by': 'player', 'op': 'go', 'atMs': 1, 'distDm': 1.5, 'cps': 0}),
      throwsA(isA<IllegalAction>()),
    );
    expect(
      () => r.actionFromJson({
        'by': 'player',
        'op': 'pick',
        'allow': [1],
      }),
      throwsA(isA<IllegalAction>()),
    );
    expect(() => r.actionFromJson({'by': 'player', 'op': 'fly', 'atMs': 1}), throwsA(isA<IllegalAction>()));
    expect(() => r.aiAction(run, 1, Prng(1)), throwsUnsupportedError);
  });

  final vectors = File('$repoRoot/vectors/sprint.json').existsSync();
  test(
    'vectors/sprint.json',
    () => expect(checkVectors(SprintRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/sprint.json') ? 'pending in parity.yaml' : false,
  );
}
