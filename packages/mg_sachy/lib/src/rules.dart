import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/sachy.md, version 1: Gardner minichess 5×5. Pure Dart: no Flutter imports here.
class SachyConfig {
  const SachyConfig({
    required this.aiDepth,
    required this.aiErrorPct,
    required this.quietLimit,
    required this.fastPlies,
  });

  factory SachyConfig.fromTuning(TuningMinigamesSachy t) => SachyConfig(
    aiDepth: List.unmodifiable(t.aiDepth),
    aiErrorPct: List.unmodifiable(t.aiErrorPct),
    quietLimit: t.quietLimit,
    fastPlies: t.fastPlies,
  );

  factory SachyConfig.fromJson(Map<String, Object?> j) => SachyConfig(
    aiDepth: List.unmodifiable((j['aiDepth'] as List).cast<int>()),
    aiErrorPct: List.unmodifiable((j['aiErrorPct'] as List).cast<int>()),
    quietLimit: j['quietLimit'] as int,
    fastPlies: j['fastPlies'] as int,
  );

  final List<int> aiDepth, aiErrorPct;
  final int quietLimit, fastPlies;
}

class SachyState {
  const SachyState({
    required this.board,
    required this.turn,
    required this.plies,
    required this.quiet,
    required this.over,
    required this.winner,
    required this.byCount,
    required this.rng,
  });

  /// 25 chars, row 0 on top: '.', upper case player (white), lower case AI (black).
  final String board;

  /// 'player' or 'ai'.
  final String turn;
  final int plies, quiet;
  final bool over;

  /// '' while the game runs, then 'player', 'ai' or 'draw'.
  final String winner;
  final bool byCount;
  final int rng;

  SachyState copyWith({
    String? board,
    String? turn,
    int? plies,
    int? quiet,
    bool? over,
    String? winner,
    bool? byCount,
  }) => SachyState(
    board: board ?? this.board,
    turn: turn ?? this.turn,
    plies: plies ?? this.plies,
    quiet: quiet ?? this.quiet,
    over: over ?? this.over,
    winner: winner ?? this.winner,
    byCount: byCount ?? this.byCount,
    rng: rng,
  );

  Map<String, Object?> toJson() => {
    'board': board,
    'turn': turn,
    'plies': plies,
    'quiet': quiet,
    'over': over,
    'winner': winner,
    'byCount': byCount,
    'rng': rng,
  };
}

/// {by: player|ai, from, to} or {by: timeout}.
class SachyAction {
  const SachyAction(this.by, this.from, this.to);
  const SachyAction.timeout() : by = 'timeout', from = -1, to = -1;

  final String by;
  final int from, to;

  Map<String, Object?> toJson() => by == 'timeout' ? {'by': by} : {'by': by, 'from': from, 'to': to};

  @override
  bool operator ==(Object other) => other is SachyAction && other.by == by && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(by, from, to);

  @override
  String toString() => toJson().toString();
}

class SachyResult {
  const SachyResult({
    required this.winner,
    required this.stars,
    required this.score,
    required this.byCount,
    required this.player,
    required this.ai,
    required this.plies,
  });

  final String winner;
  final int stars, score;
  final bool byCount;
  final int player, ai, plies;

  Map<String, Object?> toJson() => {
    'winner': winner,
    'stars': stars,
    'score': score,
    'byCount': byCount,
    'player': player,
    'ai': ai,
    'plies': plies,
  };
}

const sachyStartBoard = 'rnbqkppppp.....PPPPPRNBQK';
const _n = 5;
const _value = {'p': 1, 'n': 3, 'b': 3, 'r': 5, 'q': 9, 'k': 0};
const _rook = [(-1, 0), (1, 0), (0, -1), (0, 1)];
const _bishop = [(-1, -1), (-1, 1), (1, -1), (1, 1)];
const _king = [..._rook, ..._bishop];
const _knight = [(-2, -1), (-2, 1), (-1, -2), (-1, 2), (1, -2), (1, 2), (2, -1), (2, 1)];
const _inf = 1 << 30;

/// +1 player piece, −1 AI piece, 0 empty.
int _owner(String ch) => ch == '.' ? 0 : (ch == ch.toUpperCase() ? 1 : -1);
int _sign(String side) => side == 'player' ? 1 : -1;

/// Pseudo-legal moves of side [sg] as (from, to), ascending by from, then to.
List<(int, int)> _pseudo(List<String> b, int sg) {
  final out = <(int, int)>[];
  int at(int r, int c) => r >= 0 && r < _n && c >= 0 && c < _n ? r * _n + c : -1;
  for (var i = 0; i < 25; i++) {
    final ch = b[i];
    if (_owner(ch) != sg) continue;
    final r0 = i ~/ _n, c0 = i % _n;
    final t = <int>[];
    final p = ch.toLowerCase();
    if (p == 'p') {
      final r = r0 - sg;
      final f = at(r, c0);
      if (f >= 0 && b[f] == '.') t.add(f);
      for (final dc in const [-1, 1]) {
        final x = at(r, c0 + dc);
        if (x >= 0 && _owner(b[x]) == -sg) t.add(x);
      }
    } else if (p == 'n' || p == 'k') {
      for (final (dr, dc) in p == 'n' ? _knight : _king) {
        final x = at(r0 + dr, c0 + dc);
        if (x >= 0 && _owner(b[x]) != sg) t.add(x);
      }
    } else {
      final dirs = p == 'r'
          ? _rook
          : p == 'b'
          ? _bishop
          : _king;
      for (final (dr, dc) in dirs) {
        var r = r0 + dr, c = c0 + dc;
        for (var x = at(r, c); x >= 0; r += dr, c += dc, x = at(r, c)) {
          final o = _owner(b[x]);
          if (o == sg) break;
          t.add(x);
          if (o != 0) break;
        }
      }
    }
    t.sort();
    for (final x in t) {
      out.add((i, x));
    }
  }
  return out;
}

/// Board after moving from → to (promotion to a queen on the last row).
List<String> _moved(List<String> b, int from, int to) {
  final n = [...b];
  var ch = n[from];
  final row = to ~/ _n;
  if (ch == 'P' && row == 0) {
    ch = 'Q';
  } else if (ch == 'p' && row == _n - 1) {
    ch = 'q';
  }
  n[to] = ch;
  n[from] = '.';
  return n;
}

bool _inCheck(List<String> b, int sg) {
  final k = b.indexOf(sg == 1 ? 'K' : 'k');
  if (k < 0) return true;
  return _pseudo(b, -sg).any((m) => m.$2 == k);
}

List<(int, int)> _legal(List<String> b, int sg) => [
  for (final m in _pseudo(b, sg))
    if (!_inCheck(_moved(b, m.$1, m.$2), sg)) m,
];

/// Material of [side] ('player' or 'ai') on [board]: P 1, N 3, B 3, R 5, Q 9.
int sachyMaterial(String board, String side) {
  final sg = _sign(side);
  var m = 0;
  for (var i = 0; i < board.length; i++) {
    if (_owner(board[i]) == sg) m += _value[board[i].toLowerCase()]!;
  }
  return m;
}

bool _kingsOnly(List<String> b) => b.every((ch) => ch == '.' || ch == 'k' || ch == 'K');

int _evaluate(List<String> b, int sg) {
  var v = 0;
  for (var i = 0; i < 25; i++) {
    final o = _owner(b[i]);
    if (o == 0) continue;
    final p = b[i].toLowerCase();
    final r = i ~/ _n;
    final adv = p == 'p' ? (o == 1 ? 4 - r : r) : 0;
    v += o * sg * (_value[p]! * 100 + adv * 10);
  }
  return v;
}

int _quietAfter(List<String> b, (int, int) m, int quiet) =>
    b[m.$2] != '.' || b[m.$1].toLowerCase() == 'p' ? 0 : quiet + 1;

int _search(List<String> b, int sg, int quiet, int d, int quietLimit, int alpha, int beta) {
  final ms = _legal(b, sg);
  if (ms.isEmpty) return _inCheck(b, sg) ? -(100000 + d) : 0;
  if (_kingsOnly(b) || quiet >= quietLimit) return 0;
  if (d == 0) return _evaluate(b, sg);
  var best = -_inf;
  for (final m in ms) {
    final v = -_search(_moved(b, m.$1, m.$2), -sg, _quietAfter(b, m, quiet), d - 1, quietLimit, -beta, -alpha);
    if (v > best) best = v;
    if (v > alpha) alpha = v;
    if (alpha >= beta) break;
  }
  return best;
}

String _other(String s) => s == 'player' ? 'ai' : 'player';

class SachyRules extends MgRules<SachyState, SachyAction, SachyResult> {
  SachyConfig? _cfg;
  SachyConfig get _c => _cfg ?? (throw StateError('sachy: init first'));

  @override
  String get id => 'sachy';

  @override
  int get specVersion => 1;

  @override
  SachyState init(Map<String, Object?> config, int seed) => start(SachyConfig.fromJson(config), seed);

  SachyState start(SachyConfig config, int seed) {
    _cfg = config;
    return SachyState(
      board: sachyStartBoard,
      turn: 'player',
      plies: 0,
      quiet: 0,
      over: false,
      winner: '',
      byCount: false,
      rng: Prng(seed).state,
    );
  }

  @override
  List<SachyAction> legalActions(SachyState s) {
    if (s.over) return const [];
    return [for (final m in _legal(s.board.split(''), _sign(s.turn))) SachyAction(s.turn, m.$1, m.$2)];
  }

  /// True when the side to move is in check.
  bool check(SachyState s) => _inCheck(s.board.split(''), _sign(s.turn));

  @override
  SachyState apply(SachyState s, SachyAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') {
      final p = sachyMaterial(s.board, 'player'), q = sachyMaterial(s.board, 'ai');
      return s.copyWith(
        over: true,
        byCount: true,
        winner: p > q
            ? 'player'
            : q > p
            ? 'ai'
            : 'draw',
      );
    }
    if (a.by != s.turn) throw IllegalAction(id, a);
    final b = s.board.split('');
    final sg = _sign(s.turn);
    if (!_legal(b, sg).contains((a.from, a.to))) throw IllegalAction(id, a);
    final nb = _moved(b, a.from, a.to);
    final n = s.copyWith(
      board: nb.join(),
      turn: _other(s.turn),
      plies: s.plies + 1,
      quiet: _quietAfter(b, (a.from, a.to), s.quiet),
    );
    if (_legal(nb, -sg).isEmpty) return n.copyWith(over: true, winner: _inCheck(nb, -sg) ? s.turn : 'draw');
    if (_kingsOnly(nb) || n.quiet >= _c.quietLimit) return n.copyWith(over: true, winner: 'draw');
    return n;
  }

  @override
  SachyAction aiAction(SachyState s, int level, Prng ai) {
    if (s.over) throw IllegalAction(id, {'by': s.turn});
    final c = _c;
    final lv = level.clamp(1, 5);
    final err = c.aiErrorPct[lv - 1];
    final depth = c.aiDepth[lv - 1] < 1 ? 1 : c.aiDepth[lv - 1];
    final b = s.board.split('');
    final sg = _sign(s.turn);
    final legal = _legal(b, sg);
    if (ai.nextInt(100) < err) {
      final m = legal[ai.nextInt(legal.length)];
      return SachyAction(s.turn, m.$1, m.$2);
    }
    var best = -_inf, bestI = 0, alpha = -_inf;
    for (var i = 0; i < legal.length; i++) {
      final m = legal[i];
      final v = -_search(
        _moved(b, m.$1, m.$2),
        -sg,
        _quietAfter(b, m, s.quiet),
        depth - 1,
        c.quietLimit,
        -_inf,
        -alpha,
      );
      if (v > best) {
        best = v;
        bestI = i;
      }
      if (v > alpha) alpha = v;
    }
    return SachyAction(s.turn, legal[bestI].$1, legal[bestI].$2);
  }

  @override
  SachyResult? result(SachyState s) {
    if (!s.over) return null;
    final winner = s.winner == '' ? 'draw' : s.winner;
    final player = sachyMaterial(s.board, 'player'), ai = sachyMaterial(s.board, 'ai');
    final stars = winner != 'player'
        ? 0
        : s.byCount
        ? 1
        : s.plies <= _c.fastPlies
        ? 3
        : 2;
    return SachyResult(
      winner: winner,
      stars: stars,
      score: player * 10,
      byCount: s.byCount,
      player: player,
      ai: ai,
      plies: s.plies,
    );
  }

  @override
  SachyAction actionFromJson(Map<String, Object?> j) => j['by'] == 'timeout'
      ? const SachyAction.timeout()
      : SachyAction(j['by'] as String, j['from'] as int, j['to'] as int);

  @override
  Map<String, Object?> stateToJson(SachyState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(SachyResult r) => r.toJson();
}
