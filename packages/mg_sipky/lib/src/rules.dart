import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/sipky.md, version 1. Pure Dart, integer arithmetic only: no Flutter imports here.
class SipkyConfig {
  const SipkyConfig({
    required this.start,
    required this.maxRounds,
    required this.playerScatter,
    required this.aiScatter,
    required this.starDarts,
  });

  factory SipkyConfig.fromTuning(TuningMinigamesSipky t) => SipkyConfig(
    start: t.start,
    maxRounds: t.maxRounds,
    playerScatter: t.playerScatter,
    aiScatter: List.unmodifiable(t.aiScatter),
    starDarts: List.unmodifiable(t.starDarts),
  );

  factory SipkyConfig.fromJson(Map<String, Object?> j) => SipkyConfig(
    start: j['start'] as int,
    maxRounds: j['maxRounds'] as int,
    playerScatter: j['playerScatter'] as int,
    aiScatter: List.unmodifiable((j['aiScatter'] as List).cast<int>()),
    starDarts: List.unmodifiable((j['starDarts'] as List).cast<int>()),
  );

  final int start, maxRounds, playerScatter;
  final List<int> aiScatter, starDarts;
}

/// A landing point (board units, y up) with its points and multiplier.
class Hit {
  const Hit(this.x, this.y, this.points, this.mult);

  final int x, y, points, mult;

  Map<String, Object?> toJson() => {'x': x, 'y': y, 'points': points, 'mult': mult};
}

class SipkyState {
  const SipkyState({
    required this.player,
    required this.ai,
    required this.turn,
    required this.dart,
    required this.turnStart,
    required this.playerDarts,
    required this.round,
    required this.lastHit,
    required this.over,
    required this.rng,
  });

  /// Remaining scores.
  final int player, ai;

  /// 'player' or 'ai'.
  final String turn;
  final int dart, turnStart, playerDarts, round;
  final Hit lastHit;
  final bool over;
  final int rng;

  int score(String side) => side == 'player' ? player : ai;

  SipkyState copyWith({
    int? player,
    int? ai,
    String? turn,
    int? dart,
    int? turnStart,
    int? playerDarts,
    int? round,
    Hit? lastHit,
    bool? over,
    int? rng,
  }) => SipkyState(
    player: player ?? this.player,
    ai: ai ?? this.ai,
    turn: turn ?? this.turn,
    dart: dart ?? this.dart,
    turnStart: turnStart ?? this.turnStart,
    playerDarts: playerDarts ?? this.playerDarts,
    round: round ?? this.round,
    lastHit: lastHit ?? this.lastHit,
    over: over ?? this.over,
    rng: rng ?? this.rng,
  );

  SipkyState withScore(String side, int v) => side == 'player' ? copyWith(player: v) : copyWith(ai: v);

  Map<String, Object?> toJson() => {
    'player': player,
    'ai': ai,
    'turn': turn,
    'dart': dart,
    'turnStart': turnStart,
    'playerDarts': playerDarts,
    'round': round,
    'lastHit': lastHit.toJson(),
    'over': over,
    'rng': rng,
  };
}

/// {by: player, x, y}, {by: ai, x, y, level} or {by: timeout}.
class SipkyAction {
  const SipkyAction.player(this.x, this.y) : by = 'player', level = 0;
  const SipkyAction.ai(this.x, this.y, this.level) : by = 'ai';
  const SipkyAction.timeout() : by = 'timeout', x = 0, y = 0, level = 0;

  final String by;
  final int x, y, level;

  Map<String, Object?> toJson() => switch (by) {
    'timeout' => {'by': by},
    'ai' => {'by': by, 'x': x, 'y': y, 'level': level},
    _ => {'by': by, 'x': x, 'y': y},
  };

  @override
  String toString() => toJson().toString();
}

class SipkyResult {
  const SipkyResult({
    required this.winner,
    required this.stars,
    required this.score,
    required this.player,
    required this.ai,
    required this.playerDarts,
  });

  final String winner;
  final int stars, score, player, ai, playerDarts;

  Map<String, Object?> toJson() => {
    'winner': winner,
    'stars': stars,
    'score': score,
    'player': player,
    'ai': ai,
    'playerDarts': playerDarts,
  };
}

/// Sector values from the top, clockwise.
const sipkySectors = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5];

/// Sector boundaries B[j]: direction 9° + 18°·j clockwise from +y, ×10⁶.
const List<(int, int)> _b = [
  (156434, 987688), (453990, 891007), (707107, 707107), (891007, 453990), (987688, 156434), //
  (987688, -156434), (891007, -453990), (707107, -707107), (453990, -891007), (156434, -987688),
  (-156434, -987688), (-453990, -891007), (-707107, -707107), (-891007, -453990), (-987688, -156434),
  (-987688, 156434), (-891007, 453990), (-707107, 707107), (-453990, 891007), (-156434, 987688),
];

/// Sector centres C[k]: direction 18°·k clockwise from +y, ×10⁶.
const List<(int, int)> _c = [
  (0, 1000000), (309017, 951057), (587785, 809017), (809017, 587785), (951057, 309017), //
  (1000000, 0), (951057, -309017), (809017, -587785), (587785, -809017), (309017, -951057),
  (0, -1000000), (-309017, -951057), (-587785, -809017), (-809017, -587785), (-951057, -309017),
  (-1000000, 0), (-951057, 309017), (-809017, 587785), (-587785, 809017), (-309017, 951057),
];

/// Board radii in 0.1 mm.
abstract final class SipkyRing {
  static const bull = 64, outerBull = 159, tripleIn = 990, tripleOut = 1070, doubleIn = 1620, doubleOut = 1700;
}

/// Radii the AI aims at.
abstract final class SipkyAim {
  static const single = 574, triple = 1030, double = 1660;
}

int _cross((int, int) a, int x, int y) => a.$1 * y - a.$2 * x;

/// Sector index: the first k with cross(B[k−1], p) ≤ 0 and cross(B[k], p) > 0.
int sipkySectorAt(int x, int y) {
  for (var k = 0; k < 20; k++) {
    if (_cross(_b[(k + 19) % 20], x, y) <= 0 && _cross(_b[k], x, y) > 0) return k;
  }
  return 0;
}

/// Points and multiplier of a landing point (board units, y up).
({int points, int mult}) sipkyScoreAt(int x, int y) {
  final r2 = x * x + y * y;
  if (r2 <= SipkyRing.bull * SipkyRing.bull) return (points: 50, mult: 2);
  if (r2 <= SipkyRing.outerBull * SipkyRing.outerBull) return (points: 25, mult: 1);
  if (r2 >= SipkyRing.doubleOut * SipkyRing.doubleOut) return (points: 0, mult: 0);
  final v = sipkySectors[sipkySectorAt(x, y)];
  if (r2 >= SipkyRing.tripleIn * SipkyRing.tripleIn && r2 < SipkyRing.tripleOut * SipkyRing.tripleOut) {
    return (points: 3 * v, mult: 3);
  }
  if (r2 >= SipkyRing.doubleIn * SipkyRing.doubleIn) return (points: 2 * v, mult: 2);
  return (points: v, mult: 1);
}

int _rnd(int q) => (q + q.sign * 500000) ~/ 1000000;

/// The point on the centre line of the sector with [value] at radius [r].
(int, int) sipkyPointOn(int value, int r) {
  final c = _c[sipkySectors.indexOf(value)];
  return (_rnd(c.$1 * r), _rnd(c.$2 * r));
}

/// AI target for remaining score [z] (spec "AI", no randomness).
(int, int) sipkyAiTarget(int z) {
  if (z == 50) return (0, 0);
  if (z <= 20) return sipkyPointOn(z, SipkyAim.single);
  if (z <= 40 && z.isEven) return sipkyPointOn(z ~/ 2, SipkyAim.double);
  if (z <= 60 && z % 3 == 0) return sipkyPointOn(z ~/ 3, SipkyAim.triple);
  if (z <= 60 && z - 20 >= 1 && z - 20 <= 20) return sipkyPointOn(z - 20, SipkyAim.single);
  return sipkyPointOn(20, SipkyAim.triple);
}

String _other(String side) => side == 'player' ? 'ai' : 'player';

class SipkyRules extends MgRules<SipkyState, SipkyAction, SipkyResult> {
  SipkyConfig? _cfg;

  SipkyConfig get _conf => _cfg ?? (throw StateError('sipky: init first'));

  @override
  String get id => 'sipky';

  @override
  int get specVersion => 1;

  /// Starts a game; [config] is the vector form (see [SipkyConfig.fromJson]).
  @override
  SipkyState init(Map<String, Object?> config, int seed) => start(SipkyConfig.fromJson(config), seed);

  SipkyState start(SipkyConfig config, int seed) {
    _cfg = config;
    return SipkyState(
      player: config.start,
      ai: config.start,
      turn: 'player',
      dart: 0,
      turnStart: config.start,
      playerDarts: 0,
      round: 1,
      lastHit: const Hit(0, 0, 0, 0),
      over: false,
      rng: Prng(seed).state,
    );
  }

  /// Actions are continuous; [apply] checks them.
  @override
  List<SipkyAction> legalActions(SipkyState s) => const [];

  @override
  SipkyState apply(SipkyState s, SipkyAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(over: true);
    if (a.by != s.turn) throw IllegalAction(id, a);
    final c = _conf;
    final sc = a.by == 'player' ? c.playerScatter : c.aiScatter[a.level.clamp(1, c.aiScatter.length) - 1];
    final r = withRng(s.rng, (p) {
      final dx = p.nextInt(2 * sc + 1) - sc;
      final dy = p.nextInt(2 * sc + 1) - sc;
      return (a.x + dx, a.y + dy);
    });
    final (x, y) = r.value;
    final hit = sipkyScoreAt(x, y);
    final side = s.turn;
    final n = s.copyWith(
      rng: r.rng,
      lastHit: Hit(x, y, hit.points, hit.mult),
      playerDarts: side == 'player' ? s.playerDarts + 1 : s.playerDarts,
    );
    final left = s.score(side) - hit.points;
    if (left < 0) return _endTurn(n.withScore(side, s.turnStart));
    if (left == 0) return n.withScore(side, 0).copyWith(over: true);
    if (s.dart >= 2) return _endTurn(n.withScore(side, left));
    return n.withScore(side, left).copyWith(dart: s.dart + 1);
  }

  SipkyState _endTurn(SipkyState s) {
    final turn = _other(s.turn);
    final n = s.copyWith(dart: 0, turn: turn, turnStart: s.score(turn));
    if (s.turn != 'ai') return n;
    final round = s.round + 1;
    return n.copyWith(round: round, over: round > _conf.maxRounds);
  }

  @override
  SipkyAction aiAction(SipkyState s, int level, Prng ai) {
    final (x, y) = sipkyAiTarget(s.ai);
    return SipkyAction.ai(x, y, level);
  }

  @override
  SipkyResult? result(SipkyState s) {
    if (!s.over) return null;
    final winner = s.player < s.ai
        ? 'player'
        : s.ai < s.player
        ? 'ai'
        : 'draw';
    final d = _conf.starDarts;
    final stars = winner != 'player'
        ? 0
        : s.playerDarts <= d[0]
        ? 3
        : s.playerDarts <= d[1]
        ? 2
        : 1;
    return SipkyResult(
      winner: winner,
      stars: stars,
      score: _conf.start - s.player,
      player: s.player,
      ai: s.ai,
      playerDarts: s.playerDarts,
    );
  }

  @override
  SipkyAction actionFromJson(Map<String, Object?> j) => switch (j['by']) {
    'timeout' => const SipkyAction.timeout(),
    'ai' => SipkyAction.ai(j['x'] as int, j['y'] as int, j['level'] as int),
    'player' => SipkyAction.player(j['x'] as int, j['y'] as int),
    _ => throw IllegalAction(id, j),
  };

  @override
  Map<String, Object?> stateToJson(SipkyState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(SipkyResult r) => r.toJson();
}
