import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/piskvorky.md, version 1. Pure Dart: no Flutter imports here.
class PiskvorkyConfig {
  const PiskvorkyConfig({
    required this.size,
    required this.aiErrorPct,
    required this.defensePct,
    required this.fastMoves,
  });

  factory PiskvorkyConfig.fromTuning(TuningMinigamesPiskvorky t) => PiskvorkyConfig(
    size: t.size,
    aiErrorPct: List.unmodifiable(t.aiErrorPct),
    defensePct: List.unmodifiable(t.defensePct),
    fastMoves: t.fastMoves,
  );

  factory PiskvorkyConfig.fromJson(Map<String, Object?> j) => PiskvorkyConfig(
    size: j['size'] as int,
    aiErrorPct: List.unmodifiable((j['aiErrorPct'] as List).cast<int>()),
    defensePct: List.unmodifiable((j['defensePct'] as List).cast<int>()),
    fastMoves: j['fastMoves'] as int,
  );

  final int size;
  final List<int> aiErrorPct, defensePct;
  final int fastMoves;
}

class PiskvorkyState {
  const PiskvorkyState({
    required this.board,
    required this.turn,
    required this.moves,
    required this.over,
    required this.winner,
    required this.rng,
  });

  /// size² chars, row-major from the top: '.', 'x' (player), 'o' (AI).
  final String board;

  /// 'player' or 'ai'.
  final String turn;

  /// Player moves so far.
  final int moves;
  final bool over;

  /// '' while the game runs, then 'player', 'ai' or 'draw'.
  final String winner;
  final int rng;

  PiskvorkyState copyWith({String? board, String? turn, int? moves, bool? over, String? winner}) => PiskvorkyState(
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

/// {by: player|ai, cell} or {by: timeout} (cell -1).
class PiskvorkyAction {
  const PiskvorkyAction(this.by, this.cell);
  const PiskvorkyAction.timeout() : by = 'timeout', cell = -1;

  final String by;
  final int cell;

  Map<String, Object?> toJson() => by == 'timeout' ? {'by': by} : {'by': by, 'cell': cell};

  @override
  bool operator ==(Object other) => other is PiskvorkyAction && other.by == by && other.cell == cell;

  @override
  int get hashCode => Object.hash(by, cell);

  @override
  String toString() => toJson().toString();
}

class PiskvorkyResult {
  const PiskvorkyResult({required this.winner, required this.stars, required this.score, required this.moves});

  final String winner;
  final int stars, score, moves;

  Map<String, Object?> toJson() => {'winner': winner, 'stars': stars, 'score': score, 'moves': moves};
}

String _mark(String side) => side == 'player' ? 'x' : 'o';
String _other(String side) => side == 'player' ? 'ai' : 'player';

/// The four line directions as (dr, dc): →, ↓, ↘, ↙.
const _dirs = [(0, 1), (1, 0), (1, 1), (1, -1)];

/// Length of the run of [m] through [cell] (counting [cell] as [m]) and its open ends in direction [d].
({int len, int open}) runAt(String board, int size, int cell, String m, int d) {
  final (dr, dc) = _dirs[d];
  final r0 = cell ~/ size, c0 = cell % size;
  var len = 1, open = 0;
  for (final sg in const [1, -1]) {
    var r = r0 + dr * sg, c = c0 + dc * sg;
    while (r >= 0 && r < size && c >= 0 && c < size && board[r * size + c] == m) {
      len++;
      r += dr * sg;
      c += dc * sg;
    }
    if (r >= 0 && r < size && c >= 0 && c < size && board[r * size + c] == '.') open++;
  }
  return (len: len, open: open);
}

/// The winning run through [cell] (cells ascending), or [] (UI highlight).
List<int> winningLine(String board, int size, int cell) {
  final m = board[cell];
  if (m != 'x' && m != 'o') return const [];
  for (final (dr, dc) in _dirs) {
    final r0 = cell ~/ size, c0 = cell % size;
    final line = [cell];
    for (final sg in const [1, -1]) {
      var r = r0 + dr * sg, c = c0 + dc * sg;
      while (r >= 0 && r < size && c >= 0 && c < size && board[r * size + c] == m) {
        line.add(r * size + c);
        r += dr * sg;
        c += dc * sg;
      }
    }
    if (line.length >= 5) return line..sort();
  }
  return const [];
}

/// Line values by L (1–4) and open ends E (0–2); L ≥ 5 is 100000.
const _value = [
  [0, 0, 0],
  [0, 1, 10],
  [0, 10, 100],
  [0, 100, 1000],
  [0, 1000, 10000],
];

/// útok(p, s): sum over the four directions of the line value a mark [m] on [cell] would make.
int attack(String board, int size, int cell, String m) {
  var v = 0;
  for (var d = 0; d < 4; d++) {
    final run = runAt(board, size, cell, m, d);
    v += run.len >= 5 ? 100000 : _value[run.len][run.open];
  }
  return v;
}

/// AI candidates: empty cells within Chebyshev distance 2 of a mark, ascending; empty board → centre.
List<int> candidates(String board, int size) {
  final out = <int>[];
  var any = false;
  for (var i = 0; i < board.length; i++) {
    if (board[i] != '.') {
      any = true;
      continue;
    }
    final r = i ~/ size, c = i % size;
    final r1 = r - 2 < 0 ? 0 : r - 2, r2 = r + 2 > size - 1 ? size - 1 : r + 2;
    final c1 = c - 2 < 0 ? 0 : c - 2, c2 = c + 2 > size - 1 ? size - 1 : c + 2;
    var near = false;
    for (var rr = r1; rr <= r2 && !near; rr++) {
      for (var cc = c1; cc <= c2; cc++) {
        if (board[rr * size + cc] != '.') {
          near = true;
          break;
        }
      }
    }
    if (near) out.add(i);
  }
  if (!any) return [(size >> 1) * size + (size >> 1)];
  return out;
}

class PiskvorkyRules extends MgRules<PiskvorkyState, PiskvorkyAction, PiskvorkyResult> {
  PiskvorkyConfig? _cfg;

  PiskvorkyConfig get _c => _cfg ?? (throw StateError('piskvorky: init first'));

  @override
  String get id => 'piskvorky';

  @override
  int get specVersion => 1;

  /// Starts a game; [config] is the vector form (see [PiskvorkyConfig.fromJson]).
  @override
  PiskvorkyState init(Map<String, Object?> config, int seed) => start(PiskvorkyConfig.fromJson(config), seed);

  PiskvorkyState start(PiskvorkyConfig config, int seed) {
    _cfg = config;
    return PiskvorkyState(
      board: '.' * (config.size * config.size),
      turn: 'player',
      moves: 0,
      over: false,
      winner: '',
      rng: Prng(seed).state,
    );
  }

  @override
  List<PiskvorkyAction> legalActions(PiskvorkyState s) {
    if (s.over) return const [];
    return [
      for (var i = 0; i < s.board.length; i++)
        if (s.board[i] == '.') PiskvorkyAction(s.turn, i),
    ];
  }

  @override
  PiskvorkyState apply(PiskvorkyState s, PiskvorkyAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(over: true, winner: 'draw');
    final cell = a.cell;
    if (a.by != s.turn || cell < 0 || cell >= s.board.length || s.board[cell] != '.') throw IllegalAction(id, a);
    final m = _mark(s.turn);
    final board = s.board.replaceRange(cell, cell + 1, m);
    final moves = s.turn == 'player' ? s.moves + 1 : s.moves;
    final size = _c.size;
    for (var d = 0; d < 4; d++) {
      if (runAt(board, size, cell, m, d).len >= 5) {
        return s.copyWith(board: board, moves: moves, over: true, winner: s.turn);
      }
    }
    if (!board.contains('.')) return s.copyWith(board: board, moves: moves, over: true, winner: 'draw');
    return s.copyWith(board: board, moves: moves, turn: _other(s.turn));
  }

  @override
  PiskvorkyAction aiAction(PiskvorkyState s, int level, Prng ai) {
    if (s.over) throw IllegalAction(id, {'by': s.turn});
    final c = _c;
    final lv = level.clamp(1, c.aiErrorPct.length);
    final err = c.aiErrorPct[lv - 1];
    final def = c.defensePct[lv.clamp(1, c.defensePct.length) - 1];
    final cand = candidates(s.board, c.size);
    // Drawn on every AI move, even with a single candidate (Upřesnění v1).
    final r = ai.nextInt(100);
    if (r < err) return PiskvorkyAction(s.turn, cand[ai.nextInt(cand.length)]);
    final own = _mark(s.turn), opp = _mark(_other(s.turn));
    var best = -1, bestCell = cand.first;
    for (final p in cand) {
      // def > 100 may rank blocking above an own five: v1 as written.
      final v = attack(s.board, c.size, p, own) + (attack(s.board, c.size, p, opp) * def) ~/ 100;
      if (v > best) {
        best = v;
        bestCell = p;
      }
    }
    return PiskvorkyAction(s.turn, bestCell);
  }

  @override
  PiskvorkyResult? result(PiskvorkyState s) {
    if (!s.over) return null;
    final winner = s.winner.isEmpty ? 'draw' : s.winner;
    var marks = 0;
    for (var i = 0; i < s.board.length; i++) {
      if (s.board[i] != '.') marks++;
    }
    final win = winner == 'player';
    return PiskvorkyResult(
      winner: winner,
      stars: win ? (s.moves <= _c.fastMoves ? 3 : 2) : 0,
      score: win ? (s.board.length - marks) * 10 : 0,
      moves: s.moves,
    );
  }

  @override
  PiskvorkyAction actionFromJson(Map<String, Object?> json) => json['by'] == 'timeout'
      ? const PiskvorkyAction.timeout()
      : PiskvorkyAction(json['by'] as String, json['cell'] as int);

  @override
  Map<String, Object?> stateToJson(PiskvorkyState state) => state.toJson();

  @override
  Map<String, Object?> resultToJson(PiskvorkyResult result) => result.toJson();
}
