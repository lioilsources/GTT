import 'dart:math' as math;

import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/sprint.md, version 1: destination pick, checkpoint order, time and stars (P0,
/// integers only). Port of web/src/minigames/sprint/rules.ts.
class SprintConfig {
  const SprintConfig({
    required this.dests,
    required this.level,
    required this.parBaseMs,
    required this.parDmPerS,
    required this.hitPenaltyMs,
    required this.starPct,
  });

  /// Config from tuning (minigames.sprint), the destination ids of the city and the difficulty.
  factory SprintConfig.fromTuning(TuningMinigamesSprint t, List<String> dests, int level) => SprintConfig(
    dests: List.unmodifiable(dests),
    level: level,
    parBaseMs: t.parBaseMs,
    parDmPerS: List.unmodifiable(t.parDmPerS),
    hitPenaltyMs: t.hitPenaltyMs,
    starPct: List.unmodifiable(t.starPct),
  );

  factory SprintConfig.fromJson(Map<String, Object?> j) => SprintConfig(
    dests: List.unmodifiable((j['dests'] as List).cast<String>()),
    level: j['level'] as int,
    parBaseMs: j['parBaseMs'] as int,
    parDmPerS: List.unmodifiable((j['parDmPerS'] as List).cast<int>()),
    hitPenaltyMs: j['hitPenaltyMs'] as int,
    starPct: List.unmodifiable((j['starPct'] as List).cast<int>()),
  );

  /// Destination ids in pack order (the Taxi definition).
  final List<String> dests;
  final int level, parBaseMs, hitPenaltyMs;

  /// Par average speed (dm/s) by difficulty 1–5; time in % of par for 3, 2, 1 stars.
  final List<int> parDmPerS, starPct;

  /// Par for a route of [distDm].
  int par(int distDm) => parBaseMs + distDm * 1000 ~/ parDmPerS[level - 1];

  /// Stars for a finished time against par.
  int stars(int timeMs, int parMs) {
    for (var i = 0; i < 3; i++) {
      if (timeMs * 100 <= parMs * starPct[i]) return 3 - i;
    }
    return 0;
  }
}

class SprintState {
  const SprintState({
    required this.rng,
    this.phase = 'pick',
    this.dest = '',
    this.distDm = 0,
    this.cps = 0,
    this.parMs = 0,
    this.goMs = 0,
    this.clockMs = 0,
    this.passed = 0,
    this.splits = const [],
    this.hits = 0,
    this.finished = false,
    this.timeMs = 0,
  });

  final int rng;

  /// 'pick', 'ready', 'run' or 'over'.
  final String phase;
  final String dest;
  final int distDm, cps, parMs, goMs, clockMs, passed, hits, timeMs;
  final List<int> splits;
  final bool finished;

  SprintState copyWith({
    int? rng,
    String? phase,
    String? dest,
    int? distDm,
    int? cps,
    int? parMs,
    int? goMs,
    int? clockMs,
    int? passed,
    List<int>? splits,
    int? hits,
    bool? finished,
    int? timeMs,
  }) => SprintState(
    rng: rng ?? this.rng,
    phase: phase ?? this.phase,
    dest: dest ?? this.dest,
    distDm: distDm ?? this.distDm,
    cps: cps ?? this.cps,
    parMs: parMs ?? this.parMs,
    goMs: goMs ?? this.goMs,
    clockMs: clockMs ?? this.clockMs,
    passed: passed ?? this.passed,
    splits: splits ?? this.splits,
    hits: hits ?? this.hits,
    finished: finished ?? this.finished,
    timeMs: timeMs ?? this.timeMs,
  );

  Map<String, Object?> toJson() => {
    'rng': rng,
    'phase': phase,
    'dest': dest,
    'distDm': distDm,
    'cps': cps,
    'parMs': parMs,
    'goMs': goMs,
    'clockMs': clockMs,
    'passed': passed,
    'splits': splits,
    'hits': hits,
    'finished': finished,
    'timeMs': timeMs,
  };
}

/// {by: player, op: pick | go | cp | hit | finish, …} or {by: timeout}.
class SprintAction {
  const SprintAction.pick(this.allow) : by = 'player', op = 'pick', atMs = 0, distDm = 0, cps = 0, index = 0;
  const SprintAction.go(this.atMs, this.distDm, this.cps) : by = 'player', op = 'go', allow = const [], index = 0;
  const SprintAction.cp(this.atMs, this.index) : by = 'player', op = 'cp', allow = const [], distDm = 0, cps = 0;
  const SprintAction.hit(this.atMs) : by = 'player', op = 'hit', allow = const [], distDm = 0, cps = 0, index = 0;
  const SprintAction.finish(this.atMs) : by = 'player', op = 'finish', allow = const [], distDm = 0, cps = 0, index = 0;
  const SprintAction.timeout() : by = 'timeout', op = '', allow = const [], atMs = 0, distDm = 0, cps = 0, index = 0;

  final String by, op;
  final List<String> allow;
  final int atMs, distDm, cps, index;

  Map<String, Object?> toJson() => switch (op) {
    'pick' => {'by': by, 'op': op, 'allow': allow},
    'go' => {'by': by, 'op': op, 'atMs': atMs, 'distDm': distDm, 'cps': cps},
    'cp' => {'by': by, 'op': op, 'atMs': atMs, 'index': index},
    'hit' || 'finish' => {'by': by, 'op': op, 'atMs': atMs},
    _ => {'by': by},
  };

  @override
  String toString() => toJson().toString();
}

class SprintResult {
  const SprintResult({
    required this.winner,
    required this.stars,
    required this.score,
    required this.timeMs,
    required this.parMs,
    required this.dest,
    required this.hits,
  });
  final String winner, dest;
  final int stars, score, timeMs, parMs, hits;

  Map<String, Object?> toJson() => {
    'winner': winner,
    'stars': stars,
    'score': score,
    'timeMs': timeMs,
    'parMs': parMs,
    'dest': dest,
    'hits': hits,
  };
}

class SprintRules extends MgRules<SprintState, SprintAction, SprintResult> {
  SprintConfig? _cfg;

  SprintConfig get config => _cfg ?? (throw StateError('sprint: init first'));

  @override
  String get id => 'sprint';

  @override
  int get specVersion => 1;

  @override
  SprintState init(Map<String, Object?> config, int seed) => start(SprintConfig.fromJson(config), seed);

  SprintState start(SprintConfig config, int seed) {
    _cfg = config;
    return SprintState(rng: Prng(seed).state);
  }

  @override
  List<SprintAction> legalActions(SprintState s) => switch (s.phase) {
    'pick' => const [SprintAction.pick([]), SprintAction.timeout()],
    'ready' => [SprintAction.go(s.clockMs, 0, 0), const SprintAction.timeout()],
    'run' => [
      if (s.passed < s.cps) SprintAction.cp(s.clockMs, s.passed),
      SprintAction.hit(s.clockMs),
      if (s.passed == s.cps) SprintAction.finish(s.clockMs),
      const SprintAction.timeout(),
    ],
    _ => const [],
  };

  @override
  SprintState apply(SprintState s, SprintAction a) {
    if (s.phase == 'over') throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(phase: 'over');
    if (a.by != 'player') throw IllegalAction(id, a);
    final c = config;
    if (a.op == 'pick') {
      if (s.phase != 'pick' || a.allow.any((d) => !c.dests.contains(d))) throw IllegalAction(id, a);
      final pool = a.allow.isEmpty ? c.dests : c.dests.where(a.allow.contains).toList();
      // City without destinations: over without a draw.
      if (pool.isEmpty) return s.copyWith(phase: 'over', finished: false);
      final r = withRng(s.rng, (p) => pool[p.nextInt(pool.length)]);
      return s.copyWith(rng: r.rng, dest: r.value, phase: 'ready');
    }
    if (a.atMs < s.clockMs) throw IllegalAction(id, a);
    switch (a.op) {
      case 'go':
        if (s.phase != 'ready' || a.distDm < 0 || a.cps < 0) throw IllegalAction(id, a);
        return s.copyWith(
          goMs: a.atMs,
          clockMs: a.atMs,
          distDm: a.distDm,
          cps: a.cps,
          parMs: c.par(a.distDm),
          phase: 'run',
        );
      case 'cp':
        if (s.phase != 'run' || a.index != s.passed || s.passed >= s.cps) throw IllegalAction(id, a);
        return s.copyWith(clockMs: a.atMs, passed: s.passed + 1, splits: [...s.splits, a.atMs - s.goMs]);
      case 'hit':
        if (s.phase != 'run') throw IllegalAction(id, a);
        return s.copyWith(clockMs: a.atMs, hits: s.hits + 1);
      case 'finish':
        if (s.phase != 'run' || s.passed != s.cps) throw IllegalAction(id, a);
        return s.copyWith(
          clockMs: a.atMs,
          timeMs: a.atMs - s.goMs + s.hits * c.hitPenaltyMs,
          finished: true,
          phase: 'over',
        );
    }
    throw IllegalAction(id, a);
  }

  @override
  SprintAction aiAction(SprintState state, int level, Prng ai) => throw UnsupportedError('sprint: no opponent');

  @override
  SprintResult? result(SprintState s) {
    if (s.phase != 'over') return null;
    final c = config;
    final stars = s.finished ? c.stars(s.timeMs, s.parMs) : 0;
    final score = s.finished ? math.max(0, 2 * s.parMs - s.timeMs) ~/ 100 : 0;
    return SprintResult(
      winner: stars >= 1 ? 'player' : 'draw',
      stars: stars,
      score: score,
      timeMs: s.timeMs,
      parMs: s.parMs,
      dest: s.dest,
      hits: s.hits,
    );
  }

  /// Strict JSON reading: wrong types are illegal actions (the web side checks the same).
  @override
  SprintAction actionFromJson(Map<String, Object?> j) {
    if (j['by'] == 'timeout') return const SprintAction.timeout();
    if (j['by'] != 'player') throw IllegalAction(id, j);
    final op = j['op'];
    if (op == 'pick') {
      final allow = j['allow'];
      if (allow is! List || allow.any((d) => d is! String)) throw IllegalAction(id, j);
      return SprintAction.pick(List.unmodifiable(allow.cast<String>()));
    }
    final at = j['atMs'];
    if (at is! int) throw IllegalAction(id, j);
    switch (op) {
      case 'go':
        final dist = j['distDm'], cps = j['cps'];
        if (dist is! int || cps is! int) throw IllegalAction(id, j);
        return SprintAction.go(at, dist, cps);
      case 'cp':
        final index = j['index'];
        if (index is! int) throw IllegalAction(id, j);
        return SprintAction.cp(at, index);
      case 'hit':
        return SprintAction.hit(at);
      case 'finish':
        return SprintAction.finish(at);
    }
    throw IllegalAction(id, j);
  }

  @override
  Map<String, Object?> stateToJson(SprintState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(SprintResult r) => r.toJson();
}
