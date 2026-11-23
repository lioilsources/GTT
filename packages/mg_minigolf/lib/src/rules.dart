import 'package:mg_physics/mg_physics.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/minigolf.md, version 1 (physics: specs/minigames/fyzika.md v1). Pure Dart.
class MinigolfConfig {
  const MinigolfConfig({
    required this.level,
    required this.holes,
    required this.ballR,
    required this.cupR,
    required this.cupSpeed,
    required this.maxSpeed,
    required this.dec,
    required this.sandDec,
    required this.eWall,
    required this.eBumper,
    required this.maxSteps,
    required this.maxStrokes,
    required this.scatter,
    required this.starOver,
  });

  factory MinigolfConfig.fromTuning(TuningMinigamesMinigolf t, int level) => MinigolfConfig(
    level: level,
    holes: List.unmodifiable([
      for (final h in [t.h1, t.h2, t.h3, t.h4, t.h5, t.h6]) List<int>.unmodifiable(h),
    ]),
    ballR: t.ballR,
    cupR: t.cupR,
    cupSpeed: t.cupSpeed,
    maxSpeed: t.maxSpeed,
    dec: t.dec,
    sandDec: t.sandDec,
    eWall: t.eWall,
    eBumper: t.eBumper,
    maxSteps: t.maxSteps,
    maxStrokes: t.maxStrokes,
    scatter: List.unmodifiable(t.scatter),
    starOver: List.unmodifiable(t.starOver),
  );

  factory MinigolfConfig.fromJson(Map<String, Object?> j) {
    int i(String k) => j[k] as int;
    List<int> l(String k) => List.unmodifiable((j[k] as List).cast<int>());
    return MinigolfConfig(
      level: i('level'),
      holes: List.unmodifiable([for (final h in j['holes'] as List) List<int>.unmodifiable((h as List).cast<int>())]),
      ballR: i('ballR'),
      cupR: i('cupR'),
      cupSpeed: i('cupSpeed'),
      maxSpeed: i('maxSpeed'),
      dec: i('dec'),
      sandDec: i('sandDec'),
      eWall: i('eWall'),
      eBumper: i('eBumper'),
      maxSteps: i('maxSteps'),
      maxStrokes: i('maxStrokes'),
      scatter: l('scatter'),
      starOver: l('starOver'),
    );
  }

  final int level;

  /// Six holes in the flat mm format of the spec.
  final List<List<int>> holes;
  final int ballR, cupR, cupSpeed, maxSpeed, dec, sandDec, eWall, eBumper, maxSteps, maxStrokes;
  final List<int> scatter, starOver;
}

class Box {
  const Box(this.x0, this.y0, this.x1, this.y1);

  final int x0, y0, x1, y1;

  bool contains(int x, int y) => x0 <= x && x <= x1 && y0 <= y && y <= y1;
}

/// A hole in u (mm × 100).
class Hole {
  const Hole({
    required this.w,
    required this.h,
    required this.par,
    required this.sx,
    required this.sy,
    required this.cx,
    required this.cy,
    required this.walls,
    required this.bumpers,
    required this.sand,
    required this.water,
  });

  /// Parses the flat mm list; a malformed list throws (a load error, the spec says).
  factory Hole.parse(List<int> a) {
    const u = 100;
    var i = 0;
    int next() {
      if (i >= a.length) throw FormatException('minigolf: malformed hole $a');
      return a[i++];
    }

    List<Box> boxes() => List.generate(next(), (_) => Box(next() * u, next() * u, next() * u, next() * u));
    final w = next() * u, h = next() * u, par = next();
    final sx = next() * u, sy = next() * u, cx = next() * u, cy = next() * u;
    final walls = boxes();
    final bumpers = List.generate(next(), (_) => (x: next() * u, y: next() * u, r: next() * u));
    final sand = boxes();
    final water = boxes();
    if (i != a.length) throw FormatException('minigolf: malformed hole $a');
    return Hole(
      w: w,
      h: h,
      par: par,
      sx: sx,
      sy: sy,
      cx: cx,
      cy: cy,
      walls: walls,
      bumpers: bumpers,
      sand: sand,
      water: water,
    );
  }

  final int w, h, par, sx, sy, cx, cy;
  final List<Box> walls, sand, water;
  final List<({int x, int y, int r})> bumpers;
}

/// Statics in the spec's order: borders (200 mm thick), walls (eWall), bumpers (eBumper).
List<Static> holeStatics(MinigolfConfig c, Hole h) {
  const t = 200 * 100;
  final e = c.eWall;
  return [
    RectStatic(-t, -t, 0, h.h + t, e),
    RectStatic(h.w, -t, h.w + t, h.h + t, e),
    RectStatic(0, -t, h.w, 0, e),
    RectStatic(0, h.h, h.w, h.h + t, e),
    for (final b in h.walls) RectStatic(b.x0, b.y0, b.x1, b.y1, e),
    for (final b in h.bumpers) CircleStatic(b.x, b.y, b.r, c.eBumper),
  ];
}

enum PuttEnd { rest, water, cup }

/// Simulates a putt from (x, y) with velocity [v]; [onStep] (UI) sees the ball after every step.
({PuttEnd end, int x, int y}) simulatePutt(
  MinigolfConfig c,
  Hole h,
  int x,
  int y,
  ({int vx, int vy}) v, {
  void Function(Body ball)? onStep,
}) {
  final ball = Body(x: x, y: y, vx: v.vx, vy: v.vy, r: c.ballR);
  var end = PuttEnd.rest;
  final cup2 = c.cupR * c.cupR;
  final world = World(
    bodies: [ball],
    statics: holeStatics(c, h),
    eBody: 1000,
    dec: (_, b) => h.sand.any((s) => s.contains(b.x, b.y)) ? c.sandDec : c.dec,
    capture: (_) {
      if (h.water.any((b) => b.contains(ball.x, ball.y))) {
        end = PuttEnd.water;
        return true;
      }
      final dx = ball.x - h.cx, dy = ball.y - h.cy;
      if (dx * dx + dy * dy <= cup2 && ball.vx * ball.vx + ball.vy * ball.vy <= c.cupSpeed * c.cupSpeed) {
        end = PuttEnd.cup;
        return true;
      }
      return false;
    },
  );
  simulate(world, c.maxSteps, onStep: onStep == null ? null : (_) => onStep(ball));
  final dx = ball.x - h.cx, dy = ball.y - h.cy;
  if (end == PuttEnd.rest && dx * dx + dy * dy <= cup2) end = PuttEnd.cup;
  return (end: end, x: ball.x, y: ball.y);
}

class MinigolfState {
  const MinigolfState({
    required this.hole,
    required this.strokes,
    required this.scores,
    required this.x,
    required this.y,
    required this.over,
    required this.rng,
  });

  final int hole, strokes;
  final List<int> scores;
  final int x, y;
  final bool over;
  final int rng;

  MinigolfState copyWith({int? hole, int? strokes, List<int>? scores, int? x, int? y, bool? over, int? rng}) =>
      MinigolfState(
        hole: hole ?? this.hole,
        strokes: strokes ?? this.strokes,
        scores: scores ?? this.scores,
        x: x ?? this.x,
        y: y ?? this.y,
        over: over ?? this.over,
        rng: rng ?? this.rng,
      );

  Map<String, Object?> toJson() => {
    'hole': hole,
    'strokes': strokes,
    'scores': scores,
    'x': x,
    'y': y,
    'over': over,
    'rng': rng,
  };
}

/// {by: player, op: putt, x, y, power} or {by: timeout}.
class MinigolfAction {
  const MinigolfAction.putt(this.x, this.y, this.power) : by = 'player', op = 'putt';
  const MinigolfAction.timeout() : by = 'timeout', op = '', x = 0, y = 0, power = 0;
  const MinigolfAction._(this.by, this.op, this.x, this.y, this.power);

  final String by, op;
  final int x, y, power;

  Map<String, Object?> toJson() => by == 'timeout' ? {'by': by} : {'by': by, 'op': op, 'x': x, 'y': y, 'power': power};

  @override
  bool operator ==(Object other) =>
      other is MinigolfAction &&
      other.by == by &&
      other.op == op &&
      other.x == x &&
      other.y == y &&
      other.power == power;

  @override
  int get hashCode => Object.hash(by, op, x, y, power);

  @override
  String toString() => toJson().toString();
}

class MinigolfResult {
  const MinigolfResult({
    required this.winner,
    required this.stars,
    required this.score,
    required this.scores,
    required this.par,
  });

  final String winner;
  final int stars, score;
  final List<int> scores;
  final int par;

  Map<String, Object?> toJson() => {'winner': winner, 'stars': stars, 'score': score, 'scores': scores, 'par': par};
}

class MinigolfRules extends MgRules<MinigolfState, MinigolfAction, MinigolfResult> {
  MinigolfConfig? _cfg;
  List<Hole> _holes = const [];

  MinigolfConfig get config => _cfg ?? (throw StateError('minigolf: init first'));

  @override
  String get id => 'minigolf';

  @override
  int get specVersion => 1;

  @override
  MinigolfState init(Map<String, Object?> config, int seed) => start(MinigolfConfig.fromJson(config), seed);

  MinigolfState start(MinigolfConfig config, int seed) {
    _cfg = config;
    _holes = List.unmodifiable(config.holes.map(Hole.parse));
    final h = _holes[0];
    return MinigolfState(hole: 1, strokes: 0, scores: const [], x: h.sx, y: h.sy, over: false, rng: Prng(seed).state);
  }

  /// Hole n (1–6) in u.
  Hole holeAt(int n) => _holes[n - 1];

  @override
  List<MinigolfAction> legalActions(MinigolfState s) => const [];

  bool legal(MinigolfState s, MinigolfAction a) {
    if (s.over || a.by != 'player' || a.op != 'putt') return false;
    return a.power >= 1 && a.power <= 100 && !(a.x == s.x && a.y == s.y);
  }

  /// The ball velocity of a putt and the rng after its scatter.
  ({int vx, int vy, int rng}) velocity(MinigolfState s, MinigolfAction a) {
    final c = config;
    final r = withRng(s.rng, (p) {
      final n = normalizedAim(s.x, s.y, a.x, a.y)!;
      final sc = c.scatter[c.level - 1];
      final ex = p.nextInt(2 * sc + 1) - sc;
      final ey = p.nextInt(2 * sc + 1) - sc;
      return shotVelocity(s.x, s.y, n.x + ex, n.y + ey, trunc(a.power * c.maxSpeed, 100))!;
    });
    return (vx: r.value.vx, vy: r.value.vy, rng: r.rng);
  }

  @override
  MinigolfState apply(MinigolfState s, MinigolfAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(over: true);
    if (!legal(s, a)) throw IllegalAction(id, a);
    final v = velocity(s, a);
    final out = simulatePutt(config, holeAt(s.hole), s.x, s.y, (vx: v.vx, vy: v.vy));
    return settle(s.copyWith(strokes: s.strokes + 1, rng: v.rng), s, out);
  }

  /// Rules after the simulation: splash, holed, stroke cap, next hole.
  MinigolfState settle(MinigolfState n, MinigolfState before, ({PuttEnd end, int x, int y}) out) {
    var s = n.copyWith(x: out.x, y: out.y);
    if (out.end == PuttEnd.water) s = s.copyWith(strokes: s.strokes + 1, x: before.x, y: before.y);
    if (out.end == PuttEnd.cup) return _nextHole(s, s.strokes);
    if (s.strokes >= config.maxStrokes) return _nextHole(s, config.maxStrokes + 1);
    return s;
  }

  MinigolfState _nextHole(MinigolfState s, int score) {
    final scores = List<int>.unmodifiable([...s.scores, score]);
    if (s.hole >= 6) return s.copyWith(scores: scores, hole: 7, strokes: 0, over: true);
    final h = holeAt(s.hole + 1);
    return s.copyWith(scores: scores, hole: s.hole + 1, strokes: 0, x: h.sx, y: h.sy);
  }

  @override
  MinigolfAction aiAction(MinigolfState s, int level, Prng ai) {
    final h = holeAt(s.hole < 6 ? s.hole : 6);
    return MinigolfAction.putt(h.cx, h.cy, 50);
  }

  @override
  MinigolfResult? result(MinigolfState s) {
    if (!s.over) return null;
    final score = s.scores.fold(0, (a, b) => a + b);
    var par = 0;
    for (var i = 0; i < s.scores.length; i++) {
      par += holeAt(i + 1).par;
    }
    final so = config.starOver;
    final over = score - par;
    final stars = s.scores.length < 6
        ? 0
        : over <= so[0]
        ? 3
        : over <= so[1]
        ? 2
        : over <= so[2]
        ? 1
        : 0;
    return MinigolfResult(winner: stars >= 1 ? 'player' : 'ai', stars: stars, score: score, scores: s.scores, par: par);
  }

  @override
  MinigolfAction actionFromJson(Map<String, Object?> j) => j['by'] == 'timeout'
      ? const MinigolfAction.timeout()
      : MinigolfAction._(j['by'] as String, j['op'] as String, j['x'] as int, j['y'] as int, j['power'] as int);

  @override
  Map<String, Object?> stateToJson(MinigolfState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(MinigolfResult r) => r.toJson();
}
