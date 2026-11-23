import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/stickball.md, version 1. Pure Dart: no Flutter imports here.
class StickballConfig {
  const StickballConfig({
    required this.level,
    required this.maxOuts,
    required this.strikesOut,
    required this.ballsWalk,
    required this.zonePct,
    required this.flightMin,
    required this.flightVar,
    required this.perfectMs,
    required this.goodMs,
    required this.okMs,
    required this.foulMs,
    required this.catchPct,
    required this.starRuns,
  });

  factory StickballConfig.fromTuning(TuningMinigamesStickball t, int level) => StickballConfig(
    level: level,
    maxOuts: t.maxOuts,
    strikesOut: t.strikesOut,
    ballsWalk: t.ballsWalk,
    zonePct: List.unmodifiable(t.zonePct),
    flightMin: List.unmodifiable(t.flightMin),
    flightVar: List.unmodifiable(t.flightVar),
    perfectMs: t.perfectMs,
    goodMs: t.goodMs,
    okMs: t.okMs,
    foulMs: t.foulMs,
    catchPct: List.unmodifiable(t.catchPct),
    starRuns: List.unmodifiable(t.starRuns),
  );

  factory StickballConfig.fromJson(Map<String, Object?> j) {
    List<int> ints(String k) => List.unmodifiable((j[k] as List).cast<int>());
    return StickballConfig(
      level: j['level'] as int,
      maxOuts: j['maxOuts'] as int,
      strikesOut: j['strikesOut'] as int,
      ballsWalk: j['ballsWalk'] as int,
      zonePct: ints('zonePct'),
      flightMin: ints('flightMin'),
      flightVar: ints('flightVar'),
      perfectMs: j['perfectMs'] as int,
      goodMs: j['goodMs'] as int,
      okMs: j['okMs'] as int,
      foulMs: j['foulMs'] as int,
      catchPct: ints('catchPct'),
      starRuns: ints('starRuns'),
    );
  }

  final int level, maxOuts, strikesOut, ballsWalk, perfectMs, goodMs, okMs, foulMs;
  final List<int> zonePct, flightMin, flightVar, catchPct, starRuns;

  /// Timing grade of a swing before lane and zone: 3 perfect … 0 foul, −1 miss.
  int grade(int errMs) {
    final e = errMs.abs();
    return e <= perfectMs
        ? 3
        : e <= goodMs
        ? 2
        : e <= okMs
        ? 1
        : e <= foulMs
        ? 0
        : -1;
  }
}

class StickballPitch {
  const StickballPitch(this.zone, this.lane, this.flightMs);

  static const none = StickballPitch(false, 0, 0);

  final bool zone;

  /// 0 low, 1 mid, 2 high.
  final int lane;
  final int flightMs;

  Map<String, Object?> toJson() => {'zone': zone, 'lane': lane, 'flightMs': flightMs};
}

class StickballState {
  const StickballState({
    required this.phase,
    required this.outs,
    required this.strikes,
    required this.balls,
    required this.bases,
    required this.runs,
    required this.hits,
    required this.homers,
    required this.pitch,
    required this.last,
    required this.rng,
  });

  /// 'pitch', 'bat' or 'over'.
  final String phase;
  final int outs, strikes, balls;

  /// Bit 0 first, bit 1 second, bit 2 third base.
  final int bases;
  final int runs, hits, homers;
  final StickballPitch pitch;

  /// '', ball, strike, foul, single, double, homer, catch, walk, strikeout.
  final String last;
  final int rng;

  bool get over => phase == 'over';

  StickballState copyWith({
    String? phase,
    int? outs,
    int? strikes,
    int? balls,
    int? bases,
    int? runs,
    int? hits,
    int? homers,
    StickballPitch? pitch,
    String? last,
    int? rng,
  }) => StickballState(
    phase: phase ?? this.phase,
    outs: outs ?? this.outs,
    strikes: strikes ?? this.strikes,
    balls: balls ?? this.balls,
    bases: bases ?? this.bases,
    runs: runs ?? this.runs,
    hits: hits ?? this.hits,
    homers: homers ?? this.homers,
    pitch: pitch ?? this.pitch,
    last: last ?? this.last,
    rng: rng ?? this.rng,
  );

  Map<String, Object?> toJson() => {
    'phase': phase,
    'outs': outs,
    'strikes': strikes,
    'balls': balls,
    'bases': bases,
    'runs': runs,
    'hits': hits,
    'homers': homers,
    'pitch': pitch.toJson(),
    'last': last,
    'rng': rng,
  };
}

/// {by: ai, op: pitch, zone, lane, flightMs}, {by: player, op: swing, lane, errMs},
/// {by: player, op: take} or {by: timeout}.
class StickballAction {
  const StickballAction.pitch(this.zone, this.lane, this.flightMs) : by = 'ai', op = 'pitch', errMs = 0;
  const StickballAction.swing(this.lane, this.errMs) : by = 'player', op = 'swing', zone = false, flightMs = 0;
  const StickballAction.take() : by = 'player', op = 'take', zone = false, lane = 0, flightMs = 0, errMs = 0;
  const StickballAction.timeout() : by = 'timeout', op = '', zone = false, lane = 0, flightMs = 0, errMs = 0;
  const StickballAction.raw(this.by, this.op, {this.zone, this.lane, this.flightMs, this.errMs});

  final String by, op;

  /// Null in a malformed action (missing or wrong type): illegal.
  final bool? zone;
  final int? lane, flightMs, errMs;

  Map<String, Object?> toJson() => switch (op) {
    _ when by == 'timeout' => {'by': by},
    'pitch' => {'by': by, 'op': op, 'zone': zone, 'lane': lane, 'flightMs': flightMs},
    'swing' => {'by': by, 'op': op, 'lane': lane, 'errMs': errMs},
    _ => {'by': by, 'op': op},
  };

  @override
  String toString() => toJson().toString();
}

class StickballResult {
  const StickballResult({
    required this.winner,
    required this.stars,
    required this.score,
    required this.hits,
    required this.homers,
  });

  final String winner;
  final int stars, score, hits, homers;

  Map<String, Object?> toJson() => {'winner': winner, 'stars': stars, 'score': score, 'hits': hits, 'homers': homers};
}

bool _isLane(int? v) => v != null && v >= 0 && v <= 2;

class StickballRules extends MgRules<StickballState, StickballAction, StickballResult> {
  StickballConfig? _cfg;

  StickballConfig get config => _cfg ?? (throw StateError('stickball: init first'));

  @override
  String get id => 'stickball';

  @override
  int get specVersion => 1;

  @override
  StickballState init(Map<String, Object?> config, int seed) => start(StickballConfig.fromJson(config), seed);

  StickballState start(StickballConfig config, int seed) {
    _cfg = config;
    return StickballState(
      phase: 'pitch',
      outs: 0,
      strikes: 0,
      balls: 0,
      bases: 0,
      runs: 0,
      hits: 0,
      homers: 0,
      pitch: StickballPitch.none,
      last: '',
      rng: Prng(seed).state,
    );
  }

  @override
  List<StickballAction> legalActions(StickballState s) => s.phase != 'bat'
      ? const []
      : const [
          StickballAction.take(),
          StickballAction.swing(0, 0),
          StickballAction.swing(1, 0),
          StickballAction.swing(2, 0),
        ];

  @override
  StickballState apply(StickballState s, StickballAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(phase: 'over');
    final c = config;
    if (a.by == 'ai') {
      final fl = a.flightMs;
      if (s.phase != 'pitch' || a.op != 'pitch' || a.zone == null || !_isLane(a.lane) || fl == null || fl < 1) {
        throw IllegalAction(id, a);
      }
      return s.copyWith(pitch: StickballPitch(a.zone!, a.lane!, fl), phase: 'bat', last: '');
    }
    if (a.by != 'player' || s.phase != 'bat') throw IllegalAction(id, a);
    if (a.op == 'take') {
      if (s.pitch.zone) return _strike(s);
      final balls = s.balls + 1;
      return balls == c.ballsWalk ? _walk(s) : s.copyWith(balls: balls, last: 'ball', phase: 'pitch');
    }
    if (a.op != 'swing' || !_isLane(a.lane) || a.errMs == null) throw IllegalAction(id, a);
    var g = c.grade(a.errMs!);
    if (g >= 0) {
      g -= (a.lane! - s.pitch.lane).abs();
      if (!s.pitch.zone) g -= 1;
    }
    if (g == 3) return _hit(s, 4);
    if (g == 2) return _hit(s, 2);
    if (g == 1) {
      final r = withRng(s.rng, (p) => p.nextInt(100));
      final s1 = s.copyWith(rng: r.rng);
      return r.value < c.catchPct[c.level - 1] ? _out(s1, 'catch') : _hit(s1, 1);
    }
    if (g == 0) {
      return s.copyWith(
        strikes: s.strikes < c.strikesOut - 1 ? s.strikes + 1 : s.strikes,
        last: 'foul',
        phase: 'pitch',
      );
    }
    return _strike(s);
  }

  /// At-bat over: count reset, game over at maxOuts.
  StickballState _atBatOver(StickballState s, String last) =>
      s.copyWith(strikes: 0, balls: 0, last: last, phase: s.outs == config.maxOuts ? 'over' : 'pitch');

  StickballState _strike(StickballState s) {
    final strikes = s.strikes + 1;
    if (strikes == config.strikesOut) return _out(s, 'strikeout');
    return s.copyWith(strikes: strikes, last: 'strike', phase: 'pitch');
  }

  StickballState _out(StickballState s, String last) => _atBatOver(s.copyWith(outs: s.outs + 1), last);

  StickballState _hit(StickballState s, int k) {
    var runs = s.runs, bases = 0;
    for (var p = 1; p <= 3; p++) {
      if (s.bases & (1 << (p - 1)) == 0) continue;
      final q = p + k;
      if (q >= 4) {
        runs++;
      } else {
        bases |= 1 << (q - 1);
      }
    }
    if (k >= 4) {
      runs++;
    } else {
      bases |= 1 << (k - 1);
    }
    return _atBatOver(
      s.copyWith(runs: runs, bases: bases, hits: s.hits + 1, homers: s.homers + (k == 4 ? 1 : 0)),
      k == 4
          ? 'homer'
          : k == 2
          ? 'double'
          : 'single',
    );
  }

  StickballState _walk(StickballState s) {
    final b = s.bases;
    var n = b | 1;
    if (b & 1 != 0) {
      n |= 2;
      if (b & 2 != 0) n |= 4;
    }
    return _atBatOver(s.copyWith(runs: s.runs + (b & 7 == 7 ? 1 : 0), bases: n & 7), 'walk');
  }

  @override
  StickballAction aiAction(StickballState s, int level, Prng ai) {
    if (s.phase != 'pitch') throw StateError('stickball: not pitching');
    final c = config;
    final zone = ai.nextInt(100) < c.zonePct[level - 1];
    final lane = ai.nextInt(3);
    final flightMs = c.flightMin[level - 1] + ai.nextInt(c.flightVar[level - 1] + 1);
    return StickballAction.pitch(zone, lane, flightMs);
  }

  @override
  StickballResult? result(StickballState s) {
    if (!s.over) return null;
    final r = config.starRuns;
    final stars = s.runs >= r[0]
        ? 3
        : s.runs >= r[1]
        ? 2
        : s.runs >= r[2]
        ? 1
        : 0;
    return StickballResult(
      winner: stars >= 1 ? 'player' : 'ai',
      stars: stars,
      score: s.runs,
      hits: s.hits,
      homers: s.homers,
    );
  }

  @override
  StickballAction actionFromJson(Map<String, Object?> j) {
    if (j['by'] == 'timeout') return const StickballAction.timeout();
    final z = j['zone'], l = j['lane'], f = j['flightMs'], e = j['errMs'];
    return StickballAction.raw(
      j['by'] as String? ?? '',
      j['op'] as String? ?? '',
      zone: z is bool ? z : null,
      lane: l is int ? l : null,
      flightMs: f is int ? f : null,
      errMs: e is int ? e : null,
    );
  }

  @override
  Map<String, Object?> stateToJson(StickballState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(StickballResult r) => r.toJson();
}
