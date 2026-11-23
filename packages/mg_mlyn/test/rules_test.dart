import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_mlyn/mg_mlyn.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const cfg = {
  'aiDepth': [1, 2, 2, 3, 4],
  'aiErrorPct': [35, 20, 10, 5, 0],
  'quietLimit': 50,
  'flying': true,
  'star3Pieces': 6,
};

String board(Map<int, String> pieces) => [for (var i = 0; i < 24; i++) pieces[i] ?? '.'].join();

({MlynRules r, MlynState s}) setup(
  Map<int, String> pieces, {
  String turn = 'player',
  int hp = 0,
  int ha = 0,
  Map<String, Object?> c = cfg,
}) {
  final r = MlynRules();
  final s = r.init(c, 1);
  return (
    r: r,
    s: MlynState(
      board: board(pieces),
      handPlayer: hp,
      handAi: ha,
      turn: turn,
      plies: 0,
      quiet: 0,
      over: false,
      winner: '',
      byPieces: false,
      rng: s.rng,
    ),
  );
}

void main() {
  test('adjacency follows the mills', () {
    expect(adjacency[0], [1, 9]);
    expect(adjacency[4], [1, 3, 5, 7]);
    expect(adjacency[10], [3, 9, 11, 18]);
  });

  test('starts with 24 placements by the player', () {
    final r = MlynRules();
    final s = r.init(cfg, 7);
    expect(s.toJson()['hand'], {'player': 9, 'ai': 9});
    final legal = r.legalActions(s);
    expect(legal.length, 24);
    expect(legal.first, const MlynAction('player', -1, 0, -1));
  });

  test('a mill takes a stone outside mills first; placing does not count quiet', () {
    final g = setup({0: 'w', 1: 'w', 3: 'b', 4: 'b', 5: 'b', 9: 'b'}, hp: 3, ha: 3);
    final takes = [
      for (final a in g.r.legalActions(g.s))
        if (a.to == 2) a.remove,
    ];
    expect(takes, [9]);
    final n = g.r.apply(g.s, const MlynAction('player', -1, 2, 9));
    expect(n.board[9], '.');
    expect(n.handPlayer, 2);
    expect(n.quiet, 0);
    expect(() => g.r.apply(g.s, const MlynAction('player', -1, 2, -1)), throwsA(isA<IllegalAction>()));
  });

  test('a moving step without a mill counts quiet', () {
    final g = setup({0: 'w', 1: 'w', 14: 'w', 3: 'b', 4: 'b', 5: 'b', 21: 'b'});
    final n = g.r.apply(g.s, const MlynAction('player', 14, 13, -1));
    expect(n.quiet, 1);
  });

  test('under three stones after placing loses; score counts AI stones', () {
    final g = setup({0: 'w', 1: 'w', 14: 'w', 3: 'b', 4: 'b', 5: 'b'});
    final n = g.r.apply(g.s, const MlynAction('player', 14, 2, 3));
    expect(n.over, isTrue);
    expect(n.winner, 'player');
    expect(g.r.result(n)!.toJson(), {'winner': 'player', 'stars': 2, 'score': 700, 'byPieces': false, 'plies': 1});
  });

  test('three stones may fly', () {
    final g = setup({0: 'w', 1: 'w', 9: 'w', 3: 'b', 4: 'b', 5: 'b'}, turn: 'ai');
    expect(g.r.legalActions(g.s).length, 3 * 18);
  });

  test('timeout decides by stones on board and in hand', () {
    final g = setup({0: 'w'}, hp: 3, ha: 2);
    final n = g.r.apply(g.s, const MlynAction.timeout());
    expect(g.r.result(n)!.toJson(), {'winner': 'player', 'stars': 1, 'score': 700, 'byPieces': true, 'plies': 0});
  });

  test('the AI returns a legal move at every level', () {
    final r = MlynRules();
    var s = r.init(cfg, 11);
    s = r.apply(s, const MlynAction('player', -1, 4, -1));
    final legal = r.legalActions(s);
    for (var level = 1; level <= 5; level++) {
      expect(legal, contains(r.aiAction(s, level, aiPrng(level))));
    }
  });

  final vectors = File('$repoRoot/vectors/mlyn.json').existsSync();
  test(
    'vectors/mlyn.json',
    () => expect(checkVectors(MlynRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/mlyn.json') ? 'pending in parity.yaml' : false,
  );
}
