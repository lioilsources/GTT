import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_dama/mg_dama.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const cfg = {
  'aiDepth': [1, 2, 3, 4, 5],
  'aiErrorPct': [35, 20, 10, 5, 0],
  'quietLimit': 50,
  'fastPlies': 80,
};

String board(Map<int, String> pieces) => [for (var i = 0; i < 32; i++) pieces[i] ?? '.'].join();

({DamaRules r, DamaState s}) setup(Map<int, String> pieces, {String turn = 'player', Map<String, Object?> c = cfg}) {
  final r = DamaRules();
  final s = r.init(c, 1);
  return (
    r: r,
    s: DamaState(
      board: board(pieces),
      turn: turn,
      plies: 0,
      quiet: 0,
      over: false,
      winner: '',
      byMaterial: false,
      rng: s.rng,
    ),
  );
}

List<List<int>> paths(DamaRules r, DamaState s) => [for (final a in r.legalActions(s)) a.path];

void main() {
  test('starts with the player and 7 legal moves in path order', () {
    final r = DamaRules();
    final s = r.init(cfg, 42);
    expect(s.board, 'bbbbbbbbbbbb........wwwwwwwwwwww');
    expect(s.turn, 'player');
    expect(paths(r, s), [
      [20, 16],
      [21, 16],
      [21, 17],
      [22, 17],
      [22, 18],
      [23, 18],
      [23, 19],
    ]);
  });

  test('capturing is compulsory', () {
    final g = setup({21: 'w', 28: 'w', 17: 'b', 0: 'b'});
    expect(paths(g.r, g.s), [
      [21, 14],
    ]);
    expect(() => g.r.apply(g.s, const DamaAction('player', [28, 24])), throwsA(isA<IllegalAction>()));
    final n = g.r.apply(g.s, const DamaAction('player', [21, 14]));
    expect(n.board[17], '.');
    expect(n.board[14], 'w');
    expect(n.quiet, 0);
  });

  test('a man cannot capture backwards', () {
    final g = setup({13: 'w', 17: 'b', 0: 'b'});
    expect(paths(g.r, g.s), [
      [13, 8],
      [13, 9],
    ]);
  });

  test('a king captures from a distance and must continue', () {
    final g = setup({28: 'W', 21: 'b', 9: 'b', 31: 'b'});
    final ps = paths(g.r, g.s);
    expect(
      ps,
      containsAll([
        [28, 14, 0],
        [28, 14, 5],
        [28, 17],
      ]),
    );
    expect(ps, isNot(contains([28, 14])));
    final n = g.r.apply(g.s, const DamaAction('player', [28, 14, 5]));
    expect(n.board, board({5: 'W', 31: 'b'}));
  });

  test('a man promotes only at the end of its move', () {
    final g = setup({10: 'w', 6: 'b', 5: 'b', 31: 'b'});
    expect(paths(g.r, g.s), [
      [10, 1],
    ]);
    final n = g.r.apply(g.s, const DamaAction('player', [10, 1]));
    expect(n.board[1], 'W');
    expect(n.board[5], 'b');
  });

  test('a side without a move loses; a fast win gives 3 stars', () {
    final g = setup({4: 'w', 0: 'b', 3: 'b'}, turn: 'ai');
    final n = g.r.apply(g.s, const DamaAction('ai', [3, 7]));
    expect(n.over, isTrue);
    expect(n.winner, 'ai');
    expect(g.r.result(n)!.stars, 0);
    final w = setup({9: 'w', 5: 'b'});
    final m = w.r.apply(w.s, const DamaAction('player', [9, 0]));
    expect(w.r.result(m)!.toJson(), {'winner': 'player', 'stars': 3, 'score': 1200, 'byMaterial': false, 'plies': 1});
  });

  test('quiet king moves reach the draw limit', () {
    final g = setup({31: 'W', 0: 'B'}, c: {...cfg, 'quietLimit': 2});
    var n = g.r.apply(g.s, const DamaAction('player', [31, 27]));
    expect(n.over, isFalse);
    n = g.r.apply(n, const DamaAction('ai', [0, 4]));
    expect(n.winner, 'draw');
    expect(n.quiet, 2);
  });

  test('timeout decides by material', () {
    final g = setup({31: 'W', 0: 'b', 1: 'b'});
    final n = g.r.apply(g.s, const DamaAction.timeout());
    expect(g.r.result(n)!.toJson(), {'winner': 'player', 'stars': 1, 'score': 1000, 'byMaterial': true, 'plies': 0});
  });

  test('the AI returns a legal move at every level, depth 5 quickly', () {
    final r = DamaRules();
    var s = r.init(cfg, 11);
    s = r.apply(s, const DamaAction('player', [22, 17]));
    final legal = r.legalActions(s);
    for (var level = 1; level <= 5; level++) {
      expect(legal, contains(r.aiAction(s, level, aiPrng(level))));
    }
    final sw = Stopwatch()..start();
    r.aiAction(s, 5, aiPrng(1));
    expect(sw.elapsedMilliseconds, lessThan(500));
  });

  final vectors = File('$repoRoot/vectors/dama.json').existsSync();
  test(
    'vectors/dama.json',
    () => expect(checkVectors(DamaRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/dama.json') ? 'pending in parity.yaml' : false,
  );
}
