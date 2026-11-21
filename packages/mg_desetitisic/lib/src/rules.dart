import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/desetitisic.md, version 1. Pure Dart: no Flutter imports here.
class DesetitisicConfig {
  const DesetitisicConfig({
    required this.target,
    required this.maxRounds,
    required this.aiBankAt,
    required this.aiErrorPct,
    required this.starMargins,
  });

  factory DesetitisicConfig.fromTuning(TuningMinigamesDesetitisic t) => DesetitisicConfig(
    target: t.target,
    maxRounds: t.maxRounds,
    aiBankAt: List.unmodifiable(t.aiBankAt),
    aiErrorPct: List.unmodifiable(t.aiErrorPct),
    starMargins: List.unmodifiable(t.starMargins),
  );

  factory DesetitisicConfig.fromJson(Map<String, Object?> j) => DesetitisicConfig(
    target: j['target'] as int,
    maxRounds: j['maxRounds'] as int,
    aiBankAt: List.unmodifiable((j['aiBankAt'] as List).cast<int>()),
    aiErrorPct: List.unmodifiable((j['aiErrorPct'] as List).cast<int>()),
    starMargins: List.unmodifiable((j['starMargins'] as List).cast<int>()),
  );

  final int target, maxRounds;
  final List<int> aiBankAt, aiErrorPct, starMargins;
}

class DesetitisicState {
  const DesetitisicState({
    required this.player,
    required this.ai,
    required this.turn,
    required this.phase,
    required this.roll,
    required this.dice,
    required this.turnScore,
    required this.round,
    required this.lastBust,
    required this.over,
    required this.rng,
  });

  final int player, ai;

  /// 'player' or 'ai'.
  final String turn;

  /// 'roll', 'keep', 'decide' or 'over'.
  final String phase;

  /// Values of the last roll; empty until the side on turn rolls.
  final List<int> roll;

  /// How many dice the next roll throws (1–6).
  final int dice;
  final int turnScore, round;
  final bool lastBust, over;
  final int rng;

  int score(String side) => side == 'player' ? player : ai;

  DesetitisicState copyWith({
    int? player,
    int? ai,
    String? turn,
    String? phase,
    List<int>? roll,
    int? dice,
    int? turnScore,
    int? round,
    bool? lastBust,
    bool? over,
    int? rng,
  }) => DesetitisicState(
    player: player ?? this.player,
    ai: ai ?? this.ai,
    turn: turn ?? this.turn,
    phase: phase ?? this.phase,
    roll: roll ?? this.roll,
    dice: dice ?? this.dice,
    turnScore: turnScore ?? this.turnScore,
    round: round ?? this.round,
    lastBust: lastBust ?? this.lastBust,
    over: over ?? this.over,
    rng: rng ?? this.rng,
  );

  Map<String, Object?> toJson() => {
    'player': player,
    'ai': ai,
    'turn': turn,
    'phase': phase,
    'roll': [...roll],
    'dice': dice,
    'turnScore': turnScore,
    'round': round,
    'lastBust': lastBust,
    'over': over,
    'rng': rng,
  };
}

/// {by, op: roll|keep|bank, dice (keep only)} or {by: timeout}.
class DesetitisicAction {
  const DesetitisicAction(this.by, this.op, [this.dice = const []]);
  const DesetitisicAction.roll(this.by) : op = 'roll', dice = const [];
  const DesetitisicAction.bank(this.by) : op = 'bank', dice = const [];
  const DesetitisicAction.keep(this.by, this.dice) : op = 'keep';
  const DesetitisicAction.timeout() : by = 'timeout', op = '', dice = const [];

  final String by, op;

  /// Indices into the roll, ascending (keep only).
  final List<int> dice;

  Map<String, Object?> toJson() => by == 'timeout'
      ? {'by': by}
      : op == 'keep'
      ? {
          'by': by,
          'op': op,
          'dice': [...dice],
        }
      : {'by': by, 'op': op};

  @override
  bool operator ==(Object other) =>
      other is DesetitisicAction &&
      other.by == by &&
      other.op == op &&
      other.dice.length == dice.length &&
      [for (var i = 0; i < dice.length; i++) other.dice[i] == dice[i]].every((e) => e);

  @override
  int get hashCode => Object.hash(by, op, Object.hashAll(dice));

  @override
  String toString() => toJson().toString();
}

class DesetitisicResult {
  const DesetitisicResult({
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

/// Value of a selection (multiset of die values) by its best decomposition into a 1–6 straight
/// (1500), triples (100 × v, three 1s = 1000) and single 1s (100) and 5s (50); null when some die
/// fits no combination or the selection is empty.
int? scoreSelection(List<int> values) {
  if (values.isEmpty) return null;
  final c = List.filled(7, 0);
  for (final v in values) {
    if (v < 1 || v > 6) return null;
    c[v]++;
  }
  // Six different values: only the straight uses 2, 3, 4 and 6 without a triple.
  if (values.length == 6 && [for (var v = 1; v <= 6; v++) c[v] == 1].every((e) => e)) return 1500;
  var total = 0;
  for (var v = 1; v <= 6; v++) {
    final triples = c[v] ~/ 3;
    final rest = c[v] - 3 * triples;
    // A triple always beats three singles (1000 > 300, 500 > 150), so take as many as fit.
    if (v == 1) {
      total += triples * 1000 + rest * 100;
    } else if (v == 5) {
      total += triples * 500 + rest * 50;
    } else if (rest != 0) {
      return null;
    } else {
      total += triples * 100 * v;
    }
  }
  return total;
}

/// The roll rule: one nextInt(6) + 1 per die, in order. Public so UIs can show a busted roll.
({List<int> values, int rng}) rollDice(int rng, int n) {
  final r = withRng(rng, (p) => [for (var i = 0; i < n; i++) p.nextInt(6) + 1]);
  return (values: r.value, rng: r.rng);
}

/// Legal selections of a roll: ascending index lists ordered by bitmask (Σ 2^i) ascending.
List<List<int>> selections(List<int> roll) => [
  for (var m = 1; m < 1 << roll.length; m++)
    if (scoreSelection([
          for (var i = 0; i < roll.length; i++)
            if (m & (1 << i) != 0) roll[i],
        ]) !=
        null)
      [
        for (var i = 0; i < roll.length; i++)
          if (m & (1 << i) != 0) i,
      ],
];

String _other(String side) => side == 'player' ? 'ai' : 'player';

class DesetitisicRules extends MgRules<DesetitisicState, DesetitisicAction, DesetitisicResult> {
  DesetitisicConfig? _cfg;

  DesetitisicConfig get _c => _cfg ?? (throw StateError('desetitisic: init first'));

  @override
  String get id => 'desetitisic';

  @override
  int get specVersion => 1;

  /// Starts a game; [config] is the vector form (see [DesetitisicConfig.fromJson]).
  @override
  DesetitisicState init(Map<String, Object?> config, int seed) => start(DesetitisicConfig.fromJson(config), seed);

  DesetitisicState start(DesetitisicConfig config, int seed) {
    _cfg = config;
    return DesetitisicState(
      player: 0,
      ai: 0,
      turn: 'player',
      phase: 'roll',
      roll: const [],
      dice: 6,
      turnScore: 0,
      round: 1,
      lastBust: false,
      over: false,
      rng: Prng(seed).state,
    );
  }

  @override
  List<DesetitisicAction> legalActions(DesetitisicState s) => switch (s.phase) {
    'roll' => [DesetitisicAction.roll(s.turn)],
    'keep' => [for (final d in selections(s.roll)) DesetitisicAction.keep(s.turn, d)],
    'decide' => [DesetitisicAction.roll(s.turn), DesetitisicAction.bank(s.turn)],
    _ => const [],
  };

  @override
  DesetitisicState apply(DesetitisicState s, DesetitisicAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(over: true, phase: 'over');
    if (a.by != s.turn) throw IllegalAction(id, a);
    switch (a.op) {
      case 'roll':
        if (s.phase != 'roll' && s.phase != 'decide') throw IllegalAction(id, a);
        final r = rollDice(s.rng, s.dice);
        if (selections(r.values).isEmpty) {
          return _endTurn(s.copyWith(rng: r.rng, turnScore: 0, lastBust: true), reachedTarget: false);
        }
        return s.copyWith(rng: r.rng, roll: List.unmodifiable(r.values), phase: 'keep', lastBust: false);
      case 'keep':
        if (s.phase != 'keep') throw IllegalAction(id, a);
        final idx = a.dice;
        var ok = idx.isNotEmpty;
        for (var k = 0; ok && k < idx.length; k++) {
          ok = idx[k] >= 0 && idx[k] < s.roll.length && (k == 0 || idx[k] > idx[k - 1]);
        }
        final value = ok ? scoreSelection([for (final i in idx) s.roll[i]]) : null;
        if (value == null) throw IllegalAction(id, a);
        final dice = s.dice - idx.length;
        return s.copyWith(turnScore: s.turnScore + value, dice: dice == 0 ? 6 : dice, phase: 'decide');
      case 'bank':
        if (s.phase != 'decide') throw IllegalAction(id, a);
        final total = s.score(s.turn) + s.turnScore;
        final banked = s.turn == 'player' ? s.copyWith(player: total) : s.copyWith(ai: total);
        return _endTurn(banked, reachedTarget: total >= _c.target);
      default:
        throw IllegalAction(id, a);
    }
  }

  /// End of turn: reset the turn, pass it, count the round after the AI, then check game end.
  DesetitisicState _endTurn(DesetitisicState s, {required bool reachedTarget}) {
    final round = s.turn == 'ai' ? s.round + 1 : s.round;
    final over = reachedTarget || (s.turn == 'ai' && round > _c.maxRounds);
    return s.copyWith(
      turnScore: 0,
      dice: 6,
      roll: const [],
      phase: over ? 'over' : 'roll',
      turn: _other(s.turn),
      round: round,
      over: over,
    );
  }

  @override
  DesetitisicAction aiAction(DesetitisicState s, int level, Prng ai) {
    final c = _c;
    final lv = level.clamp(1, 5);
    final by = s.turn;
    if (s.phase == 'keep') {
      final legal = selections(s.roll);
      final err = c.aiErrorPct[lv.clamp(1, c.aiErrorPct.length) - 1];
      final r = ai.nextInt(100);
      if (r < err) return DesetitisicAction.keep(by, legal[ai.nextInt(legal.length)]);
      var best = legal.first;
      var bestV = scoreSelection([for (final i in best) s.roll[i]])!;
      for (final sel in legal.skip(1)) {
        final v = scoreSelection([for (final i in sel) s.roll[i]])!;
        if (v > bestV || (v == bestV && sel.length < best.length)) {
          best = sel;
          bestV = v;
        }
      }
      return DesetitisicAction.keep(by, best);
    }
    if (s.phase == 'decide') {
      final bankAt = c.aiBankAt[lv.clamp(1, c.aiBankAt.length) - 1];
      if (s.score(by) + s.turnScore >= c.target) return DesetitisicAction.bank(by);
      if (s.dice == 6) return DesetitisicAction.roll(by);
      if (s.turnScore >= bankAt || (s.dice <= 2 && s.turnScore >= 200)) return DesetitisicAction.bank(by);
      return DesetitisicAction.roll(by);
    }
    return DesetitisicAction.roll(by);
  }

  @override
  DesetitisicResult? result(DesetitisicState s) {
    if (!s.over) return null;
    final winner = s.player > s.ai
        ? 'player'
        : s.player < s.ai
        ? 'ai'
        : 'draw';
    final lead = s.player - s.ai;
    final m = _c.starMargins;
    final stars = winner != 'player'
        ? 0
        : lead >= m[0]
        ? 3
        : lead >= m[1]
        ? 2
        : 1;
    return DesetitisicResult(winner: winner, stars: stars, score: s.player, player: s.player, ai: s.ai);
  }

  @override
  DesetitisicAction actionFromJson(Map<String, Object?> j) => j['by'] == 'timeout'
      ? const DesetitisicAction.timeout()
      : DesetitisicAction(
          j['by'] as String,
          j['op'] as String,
          j['op'] == 'keep' ? List.unmodifiable((j['dice'] as List).cast<int>()) : const [],
        );

  @override
  Map<String, Object?> stateToJson(DesetitisicState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(DesetitisicResult r) => r.toJson();
}
