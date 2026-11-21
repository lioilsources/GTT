import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/police.md, version 1: wanted level, escape and capture in integer ticks (P0, module
/// `police`). Port of web/src/police/rules.ts.

/// Alphabetical: the order of legalActions and of the `cool` keys.
const offenceKinds = ['crash', 'hitrun', 'sidewalk', 'theft'];

class PoliceConfig {
  const PoliceConfig({
    required this.maxLevel,
    required this.escapeTicks,
    required this.captureTicks,
    required this.hitRunTicks,
    required this.cooldownTicks,
    required this.levels,
    required this.fines,
  });

  /// Config from tuning: seconds become integer ticks at `police.tick_hz`.
  factory PoliceConfig.fromTuning(TuningPolice t) {
    int ticks(double s) => (s * t.tickHz).round();
    final o = t.offenceLevel;
    return PoliceConfig(
      maxLevel: t.maxLevel,
      escapeTicks: ticks(t.escapeS),
      captureTicks: ticks(t.captureS),
      hitRunTicks: ticks(t.hitRunS),
      cooldownTicks: ticks(t.cooldownS),
      levels: {'crash': o.crash, 'hitrun': o.hitrun, 'sidewalk': o.sidewalk, 'theft': o.theft},
      fines: List.unmodifiable(t.fines),
    );
  }

  factory PoliceConfig.fromJson(Map<String, Object?> j) => PoliceConfig(
    maxLevel: j['maxLevel'] as int,
    escapeTicks: j['escapeTicks'] as int,
    captureTicks: j['captureTicks'] as int,
    hitRunTicks: j['hitRunTicks'] as int,
    cooldownTicks: j['cooldownTicks'] as int,
    levels: Map.unmodifiable((j['levels'] as Map).cast<String, int>()),
    fines: List.unmodifiable((j['fines'] as List).cast<int>()),
  );

  final int maxLevel;
  final int escapeTicks;
  final int captureTicks;
  final int hitRunTicks;
  final int cooldownTicks;
  final Map<String, int> levels;
  final List<int> fines;
}

/// Fine when busted at [level] (specs/police.md): `fines[min(level, len − 1)]`.
int fine(int level, List<int> fines) => fines.isEmpty ? 0 : fines[level.clamp(0, fines.length - 1)];

/// Mutable while one action is applied; [PoliceRules.apply] always works on a copy.
class PoliceState {
  PoliceState({
    this.level = 0,
    this.unseen = 0,
    this.capture = 0,
    this.hitRun = 0,
    this.hitRunSeen = false,
    Map<String, int>? cool,
    this.offences = 0,
    this.last = '',
    this.busted = 0,
    this.fined = 0,
  }) : cool = cool ?? {for (final k in offenceKinds) k: 0};

  int level;
  int unseen;
  int capture;
  int hitRun;
  bool hitRunSeen;
  final Map<String, int> cool;
  int offences;
  String last;
  int busted;
  int fined;

  PoliceState copy() => PoliceState(
    level: level,
    unseen: unseen,
    capture: capture,
    hitRun: hitRun,
    hitRunSeen: hitRunSeen,
    cool: Map.of(cool),
    offences: offences,
    last: last,
    busted: busted,
    fined: fined,
  );

  Map<String, Object?> toJson() => {
    'level': level,
    'unseen': unseen,
    'capture': capture,
    'hitRun': hitRun,
    'hitRunSeen': hitRunSeen,
    'cool': {for (final k in offenceKinds) k: cool[k]},
    'offences': offences,
    'last': last,
    'busted': busted,
    'fined': fined,
  };
}

/// `op` is offence (with [kind]) or tick (with [near] and [away]); [seen] in both.
class PoliceAction {
  const PoliceAction.offence(String this.kind, {required this.seen}) : op = 'offence', near = false, away = false;
  const PoliceAction.tick({required this.seen, required this.near, required this.away}) : op = 'tick', kind = null;

  final String op;
  final String? kind;
  final bool seen;
  final bool near;
  final bool away;

  Map<String, Object?> toJson() => op == 'offence'
      ? {'by': 'player', 'op': op, 'kind': kind, 'seen': seen}
      : {'by': 'player', 'op': op, 'seen': seen, 'near': near, 'away': away};

  @override
  bool operator ==(Object other) =>
      other is PoliceAction &&
      other.op == op &&
      other.kind == kind &&
      other.seen == seen &&
      other.near == near &&
      other.away == away;
  @override
  int get hashCode => Object.hash(op, kind, seen, near, away);
  @override
  String toString() => toJson().toString();
}

class PoliceRules extends MgRules<PoliceState, PoliceAction, Map<String, Object?>> {
  @override
  String get id => 'police';
  @override
  int get specVersion => 1;

  PoliceConfig? _cfg;
  PoliceConfig get config => _cfg ?? (throw StateError('police: init first'));

  PoliceState start(PoliceConfig c) {
    _cfg = c;
    return PoliceState();
  }

  @override
  PoliceState init(Map<String, Object?> config, int seed) => start(PoliceConfig.fromJson(config));

  @override
  List<PoliceAction> legalActions(PoliceState s) => [
    for (final k in offenceKinds)
      for (final seen in [false, true]) PoliceAction.offence(k, seen: seen),
    for (var b = 0; b < 8; b++) PoliceAction.tick(seen: b & 4 != 0, near: b & 2 != 0, away: b & 1 != 0),
  ];

  /// Counts a seen offence that is not cooling down (spec "Započtení přestupku"); mutates [s].
  void _commit(PoliceState s, String kind, bool seen) {
    final c = config;
    if (!seen || s.cool[kind]! > 0) return;
    final base = c.levels[kind]!;
    final up = s.level > 0 ? s.level + 1 : 0;
    s
      ..level = (base > up ? base : up).clamp(0, c.maxLevel)
      ..offences += 1
      ..last = kind
      ..unseen = 0;
    s.cool[kind] = c.cooldownTicks;
  }

  @override
  PoliceState apply(PoliceState state, PoliceAction a) {
    final c = config;
    final s = state.copy();
    if (a.op == 'offence') {
      final kind = a.kind;
      if (kind == null || !offenceKinds.contains(kind)) throw IllegalAction(id, a);
      if (kind == 'crash') {
        s.hitRunSeen = (s.hitRun > 0 && s.hitRunSeen) || a.seen;
        s.hitRun = c.hitRunTicks;
      }
      _commit(s, kind, a.seen);
      return s;
    }
    if (a.op != 'tick') throw IllegalAction(id, a);
    for (final k in offenceKinds) {
      s.cool[k] = s.cool[k]! > 0 ? s.cool[k]! - 1 : 0;
    }
    if (s.hitRun > 0) {
      if (a.away) {
        final seen = a.seen || s.hitRunSeen;
        s
          ..hitRun = 0
          ..hitRunSeen = false;
        _commit(s, 'hitrun', seen);
      } else {
        s.hitRun -= 1;
        if (s.hitRun == 0) s.hitRunSeen = false;
      }
    }
    if (s.level == 0) {
      s
        ..unseen = 0
        ..capture = 0;
      return s;
    }
    s.capture = a.near ? s.capture + 1 : 0;
    if (s.capture >= c.captureTicks) {
      s
        ..fined += fine(s.level, c.fines)
        ..busted += 1
        ..level = 0
        ..unseen = 0
        ..capture = 0
        ..hitRun = 0
        ..hitRunSeen = false;
      for (final k in offenceKinds) {
        s.cool[k] = c.cooldownTicks;
      }
      return s;
    }
    s.unseen = a.seen ? 0 : s.unseen + 1;
    if (s.unseen >= c.escapeTicks) {
      s
        ..level -= 1
        ..unseen = 0;
    }
    return s;
  }

  @override
  PoliceAction aiAction(PoliceState state, int level, Prng ai) => throw UnsupportedError('police: no opponent');

  @override
  Map<String, Object?>? result(PoliceState state) => null;

  @override
  PoliceAction actionFromJson(Map<String, Object?> j) {
    if (j['by'] != 'player' || j['seen'] is! bool) throw IllegalAction(id, j);
    final seen = j['seen'] as bool;
    return switch (j['op']) {
      'offence' => PoliceAction.offence(j['kind'] as String, seen: seen),
      'tick' => PoliceAction.tick(seen: seen, near: j['near'] as bool, away: j['away'] as bool),
      _ => throw IllegalAction(id, j),
    };
  }

  @override
  Map<String, Object?> stateToJson(PoliceState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(Map<String, Object?> r) => r;
}
