import 'package:mg_kulicky/mg_kulicky.dart' show DuelResult;
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/cara.md, version 1. Pure Dart: no Flutter imports here.
class CaraConfig {
  const CaraConfig({
    required this.rounds,
    required this.linePoints,
    required this.roundPoints,
    required this.scatter,
    required this.aiScatter,
    required this.aiAim,
    required this.starMargins,
  });

  factory CaraConfig.fromTuning(TuningMinigamesCara t) => CaraConfig(
    rounds: t.rounds,
    linePoints: t.linePoints,
    roundPoints: t.roundPoints,
    scatter: List.unmodifiable(t.scatter),
    aiScatter: List.unmodifiable(t.aiScatter),
    aiAim: List.unmodifiable(t.aiAim),
    starMargins: List.unmodifiable(t.starMargins),
  );

  factory CaraConfig.fromJson(Map<String, Object?> j) {
    List<int> ints(String k) => List.unmodifiable((j[k] as List).cast<int>());
    return CaraConfig(
      rounds: j['rounds'] as int,
      linePoints: j['linePoints'] as int,
      roundPoints: j['roundPoints'] as int,
      scatter: ints('scatter'),
      aiScatter: ints('aiScatter'),
      aiAim: ints('aiAim'),
      starMargins: ints('starMargins'),
    );
  }

  final int rounds, linePoints, roundPoints;
  final List<int> scatter, aiScatter, aiAim, starMargins;
}

class CaraCoin {
  const CaraCoin(this.y, this.burnt);

  static const empty = CaraCoin(0, false);

  /// Distance from the line in mm, negative short of it.
  final int y;

  /// Over the line (y > 0).
  final bool burnt;

  Map<String, Object?> toJson() => {'y': y, 'burnt': burnt};
}

class CaraState {
  const CaraState({
    required this.round,
    required this.turn,
    required this.playerPts,
    required this.aiPts,
    required this.playerCoin,
    required this.aiCoin,
    required this.over,
    required this.rng,
  });

  final int round;

  /// 'player' or 'ai'.
  final String turn;
  final int playerPts, aiPts;
  final CaraCoin playerCoin, aiCoin;
  final bool over;
  final int rng;

  CaraState copyWith({
    int? round,
    String? turn,
    int? playerPts,
    int? aiPts,
    CaraCoin? playerCoin,
    CaraCoin? aiCoin,
    bool? over,
    int? rng,
  }) => CaraState(
    round: round ?? this.round,
    turn: turn ?? this.turn,
    playerPts: playerPts ?? this.playerPts,
    aiPts: aiPts ?? this.aiPts,
    playerCoin: playerCoin ?? this.playerCoin,
    aiCoin: aiCoin ?? this.aiCoin,
    over: over ?? this.over,
    rng: rng ?? this.rng,
  );

  Map<String, Object?> toJson() => {
    'round': round,
    'turn': turn,
    'playerPts': playerPts,
    'aiPts': aiPts,
    'playerCoin': playerCoin.toJson(),
    'aiCoin': aiCoin.toJson(),
    'over': over,
    'rng': rng,
  };
}

/// {by: player | ai, y, level} (aimed distance from the line, negative short of it) or {by: timeout}.
class CaraAction {
  const CaraAction(this.y, this.level, {this.by = 'player'});
  const CaraAction.timeout() : by = 'timeout', y = 0, level = 0;

  final String by;
  final int y, level;

  Map<String, Object?> toJson() => by == 'timeout' ? {'by': by} : {'by': by, 'y': y, 'level': level};

  @override
  String toString() => toJson().toString();
}

class CaraRules extends MgRules<CaraState, CaraAction, DuelResult> {
  CaraConfig? _cfg;

  CaraConfig get config => _cfg ?? (throw StateError('cara: init first'));

  @override
  String get id => 'cara';

  @override
  int get specVersion => 1;

  @override
  CaraState init(Map<String, Object?> config, int seed) => start(CaraConfig.fromJson(config), seed);

  CaraState start(CaraConfig config, int seed) {
    _cfg = config;
    return CaraState(
      round: 1,
      turn: 'player',
      playerPts: 0,
      aiPts: 0,
      playerCoin: CaraCoin.empty,
      aiCoin: CaraCoin.empty,
      over: false,
      rng: Prng(seed).state,
    );
  }

  /// Actions are continuous; [apply] checks them.
  @override
  List<CaraAction> legalActions(CaraState s) => const [];

  @override
  CaraState apply(CaraState s, CaraAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(over: true);
    final c = config;
    final table = a.by == 'player' ? c.scatter : c.aiScatter;
    if (a.by != s.turn || a.level < 1 || a.level > table.length) throw IllegalAction(id, a);
    final sc = table[a.level - 1];
    final r = withRng(s.rng, (p) => a.y + p.nextInt(2 * sc + 1) - sc);
    final coin = CaraCoin(r.value, r.value > 0);
    if (a.by == 'player') return s.copyWith(playerCoin: coin, turn: 'ai', rng: r.rng);
    final pc = s.playerCoin;
    var playerPts = s.playerPts, aiPts = s.aiPts;
    if (pc.y == 0 || coin.y == 0) {
      // A coin right on the line scores linePoints; both may. No round point then.
      if (pc.y == 0) playerPts += c.linePoints;
      if (coin.y == 0) aiPts += c.linePoints;
    } else if (!pc.burnt && (coin.burnt || pc.y > coin.y)) {
      playerPts += c.roundPoints;
    } else if (!coin.burnt && (pc.burnt || coin.y > pc.y)) {
      aiPts += c.roundPoints;
    }
    final round = s.round + 1;
    return s.copyWith(
      aiCoin: coin,
      playerPts: playerPts,
      aiPts: aiPts,
      round: round,
      turn: 'player',
      over: round > c.rounds,
      rng: r.rng,
    );
  }

  /// The better the rival, the closer to the line it aims. Does not use the ai stream.
  @override
  CaraAction aiAction(CaraState s, int level, Prng ai) => CaraAction(-config.aiAim[level - 1], level, by: 'ai');

  @override
  DuelResult? result(CaraState s) => s.over ? DuelResult.of(s.playerPts, s.aiPts, config.starMargins) : null;

  @override
  CaraAction actionFromJson(Map<String, Object?> j) => j['by'] == 'timeout'
      ? const CaraAction.timeout()
      : CaraAction(j['y'] as int, j['level'] as int, by: j['by'] as String);

  @override
  Map<String, Object?> stateToJson(CaraState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(DuelResult r) => r.toJson();
}
