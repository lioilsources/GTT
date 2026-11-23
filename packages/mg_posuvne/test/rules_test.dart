import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_posuvne/mg_posuvne.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const shuffle = [10, 20, 35, 60, 100];

PosuvneState at(List<int> tiles, {int par = 1}) =>
    PosuvneState(tiles: tiles, moves: 0, par: par, over: false, solved: false, rng: 1);

void main() {
  final r = PosuvneRules();

  test('the shuffle makes par moves and never ends solved', () {
    for (var seed = 1; seed < 50; seed++) {
      final s = r.init({'shuffleMoves': shuffle, 'level': 1}, seed);
      expect(s.par, anyOf(10, 11));
      expect(isSolved(s.tiles), isFalse);
      expect([...s.tiles]..sort(), List.generate(16, (i) => i));
    }
  });

  test('level is clamped to the table', () {
    expect(r.init({'shuffleMoves': shuffle, 'level': 9}, 3).par, anyOf(100, 101));
    expect(r.init({'shuffleMoves': shuffle, 'level': 0}, 3).par, anyOf(10, 11));
  });

  test('legal actions are the tiles next to the gap, ascending', () {
    final s = at([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 0, 15]);
    expect(r.legalActions(s).map((a) => a.tile), [11, 14, 15]);
    expect(() => r.apply(s, const PosuvneAction(1)), throwsA(isA<IllegalAction>()));
  });

  test('solving gives 3 stars at par, timeout loses', () {
    final s = at([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 0, 15]);
    final n = r.apply(s, const PosuvneAction(15));
    expect(n.solved, isTrue);
    expect(r.result(n)!.toJson(), {'winner': 'player', 'stars': 3, 'score': 1000, 'moves': 1, 'par': 1});
    final t = r.apply(s, const PosuvneAction.timeout());
    expect(r.result(t)!.toJson(), {'winner': 'ai', 'stars': 0, 'score': 0, 'moves': 0, 'par': 1});
  });

  test('a tap slides the run from the gap outwards', () {
    final s = at([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 0, 13, 14, 15]);
    expect(slideTiles(s, 15), [13, 14, 15]);
    expect(slideTiles(s, 0), [9, 5, 1]);
    expect(slideTiles(s, 5), isEmpty);
    expect(slideTiles(s, 12), isEmpty);
  });

  final vectors = File('$repoRoot/vectors/posuvne.json').existsSync();
  test(
    'vectors/posuvne.json',
    () => expect(checkVectors(PosuvneRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/posuvne.json') ? 'pending in parity.yaml' : false,
  );
}
