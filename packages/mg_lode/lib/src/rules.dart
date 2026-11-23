import 'dart:typed_data';

import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/lode.md, version 1. Pure Dart: no Flutter imports here.
class LodeConfig {
  const LodeConfig({
    required this.fleet,
    required this.shuffles,
    required this.aiErrorPct,
    required this.fastShots,
    required this.okShots,
  });

  factory LodeConfig.fromTuning(TuningMinigamesLode t) => LodeConfig(
    fleet: List.unmodifiable(t.fleet),
    shuffles: t.shuffles,
    aiErrorPct: List.unmodifiable(t.aiErrorPct),
    fastShots: t.fastShots,
    okShots: t.okShots,
  );

  factory LodeConfig.fromJson(Map<String, Object?> j) => LodeConfig(
    fleet: List.unmodifiable((j['fleet'] as List).cast<int>()),
    shuffles: j['shuffles'] as int,
    aiErrorPct: List.unmodifiable((j['aiErrorPct'] as List).cast<int>()),
    fastShots: j['fastShots'] as int,
    okShots: j['okShots'] as int,
  );

  final List<int> fleet;
  final int shuffles;
  final List<int> aiErrorPct;
  final int fastShots, okShots;
}

class LodeState {
  const LodeState({
    required this.pShips,
    required this.aShips,
    required this.pShots,
    required this.aShots,
    required this.turn,
    required this.shots,
    required this.shuffles,
    required this.over,
    required this.winner,
    required this.rng,
  });

  /// Ships in fleet order; a ship is its cells ascending (i = y * 10 + x).
  final List<List<int>> pShips, aShips;

  /// AI shots on the player's board / player shots on the AI board: '.', 'o' water, 'x' hit.
  final String pShots, aShots;

  /// 'player' or 'ai'.
  final String turn;
  final int shots, shuffles;
  final bool over;

  /// '' while the game runs, then 'player', 'ai' or 'draw'.
  final String winner;
  final int rng;

  LodeState copyWith({
    List<List<int>>? pShips,
    String? pShots,
    String? aShots,
    String? turn,
    int? shots,
    int? shuffles,
    bool? over,
    String? winner,
    int? rng,
  }) => LodeState(
    pShips: pShips ?? this.pShips,
    aShips: aShips,
    pShots: pShots ?? this.pShots,
    aShots: aShots ?? this.aShots,
    turn: turn ?? this.turn,
    shots: shots ?? this.shots,
    shuffles: shuffles ?? this.shuffles,
    over: over ?? this.over,
    winner: winner ?? this.winner,
    rng: rng ?? this.rng,
  );

  Map<String, Object?> toJson() => {
    'pShips': pShips,
    'aShips': aShips,
    'pShots': pShots,
    'aShots': aShots,
    'turn': turn,
    'shots': shots,
    'shuffles': shuffles,
    'over': over,
    'winner': winner,
    'rng': rng,
  };
}

/// {by: player, op: shuffle}, {by: player|ai, op: shot, cell} or {by: timeout}.
class LodeAction {
  const LodeAction.shot(this.by, this.cell) : op = 'shot';
  const LodeAction.shuffle() : by = 'player', op = 'shuffle', cell = -1;
  const LodeAction.timeout() : by = 'timeout', op = '', cell = -1;

  final String by, op;
  final int cell;

  Map<String, Object?> toJson() => switch (op) {
    'shot' => {'by': by, 'op': op, 'cell': cell},
    'shuffle' => {'by': by, 'op': op},
    _ => {'by': by},
  };

  @override
  bool operator ==(Object other) => other is LodeAction && other.by == by && other.op == op && other.cell == cell;

  @override
  int get hashCode => Object.hash(by, op, cell);

  @override
  String toString() => toJson().toString();
}

class LodeResult {
  const LodeResult({required this.winner, required this.stars, required this.score, required this.shots});

  final String winner;
  final int stars, score, shots;

  Map<String, Object?> toJson() => {'winner': winner, 'stars': stars, 'score': score, 'shots': shots};
}

/// Deals one fleet from [rng] (specs/minigames/lode.md "Pole a rozmístění").
List<List<int>> placeFleet(List<int> fleet, Prng rng) {
  final taken = Uint8List(100); // ship cells and their neighbours
  final ships = <List<int>>[];
  for (final len in fleet) {
    while (true) {
      final dir = rng.nextInt(2);
      final x = rng.nextInt(dir == 0 ? 11 - len : 10);
      final y = rng.nextInt(dir == 1 ? 11 - len : 10);
      final cells = [for (var k = 0; k < len; k++) dir == 0 ? y * 10 + x + k : (y + k) * 10 + x];
      if (cells.any((c) => taken[c] != 0)) continue;
      for (final c in cells) {
        final cx = c % 10, cy = c ~/ 10;
        for (var yy = cy - 1 < 0 ? 0 : cy - 1; yy <= (cy + 1 > 9 ? 9 : cy + 1); yy++) {
          for (var xx = cx - 1 < 0 ? 0 : cx - 1; xx <= (cx + 1 > 9 ? 9 : cx + 1); xx++) {
            taken[yy * 10 + xx] = 1;
          }
        }
      }
      ships.add(List.unmodifiable(cells));
      break;
    }
  }
  return List.unmodifiable(ships);
}

bool sunk(List<int> ship, String shots) => ship.every((c) => shots[c] == 'x');

bool _allSunk(List<List<int>> ships, String shots) => ships.every((s) => sunk(s, shots));

int _hits(String shots) {
  var n = 0;
  for (var i = 0; i < shots.length; i++) {
    if (shots[i] == 'x') n++;
  }
  return n;
}

/// Cells next to (also diagonally) any sunk ship.
Set<int> _nearSunk(List<List<int>> ships, String shots) {
  final out = <int>{};
  for (final s in ships) {
    if (!sunk(s, shots)) continue;
    for (final c in s) {
      final cx = c % 10, cy = c ~/ 10;
      for (var yy = cy - 1 < 0 ? 0 : cy - 1; yy <= (cy + 1 > 9 ? 9 : cy + 1); yy++) {
        for (var xx = cx - 1 < 0 ? 0 : cx - 1; xx <= (cx + 1 > 9 ? 9 : cx + 1); xx++) {
          out.add(yy * 10 + xx);
        }
      }
    }
  }
  return out;
}

/// AI target candidates from hits on ships not yet sunk ([] = hunt), ascending.
List<int> targetCandidates(List<List<int>> ships, String shots) {
  // Insertion order matters only for the final sort; a LinkedHashSet keeps it like the web Set.
  final live = <int>{};
  for (final s in ships) {
    if (sunk(s, shots)) continue;
    for (final c in s) {
      if (shots[c] == 'x') live.add(c);
    }
  }
  if (live.isEmpty) return const [];
  bool free(int x, int y) => x >= 0 && x < 10 && y >= 0 && y < 10 && shots[y * 10 + x] == '.';
  final out = <int>{};
  var lines = false;
  for (final c in live) {
    final x = c % 10, y = c ~/ 10;
    for (final (dx, dy) in const [(1, 0), (0, 1)]) {
      // Start of a run of at least two live hits in this direction.
      if (x - dx >= 0 && y - dy >= 0 && live.contains((y - dy) * 10 + x - dx)) continue;
      var len = 1;
      while (x + dx * len < 10 && y + dy * len < 10 && live.contains((y + dy * len) * 10 + x + dx * len)) {
        len++;
      }
      if (len < 2) continue;
      lines = true;
      if (free(x - dx, y - dy)) out.add((y - dy) * 10 + x - dx);
      if (free(x + dx * len, y + dy * len)) out.add((y + dy * len) * 10 + x + dx * len);
    }
  }
  if (!lines || out.isEmpty) {
    for (final c in live) {
      final x = c % 10, y = c ~/ 10;
      for (final (dx, dy) in const [(0, -1), (-1, 0), (1, 0), (0, 1)]) {
        if (free(x + dx, y + dy)) out.add((y + dy) * 10 + x + dx);
      }
    }
  }
  return out.toList()..sort();
}

String _other(String s) => s == 'player' ? 'ai' : 'player';

class LodeRules extends MgRules<LodeState, LodeAction, LodeResult> {
  LodeConfig? _cfg;
  LodeConfig get _c => _cfg ?? (throw StateError('lode: init first'));

  @override
  String get id => 'lode';

  @override
  int get specVersion => 1;

  @override
  LodeState init(Map<String, Object?> config, int seed) => start(LodeConfig.fromJson(config), seed);

  LodeState start(LodeConfig config, int seed) {
    _cfg = config;
    final r = Prng(seed);
    final pShips = placeFleet(config.fleet, r);
    final aShips = placeFleet(config.fleet, r);
    final empty = '.' * 100;
    return LodeState(
      pShips: pShips,
      aShips: aShips,
      pShots: empty,
      aShots: empty,
      turn: 'player',
      shots: 0,
      shuffles: config.shuffles,
      over: false,
      winner: '',
      rng: r.state,
    );
  }

  bool canShuffle(LodeState s) => !s.over && s.turn == 'player' && s.shots == 0 && s.shuffles > 0;

  @override
  List<LodeAction> legalActions(LodeState s) {
    if (s.over) return const [];
    final board = s.turn == 'player' ? s.aShots : s.pShots;
    return [
      if (s.turn == 'player' && canShuffle(s)) const LodeAction.shuffle(),
      for (var i = 0; i < 100; i++)
        if (board[i] == '.') LodeAction.shot(s.turn, i),
    ];
  }

  @override
  LodeState apply(LodeState s, LodeAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') {
      final p = _hits(s.aShots), q = _hits(s.pShots);
      return s.copyWith(
        over: true,
        winner: p > q
            ? 'player'
            : q > p
            ? 'ai'
            : 'draw',
      );
    }
    if (a.by != s.turn) throw IllegalAction(id, a);
    if (a.op == 'shuffle') {
      if (!canShuffle(s)) throw IllegalAction(id, a);
      final w = withRng(s.rng, (r) => placeFleet(_c.fleet, r));
      return s.copyWith(pShips: w.value, shuffles: s.shuffles - 1, rng: w.rng);
    }
    if (a.op != 'shot' || a.cell < 0 || a.cell >= 100) throw IllegalAction(id, a);
    final mine = s.turn == 'player';
    final board = mine ? s.aShots : s.pShots;
    if (board[a.cell] != '.') throw IllegalAction(id, a);
    final ships = mine ? s.aShips : s.pShips;
    final hit = ships.any((sh) => sh.contains(a.cell));
    final shots = board.substring(0, a.cell) + (hit ? 'x' : 'o') + board.substring(a.cell + 1);
    final n = mine ? s.copyWith(aShots: shots, shots: s.shots + 1) : s.copyWith(pShots: shots);
    if (hit && _allSunk(ships, shots)) return n.copyWith(over: true, winner: s.turn);
    return hit ? n : n.copyWith(turn: _other(s.turn));
  }

  @override
  LodeAction aiAction(LodeState s, int level, Prng ai) {
    if (s.over) throw IllegalAction(id, {'by': s.turn});
    final c = _c;
    final board = s.turn == 'ai' ? s.pShots : s.aShots;
    final ships = s.turn == 'ai' ? s.pShips : s.aShips;
    final free = [
      for (var i = 0; i < 100; i++)
        if (board[i] == '.') i,
    ];
    final lv = level.clamp(1, c.aiErrorPct.length);
    final err = c.aiErrorPct[lv - 1];
    LodeAction shot(int cell) => LodeAction.shot(s.turn, cell);
    final r = ai.nextInt(100);
    if (r < err) return shot(free[ai.nextInt(free.length)]);
    final target = targetCandidates(ships, board);
    if (target.isNotEmpty) return shot(target[ai.nextInt(target.length)]);
    var pool = free;
    if (lv >= 3) {
      final even = [
        for (final i in free)
          if ((i % 10 + i ~/ 10) % 2 == 0) i,
      ];
      if (even.isNotEmpty) pool = even;
    }
    if (lv >= 4) {
      final near = _nearSunk(ships, board);
      final rest = [
        for (final i in pool)
          if (!near.contains(i)) i,
      ];
      if (rest.isNotEmpty) pool = rest;
    }
    return shot(pool[ai.nextInt(pool.length)]);
  }

  @override
  LodeResult? result(LodeState s) {
    if (!s.over) return null;
    final winner = s.winner == '' ? 'draw' : s.winner;
    final c = _c;
    final win = winner == 'player';
    final stars = !win
        ? 0
        : s.shots <= c.fastShots
        ? 3
        : s.shots <= c.okShots
        ? 2
        : 1;
    final score = win ? (1000 - 10 * s.shots < 0 ? 0 : 1000 - 10 * s.shots) : 0;
    return LodeResult(winner: winner, stars: stars, score: score, shots: s.shots);
  }

  @override
  LodeAction actionFromJson(Map<String, Object?> j) {
    if (j['by'] == 'timeout') return const LodeAction.timeout();
    if (j['op'] == 'shuffle') {
      if (j['by'] != 'player') throw IllegalAction(id, j);
      return const LodeAction.shuffle();
    }
    return LodeAction.shot(j['by'] as String, j['cell'] as int);
  }

  @override
  Map<String, Object?> stateToJson(LodeState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(LodeResult r) => r.toJson();
}
