import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_ctyri/mg_ctyri.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const cfg = {
  'aiDepth': [1, 2, 3, 5, 7],
  'aiErrorPct': [35, 20, 10, 5, 0],
  'fastMoves': 12,
};

String board(Map<int, String> tokens) => [for (var i = 0; i < 42; i++) tokens[i] ?? '.'].join();

({CtyriRules r, CtyriState s}) setup(Map<int, String> tokens, {String turn = 'player', int moves = 0}) {
  final r = CtyriRules();
  final s = r.init(cfg, 1);
  return (
    r: r,
    s: CtyriState(board: board(tokens), turn: turn, moves: moves, over: false, winner: '', rng: s.rng),
  );
}

void main() {
  test('69 windows, 7 legal columns, a disc falls to the bottom', () {
    expect(windows.length, 69);
    final r = CtyriRules();
    final s = r.init(cfg, 5);
    expect([for (final a in r.legalActions(s)) a.col], [0, 1, 2, 3, 4, 5, 6]);
    final n = r.apply(s, const CtyriAction('player', 3));
    expect(n.board[38], 'x');
    expect(n.turn, 'ai');
    expect(n.moves, 1);
    expect(() => r.apply(n, const CtyriAction('player', 3)), throwsA(isA<IllegalAction>()));
  });

  test('a full column is not legal', () {
    final g = setup({for (var r = 0; r < 6; r++) r * 7: r.isEven ? 'x' : 'o'});
    expect([for (final a in g.r.legalActions(g.s)) a.col], [1, 2, 3, 4, 5, 6]);
    expect(() => g.r.apply(g.s, const CtyriAction('player', 0)), throwsA(isA<IllegalAction>()));
  });

  test('four in a row wins with stars and score', () {
    final g = setup({35: 'x', 36: 'x', 37: 'x', 28: 'o', 29: 'o', 30: 'o'}, moves: 3);
    final n = g.r.apply(g.s, const CtyriAction('player', 3));
    expect(n.winner, 'player');
    expect(winningLine(n.board, 38), [35, 36, 37, 38]);
    expect(g.r.result(n)!.toJson(), {'winner': 'player', 'stars': 3, 'score': (42 - 7) * 20, 'moves': 4});
  });

  test('AI wins when it can and blocks otherwise (level 5)', () {
    final win = setup({35: 'x', 36: 'x', 40: 'x', 28: 'o', 21: 'o', 14: 'o'}, turn: 'ai');
    expect(win.r.aiAction(win.s, 5, aiPrng(1)).col, 0);
    final block = setup({35: 'x', 36: 'x', 37: 'x', 41: 'o', 34: 'o'}, turn: 'ai');
    expect(block.r.aiAction(block.s, 5, aiPrng(1)).col, 3);
  });

  test('AI depth 7 answers quickly', () {
    final r = CtyriRules();
    final s = r.apply(r.init(cfg, 2), const CtyriAction('player', 3));
    final sw = Stopwatch()..start();
    expect(r.legalActions(s), contains(r.aiAction(s, 5, aiPrng(2))));
    expect(sw.elapsedMilliseconds, lessThan(1000));
  });

  test('timeout is a draw', () {
    final g = setup({});
    final n = g.r.apply(g.s, const CtyriAction.timeout());
    expect(g.r.result(n)!.toJson(), {'winner': 'draw', 'stars': 0, 'score': 0, 'moves': 0});
  });

  final vectors = File('$repoRoot/vectors/ctyri.json').existsSync();
  test(
    'vectors/ctyri.json',
    () => expect(checkVectors(CtyriRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/ctyri.json') ? 'pending in parity.yaml' : false,
  );
}
