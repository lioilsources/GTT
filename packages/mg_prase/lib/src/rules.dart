import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/prase.md, version 1. Pure Dart: no Flutter imports here.
class PraseConfig {
  const PraseConfig({
    required this.target,
    required this.maxRounds,
    required this.aiHoldAt,
    required this.aiErrorPct,
    required this.starMargins,
  });

  factory PraseConfig.fromTuning(TuningMinigamesPrase t) => PraseConfig(
    target: t.target,
    maxRounds: t.maxRounds,
    aiHoldAt: List.unmodifiable(t.aiHoldAt),
    aiErrorPct: List.unmodifiable(t.aiErrorPct),
    starMargins: List.unmodifiable(t.starMargins),
  );

  factory PraseConfig.fromJson(Map<String, Object?> j) => PraseConfig(
    target: j['target'] as int,
    maxRounds: j['maxRounds'] as int,
    aiHoldAt: List.unmodifiable((j['aiHoldAt'] as List).cast<int>()),
    aiErrorPct: List.unmodifiable((j['aiErrorPct'] as List).cast<int>()),
    starMargins: List.unmodifiable((j['starMargins'] as List).cast<int>()),
  );

  final int target, maxRounds;
  final List<int> aiHoldAt, aiErrorPct, starMargins;
}

class PraseState {
  const PraseState({
    required this.player,
    required this.ai,
    required this.turn,
    required this.turnScore,
    required this.die,
    required this.bust,
    required this.round,
    required this.over,
    required this.rng,
  });

  final int player, ai;

  /// 'player' or 'ai'.
  final String turn;
  final int turnScore;

  /// Last rolled value; 0 before the first roll of the game.
  final int die;
  final bool bust;
  final int round;
  final bool over;
  final int rng;

  int score(String side) => side == 'player' ? player : ai;

  PraseState copyWith({
    int? player,
    int? ai,
    String? turn,
    int? turnScore,
    int? die,
    bool? bust,
    int? round,
    bool? over,
    int? rng,
  }) => PraseState(
    player: player ?? this.player,
    ai: ai ?? this.ai,
    turn: turn ?? this.turn,
    turnScore: turnScore ?? this.turnScore,
    die: die ?? this.die,
    bust: bust ?? this.bust,
    round: round ?? this.round,
    over: over ?? this.over,
    rng: rng ?? this.rng,
  );

  Map<String, Object?> toJson() => {
    'player': player,
    'ai': ai,
    'turn': turn,
    'turnScore': turnScore,
    'die': die,
    'bust': bust,
    'round': round,
    'over': over,
    'rng': rng,
  };
}

/// {by, op: roll|hold} or {by: timeout}.
class PraseAction {
  const PraseAction(this.by, this.op);
  const PraseAction.roll(this.by) : op = 'roll';
  const PraseAction.hold(this.by) : op = 'hold';
  const PraseAction.timeout() : by = 'timeout', op = '';

  final String by, op;

  Map<String, Object?> toJson() => by == 'timeout' ? {'by': by} : {'by': by, 'op': op};

  @override
  bool operator ==(Object other) => other is PraseAction && other.by == by && other.op == op;

  @override
  int get hashCode => Object.hash(by, op);

  @override
  String toString() => toJson().toString();
}

class PraseResult {
  const PraseResult({
    required this.winner,
    required this.stars,
    required this.score,
    required this.player,
    required this.ai,
  });

  final String winner;
  final int stars, score, player, ai;

  Map<String, Object?> toJson() => {'winner': winner, 'stars': stars, 'score': score, 'player': player, 'ai': ai};
}

class PraseRules extends MgRules<PraseState, PraseAction, PraseResult> {
  PraseConfig? _cfg;

  PraseConfig get _c => _cfg ?? (throw StateError('prase: init first'));

  @override
  String get id => 'prase';

  @override
  int get specVersion => 1;

  /// Starts a game; [config] is the vector form (see [PraseConfig.fromJson]).
  @override
  PraseState init(Map<String, Object?> config, int seed) => start(PraseConfig.fromJson(config), seed);

  PraseState start(PraseConfig config, int seed) {
    _cfg = config;
    return PraseState(
      player: 0,
      ai: 0,
      turn: 'player',
      turnScore: 0,
      die: 0,
      bust: false,
      round: 1,
      over: false,
      rng: Prng(seed).state,
    );
  }

  @override
  List<PraseAction> legalActions(PraseState s) {
    if (s.over) return const [];
    return s.turnScore == 0 ? [PraseAction.roll(s.turn)] : [PraseAction.roll(s.turn), PraseAction.hold(s.turn)];
  }

  /// Turn passes; after the AI's turn the round advances and may end the game.
  PraseState _endTurn(PraseState s) {
    final round = s.turn == 'ai' ? s.round + 1 : s.round;
    return s.copyWith(
      turnScore: 0,
      turn: s.turn == 'player' ? 'ai' : 'player',
      round: round,
      over: s.turn == 'ai' && round > _c.maxRounds ? true : s.over,
    );
  }

  @override
  PraseState apply(PraseState s, PraseAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(over: true);
    if (a.by != s.turn) throw IllegalAction(id, a);
    switch (a.op) {
      case 'roll':
        final r = withRng(s.rng, (p) => p.nextInt(6) + 1);
        final n = s.copyWith(die: r.value, rng: r.rng);
        if (r.value == 1) return _endTurn(n.copyWith(turnScore: 0, bust: true));
        return n.copyWith(turnScore: s.turnScore + r.value, bust: false);
      case 'hold':
        if (s.turnScore == 0) throw IllegalAction(id, a);
        final banked = s.score(s.turn) + s.turnScore;
        final n = s.turn == 'player' ? s.copyWith(player: banked) : s.copyWith(ai: banked);
        if (banked >= _c.target) return n.copyWith(turnScore: 0, over: true);
        return _endTurn(n);
      default:
        throw IllegalAction(id, a);
    }
  }

  @override
  PraseAction aiAction(PraseState s, int level, Prng ai) {
    final legal = legalActions(s);
    if (s.turn != 'ai' || legal.isEmpty) throw IllegalAction(id, const PraseAction('ai', ''));
    final c = _c;
    final err = level >= 1 && level <= c.aiErrorPct.length ? c.aiErrorPct[level - 1] : 0;
    if (ai.nextInt(100) < err) return legal[ai.nextInt(legal.length)];
    const roll = PraseAction.roll('ai');
    const hold = PraseAction.hold('ai');
    final t = s.turnScore;
    if (t == 0) return roll;
    if (s.ai + t >= c.target) return hold;
    if (level >= 3 && s.round == c.maxRounds) return s.ai + t > s.player ? hold : roll;
    if (level >= 4 && s.player >= c.target - 20) return roll;
    final holdAt = level >= 1 && level <= c.aiHoldAt.length ? c.aiHoldAt[level - 1] : 20;
    return t >= holdAt ? hold : roll;
  }

  @override
  PraseResult? result(PraseState s) {
    if (!s.over) return null;
    final p = s.player, a = s.ai;
    final winner = p > a
        ? 'player'
        : p < a
        ? 'ai'
        : 'draw';
    final m = _c.starMargins;
    final stars = winner != 'player'
        ? 0
        : p - a >= m[0]
        ? 3
        : p - a >= m[1]
        ? 2
        : 1;
    return PraseResult(winner: winner, stars: stars, score: p, player: p, ai: a);
  }

  @override
  PraseAction actionFromJson(Map<String, Object?> j) =>
      j['by'] == 'timeout' ? const PraseAction.timeout() : PraseAction(j['by'] as String, j['op'] as String);

  @override
  Map<String, Object?> stateToJson(PraseState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(PraseResult r) => r.toJson();
}
