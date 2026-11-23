import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_reversi/mg_reversi.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const cfg = {
  'aiDepth': [1, 2, 3, 4, 5],
  'aiErrorPct': [35, 20, 10, 5, 0],
  'star3Margin': 20,
};

ReversiState withBoard(ReversiRules r, String board, {String turn = 'player', int passes = 0}) {
  final s = r.init(cfg, 1);
  return ReversiState(
    board: board,
    turn: turn,
    plies: 0,
    passes: passes,
    over: false,
    winner: '',
    byCount: false,
    rng: s.rng,
  );
}

String board(Map<int, String> discs) => [for (var i = 0; i < 64; i++) discs[i] ?? '.'].join();

void main() {
  test('starts with the player and four legal moves ascending', () {
    final r = ReversiRules();
    final s = r.init(cfg, 42);
    expect(s.board, board({27: 'o', 36: 'o', 28: 'x', 35: 'x'}));
    expect([for (final a in r.legalActions(s)) a.cell], [19, 26, 37, 44]);
  });

  test('a move flips the trapped line and passes the turn', () {
    final r = ReversiRules();
    final n = r.apply(r.init(cfg, 1), const ReversiAction('player', 19));
    expect(n.board, board({19: 'x', 27: 'x', 28: 'x', 35: 'x', 36: 'o'}));
    expect(n.turn, 'ai');
    expect(n.plies, 1);
    expect(() => r.apply(n, const ReversiAction('ai', 0)), throwsA(isA<IllegalAction>()));
  });

  test('pass only without a move; two passes end the game', () {
    final r = ReversiRules();
    final s = withBoard(r, board({0: 'x', 1: 'o', 63: 'o'}));
    expect([for (final a in r.legalActions(s)) a.cell], [2]);
    expect(() => r.apply(s, const ReversiAction('player', -1)), throwsA(isA<IllegalAction>()));
    final blocked = withBoard(r, board({0: 'x', 63: 'o'}), passes: 1);
    expect(r.legalActions(blocked), [const ReversiAction('player', -1)]);
    final n = r.apply(blocked, const ReversiAction('player', -1));
    expect(n.over, isTrue);
    expect(n.winner, 'draw');
  });

  test('timeout decides by count, one star', () {
    final r = ReversiRules();
    final s = withBoard(r, board({0: 'x', 1: 'x', 63: 'o'}));
    final n = r.apply(s, const ReversiAction.timeout());
    expect(r.result(n)!.toJson(), {'winner': 'player', 'stars': 1, 'score': 20, 'byCount': true, 'player': 2, 'ai': 1});
  });

  test('the AI returns a legal move at every level', () {
    final r = ReversiRules();
    final s = r.apply(r.init(cfg, 3), const ReversiAction('player', 19));
    final legal = r.legalActions(s);
    for (var level = 1; level <= 5; level++) {
      expect(legal, contains(r.aiAction(s, level, aiPrng(level))));
    }
  });

  final vectors = File('$repoRoot/vectors/reversi.json').existsSync();
  test(
    'vectors/reversi.json',
    () => expect(checkVectors(ReversiRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/reversi.json') ? 'pending in parity.yaml' : false,
  );
}
