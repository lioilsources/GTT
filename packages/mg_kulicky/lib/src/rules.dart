import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// Result shared by the two-sided point games (Kuličky, Čára, Nohejbal): stars by the lead.
class DuelResult {
  const DuelResult({
    required this.winner,
    required this.stars,
    required this.score,
    required this.playerPts,
    required this.aiPts,
  });

  /// Stars 3, 2, 1 for the first `margin >= starMargins[i]`, else 0; winner by the sign of the margin.
  factory DuelResult.of(int playerPts, int aiPts, List<int> starMargins) {
    final margin = playerPts - aiPts;
    var stars = 0;
    for (var i = 0; i < starMargins.length && i < 3; i++) {
      if (margin >= starMargins[i]) {
        stars = 3 - i;
        break;
      }
    }
    return DuelResult(
      winner: margin > 0
          ? 'player'
          : margin < 0
          ? 'ai'
          : 'draw',
      stars: stars,
      score: playerPts,
      playerPts: playerPts,
      aiPts: aiPts,
    );
  }

  final String winner;
  final int stars, score, playerPts, aiPts;

  Map<String, Object?> toJson() => {
    'winner': winner,
    'stars': stars,
    'score': score,
    'playerPts': playerPts,
    'aiPts': aiPts,
  };
}

/// Landing point: x then y scatter from the state rng (kulicky.md "Cvrnk").
({int x, int y}) scatterShot(Prng r, int x, int y, int s) {
  final lx = x + r.nextInt(2 * s + 1) - s;
  final ly = y + r.nextInt(2 * s + 1) - s;
  return (x: lx, y: ly);
}

/// specs/minigames/kulicky.md, version 1. Pure Dart: no Flutter imports here.
class KulickyConfig {
  const KulickyConfig({
    required this.rounds,
    required this.holeR,
    required this.holePoints,
    required this.closerPoints,
    required this.scatter,
    required this.aiScatter,
    required this.starMargins,
  });

  factory KulickyConfig.fromTuning(TuningMinigamesKulicky t) => KulickyConfig(
    rounds: t.rounds,
    holeR: t.holeR,
    holePoints: t.holePoints,
    closerPoints: t.closerPoints,
    scatter: List.unmodifiable(t.scatter),
    aiScatter: List.unmodifiable(t.aiScatter),
    starMargins: List.unmodifiable(t.starMargins),
  );

  factory KulickyConfig.fromJson(Map<String, Object?> j) {
    List<int> ints(String k) => List.unmodifiable((j[k] as List).cast<int>());
    return KulickyConfig(
      rounds: j['rounds'] as int,
      holeR: j['holeR'] as int,
      holePoints: j['holePoints'] as int,
      closerPoints: j['closerPoints'] as int,
      scatter: ints('scatter'),
      aiScatter: ints('aiScatter'),
      starMargins: ints('starMargins'),
    );
  }

  final int rounds, holeR, holePoints, closerPoints;
  final List<int> scatter, aiScatter, starMargins;
}

class KulickyShot {
  const KulickyShot(this.x, this.y, this.inHole);

  static const empty = KulickyShot(0, 0, false);

  final int x, y;
  final bool inHole;

  int get d2 => x * x + y * y;

  Map<String, Object?> toJson() => {'x': x, 'y': y, 'inHole': inHole};
}

class KulickyState {
  const KulickyState({
    required this.round,
    required this.turn,
    required this.playerPts,
    required this.aiPts,
    required this.playerShot,
    required this.aiShot,
    required this.over,
    required this.rng,
  });

  /// 1..rounds (rounds + 1 once the game is played out).
  final int round;

  /// 'player' or 'ai'.
  final String turn;
  final int playerPts, aiPts;
  final KulickyShot playerShot, aiShot;
  final bool over;
  final int rng;

  KulickyState copyWith({
    int? round,
    String? turn,
    int? playerPts,
    int? aiPts,
    KulickyShot? playerShot,
    KulickyShot? aiShot,
    bool? over,
    int? rng,
  }) => KulickyState(
    round: round ?? this.round,
    turn: turn ?? this.turn,
    playerPts: playerPts ?? this.playerPts,
    aiPts: aiPts ?? this.aiPts,
    playerShot: playerShot ?? this.playerShot,
    aiShot: aiShot ?? this.aiShot,
    over: over ?? this.over,
    rng: rng ?? this.rng,
  );

  Map<String, Object?> toJson() => {
    'round': round,
    'turn': turn,
    'playerPts': playerPts,
    'aiPts': aiPts,
    'playerShot': playerShot.toJson(),
    'aiShot': aiShot.toJson(),
    'over': over,
    'rng': rng,
  };
}

/// {by: player | ai, x, y, level} (aim point in mm, difficulty) or {by: timeout}.
class KulickyAction {
  const KulickyAction(this.x, this.y, this.level, {this.by = 'player'});
  const KulickyAction.timeout() : by = 'timeout', x = 0, y = 0, level = 0;

  final String by;
  final int x, y, level;

  Map<String, Object?> toJson() => by == 'timeout' ? {'by': by} : {'by': by, 'x': x, 'y': y, 'level': level};

  @override
  String toString() => toJson().toString();
}

class KulickyRules extends MgRules<KulickyState, KulickyAction, DuelResult> {
  KulickyConfig? _cfg;

  KulickyConfig get config => _cfg ?? (throw StateError('kulicky: init first'));

  @override
  String get id => 'kulicky';

  @override
  int get specVersion => 1;

  @override
  KulickyState init(Map<String, Object?> config, int seed) => start(KulickyConfig.fromJson(config), seed);

  KulickyState start(KulickyConfig config, int seed) {
    _cfg = config;
    return KulickyState(
      round: 1,
      turn: 'player',
      playerPts: 0,
      aiPts: 0,
      playerShot: KulickyShot.empty,
      aiShot: KulickyShot.empty,
      over: false,
      rng: Prng(seed).state,
    );
  }

  /// Actions are continuous; [apply] checks them.
  @override
  List<KulickyAction> legalActions(KulickyState s) => const [];

  @override
  KulickyState apply(KulickyState s, KulickyAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(over: true);
    final c = config;
    final table = a.by == 'player' ? c.scatter : c.aiScatter;
    if (a.by != s.turn || a.level < 1 || a.level > table.length) throw IllegalAction(id, a);
    final sc = table[a.level - 1];
    final r = withRng(s.rng, (p) => scatterShot(p, a.x, a.y, sc));
    final p = r.value;
    final shot = KulickyShot(p.x, p.y, p.x * p.x + p.y * p.y <= c.holeR * c.holeR);
    if (a.by == 'player') return s.copyWith(playerShot: shot, turn: 'ai', rng: r.rng);
    final ps = s.playerShot;
    var playerPts = s.playerPts, aiPts = s.aiPts;
    if (ps.inHole) playerPts += c.holePoints;
    if (shot.inHole) aiPts += c.holePoints;
    if (!ps.inHole && !shot.inHole) {
      if (ps.d2 < shot.d2) {
        playerPts += c.closerPoints;
      } else if (shot.d2 < ps.d2) {
        aiPts += c.closerPoints;
      }
    }
    final round = s.round + 1;
    return s.copyWith(
      aiShot: shot,
      playerPts: playerPts,
      aiPts: aiPts,
      round: round,
      turn: 'player',
      over: round > c.rounds,
      rng: r.rng,
    );
  }

  /// Aims straight at the hole; accuracy comes from aiScatter. Does not use the ai stream.
  @override
  KulickyAction aiAction(KulickyState s, int level, Prng ai) => KulickyAction(0, 0, level, by: 'ai');

  @override
  DuelResult? result(KulickyState s) => s.over ? DuelResult.of(s.playerPts, s.aiPts, config.starMargins) : null;

  @override
  KulickyAction actionFromJson(Map<String, Object?> j) => j['by'] == 'timeout'
      ? const KulickyAction.timeout()
      : KulickyAction(j['x'] as int, j['y'] as int, j['level'] as int, by: j['by'] as String);

  @override
  Map<String, Object?> stateToJson(KulickyState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(DuelResult r) => r.toJson();
}
