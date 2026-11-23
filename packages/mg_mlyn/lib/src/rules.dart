import 'dart:typed_data';

import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/mlyn.md, version 1. Pure Dart: no Flutter imports here.
class MlynConfig {
  const MlynConfig({
    required this.aiDepth,
    required this.aiErrorPct,
    required this.quietLimit,
    required this.flying,
    required this.star3Pieces,
  });

  factory MlynConfig.fromTuning(TuningMinigamesMlyn t) => MlynConfig(
    aiDepth: List.unmodifiable(t.aiDepth),
    aiErrorPct: List.unmodifiable(t.aiErrorPct),
    quietLimit: t.quietLimit,
    flying: t.flying,
    star3Pieces: t.star3Pieces,
  );

  factory MlynConfig.fromJson(Map<String, Object?> j) => MlynConfig(
    aiDepth: List.unmodifiable((j['aiDepth'] as List).cast<int>()),
    aiErrorPct: List.unmodifiable((j['aiErrorPct'] as List).cast<int>()),
    quietLimit: j['quietLimit'] as int,
    flying: j['flying'] as bool,
    star3Pieces: j['star3Pieces'] as int,
  );

  final List<int> aiDepth, aiErrorPct;
  final int quietLimit;
  final bool flying;
  final int star3Pieces;
}

class MlynState {
  const MlynState({
    required this.board,
    required this.handPlayer,
    required this.handAi,
    required this.turn,
    required this.plies,
    required this.quiet,
    required this.over,
    required this.winner,
    required this.byPieces,
    required this.rng,
  });

  /// 24 points: '.', 'w' (player), 'b' (AI).
  final String board;

  /// Stones still to place.
  final int handPlayer, handAi;

  /// 'player' or 'ai'.
  final String turn;
  final int plies, quiet;
  final bool over;

  /// '' while the game runs, then 'player', 'ai' or 'draw'.
  final String winner;
  final bool byPieces;
  final int rng;

  int hand(String side) => side == 'player' ? handPlayer : handAi;

  MlynState copyWith({
    String? board,
    int? handPlayer,
    int? handAi,
    String? turn,
    int? plies,
    int? quiet,
    bool? over,
    String? winner,
    bool? byPieces,
  }) => MlynState(
    board: board ?? this.board,
    handPlayer: handPlayer ?? this.handPlayer,
    handAi: handAi ?? this.handAi,
    turn: turn ?? this.turn,
    plies: plies ?? this.plies,
    quiet: quiet ?? this.quiet,
    over: over ?? this.over,
    winner: winner ?? this.winner,
    byPieces: byPieces ?? this.byPieces,
    rng: rng,
  );

  Map<String, Object?> toJson() => {
    'board': board,
    'hand': {'player': handPlayer, 'ai': handAi},
    'turn': turn,
    'plies': plies,
    'quiet': quiet,
    'over': over,
    'winner': winner,
    'byPieces': byPieces,
    'rng': rng,
  };
}

/// {by: player|ai, from, to, remove} or {by: timeout}.
class MlynAction {
  const MlynAction(this.by, this.from, this.to, this.remove);
  const MlynAction.timeout() : by = 'timeout', from = -1, to = -1, remove = -1;

  final String by;
  final int from, to, remove;

  Map<String, Object?> toJson() =>
      by == 'timeout' ? {'by': by} : {'by': by, 'from': from, 'to': to, 'remove': remove};

  @override
  bool operator ==(Object other) =>
      other is MlynAction && other.by == by && other.from == from && other.to == to && other.remove == remove;

  @override
  int get hashCode => Object.hash(by, from, to, remove);

  @override
  String toString() => toJson().toString();
}

class MlynResult {
  const MlynResult({
    required this.winner,
    required this.stars,
    required this.score,
    required this.byPieces,
    required this.plies,
  });

  final String winner;
  final int stars, score;
  final bool byPieces;
  final int plies;

  Map<String, Object?> toJson() => {
    'winner': winner,
    'stars': stars,
    'score': score,
    'byPieces': byPieces,
    'plies': plies,
  };
}

// ---- Board geometry -------------------------------------------------------------------------

/// The 16 mills in spec order.
const List<List<int>> mills = [
  [0, 1, 2], [3, 4, 5], [6, 7, 8], [9, 10, 11], [12, 13, 14], [15, 16, 17], [18, 19, 20], [21, 22, 23], //
  [0, 9, 21], [3, 10, 18], [6, 11, 15], [1, 4, 7], [16, 19, 22], [8, 12, 17], [5, 13, 20], [2, 14, 23],
];

/// adjacency[p] = neighbours of point p, ascending.
final List<List<int>> adjacency = () {
  final a = [for (var i = 0; i < 24; i++) <int>{}];
  for (final m in mills) {
    a[m[0]].add(m[1]);
    a[m[1]]
      ..add(m[0])
      ..add(m[2]);
    a[m[2]].add(m[1]);
  }
  return [for (final s in a) List<int>.unmodifiable(s.toList()..sort())];
}();

final List<List<int>> _millsOf = () {
  final m = [for (var i = 0; i < 24; i++) <int>[]];
  for (var k = 0; k < mills.length; k++) {
    for (final p in mills[k]) {
      m[p].add(k);
    }
  }
  return m;
}();

// ---- Search position (mutable, cheap) -------------------------------------------------------

/// Board as +1 player / -1 AI / 0 empty; hand[0] player, hand[1] AI.
class _Pos {
  _Pos(this.b, this.hand);
  final Int8List b;
  final List<int> hand;
  _Pos clone() => _Pos(Int8List.fromList(b), [hand[0], hand[1]]);
}

int _hi(int s) => s > 0 ? 0 : 1;

bool _inMill(Int8List b, int p) {
  final s = b[p];
  if (s == 0) return false;
  for (final k in _millsOf[p]) {
    final m = mills[k];
    if (b[m[0]] == s && b[m[1]] == s && b[m[2]] == s) return true;
  }
  return false;
}

int _count(Int8List b, int s) {
  var n = 0;
  for (var i = 0; i < 24; i++) {
    if (b[i] == s) n++;
  }
  return n;
}

int _closedMills(Int8List b, int s) {
  var n = 0;
  for (final m in mills) {
    if (b[m[0]] == s && b[m[1]] == s && b[m[2]] == s) n++;
  }
  return n;
}

/// Points of the opponent of [s] that a mill may take, ascending (none on board → [-1]).
List<int> _removable(Int8List b, int s) {
  final out = <int>[], all = <int>[];
  for (var i = 0; i < 24; i++) {
    if (b[i] != -s) continue;
    all.add(i);
    if (!_inMill(b, i)) out.add(i);
  }
  if (out.isNotEmpty) return out;
  return all.isNotEmpty ? all : const [-1];
}

/// (from, to) pairs of side [s] ignoring removals, in (from, to) order.
List<(int, int)> _steps(_Pos pos, int s, bool flying) {
  final b = pos.b;
  final out = <(int, int)>[];
  if (pos.hand[_hi(s)] > 0) {
    for (var t = 0; t < 24; t++) {
      if (b[t] == 0) out.add((-1, t));
    }
    return out;
  }
  final fly = flying && _count(b, s) == 3;
  for (var f = 0; f < 24; f++) {
    if (b[f] != s) continue;
    if (fly) {
      for (var t = 0; t < 24; t++) {
        if (b[t] == 0) out.add((f, t));
      }
    } else {
      for (final t in adjacency[f]) {
        if (b[t] == 0) out.add((f, t));
      }
    }
  }
  return out;
}

typedef _Move = ({int from, int to, int remove});

/// Every legal move of [s] in (from, to, remove) order.
List<_Move> _generate(_Pos pos, int s, bool flying) {
  final out = <_Move>[];
  final b = pos.b;
  for (final (f, t) in _steps(pos, s, flying)) {
    if (f >= 0) b[f] = 0;
    b[t] = s;
    if (_inMill(b, t)) {
      for (final r in _removable(b, s)) {
        out.add((from: f, to: t, remove: r));
      }
    } else {
      out.add((from: f, to: t, remove: -1));
    }
    b[t] = 0;
    if (f >= 0) b[f] = s;
  }
  return out;
}

/// Plays [m] in place; returns true when it closed a mill.
bool _play(_Pos pos, _Move m, int s) {
  final b = pos.b;
  if (m.from >= 0) {
    b[m.from] = 0;
  } else {
    pos.hand[_hi(s)]--;
  }
  b[m.to] = s;
  final mill = _inMill(b, m.to);
  if (mill && m.remove >= 0) b[m.remove] = 0;
  return mill;
}

/// True when side [s] to move has lost: placing done and under 3 stones, or no legal move.
bool _lost(_Pos pos, int s, bool flying) {
  if (pos.hand[_hi(s)] == 0 && _count(pos.b, s) < 3) return true;
  return _steps(pos, s, flying).isEmpty;
}

int _evaluate(_Pos pos, int s, bool flying) {
  final b = pos.b;
  final own = _count(b, s) + pos.hand[_hi(s)], opp = _count(b, -s) + pos.hand[_hi(-s)];
  var v = 100 * (own - opp) + 10 * (_closedMills(b, s) - _closedMills(b, -s));
  if (pos.hand[0] == 0 && pos.hand[1] == 0) {
    v += _steps(pos, s, flying).length - _steps(pos, -s, flying).length;
  }
  return v;
}

const _loss = 100000;
const _inf = 1 << 30;

int _search(_Pos pos, int s, int quiet, int depth, int alpha, int beta, MlynConfig c) {
  if (_lost(pos, s, c.flying)) return -(_loss + depth);
  if (quiet >= c.quietLimit) return 0;
  if (depth == 0) return _evaluate(pos, s, c.flying);
  var best = -_inf;
  for (final m in _generate(pos, s, c.flying)) {
    final child = pos.clone();
    final mill = _play(child, m, s);
    final q = mill
        ? 0
        : m.from >= 0
        ? quiet + 1
        : quiet;
    final v = -_search(child, -s, q, depth - 1, -beta, -alpha, c);
    if (v > best) best = v;
    if (v > alpha) alpha = v;
    if (alpha >= beta) break;
  }
  return best;
}

String _other(String s) => s == 'player' ? 'ai' : 'player';
int _sign(String s) => s == 'player' ? 1 : -1;

_Pos _toPos(MlynState s) {
  final b = Int8List(24);
  for (var i = 0; i < 24; i++) {
    b[i] = s.board[i] == 'w'
        ? 1
        : s.board[i] == 'b'
        ? -1
        : 0;
  }
  return _Pos(b, [s.handPlayer, s.handAi]);
}

String _boardString(Int8List b) => [
  for (var i = 0; i < 24; i++)
    b[i] == 1
        ? 'w'
        : b[i] == -1
        ? 'b'
        : '.',
].join();

/// Stones of a side on the board.
int stones(String board, String side) {
  final ch = side == 'player' ? 'w' : 'b';
  var n = 0;
  for (var i = 0; i < board.length; i++) {
    if (board[i] == ch) n++;
  }
  return n;
}

class MlynRules extends MgRules<MlynState, MlynAction, MlynResult> {
  MlynConfig? _cfg;

  MlynConfig get _c => _cfg ?? (throw StateError('mlyn: init first'));

  @override
  String get id => 'mlyn';

  @override
  int get specVersion => 1;

  /// Starts a game; [config] is the vector form (see [MlynConfig.fromJson]).
  @override
  MlynState init(Map<String, Object?> config, int seed) => start(MlynConfig.fromJson(config), seed);

  MlynState start(MlynConfig config, int seed) {
    _cfg = config;
    return MlynState(
      board: '.' * 24,
      handPlayer: 9,
      handAi: 9,
      turn: 'player',
      plies: 0,
      quiet: 0,
      over: false,
      winner: '',
      byPieces: false,
      rng: Prng(seed).state,
    );
  }

  @override
  List<MlynAction> legalActions(MlynState s) {
    if (s.over) return const [];
    return [
      for (final m in _generate(_toPos(s), _sign(s.turn), _c.flying)) MlynAction(s.turn, m.from, m.to, m.remove),
    ];
  }

  @override
  MlynState apply(MlynState s, MlynAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') {
      final p = stones(s.board, 'player') + s.handPlayer, q = stones(s.board, 'ai') + s.handAi;
      return s.copyWith(
        over: true,
        byPieces: true,
        winner: p > q
            ? 'player'
            : q > p
            ? 'ai'
            : 'draw',
      );
    }
    if (a.by != s.turn) throw IllegalAction(id, a);
    final pos = _toPos(s);
    final sg = _sign(s.turn);
    _Move? m;
    for (final x in _generate(pos, sg, _c.flying)) {
      if (x.from == a.from && x.to == a.to && x.remove == a.remove) {
        m = x;
        break;
      }
    }
    if (m == null) throw IllegalAction(id, a);
    final mill = _play(pos, m, sg);
    final quiet = mill
        ? 0
        : m.from >= 0
        ? s.quiet + 1
        : s.quiet;
    final n = s.copyWith(
      board: _boardString(pos.b),
      handPlayer: pos.hand[0],
      handAi: pos.hand[1],
      turn: _other(s.turn),
      plies: s.plies + 1,
      quiet: quiet,
    );
    if (_lost(pos, -sg, _c.flying)) return n.copyWith(over: true, winner: s.turn);
    if (quiet >= _c.quietLimit) return n.copyWith(over: true, winner: 'draw');
    return n;
  }

  @override
  MlynAction aiAction(MlynState s, int level, Prng ai) {
    final c = _c;
    final pos = _toPos(s);
    final sg = _sign(s.turn);
    final legal = _generate(pos, sg, c.flying);
    if (s.over || legal.isEmpty) throw IllegalAction(id, {'by': s.turn});
    final lv = level.clamp(1, c.aiErrorPct.length);
    final err = c.aiErrorPct[lv - 1];
    final d = c.aiDepth[lv.clamp(1, c.aiDepth.length) - 1];
    final depth = d < 1 ? 1 : d;
    final r = ai.nextInt(100);
    if (r < err) {
      final m = legal[ai.nextInt(legal.length)];
      return MlynAction(s.turn, m.from, m.to, m.remove);
    }
    var best = -_inf, bestI = 0, alpha = -_inf;
    for (var i = 0; i < legal.length; i++) {
      final m = legal[i];
      final child = pos.clone();
      final mill = _play(child, m, sg);
      final q = mill
          ? 0
          : m.from >= 0
          ? s.quiet + 1
          : s.quiet;
      final v = -_search(child, -sg, q, depth - 1, -_inf, -alpha, c);
      if (v > best) {
        best = v;
        bestI = i;
      }
      if (v > alpha) alpha = v;
    }
    final m = legal[bestI];
    return MlynAction(s.turn, m.from, m.to, m.remove);
  }

  @override
  MlynResult? result(MlynState s) {
    if (!s.over) return null;
    final winner = s.winner == '' ? 'draw' : s.winner;
    final stars = winner != 'player'
        ? 0
        : s.byPieces
        ? 1
        : stones(s.board, 'player') >= _c.star3Pieces
        ? 3
        : 2;
    return MlynResult(
      winner: winner,
      stars: stars,
      score: 100 * (9 - stones(s.board, 'ai') - s.handAi),
      byPieces: s.byPieces,
      plies: s.plies,
    );
  }

  @override
  MlynAction actionFromJson(Map<String, Object?> j) => j['by'] == 'timeout'
      ? const MlynAction.timeout()
      : MlynAction(j['by'] as String, j['from'] as int, j['to'] as int, j['remove'] as int);

  @override
  Map<String, Object?> stateToJson(MlynState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(MlynResult r) => r.toJson();
}
