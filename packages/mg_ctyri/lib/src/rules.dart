import 'dart:typed_data';

import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/ctyri.md, version 1. Pure Dart: no Flutter imports here.
class CtyriConfig {
  const CtyriConfig({required this.aiDepth, required this.aiErrorPct, required this.fastMoves});

  factory CtyriConfig.fromTuning(TuningMinigamesCtyri t) => CtyriConfig(
    aiDepth: List.unmodifiable(t.aiDepth),
    aiErrorPct: List.unmodifiable(t.aiErrorPct),
    fastMoves: t.fastMoves,
  );

  factory CtyriConfig.fromJson(Map<String, Object?> j) => CtyriConfig(
    aiDepth: List.unmodifiable((j['aiDepth'] as List).cast<int>()),
    aiErrorPct: List.unmodifiable((j['aiErrorPct'] as List).cast<int>()),
    fastMoves: j['fastMoves'] as int,
  );

  final List<int> aiDepth, aiErrorPct;
  final int fastMoves;
}

class CtyriState {
  const CtyriState({
    required this.board,
    required this.turn,
    required this.moves,
    required this.over,
    required this.winner,
    required this.rng,
  });

  /// 42 chars, row 0 on top: '.', 'x' (player), 'o' (AI).
  final String board;

  /// 'player' or 'ai'.
  final String turn;

  /// Player moves so far.
  final int moves;
  final bool over;

  /// '' while the game runs, then 'player', 'ai' or 'draw'.
  final String winner;
  final int rng;

  CtyriState copyWith({String? board, String? turn, int? moves, bool? over, String? winner}) => CtyriState(
    board: board ?? this.board,
    turn: turn ?? this.turn,
    moves: moves ?? this.moves,
    over: over ?? this.over,
    winner: winner ?? this.winner,
    rng: rng,
  );

  Map<String, Object?> toJson() => {
    'board': board,
    'turn': turn,
    'moves': moves,
    'over': over,
    'winner': winner,
    'rng': rng,
  };
}

/// {by: player|ai, col} or {by: timeout} (col -1).
class CtyriAction {
  const CtyriAction(this.by, this.col);
  const CtyriAction.timeout() : by = 'timeout', col = -1;

  final String by;
  final int col;

  Map<String, Object?> toJson() => by == 'timeout' ? {'by': by} : {'by': by, 'col': col};

  @override
  bool operator ==(Object other) => other is CtyriAction && other.by == by && other.col == col;

  @override
  int get hashCode => Object.hash(by, col);

  @override
  String toString() => toJson().toString();
}

class CtyriResult {
  const CtyriResult({required this.winner, required this.stars, required this.score, required this.moves});

  final String winner;
  final int stars, score, moves;

  Map<String, Object?> toJson() => {'winner': winner, 'stars': stars, 'score': score, 'moves': moves};
}

const cols = 7;
const rows = 6;
const _n = cols * rows;
const _dirs = [(0, 1), (1, 0), (1, 1), (1, -1)];

/// The 69 windows of four cells (horizontal, vertical, both diagonals).
final List<List<int>> windows = () {
  final w = <List<int>>[];
  for (final (dr, dc) in _dirs) {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final er = r + 3 * dr, ec = c + 3 * dc;
        if (er < 0 || er >= rows || ec < 0 || ec >= cols) continue;
        w.add(List.unmodifiable([for (var k = 0; k < 4; k++) (r + k * dr) * cols + c + k * dc]));
      }
    }
  }
  return List<List<int>>.unmodifiable(w);
}();

// Search board: +1 player, -1 AI, 0 empty.
Int8List _parse(String board) {
  final b = Int8List(_n);
  for (var i = 0; i < _n; i++) {
    b[i] = board[i] == 'x'
        ? 1
        : board[i] == 'o'
        ? -1
        : 0;
  }
  return b;
}

/// Row a token dropped into [col] lands on, or -1 when the column is full.
int _landing(Int8List b, int col) {
  for (var r = rows - 1; r >= 0; r--) {
    if (b[r * cols + col] == 0) return r;
  }
  return -1;
}

List<int> _winLine(Int8List b, int cell) {
  final s = b[cell];
  if (s == 0) return const [];
  final r0 = cell ~/ cols, c0 = cell % cols;
  for (final (dr, dc) in _dirs) {
    final line = [cell];
    for (final sg in const [1, -1]) {
      var r = r0 + dr * sg, c = c0 + dc * sg;
      while (r >= 0 && r < rows && c >= 0 && c < cols && b[r * cols + c] == s) {
        line.add(r * cols + c);
        r += dr * sg;
        c += dc * sg;
      }
    }
    if (line.length >= 4) return line..sort();
  }
  return const [];
}

bool _wins(Int8List b, int cell) => _winLine(b, cell).isNotEmpty;

/// The winning four through [cell] (UI highlight).
List<int> winningLine(String board, int cell) => _winLine(_parse(board), cell);

/// Leaf evaluation from the side [s] to move.
int _evaluate(Int8List b, int s) {
  var v = 0;
  for (final w in windows) {
    var own = 0, opp = 0;
    for (final i in w) {
      final p = b[i] * s;
      if (p > 0) {
        own++;
      } else if (p < 0) {
        opp++;
      }
    }
    if (opp == 0) {
      v += own == 3
          ? 50
          : own == 2
          ? 5
          : 0;
    } else if (own == 0) {
      v -= opp == 3
          ? 60
          : opp == 2
          ? 5
          : 0;
    }
  }
  for (var r = 0; r < rows; r++) {
    v += 3 * b[r * cols + 3] * s;
  }
  return v;
}

const _loss = 100000;
const _inf = 1 << 30;

/// Negamax with alpha-beta; [last] is the cell the opponent just played (-1 at the root).
int _search(Int8List b, int s, int last, int filled, int depth, int alpha, int beta) {
  if (last >= 0 && _wins(b, last)) return -(_loss + depth);
  if (filled == _n) return 0;
  if (depth == 0) return _evaluate(b, s);
  var best = -_inf;
  for (var c = 0; c < cols; c++) {
    final r = _landing(b, c);
    if (r < 0) continue;
    final i = r * cols + c;
    b[i] = s;
    final v = -_search(b, -s, i, filled + 1, depth - 1, -beta, -alpha);
    b[i] = 0;
    if (v > best) best = v;
    if (v > alpha) alpha = v;
    if (alpha >= beta) break;
  }
  return best;
}

String _other(String s) => s == 'player' ? 'ai' : 'player';
int _sign(String s) => s == 'player' ? 1 : -1;

class CtyriRules extends MgRules<CtyriState, CtyriAction, CtyriResult> {
  CtyriConfig? _cfg;

  CtyriConfig get _c => _cfg ?? (throw StateError('ctyri: init first'));

  @override
  String get id => 'ctyri';

  @override
  int get specVersion => 1;

  /// Starts a game; [config] is the vector form (see [CtyriConfig.fromJson]).
  @override
  CtyriState init(Map<String, Object?> config, int seed) => start(CtyriConfig.fromJson(config), seed);

  CtyriState start(CtyriConfig config, int seed) {
    _cfg = config;
    return CtyriState(board: '.' * _n, turn: 'player', moves: 0, over: false, winner: '', rng: Prng(seed).state);
  }

  @override
  List<CtyriAction> legalActions(CtyriState s) {
    if (s.over) return const [];
    return [
      for (var c = 0; c < cols; c++)
        if (s.board[c] == '.') CtyriAction(s.turn, c),
    ];
  }

  /// The cell a token dropped into [col] lands on, or -1 (UI).
  int landingCell(CtyriState s, int col) {
    final r = _landing(_parse(s.board), col);
    return r < 0 ? -1 : r * cols + col;
  }

  @override
  CtyriState apply(CtyriState s, CtyriAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(over: true, winner: 'draw');
    final b = _parse(s.board);
    if (a.by != s.turn || a.col < 0 || a.col >= cols) throw IllegalAction(id, a);
    final r = _landing(b, a.col);
    if (r < 0) throw IllegalAction(id, a);
    final cell = r * cols + a.col;
    b[cell] = _sign(s.turn);
    final board = s.board.replaceRange(cell, cell + 1, s.turn == 'player' ? 'x' : 'o');
    final moves = s.turn == 'player' ? s.moves + 1 : s.moves;
    if (_wins(b, cell)) return s.copyWith(board: board, moves: moves, over: true, winner: s.turn);
    if (!board.contains('.')) return s.copyWith(board: board, moves: moves, over: true, winner: 'draw');
    return s.copyWith(board: board, moves: moves, turn: _other(s.turn));
  }

  @override
  CtyriAction aiAction(CtyriState s, int level, Prng ai) {
    final legal = legalActions(s);
    if (legal.isEmpty) throw IllegalAction(id, {'by': s.turn});
    final c = _c;
    final lv = level.clamp(1, c.aiErrorPct.length);
    final err = c.aiErrorPct[lv - 1];
    final d = c.aiDepth[lv.clamp(1, c.aiDepth.length) - 1];
    final depth = d < 1 ? 1 : d;
    final r = ai.nextInt(100);
    if (r < err) return legal[ai.nextInt(legal.length)];
    final b = _parse(s.board);
    final sg = _sign(s.turn);
    var filled = 0;
    for (var i = 0; i < _n; i++) {
      if (b[i] != 0) filled++;
    }
    // Root window (alpha, +inf); a new best only on a strictly higher value (Upřesnění v1).
    var best = -_inf, bestI = 0, alpha = -_inf;
    for (var k = 0; k < legal.length; k++) {
      final col = legal[k].col;
      final i = _landing(b, col) * cols + col;
      b[i] = sg;
      final v = -_search(b, -sg, i, filled + 1, depth - 1, -_inf, -alpha);
      b[i] = 0;
      if (v > best) {
        best = v;
        bestI = k;
      }
      if (v > alpha) alpha = v;
    }
    return legal[bestI];
  }

  @override
  CtyriResult? result(CtyriState s) {
    if (!s.over) return null;
    final winner = s.winner.isEmpty ? 'draw' : s.winner;
    var tokens = 0;
    for (var i = 0; i < s.board.length; i++) {
      if (s.board[i] != '.') tokens++;
    }
    final win = winner == 'player';
    return CtyriResult(
      winner: winner,
      stars: win ? (s.moves <= _c.fastMoves ? 3 : 2) : 0,
      score: win ? (_n - tokens) * 20 : 0,
      moves: s.moves,
    );
  }

  @override
  CtyriAction actionFromJson(Map<String, Object?> json) =>
      json['by'] == 'timeout' ? const CtyriAction.timeout() : CtyriAction(json['by'] as String, json['col'] as int);

  @override
  Map<String, Object?> stateToJson(CtyriState state) => state.toJson();

  @override
  Map<String, Object?> resultToJson(CtyriResult result) => result.toJson();
}
