import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/strelnice.md, version 1. Pure Dart: no Flutter imports here.
/// `tick_hz` is UI-only and not part of the config.
class StrelniceConfig {
  const StrelniceConfig({
    required this.rounds,
    required this.roundTicks,
    required this.targets,
    required this.width,
    required this.lanes,
    required this.kinds,
    required this.kindPct,
    required this.magazine,
    required this.reloadTicks,
    required this.starScores,
  });

  factory StrelniceConfig.fromTuning(TuningMinigamesStrelnice t) => StrelniceConfig(
    rounds: t.rounds,
    roundTicks: t.roundTicks,
    targets: t.targets,
    width: t.width,
    lanes: List.unmodifiable(t.lanes),
    kinds: List.unmodifiable(t.kinds),
    kindPct: List.unmodifiable(t.kindPct),
    magazine: t.magazine,
    reloadTicks: t.reloadTicks,
    starScores: List.unmodifiable(t.starScores),
  );

  factory StrelniceConfig.fromJson(Map<String, Object?> j) {
    List<int> l(String k) => List.unmodifiable((j[k] as List).cast<int>());
    return StrelniceConfig(
      rounds: j['rounds'] as int,
      roundTicks: j['roundTicks'] as int,
      targets: j['targets'] as int,
      width: j['width'] as int,
      lanes: l('lanes'),
      kinds: l('kinds'),
      kindPct: l('kindPct'),
      magazine: j['magazine'] as int,
      reloadTicks: j['reloadTicks'] as int,
      starScores: l('starScores'),
    );
  }

  final int rounds, roundTicks, targets, width, magazine, reloadTicks;
  final List<int> lanes;

  /// Triples (radius, speed per tick, points): small, medium, large.
  final List<int> kinds;
  final List<int> kindPct, starScores;

  int radius(int kind) => kinds[3 * kind];
  int speed(int kind) => kinds[3 * kind + 1];
  int points(int kind) => kinds[3 * kind + 2];

  Map<String, Object?> toJson() => {
    'rounds': rounds,
    'roundTicks': roundTicks,
    'targets': targets,
    'width': width,
    'lanes': lanes,
    'kinds': kinds,
    'kindPct': kindPct,
    'magazine': magazine,
    'reloadTicks': reloadTicks,
    'starScores': starScores,
  };
}

class Target {
  const Target({required this.lane, required this.kind, required this.spawn, required this.dir, this.hit = false});

  final int lane, kind, spawn, dir;
  final bool hit;

  Target copyWith({bool? hit}) => Target(lane: lane, kind: kind, spawn: spawn, dir: dir, hit: hit ?? this.hit);

  Map<String, Object?> toJson() => {'lane': lane, 'kind': kind, 'spawn': spawn, 'dir': dir, 'hit': hit};
}

/// Targets of one round, drawn from [r] in the order lane → roll → spawn jitter per target.
List<Target> genTargets(StrelniceConfig c, Prng r) {
  final spacing = (c.roundTicks * 9) ~/ (10 * c.targets);
  return [for (var i = 0; i < c.targets; i++) _gen(c, r, i, spacing)];
}

Target _gen(StrelniceConfig c, Prng r, int i, int spacing) {
  final lane = r.nextInt(c.lanes.length);
  final roll = r.nextInt(100);
  final kind = roll < c.kindPct[0]
      ? 0
      : roll < c.kindPct[1]
      ? 1
      : 2;
  final spawn = i * spacing + r.nextInt(spacing);
  return Target(lane: lane, kind: kind, spawn: spawn, dir: lane % 2 == 0 ? 1 : -1);
}

/// Target position at [tick] (meaningful for tick ≥ spawn).
({int x, int y}) targetPos(Target t, int tick, StrelniceConfig c) {
  final r = c.radius(t.kind);
  final x0 = t.dir == 1 ? -r : c.width + r;
  return (x: x0 + t.dir * c.speed(t.kind) * (tick - t.spawn), y: c.lanes[t.lane]);
}

/// On the field: spawned, not hit and −r ≤ x ≤ width + r.
bool onField(Target t, int tick, StrelniceConfig c) {
  if (tick < t.spawn || t.hit) return false;
  final r = c.radius(t.kind);
  final x = targetPos(t, tick, c).x;
  return x >= -r && x <= c.width + r;
}

class StrelniceState {
  const StrelniceState({
    required this.round,
    required this.tick,
    required this.score,
    required this.shots,
    required this.hits,
    required this.ammo,
    required this.reload,
    required this.targets,
    required this.over,
    required this.rng,
  });

  final int round, tick, score, shots, hits, ammo, reload;
  final List<Target> targets;
  final bool over;
  final int rng;

  StrelniceState copyWith({
    int? round,
    int? tick,
    int? score,
    int? shots,
    int? hits,
    int? ammo,
    int? reload,
    List<Target>? targets,
    bool? over,
    int? rng,
  }) => StrelniceState(
    round: round ?? this.round,
    tick: tick ?? this.tick,
    score: score ?? this.score,
    shots: shots ?? this.shots,
    hits: hits ?? this.hits,
    ammo: ammo ?? this.ammo,
    reload: reload ?? this.reload,
    targets: targets ?? this.targets,
    over: over ?? this.over,
    rng: rng ?? this.rng,
  );

  Map<String, Object?> toJson() => {
    'round': round,
    'tick': tick,
    'score': score,
    'shots': shots,
    'hits': hits,
    'ammo': ammo,
    'reload': reload,
    'targets': [for (final t in targets) t.toJson()],
    'over': over,
    'rng': rng,
  };
}

/// {by: player, op: tick, n} · {by: player, op: shoot, x, y} · {by: timeout}.
class StrelniceAction {
  const StrelniceAction.tick(this.n) : by = 'player', op = 'tick', x = 0, y = 0;
  const StrelniceAction.shoot(this.x, this.y) : by = 'player', op = 'shoot', n = 0;
  const StrelniceAction.timeout() : by = 'timeout', op = '', n = 0, x = 0, y = 0;
  const StrelniceAction.raw(this.by, this.op, {this.n = 0, this.x = 0, this.y = 0});

  final String by, op;
  final int n, x, y;

  Map<String, Object?> toJson() => by == 'timeout'
      ? {'by': by}
      : op == 'tick'
      ? {'by': by, 'op': op, 'n': n}
      : {'by': by, 'op': op, 'x': x, 'y': y};

  @override
  String toString() => toJson().toString();
}

class StrelniceResult {
  const StrelniceResult({
    required this.winner,
    required this.stars,
    required this.score,
    required this.shots,
    required this.hits,
  });

  final String winner;
  final int stars, score, shots, hits;

  Map<String, Object?> toJson() => {'winner': winner, 'stars': stars, 'score': score, 'shots': shots, 'hits': hits};
}

class StrelniceRules extends MgRules<StrelniceState, StrelniceAction, StrelniceResult> {
  StrelniceConfig? _cfg;

  StrelniceConfig get config => _cfg ?? (throw StateError('strelnice: init first'));

  @override
  String get id => 'strelnice';

  @override
  int get specVersion => 1;

  /// Starts a game; [config] is the vector form (see [StrelniceConfig.fromJson]).
  @override
  StrelniceState init(Map<String, Object?> config, int seed) => start(StrelniceConfig.fromJson(config), seed);

  StrelniceState start(StrelniceConfig config, int seed) {
    _cfg = config;
    final g = withRng(Prng(seed).state, (r) => genTargets(config, r));
    return StrelniceState(
      round: 1,
      tick: 0,
      score: 0,
      shots: 0,
      hits: 0,
      ammo: config.magazine,
      reload: 0,
      targets: List.unmodifiable(g.value),
      over: false,
      rng: g.rng,
    );
  }

  @override
  List<StrelniceAction> legalActions(StrelniceState s) => const [];

  @override
  StrelniceState apply(StrelniceState s, StrelniceAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(over: true);
    if (a.by != 'player') throw IllegalAction(id, a);
    switch (a.op) {
      case 'tick':
        if (a.n < 1) throw IllegalAction(id, a);
        return _advance(s, a.n);
      case 'shoot':
        return _shoot(s, a.x, a.y);
    }
    throw IllegalAction(id, a);
  }

  StrelniceState _advance(StrelniceState s, int n) {
    final c = config;
    var round = s.round, tick = s.tick, ammo = s.ammo, reload = s.reload, rng = s.rng;
    var targets = s.targets;
    var over = false;
    for (var k = 0; k < n; k++) {
      tick += 1;
      if (reload > 0) {
        reload -= 1;
        if (reload == 0) ammo = c.magazine;
      }
      if (tick >= c.roundTicks) {
        if (round >= c.rounds) {
          over = true;
          break;
        }
        final g = withRng(rng, (r) => genTargets(c, r));
        round += 1;
        tick = 0;
        ammo = c.magazine;
        reload = 0;
        targets = List.unmodifiable(g.value);
        rng = g.rng;
      }
    }
    return s.copyWith(round: round, tick: tick, ammo: ammo, reload: reload, targets: targets, over: over, rng: rng);
  }

  StrelniceState _shoot(StrelniceState s, int x, int y) {
    final c = config;
    if (s.ammo <= 0 || s.reload > 0) return s;
    final ammo = s.ammo - 1;
    final reload = ammo == 0 ? c.reloadTicks : s.reload;
    for (var i = 0; i < s.targets.length; i++) {
      final t = s.targets[i];
      if (!onField(t, s.tick, c)) continue;
      final p = targetPos(t, s.tick, c);
      final r = c.radius(t.kind);
      final dx = x - p.x, dy = y - p.y;
      if (dx * dx + dy * dy <= r * r) {
        return s.copyWith(
          ammo: ammo,
          reload: reload,
          shots: s.shots + 1,
          hits: s.hits + 1,
          score: s.score + c.points(t.kind),
          targets: List.unmodifiable([
            for (var j = 0; j < s.targets.length; j++) j == i ? s.targets[j].copyWith(hit: true) : s.targets[j],
          ]),
        );
      }
    }
    return s.copyWith(ammo: ammo, reload: reload, shots: s.shots + 1);
  }

  /// No opponent: the AI just lets time pass.
  @override
  StrelniceAction aiAction(StrelniceState s, int level, Prng ai) => const StrelniceAction.tick(1);

  @override
  StrelniceResult? result(StrelniceState s) {
    if (!s.over) return null;
    final ss = config.starScores;
    final stars = s.score >= ss[0]
        ? 3
        : s.score >= ss[1]
        ? 2
        : s.score >= ss[2]
        ? 1
        : 0;
    return StrelniceResult(
      winner: stars >= 1 ? 'player' : 'ai',
      stars: stars,
      score: s.score,
      shots: s.shots,
      hits: s.hits,
    );
  }

  @override
  StrelniceAction actionFromJson(Map<String, Object?> j) => j['by'] == 'timeout'
      ? const StrelniceAction.timeout()
      : StrelniceAction.raw(
          j['by'] as String,
          j['op'] as String? ?? '',
          n: j['n'] as int? ?? 0,
          x: j['x'] as int? ?? 0,
          y: j['y'] as int? ?? 0,
        );

  @override
  Map<String, Object?> stateToJson(StrelniceState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(StrelniceResult r) => r.toJson();
}
