import 'dart:math' as math;

import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/krtek.md, version 1. Pure Dart: no Flutter imports here.
class KrtekConfig {
  const KrtekConfig({
    required this.level,
    required this.holes,
    required this.gameTicks,
    required this.firstSpawn,
    required this.spawnEvery,
    required this.upTicks,
    required this.goldPct,
    required this.bombPct,
    required this.points,
    required this.goldPoints,
    required this.bombPenalty,
    required this.starScores,
  });

  factory KrtekConfig.fromTuning(TuningMinigamesKrtek t, int level) => KrtekConfig(
    level: level,
    holes: t.holes,
    gameTicks: t.gameTicks,
    firstSpawn: t.firstSpawn,
    spawnEvery: List.unmodifiable(t.spawnEvery),
    upTicks: List.unmodifiable(t.upTicks),
    goldPct: t.goldPct,
    bombPct: List.unmodifiable(t.bombPct),
    points: t.points,
    goldPoints: t.goldPoints,
    bombPenalty: t.bombPenalty,
    starScores: List.unmodifiable(t.starScores),
  );

  factory KrtekConfig.fromJson(Map<String, Object?> j) {
    int i(String k) => j[k] as int;
    List<int> l(String k) => List.unmodifiable((j[k] as List).cast<int>());
    return KrtekConfig(
      level: i('level'),
      holes: i('holes'),
      gameTicks: i('gameTicks'),
      firstSpawn: i('firstSpawn'),
      spawnEvery: l('spawnEvery'),
      upTicks: l('upTicks'),
      goldPct: i('goldPct'),
      bombPct: l('bombPct'),
      points: i('points'),
      goldPoints: i('goldPoints'),
      bombPenalty: i('bombPenalty'),
      starScores: l('starScores'),
    );
  }

  final int level, holes, gameTicks, firstSpawn, goldPct, points, goldPoints, bombPenalty;
  final List<int> spawnEvery, upTicks, bombPct, starScores;
}

/// One hole: kind '' (empty), 'mole', 'gold' or 'bomb'; [left] ticks until it hides.
class MoleHole {
  const MoleHole(this.kind, this.left);

  static const empty = MoleHole('', 0);

  final String kind;
  final int left;

  Map<String, Object?> toJson() => {'kind': kind, 'left': left};
}

class KrtekState {
  const KrtekState({
    required this.tick,
    required this.holes,
    required this.nextSpawn,
    required this.score,
    required this.hits,
    required this.misses,
    required this.over,
    required this.rng,
  });

  final int tick;
  final List<MoleHole> holes;
  final int nextSpawn, score, hits, misses;
  final bool over;
  final int rng;

  KrtekState copyWith({List<MoleHole>? holes, int? score, int? hits, bool? over}) => KrtekState(
    tick: tick,
    holes: holes ?? this.holes,
    nextSpawn: nextSpawn,
    score: score ?? this.score,
    hits: hits ?? this.hits,
    misses: misses,
    over: over ?? this.over,
    rng: rng,
  );

  Map<String, Object?> toJson() => {
    'tick': tick,
    'holes': [for (final h in holes) h.toJson()],
    'nextSpawn': nextSpawn,
    'score': score,
    'hits': hits,
    'misses': misses,
    'over': over,
    'rng': rng,
  };
}

/// {by: player, op: tick, n}, {by: player, op: hit, hole} or {by: timeout}.
class KrtekAction {
  const KrtekAction.tick(this.n) : by = 'player', op = 'tick', hole = 0;
  const KrtekAction.hit(this.hole) : by = 'player', op = 'hit', n = 0;
  const KrtekAction.timeout() : by = 'timeout', op = '', n = 0, hole = 0;
  const KrtekAction._(this.by, this.op, this.n, this.hole);

  final String by, op;
  final int n, hole;

  Map<String, Object?> toJson() => by == 'timeout'
      ? {'by': by}
      : op == 'hit'
      ? {'by': by, 'op': op, 'hole': hole}
      : {'by': by, 'op': op, 'n': n};

  @override
  bool operator ==(Object other) =>
      other is KrtekAction && other.by == by && other.op == op && other.n == n && other.hole == hole;

  @override
  int get hashCode => Object.hash(by, op, n, hole);

  @override
  String toString() => toJson().toString();
}

class KrtekResult {
  const KrtekResult({
    required this.winner,
    required this.stars,
    required this.score,
    required this.hits,
    required this.misses,
  });

  final String winner;
  final int stars, score, hits, misses;

  Map<String, Object?> toJson() => {'winner': winner, 'stars': stars, 'score': score, 'hits': hits, 'misses': misses};
}

class KrtekRules extends MgRules<KrtekState, KrtekAction, KrtekResult> {
  KrtekConfig? _cfg;

  KrtekConfig get config => _cfg ?? (throw StateError('krtek: init first'));

  @override
  String get id => 'krtek';

  @override
  int get specVersion => 1;

  @override
  KrtekState init(Map<String, Object?> config, int seed) => start(KrtekConfig.fromJson(config), seed);

  KrtekState start(KrtekConfig config, int seed) {
    _cfg = config;
    return KrtekState(
      tick: 0,
      holes: List.unmodifiable(List.filled(config.holes, MoleHole.empty)),
      nextSpawn: config.firstSpawn,
      score: 0,
      hits: 0,
      misses: 0,
      over: false,
      rng: Prng(seed).state,
    );
  }

  @override
  List<KrtekAction> legalActions(KrtekState s) => const [];

  @override
  KrtekState apply(KrtekState s, KrtekAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(over: true);
    if (a.by != 'player') throw IllegalAction(id, a);
    final c = config;
    if (a.op == 'hit') {
      if (a.hole < 0 || a.hole >= c.holes) throw IllegalAction(id, a);
      final h = s.holes[a.hole];
      var score = s.score, hits = s.hits;
      if (h.kind == 'mole' || h.kind == 'gold') {
        score += h.kind == 'gold' ? c.goldPoints : c.points;
        hits += 1;
      } else if (h.kind == 'bomb') {
        score = math.max(0, score - c.bombPenalty);
      }
      final holes = [...s.holes]..[a.hole] = MoleHole.empty;
      return s.copyWith(holes: List.unmodifiable(holes), score: score, hits: hits);
    }
    if (a.op != 'tick' || a.n < 1) throw IllegalAction(id, a);
    final holes = [...s.holes];
    var tick = s.tick, nextSpawn = s.nextSpawn, misses = s.misses, rng = s.rng;
    var over = false;
    for (var k = 0; k < a.n && !over; k++) {
      tick += 1;
      for (var i = 0; i < holes.length; i++) {
        final h = holes[i];
        if (h.left <= 0) continue;
        final left = h.left - 1;
        if (left == 0) {
          if (h.kind == 'mole' || h.kind == 'gold') misses += 1;
          holes[i] = MoleHole.empty;
        } else {
          holes[i] = MoleHole(h.kind, left);
        }
      }
      nextSpawn -= 1;
      if (nextSpawn == 0) {
        nextSpawn = c.spawnEvery[c.level - 1];
        final empty = [
          for (var i = 0; i < holes.length; i++)
            if (holes[i].kind == '') i,
        ];
        if (empty.isNotEmpty) {
          final r = withRng(rng, (p) {
            final hole = empty[p.nextInt(empty.length)];
            return (hole: hole, roll: p.nextInt(100));
          });
          rng = r.rng;
          final bomb = c.bombPct[c.level - 1];
          final roll = r.value.roll;
          final kind = roll < bomb
              ? 'bomb'
              : roll < bomb + c.goldPct
              ? 'gold'
              : 'mole';
          holes[r.value.hole] = MoleHole(kind, c.upTicks[c.level - 1]);
        }
      }
      if (tick >= c.gameTicks) over = true;
    }
    return KrtekState(
      tick: tick,
      holes: List.unmodifiable(holes),
      nextSpawn: nextSpawn,
      score: s.score,
      hits: s.hits,
      misses: misses,
      over: over,
      rng: rng,
    );
  }

  @override
  KrtekAction aiAction(KrtekState s, int level, Prng ai) => const KrtekAction.tick(1);

  @override
  KrtekResult? result(KrtekState s) {
    if (!s.over) return null;
    final ss = config.starScores;
    final stars = s.score >= ss[0]
        ? 3
        : s.score >= ss[1]
        ? 2
        : s.score >= ss[2]
        ? 1
        : 0;
    return KrtekResult(
      winner: stars >= 1 ? 'player' : 'ai',
      stars: stars,
      score: s.score,
      hits: s.hits,
      misses: s.misses,
    );
  }

  @override
  KrtekAction actionFromJson(Map<String, Object?> j) {
    if (j['by'] == 'timeout') return const KrtekAction.timeout();
    return KrtekAction._(j['by'] as String, j['op'] as String, (j['n'] as int?) ?? 0, (j['hole'] as int?) ?? 0);
  }

  @override
  Map<String, Object?> stateToJson(KrtekState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(KrtekResult r) => r.toJson();
}
