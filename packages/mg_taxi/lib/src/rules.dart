import 'dart:math' as math;

import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/taxi.md, version 1: shift bookkeeping (P0, integers only).
/// Port of web/src/minigames/taxi/rules.ts.
class TaxiConfig {
  const TaxiConfig({
    required this.dests,
    required this.lines,
    required this.fareBase,
    required this.farePerKm,
    required this.expectBaseS,
    required this.expectDmPerS,
    required this.bonusPerS,
    required this.bonusMaxPct,
    required this.latePerS,
    required this.lateMaxPct,
    required this.tipPct,
    required this.hitTipPct,
    required this.starFares,
  });

  /// Config from tuning (minigames.taxi) and the destination ids of the city.
  factory TaxiConfig.fromTuning(TuningMinigamesTaxi t, List<String> dests) => TaxiConfig(
    dests: List.unmodifiable(dests),
    lines: t.lines,
    fareBase: t.fareBase,
    farePerKm: t.farePerKm,
    expectBaseS: t.expectBaseS,
    expectDmPerS: t.expectDmPerS,
    bonusPerS: t.bonusPerS,
    bonusMaxPct: t.bonusMaxPct,
    latePerS: t.latePerS,
    lateMaxPct: t.lateMaxPct,
    tipPct: t.tipPct,
    hitTipPct: t.hitTipPct,
    starFares: List.unmodifiable(t.starFares),
  );

  factory TaxiConfig.fromJson(Map<String, Object?> j) => TaxiConfig(
    dests: (j['dests'] as List).cast<String>(),
    lines: j['lines'] as int,
    fareBase: j['fareBase'] as int,
    farePerKm: j['farePerKm'] as int,
    expectBaseS: j['expectBaseS'] as int,
    expectDmPerS: j['expectDmPerS'] as int,
    bonusPerS: j['bonusPerS'] as int,
    bonusMaxPct: j['bonusMaxPct'] as int,
    latePerS: j['latePerS'] as int,
    lateMaxPct: j['lateMaxPct'] as int,
    tipPct: j['tipPct'] as int,
    hitTipPct: j['hitTipPct'] as int,
    starFares: (j['starFares'] as List).cast<int>(),
  );

  final List<String> dests;
  final int lines, fareBase, farePerKm, expectBaseS, expectDmPerS, bonusPerS, bonusMaxPct, latePerS, lateMaxPct;
  final int tipPct, hitTipPct;

  /// Shift fare for 3, 2, 1 stars.
  final List<int> starFares;
}

/// The breakdown of one ride (specs/minigames/taxi.md "apply – dropoff").
class TaxiRide {
  const TaxiRide({
    this.dest = '',
    this.distDm = 0,
    this.rideS = 0,
    this.expectS = 0,
    this.meter = 0,
    this.time = 0,
    this.tip = 0,
    this.fare = 0,
  });
  final String dest;
  final int distDm, rideS, expectS, meter, time, tip, fare;

  Map<String, Object?> toJson() => {
    'dest': dest,
    'distDm': distDm,
    'rideS': rideS,
    'expectS': expectS,
    'meter': meter,
    'time': time,
    'tip': tip,
    'fare': fare,
  };
}

class TaxiState {
  const TaxiState({
    required this.rng,
    this.phase = 'wait',
    this.clockMs = 0,
    this.fare = 0,
    this.rides = 0,
    this.dest = '',
    this.line = -1,
    this.pickMs = 0,
    this.hits = 0,
    this.lastDest = '',
    this.last = const TaxiRide(),
  });

  final int rng;

  /// 'wait', 'ride' or 'over'.
  final String phase;
  final int clockMs, fare, rides, line, pickMs, hits;
  final String dest, lastDest;
  final TaxiRide last;

  TaxiState copyWith({
    int? rng,
    String? phase,
    int? clockMs,
    int? fare,
    int? rides,
    String? dest,
    int? line,
    int? pickMs,
    int? hits,
    String? lastDest,
    TaxiRide? last,
  }) => TaxiState(
    rng: rng ?? this.rng,
    phase: phase ?? this.phase,
    clockMs: clockMs ?? this.clockMs,
    fare: fare ?? this.fare,
    rides: rides ?? this.rides,
    dest: dest ?? this.dest,
    line: line ?? this.line,
    pickMs: pickMs ?? this.pickMs,
    hits: hits ?? this.hits,
    lastDest: lastDest ?? this.lastDest,
    last: last ?? this.last,
  );

  Map<String, Object?> toJson() => {
    'rng': rng,
    'phase': phase,
    'clockMs': clockMs,
    'fare': fare,
    'rides': rides,
    'dest': dest,
    'line': line,
    'pickMs': pickMs,
    'hits': hits,
    'lastDest': lastDest,
    'last': last.toJson(),
  };
}

/// `by` is 'player' or 'timeout'; `op` is pickup, hit or dropoff for the player.
class TaxiAction {
  const TaxiAction.pickup(int this.atMs, this.allow) : by = 'player', op = 'pickup', distDm = null;
  const TaxiAction.hit() : by = 'player', op = 'hit', atMs = null, allow = const [], distDm = null;
  const TaxiAction.dropoff(int this.atMs, int this.distDm) : by = 'player', op = 'dropoff', allow = const [];
  const TaxiAction.timeout() : by = 'timeout', op = '', atMs = null, allow = const [], distDm = null;

  final String by, op;
  final int? atMs, distDm;
  final List<String> allow;

  Map<String, Object?> toJson() => switch (op) {
    'pickup' => {'by': by, 'op': op, 'atMs': atMs, 'allow': allow},
    'hit' => {'by': by, 'op': op},
    'dropoff' => {'by': by, 'op': op, 'atMs': atMs, 'distDm': distDm},
    _ => {'by': by},
  };

  @override
  String toString() => 'taxi ${toJson()}';
}

class TaxiResult {
  const TaxiResult({required this.winner, required this.stars, required this.score, required this.rides});
  final String winner;
  final int stars, score, rides;

  Map<String, Object?> toJson() => {'winner': winner, 'stars': stars, 'score': score, 'rides': rides};
}

/// Fare of one ride (specs/minigames/taxi.md "apply – dropoff"); `dest` is left empty.
TaxiRide taxiFare(TaxiConfig c, int distDm, int rideMs, int hits) {
  final rideS = rideMs ~/ 1000;
  final expectS = c.expectBaseS + distDm ~/ c.expectDmPerS;
  final meter = c.fareBase + distDm * c.farePerKm ~/ 10000;
  final diff = expectS - rideS;
  final time = diff >= 0
      ? math.min(diff * c.bonusPerS, meter * c.bonusMaxPct ~/ 100)
      : -math.min(-diff * c.latePerS, meter * c.lateMaxPct ~/ 100);
  final tip = meter * math.max(0, c.tipPct - hits * c.hitTipPct) ~/ 100;
  return TaxiRide(
    distDm: distDm,
    rideS: rideS,
    expectS: expectS,
    meter: meter,
    time: time,
    tip: tip,
    fare: meter + time + tip,
  );
}

/// Stars for a shift fare: starFares is [3★, 2★, 1★].
int taxiStars(TaxiConfig c, int fare) {
  for (var i = 0; i < 3 && i < c.starFares.length; i++) {
    if (fare >= c.starFares[i]) return 3 - i;
  }
  return 0;
}

class TaxiRules extends MgRules<TaxiState, TaxiAction, TaxiResult> {
  @override
  String get id => 'taxi';
  @override
  int get specVersion => 1;

  TaxiConfig? _cfg;
  TaxiConfig get config => _cfg ?? (throw StateError('taxi: init first'));

  TaxiState start(TaxiConfig c, int seed) {
    _cfg = c;
    return TaxiState(rng: Prng(seed).state);
  }

  @override
  TaxiState init(Map<String, Object?> config, int seed) => start(TaxiConfig.fromJson(config), seed);

  @override
  List<TaxiAction> legalActions(TaxiState s) => switch (s.phase) {
    'wait' => [TaxiAction.pickup(s.clockMs, const []), const TaxiAction.timeout()],
    'ride' => const [TaxiAction.hit(), TaxiAction.timeout()],
    _ => const [],
  };

  @override
  TaxiState apply(TaxiState s, TaxiAction a) {
    final c = config;
    if (s.phase == 'over') throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(phase: 'over');
    if (a.by != 'player') throw IllegalAction(id, a);
    switch (a.op) {
      case 'pickup':
        final at = a.atMs;
        if (s.phase != 'wait' ||
            at == null ||
            at < s.clockMs ||
            c.dests.isEmpty ||
            a.allow.any((d) => !c.dests.contains(d))) {
          throw IllegalAction(id, a);
        }
        var pool = a.allow.isEmpty ? [...c.dests] : c.dests.where(a.allow.contains).toList();
        if (pool.length > 1) pool = pool.where((d) => d != s.lastDest).toList();
        final r = withRng(s.rng, (p) => (dest: pool[p.nextInt(pool.length)], line: p.nextInt(c.lines)));
        return s.copyWith(
          rng: r.rng,
          phase: 'ride',
          dest: r.value.dest,
          line: r.value.line,
          pickMs: at,
          clockMs: at,
          hits: 0,
        );
      case 'hit':
        if (s.phase != 'ride') throw IllegalAction(id, a);
        return s.copyWith(hits: s.hits + 1);
      case 'dropoff':
        final at = a.atMs, dist = a.distDm;
        if (s.phase != 'ride' || at == null || at < s.pickMs || dist == null || dist < 0) throw IllegalAction(id, a);
        final f = taxiFare(c, dist, at - s.pickMs, s.hits);
        final last = TaxiRide(
          dest: s.dest,
          distDm: f.distDm,
          rideS: f.rideS,
          expectS: f.expectS,
          meter: f.meter,
          time: f.time,
          tip: f.tip,
          fare: f.fare,
        );
        return s.copyWith(
          phase: 'wait',
          fare: s.fare + last.fare,
          rides: s.rides + 1,
          lastDest: s.dest,
          dest: '',
          line: -1,
          hits: 0,
          clockMs: at,
          last: last,
        );
    }
    throw IllegalAction(id, a);
  }

  @override
  TaxiAction aiAction(TaxiState state, int level, Prng ai) => throw UnsupportedError('taxi: no opponent');

  @override
  TaxiResult? result(TaxiState s) {
    if (s.phase != 'over') return null;
    final stars = taxiStars(config, s.fare);
    return TaxiResult(winner: stars >= 1 ? 'player' : 'draw', stars: stars, score: s.fare, rides: s.rides);
  }

  /// Strict JSON reading: wrong types are illegal actions (the web side checks the same).
  @override
  TaxiAction actionFromJson(Map<String, Object?> j) {
    if (j['by'] == 'timeout') return const TaxiAction.timeout();
    if (j['by'] != 'player') throw IllegalAction(id, j);
    switch (j['op']) {
      case 'pickup':
        final at = j['atMs'], allow = j['allow'];
        if (at is! int || allow is! List || allow.any((d) => d is! String)) throw IllegalAction(id, j);
        return TaxiAction.pickup(at, allow.cast<String>());
      case 'hit':
        return const TaxiAction.hit();
      case 'dropoff':
        final at = j['atMs'], dist = j['distDm'];
        if (at is! int || dist is! int) throw IllegalAction(id, j);
        return TaxiAction.dropoff(at, dist);
    }
    throw IllegalAction(id, j);
  }

  @override
  Map<String, Object?> stateToJson(TaxiState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(TaxiResult r) => r.toJson();
}
