import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/sirky.md, version 1. Pure Dart: no Flutter imports here.
class SirkyConfig {
  const SirkyConfig({
    required this.start,
    required this.minStart,
    required this.maxStart,
    required this.maxTake,
    required this.roundsToWin,
    required this.aiErrorPct,
  });

  factory SirkyConfig.fromTuning(TuningMinigamesSirky t) => SirkyConfig(
    start: t.start,
    minStart: t.minStart,
    maxStart: t.maxStart,
    maxTake: t.maxTake,
    roundsToWin: t.roundsToWin,
    aiErrorPct: List.unmodifiable(t.aiErrorPct),
  );

  factory SirkyConfig.fromJson(Map<String, Object?> j) => SirkyConfig(
    start: j['start'] as int,
    minStart: j['minStart'] as int,
    maxStart: j['maxStart'] as int,
    maxTake: j['maxTake'] as int,
    roundsToWin: j['roundsToWin'] as int,
    aiErrorPct: List.unmodifiable((j['aiErrorPct'] as List).cast<int>()),
  );

  final int start, minStart, maxStart, maxTake, roundsToWin;
  final List<int> aiErrorPct;
}

class SirkyState {
  const SirkyState({
    required this.left,
    required this.turn,
    required this.starter,
    required this.round,
    required this.player,
    required this.ai,
    required this.over,
    required this.rng,
  });

  final int left;

  /// 'player' or 'ai'.
  final String turn, starter;
  final int round, player, ai;
  final bool over;
  final int rng;

  int score(String side) => side == 'player' ? player : ai;

  SirkyState copyWith({
    int? left,
    String? turn,
    String? starter,
    int? round,
    int? player,
    int? ai,
    bool? over,
    int? rng,
  }) => SirkyState(
    left: left ?? this.left,
    turn: turn ?? this.turn,
    starter: starter ?? this.starter,
    round: round ?? this.round,
    player: player ?? this.player,
    ai: ai ?? this.ai,
    over: over ?? this.over,
    rng: rng ?? this.rng,
  );

  Map<String, Object?> toJson() => {
    'left': left,
    'turn': turn,
    'starter': starter,
    'round': round,
    'player': player,
    'ai': ai,
    'over': over,
    'rng': rng,
  };
}

/// {by: player|ai, take} or {by: timeout} (take = 0).
class SirkyAction {
  const SirkyAction(this.by, this.take);
  const SirkyAction.timeout() : by = 'timeout', take = 0;

  final String by;
  final int take;

  Map<String, Object?> toJson() => by == 'timeout' ? {'by': by} : {'by': by, 'take': take};

  @override
  String toString() => toJson().toString();
}

class SirkyResult {
  const SirkyResult({
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

String _other(String side) => side == 'player' ? 'ai' : 'player';

class SirkyRules extends MgRules<SirkyState, SirkyAction, SirkyResult> {
  SirkyConfig? _cfg;

  SirkyConfig get _c => _cfg ?? (throw StateError('sirky: init first'));

  @override
  String get id => 'sirky';

  @override
  int get specVersion => 1;

  /// Starts a game; [config] is the vector form (see [SirkyConfig.fromJson]).
  @override
  SirkyState init(Map<String, Object?> config, int seed) => start(SirkyConfig.fromJson(config), seed);

  SirkyState start(SirkyConfig config, int seed) {
    _cfg = config;
    return SirkyState(
      left: config.start,
      turn: 'player',
      starter: 'player',
      round: 1,
      player: 0,
      ai: 0,
      over: false,
      rng: Prng(seed).state,
    );
  }

  @override
  List<SirkyAction> legalActions(SirkyState s) {
    if (s.over) return const [];
    final m = _c.maxTake < s.left ? _c.maxTake : s.left;
    return [for (var k = 1; k <= m; k++) SirkyAction(s.turn, k)];
  }

  @override
  SirkyState apply(SirkyState s, SirkyAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(over: true);
    final m = _c.maxTake < s.left ? _c.maxTake : s.left;
    if (a.by != s.turn || a.take < 1 || a.take > m) throw IllegalAction(id, a);
    final left = s.left - a.take;
    if (left > 0) return s.copyWith(left: left, turn: _other(s.turn));
    final winner = _other(a.by);
    final won = s.score(winner) + 1;
    final n = winner == 'player' ? s.copyWith(left: 0, player: won) : s.copyWith(left: 0, ai: won);
    if (won >= _c.roundsToWin) return n.copyWith(over: true);
    final starter = _other(s.starter);
    final r = withRng(s.rng, (p) => _c.minStart + p.nextInt(_c.maxStart - _c.minStart + 1));
    return n.copyWith(round: s.round + 1, starter: starter, turn: starter, left: r.value, rng: r.rng);
  }

  @override
  SirkyAction aiAction(SirkyState s, int level, Prng ai) {
    final c = _c;
    final err = c.aiErrorPct[level.clamp(1, c.aiErrorPct.length) - 1];
    final m = c.maxTake < s.left ? c.maxTake : s.left;
    final r = ai.nextInt(100);
    if (r < err) return SirkyAction(s.turn, 1 + ai.nextInt(m));
    final t = (s.left - 1) % (c.maxTake + 1);
    return SirkyAction(s.turn, t >= 1 ? t : 1);
  }

  @override
  SirkyResult? result(SirkyState s) {
    if (!s.over) return null;
    final winner = s.player > s.ai ? 'player' : 'ai';
    final stars = winner != 'player'
        ? 0
        : s.ai <= 2
        ? 3
        : s.ai == 3
        ? 2
        : 1;
    return SirkyResult(winner: winner, stars: stars, score: 100 * s.player, player: s.player, ai: s.ai);
  }

  @override
  SirkyAction actionFromJson(Map<String, Object?> j) =>
      j['by'] == 'timeout' ? const SirkyAction.timeout() : SirkyAction(j['by'] as String, j['take'] as int);

  @override
  Map<String, Object?> stateToJson(SirkyState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(SirkyResult r) => r.toJson();
}
