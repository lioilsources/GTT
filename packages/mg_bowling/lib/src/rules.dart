import 'package:mg_physics/mg_physics.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/bowling.md, version 1 (physics: specs/minigames/fyzika.md v1). Pure Dart.
class BowlingConfig {
  const BowlingConfig({
    required this.level,
    required this.laneW,
    required this.headY,
    required this.pinDx,
    required this.pinDy,
    required this.ballR,
    required this.ballM,
    required this.pinR,
    required this.pinM,
    required this.minSpeed,
    required this.maxSpeed,
    required this.pinDec,
    required this.ePin,
    required this.eWall,
    required this.deckY0,
    required this.deckY1,
    required this.knock,
    required this.maxSteps,
    required this.scatter,
    required this.starScores,
  });

  factory BowlingConfig.fromTuning(TuningMinigamesBowling t, int level) => BowlingConfig(
    level: level,
    laneW: t.laneW,
    headY: t.headY,
    pinDx: t.pinDx,
    pinDy: t.pinDy,
    ballR: t.ballR,
    ballM: t.ballM,
    pinR: t.pinR,
    pinM: t.pinM,
    minSpeed: t.minSpeed,
    maxSpeed: t.maxSpeed,
    pinDec: t.pinDec,
    ePin: t.ePin,
    eWall: t.eWall,
    deckY0: t.deckY0,
    deckY1: t.deckY1,
    knock: t.knock,
    maxSteps: t.maxSteps,
    scatter: List.unmodifiable(t.scatter),
    starScores: List.unmodifiable(t.starScores),
  );

  factory BowlingConfig.fromJson(Map<String, Object?> j) {
    int i(String k) => j[k] as int;
    List<int> l(String k) => List.unmodifiable((j[k] as List).cast<int>());
    return BowlingConfig(
      level: i('level'),
      laneW: i('laneW'),
      headY: i('headY'),
      pinDx: i('pinDx'),
      pinDy: i('pinDy'),
      ballR: i('ballR'),
      ballM: i('ballM'),
      pinR: i('pinR'),
      pinM: i('pinM'),
      minSpeed: i('minSpeed'),
      maxSpeed: i('maxSpeed'),
      pinDec: i('pinDec'),
      ePin: i('ePin'),
      eWall: i('eWall'),
      deckY0: i('deckY0'),
      deckY1: i('deckY1'),
      knock: i('knock'),
      maxSteps: i('maxSteps'),
      scatter: l('scatter'),
      starScores: l('starScores'),
    );
  }

  final int level, laneW, headY, pinDx, pinDy, ballR, ballM, pinR, pinM, minSpeed, maxSpeed, pinDec;
  final int ePin, eWall, deckY0, deckY1, knock, maxSteps;
  final List<int> scatter, starScores;

  /// Spot of pin i (0–9 = pins 1–10).
  ({int x, int y}) pinSpot(int i) {
    final k = i < 1
        ? 0
        : i < 3
        ? 1
        : i < 6
        ? 2
        : 3;
    final j = i - k * (k + 1) ~/ 2;
    return (x: laneW ~/ 2 + (2 * j - k) * pinDx, y: headY + k * pinDy);
  }
}

List<bool> _all() => List.filled(10, true);

/// Standard ten-pin score of the rolls so far (missing future rolls count 0).
int bowlingTotal(List<int> rolls) {
  int r(int i) => i < rolls.length ? rolls[i] : 0;
  var sum = 0;
  var i = 0;
  for (var f = 0; f < 10 && i < rolls.length; f++) {
    if (r(i) == 10) {
      sum += 10 + r(i + 1) + r(i + 2);
      i += 1;
    } else if (r(i) + r(i + 1) == 10) {
      sum += 10 + r(i + 2);
      i += 2;
    } else {
      sum += r(i) + r(i + 1);
      i += 2;
    }
  }
  return sum;
}

class BowlingState {
  const BowlingState({
    required this.frame,
    required this.roll,
    required this.standing,
    required this.rolls,
    required this.score,
    required this.lastKnocked,
    required this.over,
    required this.rng,
  });

  final int frame, roll;
  final List<bool> standing;
  final List<int> rolls;
  final int score, lastKnocked;
  final bool over;
  final int rng;

  BowlingState copyWith({bool? over}) => BowlingState(
    frame: frame,
    roll: roll,
    standing: standing,
    rolls: rolls,
    score: score,
    lastKnocked: lastKnocked,
    over: over ?? this.over,
    rng: rng,
  );

  Map<String, Object?> toJson() => {
    'frame': frame,
    'roll': roll,
    'standing': standing,
    'rolls': rolls,
    'score': score,
    'lastKnocked': lastKnocked,
    'over': over,
    'rng': rng,
  };
}

/// {by: player, op: roll, x, aim, power} or {by: timeout}.
class BowlingAction {
  const BowlingAction.roll(this.x, this.aim, this.power) : by = 'player', op = 'roll';
  const BowlingAction.timeout() : by = 'timeout', op = '', x = 0, aim = 0, power = 0;
  const BowlingAction._(this.by, this.op, this.x, this.aim, this.power);

  final String by, op;
  final int x, aim, power;

  Map<String, Object?> toJson() =>
      by == 'timeout' ? {'by': by} : {'by': by, 'op': op, 'x': x, 'aim': aim, 'power': power};

  @override
  bool operator ==(Object other) =>
      other is BowlingAction &&
      other.by == by &&
      other.op == op &&
      other.x == x &&
      other.aim == aim &&
      other.power == power;

  @override
  int get hashCode => Object.hash(by, op, x, aim, power);

  @override
  String toString() => toJson().toString();
}

class BowlingResult {
  const BowlingResult({required this.winner, required this.stars, required this.score, required this.rolls});

  final String winner;
  final int stars, score;
  final List<int> rolls;

  Map<String, Object?> toJson() => {'winner': winner, 'stars': stars, 'score': score, 'rolls': rolls};
}

/// Ball velocity of a roll: normalized aim, scatter from [rng] (ex, then ey), then the speed.
({int vx, int vy}) rollVelocity(BowlingConfig c, int x, int aim, int power, Prng rng) {
  final n = normalizedAim(x, 0, aim, c.headY)!;
  final s = c.scatter[c.level - 1];
  final ex = rng.nextInt(2 * s + 1) - s;
  final ey = rng.nextInt(2 * s + 1) - s;
  final sp = c.minSpeed + trunc((c.maxSpeed - c.minSpeed) * power, 100);
  return shotVelocity(x, 0, n.x + ex, n.y + ey, sp)!;
}

/// Simulates one roll; returns which pins of [standing] fell. [onStep] (UI) sees the bodies
/// (ball, then pins 1–10) after each step.
List<bool> simulateRoll(
  BowlingConfig c,
  List<bool> standing,
  int x,
  ({int vx, int vy}) v, {
  void Function(List<Body> bodies)? onStep,
}) {
  final bodies = [Body(x: x, y: 0, vx: v.vx, vy: v.vy, r: c.ballR, m: c.ballM)];
  for (var i = 0; i < 10; i++) {
    final p = c.pinSpot(i);
    bodies.add(Body(x: p.x, y: p.y, r: c.pinR, m: c.pinM, on: standing[i]));
  }
  final world = World(
    bodies: bodies,
    statics: [
      RectStatic(-50000, c.deckY0, 0, c.deckY1 + 50000, c.eWall),
      RectStatic(c.laneW, c.deckY0, c.laneW + 50000, c.deckY1 + 50000, c.eWall),
    ],
    eBody: c.ePin,
    dec: (i, _) => i == 0 ? 0 : c.pinDec,
    capture: (w) {
      for (var i = 0; i < w.bodies.length; i++) {
        final b = w.bodies[i];
        if (!b.on) continue;
        if (b.y > c.deckY1) {
          off(b);
        } else if (i == 0 && b.y < c.deckY0 && (b.x < 0 || b.x > c.laneW)) {
          off(b);
        }
      }
      return false;
    },
  );
  simulate(world, c.maxSteps, onStep: onStep == null ? null : (w) => onStep(w.bodies));
  final k2 = c.knock * c.knock;
  return [
    for (var i = 0; i < 10; i++)
      standing[i] &&
          (() {
            final b = bodies[i + 1], p = c.pinSpot(i);
            return !b.on || (b.x - p.x) * (b.x - p.x) + (b.y - p.y) * (b.y - p.y) > k2;
          })(),
  ];
}

class BowlingRules extends MgRules<BowlingState, BowlingAction, BowlingResult> {
  BowlingConfig? _cfg;

  BowlingConfig get config => _cfg ?? (throw StateError('bowling: init first'));

  @override
  String get id => 'bowling';

  @override
  int get specVersion => 1;

  @override
  BowlingState init(Map<String, Object?> config, int seed) => start(BowlingConfig.fromJson(config), seed);

  BowlingState start(BowlingConfig config, int seed) {
    _cfg = config;
    return BowlingState(
      frame: 1,
      roll: 1,
      standing: List.unmodifiable(_all()),
      rolls: const [],
      score: 0,
      lastKnocked: 0,
      over: false,
      rng: Prng(seed).state,
    );
  }

  @override
  List<BowlingAction> legalActions(BowlingState s) => const [];

  /// True when [a] is a legal roll in [s].
  bool legal(BowlingState s, BowlingAction a) {
    final c = config;
    if (s.over || a.by != 'player' || a.op != 'roll') return false;
    return a.x >= c.ballR && a.x <= c.laneW - c.ballR && a.power >= 1 && a.power <= 100;
  }

  /// The ball velocity of [a] and the rng after its scatter.
  ({int vx, int vy, int rng}) velocity(BowlingState s, BowlingAction a) {
    final r = withRng(s.rng, (p) => rollVelocity(config, a.x, a.aim, a.power, p));
    return (vx: r.value.vx, vy: r.value.vy, rng: r.rng);
  }

  @override
  BowlingState apply(BowlingState s, BowlingAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(over: true);
    if (!legal(s, a)) throw IllegalAction(id, a);
    final v = velocity(s, a);
    final fell = simulateRoll(config, s.standing, a.x, (vx: v.vx, vy: v.vy));
    final k = fell.where((f) => f).length;
    var standing = [for (var i = 0; i < 10; i++) s.standing[i] && !fell[i]];
    final rolls = [...s.rolls, k];
    var frame = s.frame, roll = s.roll;
    var over = false;
    if (frame < 10) {
      if ((roll == 1 && k == 10) || roll == 2) {
        frame += 1;
        roll = 1;
        standing = _all();
      } else {
        roll = 2;
      }
    } else {
      if (standing.every((st) => !st)) standing = _all();
      final f = rolls.sublist(rolls.length - roll);
      if (roll == 1) {
        roll = 2;
      } else if (roll == 2 && (f[0] == 10 || f[0] + f[1] == 10)) {
        roll = 3;
      } else {
        over = true;
      }
    }
    return BowlingState(
      frame: frame,
      roll: roll,
      standing: List.unmodifiable(standing),
      rolls: List.unmodifiable(rolls),
      score: bowlingTotal(rolls),
      lastKnocked: k,
      over: over,
      rng: v.rng,
    );
  }

  @override
  BowlingAction aiAction(BowlingState s, int level, Prng ai) {
    final mid = config.laneW ~/ 2;
    return BowlingAction.roll(mid, mid, 80);
  }

  @override
  BowlingResult? result(BowlingState s) {
    if (!s.over) return null;
    final ss = config.starScores;
    final stars = s.score >= ss[0]
        ? 3
        : s.score >= ss[1]
        ? 2
        : s.score >= ss[2]
        ? 1
        : 0;
    return BowlingResult(winner: stars >= 1 ? 'player' : 'ai', stars: stars, score: s.score, rolls: s.rolls);
  }

  @override
  BowlingAction actionFromJson(Map<String, Object?> j) => j['by'] == 'timeout'
      ? const BowlingAction.timeout()
      : BowlingAction._(j['by'] as String, j['op'] as String, j['x'] as int, j['aim'] as int, j['power'] as int);

  @override
  Map<String, Object?> stateToJson(BowlingState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(BowlingResult r) => r.toJson();
}
