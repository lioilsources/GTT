import 'dart:typed_data';

import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/dama.md, version 1. Pure Dart: no Flutter imports here.
class DamaConfig {
  const DamaConfig({
    required this.aiDepth,
    required this.aiErrorPct,
    required this.quietLimit,
    required this.fastPlies,
  });

  factory DamaConfig.fromTuning(TuningMinigamesDama t) => DamaConfig(
    aiDepth: List.unmodifiable(t.aiDepth),
    aiErrorPct: List.unmodifiable(t.aiErrorPct),
    quietLimit: t.quietLimit,
    fastPlies: t.fastPlies,
  );

  factory DamaConfig.fromJson(Map<String, Object?> j) => DamaConfig(
    aiDepth: List.unmodifiable((j['aiDepth'] as List).cast<int>()),
    aiErrorPct: List.unmodifiable((j['aiErrorPct'] as List).cast<int>()),
    quietLimit: j['quietLimit'] as int,
    fastPlies: j['fastPlies'] as int,
  );

  final List<int> aiDepth, aiErrorPct;
  final int quietLimit, fastPlies;
}

class DamaState {
  const DamaState({
    required this.board,
    required this.turn,
    required this.plies,
    required this.quiet,
    required this.over,
    required this.winner,
    required this.byMaterial,
    required this.rng,
  });

  /// 32 dark squares, rows from the AI side: '.', 'w', 'W' (player), 'b', 'B' (AI).
  final String board;

  /// 'player' or 'ai'.
  final String turn;
  final int plies, quiet;
  final bool over;

  /// '' while the game runs, then 'player', 'ai' or 'draw'.
  final String winner;
  final bool byMaterial;
  final int rng;

  DamaState copyWith({
    String? board,
    String? turn,
    int? plies,
    int? quiet,
    bool? over,
    String? winner,
    bool? byMaterial,
  }) => DamaState(
    board: board ?? this.board,
    turn: turn ?? this.turn,
    plies: plies ?? this.plies,
    quiet: quiet ?? this.quiet,
    over: over ?? this.over,
    winner: winner ?? this.winner,
    byMaterial: byMaterial ?? this.byMaterial,
    rng: rng,
  );

  Map<String, Object?> toJson() => {
    'board': board,
    'turn': turn,
    'plies': plies,
    'quiet': quiet,
    'over': over,
    'winner': winner,
    'byMaterial': byMaterial,
    'rng': rng,
  };
}

/// {by: player|ai, path} or {by: timeout} (empty path).
class DamaAction {
  const DamaAction(this.by, this.path);
  const DamaAction.timeout() : by = 'timeout', path = const [];

  final String by;
  final List<int> path;

  Map<String, Object?> toJson() => by == 'timeout' ? {'by': by} : {'by': by, 'path': path};

  @override
  bool operator ==(Object other) => other is DamaAction && other.by == by && comparePaths(other.path, path) == 0;

  @override
  int get hashCode => Object.hash(by, Object.hashAll(path));

  @override
  String toString() => toJson().toString();
}

class DamaResult {
  const DamaResult({
    required this.winner,
    required this.stars,
    required this.score,
    required this.byMaterial,
    required this.plies,
  });

  final String winner;
  final int stars, score;
  final bool byMaterial;
  final int plies;

  Map<String, Object?> toJson() => {
    'winner': winner,
    'stars': stars,
    'score': score,
    'byMaterial': byMaterial,
    'plies': plies,
  };
}

// ---- Board geometry -------------------------------------------------------------------------

int rowOf(int i) => i >> 2;
int colOf(int i) => 2 * (i & 3) + (1 - (rowOf(i) & 1));

/// Square index of (r, c), or -1 for a light or off-board square.
int squareAt(int r, int c) {
  if (r < 0 || r > 7 || c < 0 || c > 7 || (r + c) & 1 == 0) return -1;
  return r * 4 + (c >> 1);
}

// Directions: 0 = up-left, 1 = up-right (player forward), 2 = down-left, 3 = down-right (AI forward).
const _dr = [-1, -1, 1, 1];
const _dc = [-1, 1, -1, 1];

/// _nb[i * 4 + d] = neighbour of square i in direction d, or -1.
final Int8List _nb = () {
  final t = Int8List(128);
  for (var i = 0; i < 32; i++) {
    for (var d = 0; d < 4; d++) {
      t[i * 4 + d] = squareAt(rowOf(i) + _dr[d], colOf(i) + _dc[d]);
    }
  }
  return t;
}();

// Pieces in the search board: +1/+2 player man/king, -1/-2 AI man/king, 0 empty. Side sign: player +1.
const _chars = ['B', 'b', '.', 'w', 'W'];

Int8List parseBoard(String s) {
  final b = Int8List(32);
  for (var i = 0; i < 32; i++) {
    b[i] = switch (s[i]) {
      'w' => 1,
      'W' => 2,
      'b' => -1,
      'B' => -2,
      _ => 0,
    };
  }
  return b;
}

String boardString(Int8List b) {
  final sb = StringBuffer();
  for (var i = 0; i < 32; i++) {
    sb.write(_chars[b[i] + 2]);
  }
  return sb.toString();
}

/// One move: the path of squares and the captured squares as a bit mask.
class DamaMove {
  const DamaMove(this.path, this.caps);
  final List<int> path;
  final int caps;
}

/// Appends every capture path of the piece on [from] (lifted from the board during the search).
void _capturesFrom(Int8List b, int from, int s, List<DamaMove> out) {
  final p = b[from];
  final king = p == 2 || p == -2;
  b[from] = 0;
  final path = [from];
  final d0 = s > 0 ? 0 : 2;
  void dfs(int cur, int caps) {
    var found = false;
    if (king) {
      for (var d = 0; d < 4; d++) {
        var m = _nb[cur * 4 + d];
        while (m >= 0 && b[m] == 0) {
          m = _nb[m * 4 + d];
        }
        if (m < 0 || b[m] * s >= 0 || caps & (1 << m) != 0) continue;
        for (var l = _nb[m * 4 + d]; l >= 0 && b[l] == 0; l = _nb[l * 4 + d]) {
          found = true;
          path.add(l);
          dfs(l, caps | (1 << m));
          path.removeLast();
        }
      }
    } else {
      for (var d = d0; d < d0 + 2; d++) {
        final m = _nb[cur * 4 + d];
        if (m < 0 || b[m] * s >= 0 || caps & (1 << m) != 0) continue;
        final l = _nb[m * 4 + d];
        if (l < 0 || b[l] != 0) continue;
        found = true;
        path.add(l);
        dfs(l, caps | (1 << m));
        path.removeLast();
      }
    }
    if (!found && path.length > 1) out.add(DamaMove(List.unmodifiable(path), caps));
  }

  dfs(from, 0);
  b[from] = p;
}

/// All legal moves of side [s] (+1 player, -1 AI) in generation order; captures are compulsory.
List<DamaMove> generate(Int8List b, int s) {
  final out = <DamaMove>[];
  for (var i = 0; i < 32; i++) {
    if (b[i] * s > 0) _capturesFrom(b, i, s, out);
  }
  if (out.isNotEmpty) return out;
  final d0 = s > 0 ? 0 : 2;
  for (var i = 0; i < 32; i++) {
    final p = b[i] * s;
    if (p <= 0) continue;
    if (p == 2) {
      for (var d = 0; d < 4; d++) {
        for (var l = _nb[i * 4 + d]; l >= 0 && b[l] == 0; l = _nb[l * 4 + d]) {
          out.add(DamaMove([i, l], 0));
        }
      }
    } else {
      for (var d = d0; d < d0 + 2; d++) {
        final l = _nb[i * 4 + d];
        if (l >= 0 && b[l] == 0) out.add(DamaMove([i, l], 0));
      }
    }
  }
  return out;
}

/// True when side [s] has at least one legal move (cheaper than generating them).
bool hasMove(Int8List b, int s) {
  final d0 = s > 0 ? 0 : 2;
  for (var i = 0; i < 32; i++) {
    final p = b[i] * s;
    if (p <= 0) continue;
    final lo = p == 2 ? 0 : d0, hi = p == 2 ? 4 : d0 + 2;
    for (var d = lo; d < hi; d++) {
      final m = _nb[i * 4 + d];
      if (m < 0) continue;
      if (b[m] == 0) return true;
      if (b[m] * s < 0) {
        final l = _nb[m * 4 + d];
        if (l >= 0 && b[l] == 0) return true;
      }
    }
  }
  return false;
}

int comparePaths(List<int> a, List<int> b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}

/// Legal moves in the canonical order of legalActions (paths lexicographically).
List<DamaMove> sortedMoves(Int8List b, int s) => generate(b, s)..sort((x, y) => comparePaths(x.path, y.path));

/// Plays [m] on [b] in place; returns true when the move resets the quiet counter.
bool playMove(Int8List b, DamaMove m, int s) {
  final from = m.path.first, to = m.path.last;
  var p = b[from];
  final man = p == s;
  b[from] = 0;
  for (var c = m.caps, i = 0; c != 0; i++, c >>= 1) {
    if (c & 1 != 0) b[i] = 0;
  }
  if (man && rowOf(to) == (s > 0 ? 0 : 7)) p = 2 * s;
  b[to] = p;
  return man || m.caps != 0;
}

/// Static evaluation from the side to move: 100 per man, 300 per king.
int _evaluate(Int8List b, int s) {
  var v = 0;
  for (var i = 0; i < 32; i++) {
    final p = b[i] * s;
    v += switch (p) {
      1 => 100,
      -1 => -100,
      2 => 300,
      -2 => -300,
      _ => 0,
    };
  }
  return v;
}

const _loss = 100000;
const _inf = 1 << 30;

/// Negamax with alpha-beta; boards per ply are preallocated in [stack].
int _search(List<Int8List> stack, int ply, int s, int quiet, int depth, int alpha, int beta, int limit) {
  final b = stack[ply];
  if (depth == 0) {
    if (!hasMove(b, s)) return -_loss;
    if (quiet >= limit) return 0;
    return _evaluate(b, s);
  }
  final moves = generate(b, s);
  if (moves.isEmpty) return -(_loss + depth);
  if (quiet >= limit) return 0;
  final child = stack[ply + 1];
  var best = -_inf;
  for (final m in moves) {
    child.setAll(0, b);
    final q = playMove(child, m, s) ? 0 : quiet + 1;
    final v = -_search(stack, ply + 1, -s, q, depth - 1, -beta, -alpha, limit);
    if (v > best) best = v;
    if (v > alpha) alpha = v;
    if (alpha >= beta) break;
  }
  return best;
}

String _other(String side) => side == 'player' ? 'ai' : 'player';
int _sign(String side) => side == 'player' ? 1 : -1;

int _material(Int8List b, int s) {
  var v = 0;
  for (var i = 0; i < 32; i++) {
    final p = b[i] * s;
    if (p > 0) v += p == 2 ? 3 : 1;
  }
  return v;
}

int countPieces(String board, String side) {
  final m = side == 'player' ? 'w' : 'b', k = side == 'player' ? 'W' : 'B';
  var n = 0;
  for (var i = 0; i < board.length; i++) {
    if (board[i] == m || board[i] == k) n++;
  }
  return n;
}

/// True when the side to move must capture (UI hint).
bool mustCapture(DamaState s) {
  if (s.over) return false;
  final m = generate(parseBoard(s.board), _sign(s.turn));
  return m.isNotEmpty && m.first.caps != 0;
}

final String startBoard = '${'b' * 12}${'.' * 8}${'w' * 12}';

class DamaRules extends MgRules<DamaState, DamaAction, DamaResult> {
  DamaConfig? _cfg;

  DamaConfig get _c => _cfg ?? (throw StateError('dama: init first'));

  @override
  String get id => 'dama';

  @override
  int get specVersion => 1;

  /// Starts a game; [config] is the vector form (see [DamaConfig.fromJson]).
  @override
  DamaState init(Map<String, Object?> config, int seed) => start(DamaConfig.fromJson(config), seed);

  DamaState start(DamaConfig config, int seed) {
    _cfg = config;
    return DamaState(
      board: startBoard,
      turn: 'player',
      plies: 0,
      quiet: 0,
      over: false,
      winner: '',
      byMaterial: false,
      rng: Prng(seed).state,
    );
  }

  @override
  List<DamaAction> legalActions(DamaState s) {
    if (s.over) return const [];
    return [for (final m in sortedMoves(parseBoard(s.board), _sign(s.turn))) DamaAction(s.turn, m.path)];
  }

  @override
  DamaState apply(DamaState s, DamaAction a) {
    if (s.over) throw IllegalAction(id, a);
    final b = parseBoard(s.board);
    if (a.by == 'timeout') {
      final p = _material(b, 1), q = _material(b, -1);
      return s.copyWith(
        over: true,
        byMaterial: true,
        winner: p > q
            ? 'player'
            : q > p
            ? 'ai'
            : 'draw',
      );
    }
    if (a.by != s.turn) throw IllegalAction(id, a);
    final sg = _sign(s.turn);
    DamaMove? m;
    for (final x in generate(b, sg)) {
      if (comparePaths(x.path, a.path) == 0) {
        m = x;
        break;
      }
    }
    if (m == null) throw IllegalAction(id, a);
    final quiet = playMove(b, m, sg) ? 0 : s.quiet + 1;
    final n = s.copyWith(board: boardString(b), turn: _other(s.turn), plies: s.plies + 1, quiet: quiet);
    if (!hasMove(b, -sg)) return n.copyWith(over: true, winner: s.turn);
    if (quiet >= _c.quietLimit) return n.copyWith(over: true, winner: 'draw');
    return n;
  }

  @override
  DamaAction aiAction(DamaState s, int level, Prng ai) {
    final c = _c;
    final lv = level.clamp(1, c.aiErrorPct.length);
    final err = c.aiErrorPct[lv - 1];
    final d = c.aiDepth[lv.clamp(1, c.aiDepth.length) - 1];
    final depth = d < 1 ? 1 : d;
    final b = parseBoard(s.board);
    final sg = _sign(s.turn);
    final legal = sortedMoves(b, sg);
    if (legal.isEmpty) throw IllegalAction(id, {'by': s.turn});
    final r = ai.nextInt(100);
    if (r < err) return DamaAction(s.turn, legal[ai.nextInt(legal.length)].path);
    final stack = [for (var i = 0; i <= depth; i++) Int8List(32)];
    var best = -_inf, bestI = 0, alpha = -_inf;
    for (var i = 0; i < legal.length; i++) {
      final child = stack[1];
      child.setAll(0, b);
      final q = playMove(child, legal[i], sg) ? 0 : s.quiet + 1;
      final v = -_search(stack, 1, -sg, q, depth - 1, -_inf, -alpha, c.quietLimit);
      if (v > best) {
        best = v;
        bestI = i;
      }
      if (v > alpha) alpha = v;
    }
    return DamaAction(s.turn, legal[bestI].path);
  }

  @override
  DamaResult? result(DamaState s) {
    if (!s.over) return null;
    final winner = s.winner == '' ? 'draw' : s.winner;
    final stars = winner != 'player'
        ? 0
        : s.byMaterial
        ? 1
        : s.plies <= _c.fastPlies
        ? 3
        : 2;
    return DamaResult(
      winner: winner,
      stars: stars,
      score: 100 * (12 - countPieces(s.board, 'ai')),
      byMaterial: s.byMaterial,
      plies: s.plies,
    );
  }

  @override
  DamaAction actionFromJson(Map<String, Object?> j) => j['by'] == 'timeout'
      ? const DamaAction.timeout()
      : DamaAction(j['by'] as String, List.unmodifiable((j['path'] as List).cast<int>()));

  @override
  Map<String, Object?> stateToJson(DamaState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(DamaResult r) => r.toJson();
}
