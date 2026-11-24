import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_sachy/mg_sachy.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const cfg = {
  'aiDepth': [1, 1, 2, 3, 4],
  'aiErrorPct': [40, 25, 12, 5, 0],
  'quietLimit': 30,
  'fastPlies': 40,
};

void main() {
  final r = SachyRules();
  final s0 = r.init(cfg, 1);
  SachyState at(String board, [String turn = 'player']) => s0.copyWith(board: board, turn: turn);

  test('start: pawn steps and knight jumps only', () {
    expect(r.legalActions(s0).map((a) => '${a.from}-${a.to}'), [
      '15-10',
      '16-11',
      '17-12',
      '18-13',
      '19-14',
      '21-10',
      '21-12',
    ]);
  });

  test('pin, promotion, mate, stalemate, bare kings, timeout', () {
    expect(r.legalActions(at('r...k.....B.........K....')).where((a) => a.from == 10), isEmpty);
    expect(r.apply(at('....kP..............K....'), const SachyAction('player', 5, 0)).board[0], 'Q');
    final mate = r.apply(at('....k.....Q...K..........'), const SachyAction('player', 10, 0));
    expect([mate.over, mate.winner, r.result(mate)!.stars], [true, 'player', 3]);
    expect(r.apply(at('....k.......Q.K..........'), const SachyAction('player', 12, 13)).winner, 'draw');
    expect(r.apply(at('....k..p.....K...........'), const SachyAction('player', 13, 7)).winner, 'draw');
    expect(r.result(r.apply(s0, const SachyAction.timeout()))!.toJson(), {
      'winner': 'draw',
      'stars': 0,
      'score': 250,
      'byCount': true,
      'player': 25,
      'ai': 25,
      'plies': 0,
    });
  });

  test('the AI mates in one', () {
    expect(r.aiAction(at('K.........k............q.', 'ai'), 5, aiPrng(1)), const SachyAction('ai', 23, 3));
  });

  final vectors = File('$repoRoot/vectors/sachy.json').existsSync();
  test(
    'vectors/sachy.json',
    () => expect(checkVectors(SachyRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/sachy.json') ? 'pending in parity.yaml' : false,
  );
}
