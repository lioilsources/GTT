import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/koulena.md, version 1. Pure Dart: no Flutter imports here.
class KoulenaConfig {
  const KoulenaConfig({
    required this.series,
    required this.balls,
    required this.ringR,
    required this.ringPoints,
    required this.pockets,
    required this.pocketR,
    required this.pocketPoints,
    required this.scatter,
    required this.starScores,
  });

  factory KoulenaConfig.fromTuning(TuningMinigamesKoulena t) => KoulenaConfig(
    series: t.series,
    balls: t.balls,
    ringR: List.unmodifiable(t.ringR),
    ringPoints: List.unmodifiable(t.ringPoints),
    pockets: List.unmodifiable(t.pockets),
    pocketR: t.pocketR,
    pocketPoints: t.pocketPoints,
    scatter: List.unmodifiable(t.scatter),
    starScores: List.unmodifiable(t.starScores),
  );

  factory KoulenaConfig.fromJson(Map<String, Object?> j) {
    List<int> ints(String k) => List.unmodifiable((j[k] as List).cast<int>());
    return KoulenaConfig(
      series: j['series'] as int,
      balls: j['balls'] as int,
      ringR: ints('ringR'),
      ringPoints: ints('ringPoints'),
      pockets: ints('pockets'),
      pocketR: j['pocketR'] as int,
      pocketPoints: j['pocketPoints'] as int,
      scatter: ints('scatter'),
      starScores: ints('starScores'),
    );
  }

  final int series, balls, pocketR, pocketPoints;
  final List<int> ringR, ringPoints, scatter, starScores;

  /// Pocket centres as x, y pairs.
  final List<int> pockets;
}

class KoulenaHit {
  const KoulenaHit(this.x, this.y, this.points);

  final int x, y, points;

  Map<String, Object?> toJson() => {'x': x, 'y': y, 'points': points};
}

class KoulenaState {
  const KoulenaState({
    required this.series,
    required this.ball,
    required this.score,
    required this.seriesScores,
    required this.lastHit,
    required this.over,
    required this.rng,
  });

  /// Series 1..series (one past the last once the game is over).
  final int series;

  /// Balls rolled in the current series.
  final int ball;
  final int score;

  /// Totals of the finished series.
  final List<int> seriesScores;
  final KoulenaHit lastHit;
  final bool over;
  final int rng;

  KoulenaState copyWith({
    int? series,
    int? ball,
    int? score,
    List<int>? seriesScores,
    KoulenaHit? lastHit,
    bool? over,
    int? rng,
  }) => KoulenaState(
    series: series ?? this.series,
    ball: ball ?? this.ball,
    score: score ?? this.score,
    seriesScores: seriesScores ?? this.seriesScores,
    lastHit: lastHit ?? this.lastHit,
    over: over ?? this.over,
    rng: rng ?? this.rng,
  );

  Map<String, Object?> toJson() => {
    'series': series,
    'ball': ball,
    'score': score,
    'seriesScores': seriesScores,
    'lastHit': lastHit.toJson(),
    'over': over,
    'rng': rng,
  };
}

/// {by: player, x, y, level} (aim point in mm, difficulty) or {by: timeout}.
class KoulenaAction {
  const KoulenaAction(this.x, this.y, this.level, {this.by = 'player'});
  const KoulenaAction.timeout() : by = 'timeout', x = 0, y = 0, level = 0;

  final String by;
  final int x, y, level;

  Map<String, Object?> toJson() => by == 'timeout' ? {'by': by} : {'by': by, 'x': x, 'y': y, 'level': level};

  @override
  String toString() => toJson().toString();
}

class KoulenaResult {
  const KoulenaResult({required this.winner, required this.stars, required this.score, required this.seriesScores});

  final String winner;
  final int stars, score;
  final List<int> seriesScores;

  Map<String, Object?> toJson() => {'winner': winner, 'stars': stars, 'score': score, 'seriesScores': seriesScores};
}

/// Points for a landing point: pockets first (config order), then the first ring that holds it.
int koulenaPoints(KoulenaConfig c, int x, int y) {
  for (var i = 0; i + 1 < c.pockets.length; i += 2) {
    final dx = x - c.pockets[i], dy = y - c.pockets[i + 1];
    if (dx * dx + dy * dy <= c.pocketR * c.pocketR) return c.pocketPoints;
  }
  final d2 = x * x + y * y;
  for (var i = 0; i < c.ringR.length; i++) {
    if (d2 <= c.ringR[i] * c.ringR[i]) return i < c.ringPoints.length ? c.ringPoints[i] : 0;
  }
  return 0;
}

class KoulenaRules extends MgRules<KoulenaState, KoulenaAction, KoulenaResult> {
  KoulenaConfig? _cfg;

  KoulenaConfig get config => _cfg ?? (throw StateError('koulena: init first'));

  @override
  String get id => 'koulena';

  @override
  int get specVersion => 1;

  /// Starts a game; [config] is the vector form (see [KoulenaConfig.fromJson]).
  @override
  KoulenaState init(Map<String, Object?> config, int seed) => start(KoulenaConfig.fromJson(config), seed);

  KoulenaState start(KoulenaConfig config, int seed) {
    _cfg = config;
    return KoulenaState(
      series: 1,
      ball: 0,
      score: 0,
      seriesScores: const [],
      lastHit: const KoulenaHit(0, 0, 0),
      over: false,
      rng: Prng(seed).state,
    );
  }

  /// Actions are continuous; [apply] checks them.
  @override
  List<KoulenaAction> legalActions(KoulenaState s) => const [];

  @override
  KoulenaState apply(KoulenaState s, KoulenaAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(over: true);
    final c = config;
    if (a.by != 'player' || a.level < 1 || a.level > c.scatter.length) throw IllegalAction(id, a);
    final sc = c.scatter[a.level - 1];
    final r = withRng(s.rng, (p) {
      final x = a.x + p.nextInt(2 * sc + 1) - sc;
      final y = a.y + p.nextInt(2 * sc + 1) - sc;
      return KoulenaHit(x, y, koulenaPoints(c, x, y));
    });
    final score = s.score + r.value.points;
    final n = s.copyWith(score: score, lastHit: r.value, ball: s.ball + 1, rng: r.rng);
    if (n.ball < c.balls) return n;
    final closed = s.seriesScores.fold(0, (a, b) => a + b);
    return n.copyWith(
      seriesScores: List.unmodifiable([...s.seriesScores, score - closed]),
      series: s.series + 1,
      ball: 0,
      over: s.series >= c.series,
    );
  }

  /// No opponent: the contract still wants one, it aims at the centre with level 3.
  @override
  KoulenaAction aiAction(KoulenaState s, int level, Prng ai) => const KoulenaAction(0, 0, 3);

  @override
  KoulenaResult? result(KoulenaState s) {
    if (!s.over) return null;
    final t = config.starScores;
    final stars = s.score >= t[0]
        ? 3
        : s.score >= t[1]
        ? 2
        : s.score >= t[2]
        ? 1
        : 0;
    return KoulenaResult(
      winner: stars >= 1 ? 'player' : 'ai',
      stars: stars,
      score: s.score,
      seriesScores: s.seriesScores,
    );
  }

  @override
  KoulenaAction actionFromJson(Map<String, Object?> j) => j['by'] == 'timeout'
      ? const KoulenaAction.timeout()
      : KoulenaAction(j['x'] as int, j['y'] as int, j['level'] as int, by: j['by'] as String);

  @override
  Map<String, Object?> stateToJson(KoulenaState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(KoulenaResult r) => r.toJson();
}
