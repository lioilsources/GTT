import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/posuvne.md, version 1. Pure Dart: no Flutter imports here.
/// [level] is MinigameContext.difficulty.
class PosuvneConfig {
  const PosuvneConfig({required this.shuffleMoves, required this.level});

  factory PosuvneConfig.fromTuning(TuningMinigamesPosuvne t, int level) =>
      PosuvneConfig(shuffleMoves: List.unmodifiable(t.shuffleMoves), level: level);

  factory PosuvneConfig.fromJson(Map<String, Object?> j) =>
      PosuvneConfig(shuffleMoves: List.unmodifiable((j['shuffleMoves'] as List).cast<int>()), level: j['level'] as int);

  final List<int> shuffleMoves;
  final int level;
}

class PosuvneState {
  const PosuvneState({
    required this.tiles,
    required this.moves,
    required this.par,
    required this.over,
    required this.solved,
    required this.rng,
  });

  /// 16 numbers row by row from the top, 0 = the gap.
  final List<int> tiles;
  final int moves, par;
  final bool over, solved;
  final int rng;

  int get gap => tiles.indexOf(0);

  PosuvneState copyWith({List<int>? tiles, int? moves, bool? over, bool? solved}) => PosuvneState(
    tiles: tiles ?? this.tiles,
    moves: moves ?? this.moves,
    par: par,
    over: over ?? this.over,
    solved: solved ?? this.solved,
    rng: rng,
  );

  Map<String, Object?> toJson() => {
    'tiles': tiles,
    'moves': moves,
    'par': par,
    'over': over,
    'solved': solved,
    'rng': rng,
  };
}

/// {by: player, tile} or {by: timeout}.
class PosuvneAction {
  const PosuvneAction(this.tile) : by = 'player';
  const PosuvneAction.timeout() : by = 'timeout', tile = 0;

  final String by;
  final int tile;

  Map<String, Object?> toJson() => by == 'timeout' ? {'by': by} : {'by': by, 'tile': tile};

  @override
  bool operator ==(Object other) => other is PosuvneAction && other.by == by && other.tile == tile;

  @override
  int get hashCode => Object.hash(by, tile);

  @override
  String toString() => toJson().toString();
}

class PosuvneResult {
  const PosuvneResult({
    required this.winner,
    required this.stars,
    required this.score,
    required this.moves,
    required this.par,
  });

  final String winner;
  final int stars, score, moves, par;

  Map<String, Object?> toJson() => {'winner': winner, 'stars': stars, 'score': score, 'moves': moves, 'par': par};
}

const List<int> posuvneSolved = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 0];

bool isSolved(List<int> t) {
  for (var i = 0; i < 16; i++) {
    if (t[i] != posuvneSolved[i]) return false;
  }
  return true;
}

/// Positions next to [p] in the order up, down, left, right.
List<int> neighbours(int p) {
  final r = p >> 2, c = p & 3;
  return [if (r > 0) p - 4, if (r < 3) p + 4, if (c > 0) p - 1, if (c < 3) p + 1];
}

class PosuvneRules extends MgRules<PosuvneState, PosuvneAction, PosuvneResult> {
  @override
  String get id => 'posuvne';

  @override
  int get specVersion => 1;

  @override
  PosuvneState init(Map<String, Object?> config, int seed) => start(PosuvneConfig.fromJson(config), seed);

  PosuvneState start(PosuvneConfig c, int seed) {
    final rng = Prng(seed);
    final lv = c.level.clamp(1, c.shuffleMoves.length);
    var par = c.shuffleMoves.isEmpty ? 0 : c.shuffleMoves[lv - 1];
    final tiles = [...posuvneSolved];
    var gap = 15, last = -1;
    void step() {
      final nb = neighbours(gap).where((p) => p != last).toList();
      final p = nb[rng.nextInt(nb.length)];
      tiles[gap] = tiles[p];
      tiles[p] = 0;
      last = gap;
      gap = p;
    }

    for (var k = 0; k < par; k++) {
      step();
    }
    if (isSolved(tiles)) {
      step();
      par += 1;
    }
    return PosuvneState(
      tiles: List.unmodifiable(tiles),
      moves: 0,
      par: par,
      over: false,
      solved: false,
      rng: rng.state,
    );
  }

  @override
  List<PosuvneAction> legalActions(PosuvneState s) {
    if (s.over) return const [];
    final tiles = [for (final p in neighbours(s.gap)) s.tiles[p]]..sort();
    return [for (final t in tiles) PosuvneAction(t)];
  }

  @override
  PosuvneState apply(PosuvneState s, PosuvneAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(over: true, solved: false);
    if (a.by != 'player') throw IllegalAction(id, a);
    final gap = s.gap;
    final p = s.tiles.indexOf(a.tile);
    if (a.tile == 0 || p < 0 || !neighbours(gap).contains(p)) throw IllegalAction(id, a);
    final tiles = [...s.tiles];
    tiles[gap] = a.tile;
    tiles[p] = 0;
    final solved = isSolved(tiles);
    return s.copyWith(tiles: List.unmodifiable(tiles), moves: s.moves + 1, over: solved, solved: solved);
  }

  @override
  PosuvneAction aiAction(PosuvneState s, int level, Prng ai) => throw UnsupportedError('posuvne: no opponent');

  @override
  PosuvneResult? result(PosuvneState s) {
    if (!s.over) return null;
    if (!s.solved) return PosuvneResult(winner: 'ai', stars: 0, score: 0, moves: s.moves, par: s.par);
    final stars = s.moves <= s.par
        ? 3
        : s.moves <= 2 * s.par
        ? 2
        : 1;
    final over = s.moves - s.par > 0 ? s.moves - s.par : 0;
    final score = 1000 - 10 * over > 100 ? 1000 - 10 * over : 100;
    return PosuvneResult(winner: 'player', stars: stars, score: score, moves: s.moves, par: s.par);
  }

  @override
  PosuvneAction actionFromJson(Map<String, Object?> json) =>
      json['by'] == 'timeout' ? const PosuvneAction.timeout() : PosuvneAction(json['tile'] as int);

  @override
  Map<String, Object?> stateToJson(PosuvneState state) => state.toJson();

  @override
  Map<String, Object?> resultToJson(PosuvneResult result) => result.toJson();
}

/// The single moves the UI sends for a tap at [p]: from the gap outwards along its row or column
/// up to [p]; empty when [p] is the gap or not in line with it.
List<int> slideTiles(PosuvneState s, int p) {
  final gap = s.gap;
  final sameRow = p >> 2 == gap >> 2, sameCol = (p & 3) == (gap & 3);
  if (p == gap || (!sameRow && !sameCol)) return const [];
  final step = sameRow ? (p > gap ? 1 : -1) : (p > gap ? 4 : -4);
  return [for (var q = gap + step; q != p + step; q += step) s.tiles[q]];
}
