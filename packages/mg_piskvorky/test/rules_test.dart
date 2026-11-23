import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_piskvorky/mg_piskvorky.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const cfg = {
  'size': 15,
  'aiErrorPct': [40, 25, 12, 5, 0],
  'defensePct': [50, 70, 90, 100, 110],
  'fastMoves': 15,
};

String board(Map<int, String> marks) => [for (var i = 0; i < 225; i++) marks[i] ?? '.'].join();

({PiskvorkyRules r, PiskvorkyState s}) setup(Map<int, String> marks, {String turn = 'player', int moves = 0}) {
  final r = PiskvorkyRules();
  final s = r.init(cfg, 1);
  return (
    r: r,
    s: PiskvorkyState(board: board(marks), turn: turn, moves: moves, over: false, winner: '', rng: s.rng),
  );
}

void main() {
  test('empty board, player first, every square legal', () {
    final r = PiskvorkyRules();
    final s = r.init(cfg, 42);
    expect(s.board, '.' * 225);
    expect(s.turn, 'player');
    expect(r.legalActions(s).length, 225);
    expect(r.legalActions(s).first, const PiskvorkyAction('player', 0));
  });

  test('five in a row wins; occupied squares are illegal', () {
    final g = setup({0: 'x', 16: 'x', 32: 'x', 48: 'x', 1: 'o', 2: 'o', 3: 'o', 4: 'o'}, moves: 4);
    expect(() => g.r.apply(g.s, const PiskvorkyAction('player', 0)), throwsA(isA<IllegalAction>()));
    final n = g.r.apply(g.s, const PiskvorkyAction('player', 64));
    expect(n.over, isTrue);
    expect(n.winner, 'player');
    expect(winningLine(n.board, 15, 64), [0, 16, 32, 48, 64]);
    expect(g.r.result(n)!.toJson(), {'winner': 'player', 'stars': 3, 'score': (225 - 9) * 10, 'moves': 5});
  });

  test('AI opens in the centre and still draws r on a single candidate', () {
    final r = PiskvorkyRules();
    final s = r.init(cfg, 3).copyWith(turn: 'ai');
    final ai = aiPrng(9);
    final before = aiPrng(9)..nextInt(100);
    expect(r.aiAction(s, 5, ai).cell, 7 * 15 + 7);
    expect(ai.state, before.state);
  });

  test('AI blocks an open four and takes its own five at level 4', () {
    final block = setup({100: 'x', 101: 'x', 102: 'x', 103: 'x', 0: 'o'}, turn: 'ai');
    expect([99, 104], contains(block.r.aiAction(block.s, 4, aiPrng(1)).cell));
    final own = setup({100: 'o', 101: 'o', 102: 'o', 103: 'o', 0: 'x', 1: 'x', 2: 'x', 30: 'x'}, turn: 'ai');
    expect([99, 104], contains(own.r.aiAction(own.s, 4, aiPrng(1)).cell));
  });

  test('timeout is a draw with 0 stars', () {
    final g = setup({0: 'x'});
    final n = g.r.apply(g.s, const PiskvorkyAction.timeout());
    expect(g.r.result(n)!.toJson(), {'winner': 'draw', 'stars': 0, 'score': 0, 'moves': 0});
  });

  final vectors = File('$repoRoot/vectors/piskvorky.json').existsSync();
  test(
    'vectors/piskvorky.json',
    () => expect(checkVectors(PiskvorkyRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/piskvorky.json') ? 'pending in parity.yaml' : false,
  );
}
