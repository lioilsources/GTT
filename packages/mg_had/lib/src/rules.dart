import 'dart:math' as math;

import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/had.md, version 1. Pure Dart: no Flutter imports here.
class HadConfig {
  const HadConfig({
    required this.level,
    required this.w,
    required this.h,
    required this.startInterval,
    required this.minInterval,
    required this.speedupEvery,
    required this.foodPoints,
    required this.starScores,
  });

  factory HadConfig.fromTuning(TuningMinigamesHad t, int level) => HadConfig(
    level: level,
    w: t.w,
    h: t.h,
    startInterval: List.unmodifiable(t.startInterval),
    minInterval: List.unmodifiable(t.minInterval),
    speedupEvery: t.speedupEvery,
    foodPoints: t.foodPoints,
    starScores: List.unmodifiable(t.starScores),
  );

  factory HadConfig.fromJson(Map<String, Object?> j) {
    List<int> l(String k) => List.unmodifiable((j[k] as List).cast<int>());
    return HadConfig(
      level: j['level'] as int,
      w: j['w'] as int,
      h: j['h'] as int,
      startInterval: l('startInterval'),
      minInterval: l('minInterval'),
      speedupEvery: j['speedupEvery'] as int,
      foodPoints: j['foodPoints'] as int,
      starScores: l('starScores'),
    );
  }

  final int level, w, h, speedupEvery, foodPoints;
  final List<int> startInterval, minInterval, starScores;
}

/// Direction d → (dx, dy): 0 up (+y), 1 right, 2 down, 3 left.
const hadDirs = [(0, 1), (1, 0), (0, -1), (-1, 0)];

typedef Cell = (int, int);

class HadState {
  const HadState({
    required this.body,
    required this.dir,
    required this.next,
    required this.food,
    required this.t,
    required this.interval,
    required this.score,
    required this.eaten,
    required this.over,
    required this.rng,
  });

  /// Head first.
  final List<Cell> body;
  final int dir, next;
  final Cell food;
  final int t, interval, score, eaten;
  final bool over;
  final int rng;

  HadState copyWith({int? next, bool? over}) => HadState(
    body: body,
    dir: dir,
    next: next ?? this.next,
    food: food,
    t: t,
    interval: interval,
    score: score,
    eaten: eaten,
    over: over ?? this.over,
    rng: rng,
  );

  Map<String, Object?> toJson() => {
    'body': [
      for (final c in body) [c.$1, c.$2],
    ],
    'dir': dir,
    'next': next,
    'food': [food.$1, food.$2],
    't': t,
    'interval': interval,
    'score': score,
    'eaten': eaten,
    'over': over,
    'rng': rng,
  };
}

/// {by: player, op: tick, n}, {by: player, op: turn, dir} or {by: timeout}.
class HadAction {
  const HadAction.tick(this.n) : by = 'player', op = 'tick', dir = 0;
  const HadAction.turn(this.dir) : by = 'player', op = 'turn', n = 0;
  const HadAction.timeout() : by = 'timeout', op = '', n = 0, dir = 0;
  const HadAction._(this.by, this.op, this.n, this.dir);

  final String by, op;
  final int n, dir;

  Map<String, Object?> toJson() => by == 'timeout'
      ? {'by': by}
      : op == 'turn'
      ? {'by': by, 'op': op, 'dir': dir}
      : {'by': by, 'op': op, 'n': n};

  @override
  bool operator ==(Object other) =>
      other is HadAction && other.by == by && other.op == op && other.n == n && other.dir == dir;

  @override
  int get hashCode => Object.hash(by, op, n, dir);

  @override
  String toString() => toJson().toString();
}

class HadResult {
  const HadResult({required this.winner, required this.stars, required this.score, required this.length});

  final String winner;
  final int stars, score, length;

  Map<String, Object?> toJson() => {'winner': winner, 'stars': stars, 'score': score, 'length': length};
}

/// Mutable working copy of one apply.
class _Run {
  _Run(HadState s)
    : body = [...s.body],
      dir = s.dir,
      next = s.next,
      food = s.food,
      t = s.t,
      interval = s.interval,
      score = s.score,
      eaten = s.eaten,
      over = s.over,
      rng = s.rng;

  final List<Cell> body;
  int dir, next;
  Cell food;
  int t, interval, score, eaten;
  bool over;
  int rng;

  HadState freeze() => HadState(
    body: List.unmodifiable(body),
    dir: dir,
    next: next,
    food: food,
    t: t,
    interval: interval,
    score: score,
    eaten: eaten,
    over: over,
    rng: rng,
  );
}

class HadRules extends MgRules<HadState, HadAction, HadResult> {
  HadConfig? _cfg;

  HadConfig get config => _cfg ?? (throw StateError('had: init first'));

  @override
  String get id => 'had';

  @override
  int get specVersion => 1;

  @override
  HadState init(Map<String, Object?> config, int seed) => start(HadConfig.fromJson(config), seed);

  HadState start(HadConfig config, int seed) {
    _cfg = config;
    final cx = config.w ~/ 2, cy = config.h ~/ 2;
    final r = _Run(
      HadState(
        body: [(cx, cy), (cx, cy - 1), (cx, cy - 2)],
        dir: 0,
        next: 0,
        food: (0, 0),
        t: 0,
        interval: config.startInterval[config.level - 1],
        score: 0,
        eaten: 0,
        over: false,
        rng: Prng(seed).state,
      ),
    );
    _placeFood(r);
    return r.freeze();
  }

  /// Food on a free cell (rows from y = 0, x from 0 in a row); none free → over (food stays).
  void _placeFood(_Run s) {
    final c = config;
    final taken = {for (final b in s.body) b.$2 * c.w + b.$1};
    final free = <Cell>[];
    for (var y = 0; y < c.h; y++) {
      for (var x = 0; x < c.w; x++) {
        if (!taken.contains(y * c.w + x)) free.add((x, y));
      }
    }
    if (free.isEmpty) {
      s.over = true;
      return;
    }
    final r = withRng(s.rng, (p) => p.nextInt(free.length));
    s.food = free[r.value];
    s.rng = r.rng;
  }

  @override
  List<HadAction> legalActions(HadState s) => const [];

  @override
  HadState apply(HadState s0, HadAction a) {
    if (s0.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s0.copyWith(over: true);
    if (a.by != 'player') throw IllegalAction(id, a);
    if (a.op == 'turn') {
      if (a.dir < 0 || a.dir > 3) throw IllegalAction(id, a);
      return a.dir == (s0.dir + 2) % 4 ? s0 : s0.copyWith(next: a.dir);
    }
    if (a.op != 'tick' || a.n < 1) throw IllegalAction(id, a);
    final s = _Run(s0);
    for (var k = 0; k < a.n && !s.over; k++) {
      s.t += 1;
      if (s.t >= s.interval) {
        s.t = 0;
        _move(s);
      }
    }
    return s.freeze();
  }

  void _move(_Run s) {
    final c = config;
    s.dir = s.next;
    final head = s.body.first;
    final d = hadDirs[s.dir];
    final nx = head.$1 + d.$1, ny = head.$2 + d.$2;
    if (nx < 0 || ny < 0 || nx >= c.w || ny >= c.h) {
      s.over = true;
      return;
    }
    final eats = nx == s.food.$1 && ny == s.food.$2;
    final check = eats ? s.body : s.body.sublist(0, s.body.length - 1);
    if (check.contains((nx, ny))) {
      s.over = true;
      return;
    }
    s.body.insert(0, (nx, ny));
    if (!eats) {
      s.body.removeLast();
      return;
    }
    s.score += c.foodPoints;
    s.eaten += 1;
    if (s.eaten % c.speedupEvery == 0) s.interval = math.max(s.interval - 1, c.minInterval[c.level - 1]);
    _placeFood(s);
  }

  @override
  HadAction aiAction(HadState s, int level, Prng ai) => const HadAction.tick(1);

  @override
  HadResult? result(HadState s) {
    if (!s.over) return null;
    final ss = config.starScores;
    final stars = s.score >= ss[0]
        ? 3
        : s.score >= ss[1]
        ? 2
        : s.score >= ss[2]
        ? 1
        : 0;
    return HadResult(winner: stars >= 1 ? 'player' : 'ai', stars: stars, score: s.score, length: s.body.length);
  }

  @override
  HadAction actionFromJson(Map<String, Object?> j) {
    if (j['by'] == 'timeout') return const HadAction.timeout();
    return HadAction._(j['by'] as String, j['op'] as String, (j['n'] as int?) ?? 0, (j['dir'] as int?) ?? 0);
  }

  @override
  Map<String, Object?> stateToJson(HadState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(HadResult r) => r.toJson();
}
