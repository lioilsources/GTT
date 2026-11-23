import 'dart:math' as math;

import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/doubledutch.md, version 1 (engine `rhythm`). Pure Dart: no Flutter imports here.
class DoubledutchConfig {
  const DoubledutchConfig({
    required this.level,
    required this.beats,
    required this.introBeats,
    required this.startGapMs,
    required this.minGapMs,
    required this.speedupEvery,
    required this.speedupMs,
    required this.trickPct,
    required this.perfectMs,
    required this.goodMs,
    required this.okMs,
    required this.maxTrips,
    required this.perfectPts,
    required this.goodPts,
    required this.okPts,
    required this.trickMult,
    required this.comboStep,
    required this.maxMult,
    required this.starPct,
  });

  factory DoubledutchConfig.fromTuning(TuningMinigamesDoubledutch t, int level) => DoubledutchConfig(
    level: level,
    beats: t.beats,
    introBeats: t.introBeats,
    startGapMs: List.unmodifiable(t.startGapMs),
    minGapMs: List.unmodifiable(t.minGapMs),
    speedupEvery: t.speedupEvery,
    speedupMs: t.speedupMs,
    trickPct: List.unmodifiable(t.trickPct),
    perfectMs: t.perfectMs,
    goodMs: t.goodMs,
    okMs: t.okMs,
    maxTrips: t.maxTrips,
    perfectPts: t.perfectPts,
    goodPts: t.goodPts,
    okPts: t.okPts,
    trickMult: t.trickMult,
    comboStep: t.comboStep,
    maxMult: t.maxMult,
    starPct: List.unmodifiable(t.starPct),
  );

  factory DoubledutchConfig.fromJson(Map<String, Object?> j) {
    List<int> ints(String k) => List.unmodifiable((j[k] as List).cast<int>());
    int i(String k) => j[k] as int;
    return DoubledutchConfig(
      level: i('level'),
      beats: i('beats'),
      introBeats: i('introBeats'),
      startGapMs: ints('startGapMs'),
      minGapMs: ints('minGapMs'),
      speedupEvery: i('speedupEvery'),
      speedupMs: i('speedupMs'),
      trickPct: ints('trickPct'),
      perfectMs: i('perfectMs'),
      goodMs: i('goodMs'),
      okMs: i('okMs'),
      maxTrips: i('maxTrips'),
      perfectPts: i('perfectPts'),
      goodPts: i('goodPts'),
      okPts: i('okPts'),
      trickMult: i('trickMult'),
      comboStep: i('comboStep'),
      maxMult: i('maxMult'),
      starPct: ints('starPct'),
    );
  }

  final int level, beats, introBeats, speedupEvery, speedupMs, perfectMs, goodMs, okMs, maxTrips;
  final int perfectPts, goodPts, okPts, trickMult, comboStep, maxMult;
  final List<int> startGapMs, minGapMs, trickPct, starPct;

  /// Gap (ms) from beat i − 1 to beat i ≥ 1 (spec "Rozestupy úderů").
  int gap(int i) => math.max(minGapMs[level - 1], startGapMs[level - 1] - (i ~/ speedupEvery) * speedupMs);

  /// Beat times (ms from the start), the first beat at [leadInMs].
  List<int> beatTimes(int leadInMs) {
    final out = <int>[];
    for (var i = 0; i < beats; i++) {
      out.add(i == 0 ? leadInMs : out[i - 1] + gap(i));
    }
    return out;
  }

  /// Combo multiplier for a combo count.
  int mult(int combo) => 1 + math.min(combo ~/ comboStep, maxMult - 1);

  /// All perfect with an unbroken combo.
  int maxScore(List<int> kinds) {
    var m = 0;
    for (var i = 0; i < beats; i++) {
      m += perfectPts * (kinds[i] == 1 ? trickMult : 1) * mult(i + 1);
    }
    return m;
  }
}

class DoubledutchState {
  const DoubledutchState({
    required this.kinds,
    required this.next,
    required this.score,
    required this.combo,
    required this.bestCombo,
    required this.trips,
    required this.perfect,
    required this.good,
    required this.ok,
    required this.misses,
    required this.over,
    required this.rng,
  });

  /// 0 jump (tap), 1 trick (swipe up) per beat.
  final List<int> kinds;
  final int next, score, combo, bestCombo, trips, perfect, good, ok, misses;
  final bool over;
  final int rng;

  DoubledutchState copyWith({
    int? next,
    int? score,
    int? combo,
    int? bestCombo,
    int? trips,
    int? perfect,
    int? good,
    int? ok,
    int? misses,
    bool? over,
  }) => DoubledutchState(
    kinds: kinds,
    next: next ?? this.next,
    score: score ?? this.score,
    combo: combo ?? this.combo,
    bestCombo: bestCombo ?? this.bestCombo,
    trips: trips ?? this.trips,
    perfect: perfect ?? this.perfect,
    good: good ?? this.good,
    ok: ok ?? this.ok,
    misses: misses ?? this.misses,
    over: over ?? this.over,
    rng: rng,
  );

  Map<String, Object?> toJson() => {
    'kinds': kinds,
    'next': next,
    'score': score,
    'combo': combo,
    'bestCombo': bestCombo,
    'trips': trips,
    'perfect': perfect,
    'good': good,
    'ok': ok,
    'misses': misses,
    'over': over,
    'rng': rng,
  };
}

/// {by: player, op: hit, input, errMs}, {by: player, op: miss} or {by: timeout}. Fields stay as
/// read so [DoubledutchRules.apply] can reject malformed ones.
class DoubledutchAction {
  const DoubledutchAction._(this.by, this.op, this.input, this.errMs);
  const DoubledutchAction.hit(int input, int errMs) : this._('player', 'hit', input, errMs);
  const DoubledutchAction.miss() : this._('player', 'miss', null, null);
  const DoubledutchAction.timeout() : this._('timeout', '', null, null);

  factory DoubledutchAction.fromJson(Map<String, Object?> j) {
    final input = j['input'], err = j['errMs'];
    return DoubledutchAction._(
      j['by'] as String? ?? '',
      j['op'] as String? ?? '',
      input is int ? input : (input == null ? null : -1),
      err is int ? err : null,
    );
  }

  final String by, op;
  final int? input, errMs;

  Map<String, Object?> toJson() => switch ((by, op)) {
    ('timeout', _) => {'by': by},
    (_, 'hit') => {'by': by, 'op': op, 'input': input, 'errMs': errMs},
    _ => {'by': by, 'op': op},
  };

  @override
  String toString() => toJson().toString();
}

class DoubledutchResult {
  const DoubledutchResult(this.winner, this.stars, this.score, this.pct, this.bestCombo, this.misses);
  final String winner;
  final int stars, score, pct, bestCombo, misses;

  Map<String, Object?> toJson() => {
    'winner': winner,
    'stars': stars,
    'score': score,
    'pct': pct,
    'bestCombo': bestCombo,
    'misses': misses,
  };
}

class DoubledutchRules extends MgRules<DoubledutchState, DoubledutchAction, DoubledutchResult> {
  DoubledutchConfig? _cfg;

  DoubledutchConfig get config => _cfg ?? (throw StateError('doubledutch: init first'));

  @override
  String get id => 'doubledutch';

  @override
  int get specVersion => 1;

  @override
  DoubledutchState init(Map<String, Object?> config, int seed) => start(DoubledutchConfig.fromJson(config), seed);

  /// One generator; it draws only for beats from introBeats on, in beat order.
  DoubledutchState start(DoubledutchConfig c, int seed) {
    _cfg = c;
    final r = Prng(seed);
    final pct = c.trickPct[c.level - 1];
    final kinds = <int>[
      for (var i = 0; i < c.beats; i++)
        if (i < c.introBeats) 0 else (r.nextInt(100) < pct ? 1 : 0),
    ];
    return DoubledutchState(
      kinds: List.unmodifiable(kinds),
      next: 0,
      score: 0,
      combo: 0,
      bestCombo: 0,
      trips: 0,
      perfect: 0,
      good: 0,
      ok: 0,
      misses: 0,
      over: false,
      rng: r.state,
    );
  }

  @override
  List<DoubledutchAction> legalActions(DoubledutchState s) =>
      s.over ? const [] : [DoubledutchAction.hit(s.kinds[s.next], 0), const DoubledutchAction.miss()];

  @override
  DoubledutchState apply(DoubledutchState s, DoubledutchAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(over: true);
    if (a.by != 'player') throw IllegalAction(id, a);
    final c = config;
    final kind = s.kinds[s.next];
    var n = s;
    bool missed;
    if (a.op == 'miss') {
      missed = true;
    } else if (a.op == 'hit') {
      final input = a.input, err = a.errMs;
      if ((input != 0 && input != 1) || err == null) throw IllegalAction(id, a);
      final e = err.abs();
      missed = input != kind || e > c.okMs;
      if (!missed) {
        final combo = s.combo + 1;
        final mult = c.mult(combo);
        final perfect = e <= c.perfectMs, good = !perfect && e <= c.goodMs, ok = !perfect && !good;
        final base = perfect ? c.perfectPts : (good ? c.goodPts : c.okPts);
        n = s.copyWith(
          combo: combo,
          bestCombo: math.max(s.bestCombo, combo),
          perfect: s.perfect + (perfect ? 1 : 0),
          good: s.good + (good ? 1 : 0),
          ok: s.ok + (ok ? 1 : 0),
          score: s.score + base * (kind == 1 ? c.trickMult : 1) * mult,
        );
      }
    } else {
      throw IllegalAction(id, a);
    }
    if (missed) n = n.copyWith(misses: n.misses + 1, trips: n.trips + 1, combo: 0);
    final next = n.next + 1;
    return n.copyWith(next: next, over: next == c.beats || n.trips == c.maxTrips);
  }

  @override
  DoubledutchAction aiAction(DoubledutchState s, int level, Prng ai) => throw StateError('doubledutch: no opponent');

  @override
  DoubledutchResult? result(DoubledutchState s) {
    if (!s.over) return null;
    final c = config;
    final max = c.maxScore(s.kinds);
    final pct = max > 0 ? s.score * 100 ~/ max : 0;
    final stars = pct >= c.starPct[0]
        ? 3
        : pct >= c.starPct[1]
        ? 2
        : pct >= c.starPct[2]
        ? 1
        : 0;
    return DoubledutchResult(stars >= 1 ? 'player' : 'ai', stars, s.score, pct, s.bestCombo, s.misses);
  }

  @override
  DoubledutchAction actionFromJson(Map<String, Object?> j) => DoubledutchAction.fromJson(j);

  @override
  Map<String, Object?> stateToJson(DoubledutchState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(DoubledutchResult r) => r.toJson();
}

/// Which beat an input at [atMs] belongs to: `next` when it comes at most okMs before its time
/// or later; null (ignored) when earlier. Returns floor(atMs − beat time).
int? inputErr(List<int> times, int next, double atMs, int okMs) {
  if (next >= times.length || atMs < times[next] - okMs) return null;
  return (atMs - times[next]).floor();
}
