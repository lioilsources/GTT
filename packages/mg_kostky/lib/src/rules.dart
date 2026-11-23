import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/kostky.md, version 1. Pure Dart: no Flutter imports here.
class KostkyConfig {
  const KostkyConfig({required this.bonusAt, required this.bonus, required this.aiErrorPct, required this.starMargins});

  factory KostkyConfig.fromTuning(TuningMinigamesKostky t) => KostkyConfig(
    bonusAt: t.bonusAt,
    bonus: t.bonus,
    aiErrorPct: List.unmodifiable(t.aiErrorPct),
    starMargins: List.unmodifiable(t.starMargins),
  );

  factory KostkyConfig.fromJson(Map<String, Object?> j) => KostkyConfig(
    bonusAt: j['bonusAt'] as int,
    bonus: j['bonus'] as int,
    aiErrorPct: List.unmodifiable((j['aiErrorPct'] as List).cast<int>()),
    starMargins: List.unmodifiable((j['starMargins'] as List).cast<int>()),
  );

  final int bonusAt, bonus;
  final List<int> aiErrorPct, starMargins;
}

const kostkyCats = 13;
const kostkyFull = 8;
const kostkySmall = 9;
const kostkyLarge = 10;
const kostkyPoker = 11;
const kostkyChance = 12;

/// What an empty category is worth giving up (spec "AI", step 3).
const _pot = [5, 10, 15, 20, 25, 30, 30, 30, 25, 30, 40, 50, 30];

class KostkyState {
  const KostkyState({
    required this.player,
    required this.ai,
    required this.turn,
    required this.round,
    required this.dice,
    required this.rolls,
    required this.over,
    required this.rng,
  });

  /// 13 categories each, −1 = not written.
  final List<int> player, ai;

  /// 'player' or 'ai'.
  final String turn;
  final int round;

  /// Five values of the last roll; empty before the first roll of a turn.
  final List<int> dice;
  final int rolls;
  final bool over;
  final int rng;

  List<int> table(String side) => side == 'player' ? player : ai;

  KostkyState copyWith({
    List<int>? player,
    List<int>? ai,
    String? turn,
    int? round,
    List<int>? dice,
    int? rolls,
    bool? over,
    int? rng,
  }) => KostkyState(
    player: player ?? this.player,
    ai: ai ?? this.ai,
    turn: turn ?? this.turn,
    round: round ?? this.round,
    dice: dice ?? this.dice,
    rolls: rolls ?? this.rolls,
    over: over ?? this.over,
    rng: rng ?? this.rng,
  );

  Map<String, Object?> toJson() => {
    'player': [...player],
    'ai': [...ai],
    'turn': turn,
    'round': round,
    'dice': [...dice],
    'rolls': rolls,
    'over': over,
    'rng': rng,
  };
}

/// {by, op: roll, keep} | {by, op: score, cat} | {by: timeout}.
class KostkyAction {
  const KostkyAction(this.by, this.op, {this.keep = const [], this.cat = -1});
  const KostkyAction.roll(this.by, this.keep) : op = 'roll', cat = -1;
  const KostkyAction.score(this.by, this.cat) : op = 'score', keep = const [];
  const KostkyAction.timeout() : by = 'timeout', op = '', keep = const [], cat = -1;

  final String by, op;

  /// Indices of held dice, ascending (roll only).
  final List<int> keep;

  /// Category (score only).
  final int cat;

  Map<String, Object?> toJson() => by == 'timeout'
      ? {'by': by}
      : op == 'roll'
      ? {
          'by': by,
          'op': op,
          'keep': [...keep],
        }
      : {'by': by, 'op': op, 'cat': cat};

  @override
  bool operator ==(Object other) =>
      other is KostkyAction &&
      other.by == by &&
      other.op == op &&
      other.cat == cat &&
      other.keep.length == keep.length &&
      [for (var i = 0; i < keep.length; i++) other.keep[i] == keep[i]].every((e) => e);

  @override
  int get hashCode => Object.hash(by, op, cat, Object.hashAll(keep));

  @override
  String toString() => toJson().toString();
}

class KostkyResult {
  const KostkyResult({
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

/// n[v] = dice showing v (index 0 unused).
List<int> diceCounts(List<int> dice) {
  final n = List.filled(7, 0);
  for (final d in dice) {
    n[d]++;
  }
  return n;
}

bool _hasRun(List<int> n, int from, int len) {
  for (var v = from; v < from + len; v++) {
    if (n[v] == 0) return false;
  }
  return true;
}

/// Value of category [cat] for five dice (spec "Kolonky").
int catValue(int cat, List<int> dice) {
  final n = diceCounts(dice);
  final sum = dice.fold(0, (a, b) => a + b);
  final max = n.skip(1).fold(0, (a, b) => b > a ? b : a);
  if (cat <= 5) return (cat + 1) * n[cat + 1];
  switch (cat) {
    case 6:
      return max >= 3 ? sum : 0;
    case 7:
      return max >= 4 ? sum : 0;
    case kostkyFull:
      final nz = [
        for (final x in n.skip(1))
          if (x > 0) x,
      ]..sort();
      return nz.length == 2 && nz[0] == 2 && nz[1] == 3 ? 25 : 0;
    case kostkySmall:
      return _hasRun(n, 1, 4) || _hasRun(n, 2, 4) || _hasRun(n, 3, 4) ? 30 : 0;
    case kostkyLarge:
      return _hasRun(n, 1, 5) || _hasRun(n, 2, 5) ? 40 : 0;
    case kostkyPoker:
      return max == 5 ? 50 : 0;
    default:
      return sum;
  }
}

/// Sum of the written upper categories (0–5).
int upperSum(List<int> table) => table.take(6).fold(0, (a, b) => a + (b < 0 ? 0 : b));

/// Written categories plus the upper bonus; unwritten count as 0.
int tableTotal(List<int> table, KostkyConfig c) =>
    table.fold(0, (a, b) => a + (b < 0 ? 0 : b)) + (upperSum(table) >= c.bonusAt ? c.bonus : 0);

class KostkyRules extends MgRules<KostkyState, KostkyAction, KostkyResult> {
  KostkyConfig? _cfg;

  KostkyConfig get _c => _cfg ?? (throw StateError('kostky: init first'));

  @override
  String get id => 'kostky';

  @override
  int get specVersion => 1;

  /// Starts a game; [config] is the vector form (see [KostkyConfig.fromJson]).
  @override
  KostkyState init(Map<String, Object?> config, int seed) => start(KostkyConfig.fromJson(config), seed);

  KostkyState start(KostkyConfig config, int seed) {
    _cfg = config;
    return KostkyState(
      player: List.unmodifiable(List.filled(kostkyCats, -1)),
      ai: List.unmodifiable(List.filled(kostkyCats, -1)),
      turn: 'player',
      round: 1,
      dice: const [],
      rolls: 0,
      over: false,
      rng: Prng(seed).state,
    );
  }

  @override
  List<KostkyAction> legalActions(KostkyState s) {
    if (s.over) return const [];
    final by = s.turn;
    if (s.rolls == 0) return [KostkyAction.roll(by, const [])];
    return [
      if (s.rolls < 3)
        for (var m = 0; m < 31; m++)
          KostkyAction.roll(by, [
            for (var i = 0; i < 5; i++)
              if (m & (1 << i) != 0) i,
          ]),
      for (var cat = 0; cat < kostkyCats; cat++)
        if (s.table(by)[cat] < 0) KostkyAction.score(by, cat),
    ];
  }

  @override
  KostkyState apply(KostkyState s, KostkyAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(over: true);
    if (a.by != s.turn) throw IllegalAction(id, a);
    if (a.op == 'roll') {
      final keep = a.keep;
      var ok = s.rolls == 0 ? keep.isEmpty : s.rolls < 3 && keep.length < 5;
      for (var i = 0; ok && i < keep.length; i++) {
        ok = keep[i] >= 0 && keep[i] < 5 && (i == 0 || keep[i] > keep[i - 1]);
      }
      if (!ok) throw IllegalAction(id, a);
      final r = withRng(s.rng, (p) {
        final dice = [for (var i = 0; i < 5; i++) s.rolls > 0 && keep.contains(i) ? s.dice[i] : 0];
        for (var i = 0; i < 5; i++) {
          if (dice[i] == 0) dice[i] = p.nextInt(6) + 1;
        }
        return dice;
      });
      return s.copyWith(dice: List.unmodifiable(r.value), rolls: s.rolls + 1, rng: r.rng);
    }
    if (a.op != 'score' || s.rolls == 0 || a.cat < 0 || a.cat >= kostkyCats || s.table(s.turn)[a.cat] != -1) {
      throw IllegalAction(id, a);
    }
    final table = [...s.table(s.turn)];
    table[a.cat] = catValue(a.cat, s.dice);
    final t = List<int>.unmodifiable(table);
    final n = (s.turn == 'player' ? s.copyWith(player: t) : s.copyWith(ai: t)).copyWith(
      dice: const [],
      rolls: 0,
      turn: s.turn == 'player' ? 'ai' : 'player',
    );
    if (s.turn != 'ai') return n;
    return n.copyWith(round: s.round + 1, over: table.every((v) => v >= 0) ? true : null);
  }

  /// Step 3: the free category with the highest val (ties → lower index).
  int _pick(KostkyState s, int level) {
    final n = diceCounts(s.dice);
    var best = -1;
    int? bv;
    for (var i = 0; i < kostkyCats; i++) {
      if (s.ai[i] != -1) continue;
      final h = catValue(i, s.dice);
      int val;
      if (h > 0) {
        val = 10 * h;
        if (level >= 3 && i <= 5 && n[i + 1] >= 3) val += 50;
        if (level >= 3 && i == kostkyChance) val -= 50;
      } else {
        val = -_pot[i];
      }
      if (bv == null || val > bv) {
        bv = val;
        best = i;
      }
    }
    return best;
  }

  /// Dice to keep for the next roll (spec "AI", step 2), indices ascending.
  List<int> aiKeep(List<int> dice, List<int> t, int level) {
    final n = diceCounts(dice);
    var f = 6;
    for (var v = 5; v >= 1; v--) {
      if (n[v] > n[f]) f = v;
    }
    final c = n[f];
    List<int> withF() => [
      for (var i = 0; i < dice.length; i++)
        if (dice[i] == f) i,
    ];
    if (c >= 3) return withF();
    if (level >= 3 && (t[kostkySmall] == -1 || t[kostkyLarge] == -1)) {
      var bestLen = 0, bestEnd = 0, len = 0;
      for (var v = 1; v <= 6; v++) {
        len = n[v] > 0 ? len + 1 : 0;
        if (len >= bestLen && len > 0) {
          bestLen = len;
          bestEnd = v;
        }
      }
      if (bestLen >= 3) {
        return [for (var v = bestEnd - bestLen + 1; v <= bestEnd; v++) dice.indexOf(v)]..sort();
      }
    }
    if (c == 2) return withF();
    return const [];
  }

  @override
  KostkyAction aiAction(KostkyState s, int level, Prng ai) {
    final legal = legalActions(s);
    if (s.turn != 'ai' || legal.isEmpty) throw IllegalAction(id, const KostkyAction('ai', ''));
    final err = level >= 1 && level <= _c.aiErrorPct.length ? _c.aiErrorPct[level - 1] : 0;
    if (ai.nextInt(100) < err) return legal[ai.nextInt(legal.length)];
    if (s.rolls == 0) return const KostkyAction.roll('ai', []);
    KostkyAction score() => KostkyAction.score('ai', _pick(s, level));
    if (s.rolls == 3) return score();
    final t = s.ai;
    final n = diceCounts(s.dice);
    if ((t[kostkyPoker] == -1 && n.contains(5)) ||
        (t[kostkyLarge] == -1 && catValue(kostkyLarge, s.dice) > 0) ||
        (t[kostkyFull] == -1 && catValue(kostkyFull, s.dice) > 0) ||
        (t[kostkySmall] == -1 && t[kostkyLarge] != -1 && catValue(kostkySmall, s.dice) > 0)) {
      return score();
    }
    final keep = aiKeep(s.dice, t, level);
    return keep.length == 5 ? score() : KostkyAction.roll('ai', keep);
  }

  @override
  KostkyResult? result(KostkyState s) {
    if (!s.over) return null;
    final p = tableTotal(s.player, _c), a = tableTotal(s.ai, _c);
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
    return KostkyResult(winner: winner, stars: stars, score: p, player: p, ai: a);
  }

  @override
  KostkyAction actionFromJson(Map<String, Object?> j) {
    if (j['by'] == 'timeout') return const KostkyAction.timeout();
    final by = j['by'] as String;
    return switch (j['op']) {
      'roll' => KostkyAction.roll(by, List.unmodifiable((j['keep'] as List).cast<int>())),
      'score' => KostkyAction.score(by, j['cat'] as int),
      final op => KostkyAction(by, '$op'),
    };
  }

  @override
  Map<String, Object?> stateToJson(KostkyState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(KostkyResult r) => r.toJson();
}
