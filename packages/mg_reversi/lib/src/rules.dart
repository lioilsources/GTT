import 'dart:typed_data';

import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/reversi.md, version 1. Pure Dart: no Flutter imports here.
class ReversiConfig {
  const ReversiConfig({required this.aiDepth, required this.aiErrorPct, required this.star3Margin});

  factory ReversiConfig.fromTuning(TuningMinigamesReversi t) => ReversiConfig(
    aiDepth: List.unmodifiable(t.aiDepth),
    aiErrorPct: List.unmodifiable(t.aiErrorPct),
    star3Margin: t.star3Margin,
  );

  factory ReversiConfig.fromJson(Map<String, Object?> j) => ReversiConfig(
    aiDepth: List.unmodifiable((j['aiDepth'] as List).cast<int>()),
    aiErrorPct: List.unmodifiable((j['aiErrorPct'] as List).cast<int>()),
    star3Margin: j['star3Margin'] as int,
  );

  final List<int> aiDepth, aiErrorPct;
  final int star3Margin;
}

class ReversiState {
  const ReversiState({
    required this.board,
    required this.turn,
    required this.plies,
    required this.passes,
    required this.over,
    required this.winner,
    required this.byCount,
    required this.rng,
  });

  /// 64 chars, row 0 on top: '.', 'x' (player), 'o' (AI).
  final String board;

  /// 'player' or 'ai'.
  final String turn;
  final int plies, passes;
  final bool over;

  /// '' while the game runs, then 'player', 'ai' or 'draw'.
  final String winner;
  final bool byCount;
  final int rng;

  ReversiState copyWith({
    String? board,
    String? turn,
    int? plies,
    int? passes,
    bool? over,
    String? winner,
    bool? byCount,
  }) => ReversiState(
    board: board ?? this.board,
    turn: turn ?? this.turn,
    plies: plies ?? this.plies,
    passes: passes ?? this.passes,
    over: over ?? this.over,
    winner: winner ?? this.winner,
    byCount: byCount ?? this.byCount,
    rng: rng,
  );

  Map<String, Object?> toJson() => {
    'board': board,
    'turn': turn,
    'plies': plies,
    'passes': passes,
    'over': over,
    'winner': winner,
    'byCount': byCount,
    'rng': rng,
  };
}

/// {by: player|ai, cell} (cell -1 = pass) or {by: timeout}.
class ReversiAction {
  const ReversiAction(this.by, this.cell);
  const ReversiAction.timeout() : by = 'timeout', cell = -1;

  final String by;
  final int cell;

  bool get isPass => by != 'timeout' && cell < 0;

  Map<String, Object?> toJson() => by == 'timeout' ? {'by': by} : {'by': by, 'cell': cell};

  @override
  bool operator ==(Object other) => other is ReversiAction && other.by == by && other.cell == cell;

  @override
  int get hashCode => Object.hash(by, cell);

  @override
  String toString() => toJson().toString();
}

class ReversiResult {
  const ReversiResult({
    required this.winner,
    required this.stars,
    required this.score,
    required this.byCount,
    required this.player,
    required this.ai,
  });

  final String winner;
  final int stars, score;
  final bool byCount;
  final int player, ai;

  Map<String, Object?> toJson() => {
    'winner': winner,
    'stars': stars,
    'score': score,
    'byCount': byCount,
    'player': player,
    'ai': ai,
  };
}

const _dirs = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)];

const _half = [
  [100, -20, 10, 5, 5, 10, -20, 100],
  [-20, -50, -2, -2, -2, -2, -50, -20],
  [10, -2, -1, -1, -1, -1, -2, 10],
  [5, -2, -1, -1, -1, -1, -2, 5],
];

/// Square weights; rows 4-7 mirror rows 3-0.
final List<int> reversiWeights = List.unmodifiable([..._half, ..._half.reversed].expand((r) => r));

final String reversiStartBoard = () {
  final b = List.filled(64, '.');
  b[27] = 'o';
  b[36] = 'o';
  b[28] = 'x';
  b[35] = 'x';
  return b.join();
}();

Int8List _parse(String board) {
  final b = Int8List(64);
  for (var i = 0; i < 64; i++) {
    b[i] = board[i] == 'x'
        ? 1
        : board[i] == 'o'
        ? -1
        : 0;
  }
  return b;
}

String _boardString(Int8List b) {
  final s = StringBuffer();
  for (var i = 0; i < 64; i++) {
    s.write(
      b[i] == 1
          ? 'x'
          : b[i] == -1
          ? 'o'
          : '.',
    );
  }
  return s.toString();
}

/// Flips caused by [s] on empty [cell] (does not modify b), [] when illegal.
List<int> _flipsOf(Int8List b, int s, int cell) {
  if (b[cell] != 0) return const [];
  final out = <int>[];
  final r0 = cell >> 3, c0 = cell & 7;
  for (final (dr, dc) in _dirs) {
    var r = r0 + dr, c = c0 + dc;
    final run = <int>[];
    while (r >= 0 && r < 8 && c >= 0 && c < 8 && b[r * 8 + c] == -s) {
      run.add(r * 8 + c);
      r += dr;
      c += dc;
    }
    if (run.isNotEmpty && r >= 0 && r < 8 && c >= 0 && c < 8 && b[r * 8 + c] == s) out.addAll(run);
  }
  return out;
}

/// Legal cells of [s] ascending; [-1] (pass) when there are none.
List<int> _moves(Int8List b, int s) {
  final out = <int>[];
  for (var i = 0; i < 64; i++) {
    if (b[i] == 0 && _flipsOf(b, s, i).isNotEmpty) out.add(i);
  }
  return out.isEmpty ? const [-1] : out;
}

int _count(Int8List b, int s) {
  var n = 0;
  for (var i = 0; i < 64; i++) {
    if (b[i] == s) n++;
  }
  return n;
}

/// End of game with [s] to move: full board, two passes, or [s] has no disc.
bool _ended(Int8List b, int s, int passes) {
  if (passes >= 2) return true;
  var empty = false;
  for (var i = 0; i < 64; i++) {
    if (b[i] == 0) {
      empty = true;
      break;
    }
  }
  return !empty || _count(b, s) == 0;
}

const _inf = 1 << 30;

int _search(Int8List b, int s, int passes, int depth, int alpha, int beta) {
  if (_ended(b, s, passes)) {
    final d = _count(b, s) - _count(b, -s);
    return 100000 * d.sign + d;
  }
  if (depth == 0) {
    var v = 0;
    for (var i = 0; i < 64; i++) {
      v += reversiWeights[i] * b[i] * s;
    }
    return v;
  }
  var best = -_inf;
  for (final cell in _moves(b, s)) {
    final child = Int8List.fromList(b);
    var p = 0;
    if (cell >= 0) {
      for (final f in _flipsOf(child, s, cell)) {
        child[f] = s;
      }
      child[cell] = s;
    } else {
      p = passes + 1;
    }
    final v = -_search(child, -s, p, depth - 1, -beta, -alpha);
    if (v > best) best = v;
    if (v > alpha) alpha = v;
    if (alpha >= beta) break;
  }
  return best;
}

String _other(String s) => s == 'player' ? 'ai' : 'player';
int _sign(String s) => s == 'player' ? 1 : -1;

/// Discs of [side] ('player' or 'ai') on [board].
int discs(String board, String side) {
  final ch = side == 'player' ? 'x' : 'o';
  var n = 0;
  for (var i = 0; i < board.length; i++) {
    if (board[i] == ch) n++;
  }
  return n;
}

class ReversiRules extends MgRules<ReversiState, ReversiAction, ReversiResult> {
  ReversiConfig? _cfg;
  ReversiConfig get _c => _cfg ?? (throw StateError('reversi: init first'));

  @override
  String get id => 'reversi';

  @override
  int get specVersion => 1;

  @override
  ReversiState init(Map<String, Object?> config, int seed) => start(ReversiConfig.fromJson(config), seed);

  ReversiState start(ReversiConfig config, int seed) {
    _cfg = config;
    return ReversiState(
      board: reversiStartBoard,
      turn: 'player',
      plies: 0,
      passes: 0,
      over: false,
      winner: '',
      byCount: false,
      rng: Prng(seed).state,
    );
  }

  @override
  List<ReversiAction> legalActions(ReversiState s) {
    if (s.over) return const [];
    return [for (final cell in _moves(_parse(s.board), _sign(s.turn))) ReversiAction(s.turn, cell)];
  }

  @override
  ReversiState apply(ReversiState s, ReversiAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(over: true, byCount: true, winner: _leader(s.board));
    if (a.by != s.turn) throw IllegalAction(id, a);
    final b = _parse(s.board);
    final sg = _sign(s.turn);
    if (!_moves(b, sg).contains(a.cell)) throw IllegalAction(id, a);
    var plies = s.plies, passes = s.passes;
    if (a.cell >= 0) {
      for (final f in _flipsOf(b, sg, a.cell)) {
        b[f] = sg;
      }
      b[a.cell] = sg;
      plies++;
      passes = 0;
    } else {
      passes++;
    }
    final board = _boardString(b);
    final n = s.copyWith(board: board, turn: _other(s.turn), plies: plies, passes: passes);
    if (_ended(b, -sg, passes)) return n.copyWith(over: true, winner: _leader(board));
    return n;
  }

  String _leader(String board) {
    final p = discs(board, 'player'), q = discs(board, 'ai');
    return p > q
        ? 'player'
        : q > p
        ? 'ai'
        : 'draw';
  }

  @override
  ReversiAction aiAction(ReversiState s, int level, Prng ai) {
    if (s.over) throw IllegalAction(id, {'by': s.turn});
    final c = _c;
    final b = _parse(s.board);
    final sg = _sign(s.turn);
    final legal = _moves(b, sg);
    final lv = level.clamp(1, c.aiErrorPct.length);
    final err = c.aiErrorPct[lv - 1];
    final d = c.aiDepth[lv.clamp(1, c.aiDepth.length) - 1];
    final depth = d < 1 ? 1 : d;
    final r = ai.nextInt(100);
    if (r < err) return ReversiAction(s.turn, legal[ai.nextInt(legal.length)]);
    var best = -_inf, bestI = 0, alpha = -_inf;
    for (var i = 0; i < legal.length; i++) {
      final cell = legal[i];
      final child = Int8List.fromList(b);
      var p = 0;
      if (cell >= 0) {
        for (final f in _flipsOf(child, sg, cell)) {
          child[f] = sg;
        }
        child[cell] = sg;
      } else {
        p = s.passes + 1;
      }
      final v = -_search(child, -sg, p, depth - 1, -_inf, -alpha);
      if (v > best) {
        best = v;
        bestI = i;
      }
      if (v > alpha) alpha = v;
    }
    return ReversiAction(s.turn, legal[bestI]);
  }

  @override
  ReversiResult? result(ReversiState s) {
    if (!s.over) return null;
    final winner = s.winner == '' ? 'draw' : s.winner;
    final player = discs(s.board, 'player'), ai = discs(s.board, 'ai');
    final stars = winner != 'player'
        ? 0
        : s.byCount
        ? 1
        : player - ai >= _c.star3Margin
        ? 3
        : 2;
    return ReversiResult(winner: winner, stars: stars, score: player * 10, byCount: s.byCount, player: player, ai: ai);
  }

  @override
  ReversiAction actionFromJson(Map<String, Object?> j) =>
      j['by'] == 'timeout' ? const ReversiAction.timeout() : ReversiAction(j['by'] as String, j['cell'] as int);

  @override
  Map<String, Object?> stateToJson(ReversiState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(ReversiResult r) => r.toJson();
}
