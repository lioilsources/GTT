import 'package:mg_physics/mg_physics.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/hokej.md, version 2 (arithmetic and friction: specs/minigames/fyzika.md v1).
/// No rng. Pure Dart: no Flutter imports here.
class HokejConfig {
  const HokejConfig({
    required this.level,
    required this.w,
    required this.h,
    required this.puckR,
    required this.malletR,
    required this.goalHalf,
    required this.eWall,
    required this.eMallet,
    required this.dec,
    required this.maxPuck,
    required this.malletSpeed,
    required this.aiSpeed,
    required this.aiReact,
    required this.aiDefY,
    required this.homeY,
    required this.serveY,
    required this.goals,
    required this.goalPause,
    required this.starMargins,
  });

  factory HokejConfig.fromTuning(TuningMinigamesHokej t, int level) => HokejConfig(
    level: level,
    w: t.w,
    h: t.h,
    puckR: t.puckR,
    malletR: t.malletR,
    goalHalf: t.goalHalf,
    eWall: t.eWall,
    eMallet: t.eMallet,
    dec: t.dec,
    maxPuck: t.maxPuck,
    malletSpeed: t.malletSpeed,
    aiSpeed: List.unmodifiable(t.aiSpeed),
    aiReact: List.unmodifiable(t.aiReact),
    aiDefY: t.aiDefY,
    homeY: t.homeY,
    serveY: t.serveY,
    goals: t.goals,
    goalPause: t.goalPause,
    starMargins: List.unmodifiable(t.starMargins),
  );

  factory HokejConfig.fromJson(Map<String, Object?> j) {
    int i(String k) => j[k] as int;
    List<int> l(String k) => List.unmodifiable((j[k] as List).cast<int>());
    return HokejConfig(
      level: i('level'),
      w: i('w'),
      h: i('h'),
      puckR: i('puckR'),
      malletR: i('malletR'),
      goalHalf: i('goalHalf'),
      eWall: i('eWall'),
      eMallet: i('eMallet'),
      dec: i('dec'),
      maxPuck: i('maxPuck'),
      malletSpeed: i('malletSpeed'),
      aiSpeed: l('aiSpeed'),
      aiReact: l('aiReact'),
      aiDefY: i('aiDefY'),
      homeY: i('homeY'),
      serveY: i('serveY'),
      goals: i('goals'),
      goalPause: i('goalPause'),
      starMargins: l('starMargins'),
    );
  }

  final int level, w, h, puckR, malletR, goalHalf, eWall, eMallet, dec, maxPuck, malletSpeed;
  final List<int> aiSpeed, aiReact, starMargins;
  final int aiDefY, homeY, serveY, goals, goalPause;

  /// A target clipped into a half: the player's (bottom) or the AI's ([top]).
  ({int x, int y}) clipHalf(int x, int y, {required bool top}) {
    final rm = malletR, mid = h ~/ 2;
    return (x: clampInt(x, rm, w - rm), y: top ? clampInt(y, mid + rm, h - rm) : clampInt(y, rm, mid - rm));
  }
}

class Puck {
  const Puck(this.x, this.y, this.vx, this.vy);

  final int x, y, vx, vy;

  Map<String, Object?> toJson() => {'x': x, 'y': y, 'vx': vx, 'vy': vy};
}

/// A mallet and its target.
class Mallet {
  const Mallet(this.x, this.y, this.tx, this.ty);

  final int x, y, tx, ty;

  Map<String, Object?> toJson() => {'x': x, 'y': y, 'tx': tx, 'ty': ty};
}

class HokejState {
  const HokejState({
    required this.tick,
    required this.puck,
    required this.me,
    required this.ai,
    required this.playerGoals,
    required this.aiGoals,
    required this.pause,
    required this.aiClock,
    required this.over,
  });

  final int tick;
  final Puck puck;
  final Mallet me, ai;
  final int playerGoals, aiGoals, pause, aiClock;
  final bool over;

  HokejState copyWith({Mallet? me, bool? over}) => HokejState(
    tick: tick,
    puck: puck,
    me: me ?? this.me,
    ai: ai,
    playerGoals: playerGoals,
    aiGoals: aiGoals,
    pause: pause,
    aiClock: aiClock,
    over: over ?? this.over,
  );

  Map<String, Object?> toJson() => {
    'tick': tick,
    'puck': puck.toJson(),
    'me': me.toJson(),
    'ai': ai.toJson(),
    'playerGoals': playerGoals,
    'aiGoals': aiGoals,
    'pause': pause,
    'aiClock': aiClock,
    'over': over,
  };
}

/// {by: player, op: move, x, y}, {by: player, op: tick, n} or {by: timeout}.
class HokejAction {
  const HokejAction.move(this.x, this.y) : by = 'player', op = 'move', n = 0;
  const HokejAction.tick(this.n) : by = 'player', op = 'tick', x = 0, y = 0;
  const HokejAction.timeout() : by = 'timeout', op = '', x = 0, y = 0, n = 0;
  const HokejAction._(this.by, this.op, this.x, this.y, this.n);

  final String by, op;
  final int x, y, n;

  Map<String, Object?> toJson() => by == 'timeout'
      ? {'by': by}
      : op == 'move'
      ? {'by': by, 'op': op, 'x': x, 'y': y}
      : {'by': by, 'op': op, 'n': n};

  @override
  bool operator ==(Object other) =>
      other is HokejAction && other.by == by && other.op == op && other.x == x && other.y == y && other.n == n;

  @override
  int get hashCode => Object.hash(by, op, x, y, n);

  @override
  String toString() => toJson().toString();
}

class HokejResult {
  const HokejResult({
    required this.winner,
    required this.stars,
    required this.score,
    required this.playerGoals,
    required this.aiGoals,
  });

  final String winner;
  final int stars, score, playerGoals, aiGoals;

  Map<String, Object?> toJson() => {
    'winner': winner,
    'stars': stars,
    'score': score,
    'playerGoals': playerGoals,
    'aiGoals': aiGoals,
  };
}

/// Mutable mallet of one apply.
class _M {
  _M(Mallet m) : x = m.x, y = m.y, tx = m.tx, ty = m.ty;

  int x, y, tx, ty;

  Mallet freeze() => Mallet(x, y, tx, ty);

  /// Moves towards the target at most [speed]; returns the displacement.
  ({int dx, int dy}) drive(int speed) {
    final dx = tx - x, dy = ty - y;
    final l = isqrt(dx * dx + dy * dy);
    final ox = x, oy = y;
    if (l <= speed) {
      x = tx;
      y = ty;
    } else {
      x += trunc(dx * speed, l);
      y += trunc(dy * speed, l);
    }
    return (dx: x - ox, dy: y - oy);
  }
}

/// Mutable working copy of one apply.
class _Run {
  _Run(HokejState s)
    : tick = s.tick,
      puck = Body(x: s.puck.x, y: s.puck.y, vx: s.puck.vx, vy: s.puck.vy, r: 0),
      me = _M(s.me),
      ai = _M(s.ai),
      playerGoals = s.playerGoals,
      aiGoals = s.aiGoals,
      pause = s.pause,
      aiClock = s.aiClock,
      over = s.over;

  int tick;
  Body puck;
  _M me, ai;
  int playerGoals, aiGoals, pause, aiClock;
  bool over;

  HokejState freeze() => HokejState(
    tick: tick,
    puck: Puck(puck.x, puck.y, puck.vx, puck.vy),
    me: me.freeze(),
    ai: ai.freeze(),
    playerGoals: playerGoals,
    aiGoals: aiGoals,
    pause: pause,
    aiClock: aiClock,
    over: over,
  );
}

/// The automaton's new target from the puck and its mallet (spec "Soupeř").
({int x, int y}) hokejAiTarget(HokejConfig c, ({int x, int y}) p, ({int x, int y}) a) {
  final mid = c.w ~/ 2;
  final g = c.puckR + c.malletR + 100;
  final ({int x, int y}) t;
  if (p.y >= c.h ~/ 2) {
    t = a.y > p.y + c.puckR
        ? (x: p.x, y: p.y)
        : a.x <= p.x
        ? (x: p.x - g, y: p.y + g)
        : (x: p.x + g, y: p.y + g);
  } else {
    t = (x: clampInt(p.x, mid - c.goalHalf, mid + c.goalHalf), y: c.h - c.aiDefY);
  }
  return c.clipHalf(t.x, t.y, top: true);
}

class HokejRules extends MgRules<HokejState, HokejAction, HokejResult> {
  HokejConfig? _cfg;

  HokejConfig get config => _cfg ?? (throw StateError('hokej: init first'));

  @override
  String get id => 'hokej';

  @override
  int get specVersion => 2;

  @override
  HokejState init(Map<String, Object?> config, int seed) => start(HokejConfig.fromJson(config));

  HokejState start(HokejConfig config) {
    _cfg = config;
    final f = _faceoff(-1);
    return HokejState(
      tick: 0,
      puck: f.puck,
      me: f.me,
      ai: f.ai,
      playerGoals: 0,
      aiGoals: 0,
      pause: 0,
      aiClock: 0,
      over: false,
    );
  }

  /// Puck at rest `serveY` below (side −1) or above (+1) the centre, mallets and targets home.
  ({Puck puck, Mallet me, Mallet ai}) _faceoff(int side) {
    final c = config;
    final x = c.w ~/ 2;
    return (
      puck: Puck(x, c.h ~/ 2 + side * c.serveY, 0, 0),
      me: Mallet(x, c.homeY, x, c.homeY),
      ai: Mallet(x, c.h - c.homeY, x, c.h - c.homeY),
    );
  }

  @override
  List<HokejAction> legalActions(HokejState s) => const [];

  @override
  HokejState apply(HokejState s0, HokejAction a) {
    if (s0.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s0.copyWith(over: true);
    if (a.by != 'player') throw IllegalAction(id, a);
    if (a.op == 'move') {
      final t = config.clipHalf(a.x, a.y, top: false);
      return s0.copyWith(me: Mallet(s0.me.x, s0.me.y, t.x, t.y));
    }
    if (a.op != 'tick' || a.n < 1) throw IllegalAction(id, a);
    final s = _Run(s0);
    for (var k = 0; k < a.n && !s.over; k++) {
      _tick(s);
    }
    return s.freeze();
  }

  void _tick(_Run s) {
    final c = config;
    s.tick += 1;
    if (s.pause > 0) {
      s.pause -= 1;
      return;
    }
    final mv = s.me.drive(c.malletSpeed);
    s.aiClock += 1;
    if (s.aiClock >= c.aiReact[c.level - 1]) {
      s.aiClock = 0;
      final t = hokejAiTarget(c, (x: s.puck.x, y: s.puck.y), (x: s.ai.x, y: s.ai.y));
      s.ai
        ..tx = t.x
        ..ty = t.y;
    }
    final ma = s.ai.drive(c.aiSpeed[c.level - 1]);
    final p = s.puck;
    final x0 = p.x, y0 = p.y;
    p.x += p.vx;
    p.y += p.vy;
    final r = c.puckR, e = c.eWall, mid = c.w ~/ 2;
    // Step 5 (v2): goal only when the centre crosses the goal line inside the mouth.
    if (p.y < 0 || p.y > c.h) {
      final top = p.y > c.h;
      var xc = x0;
      if (!top && y0 > 0) xc = x0 + trunc(p.vx * y0, y0 - p.y);
      if (top && y0 < c.h) xc = x0 + trunc(p.vx * (c.h - y0), p.y - y0);
      if ((xc - mid).abs() <= c.goalHalf) {
        if (top) {
          s.playerGoals += 1;
        } else {
          s.aiGoals += 1;
        }
        final f = _faceoff(top ? 1 : -1);
        s
          ..puck = Body(x: f.puck.x, y: f.puck.y, r: 0)
          ..me = _M(f.me)
          ..ai = _M(f.ai)
          ..pause = c.goalPause
          ..aiClock = 0;
        if (s.playerGoals >= c.goals || s.aiGoals >= c.goals) s.over = true;
        return;
      }
      // Crossed outside the mouth: bounce off the end wall, position mirrored over the line.
      p.y = top ? 2 * c.h - p.y : 0 - p.y;
      p.vy = 0 - trunc(p.vy * e, 1000);
    }
    if ((p.x - r < 0 && p.vx < 0) || (p.x + r > c.w && p.vx > 0)) p.vx = 0 - trunc(p.vx * e, 1000);
    if (((p.y - r < 0 && p.vy < 0) || (p.y + r > c.h && p.vy > 0)) && (p.x - mid).abs() > c.goalHalf) {
      p.vy = 0 - trunc(p.vy * e, 1000);
    }
    _mallet(p, s.me, mv);
    _mallet(p, s.ai, ma);
    final sp = isqrt(p.vx * p.vx + p.vy * p.vy);
    if (sp > c.maxPuck) {
      p.vx = trunc(p.vx * c.maxPuck, sp);
      p.vy = trunc(p.vy * c.maxPuck, sp);
    }
    friction(p, c.dec);
  }

  /// Step 7 for one mallet: bounce off it (relative velocity), then push the puck out to touching.
  void _mallet(Body p, _M m, ({int dx, int dy}) mv) {
    final c = config;
    final rr = c.puckR + c.malletR;
    final dx = p.x - m.x, dy = p.y - m.y;
    final d2 = dx * dx + dy * dy;
    if (d2 <= 0 || d2 >= rr * rr) return;
    final vn = (p.vx - mv.dx) * dx + (p.vy - mv.dy) * dy;
    if (vn < 0) {
      final k = trunc(vn * (1000 + c.eMallet) * 1000, d2);
      p.vx -= trunc(k * dx, 1000000);
      p.vy -= trunc(k * dy, 1000000);
    }
    final l = isqrt(d2);
    final r = c.puckR;
    p.x = clampInt(m.x + trunc(dx * rr, l), r, c.w - r);
    p.y = m.y + trunc(dy * rr, l);
    if ((p.x - c.w ~/ 2).abs() > c.goalHalf) p.y = clampInt(p.y, r, c.h - r);
  }

  @override
  HokejAction aiAction(HokejState s, int level, Prng ai) => const HokejAction.tick(1);

  @override
  HokejResult? result(HokejState s) {
    if (!s.over) return null;
    final d = s.playerGoals - s.aiGoals;
    final winner = d > 0
        ? 'player'
        : d < 0
        ? 'ai'
        : 'draw';
    final sm = config.starMargins;
    final stars = d <= 0
        ? 0
        : d >= sm[0]
        ? 3
        : d >= sm[1]
        ? 2
        : 1;
    return HokejResult(
      winner: winner,
      stars: stars,
      score: s.playerGoals,
      playerGoals: s.playerGoals,
      aiGoals: s.aiGoals,
    );
  }

  @override
  HokejAction actionFromJson(Map<String, Object?> j) {
    if (j['by'] == 'timeout') return const HokejAction.timeout();
    return HokejAction._(
      j['by'] as String,
      j['op'] as String,
      (j['x'] as int?) ?? 0,
      (j['y'] as int?) ?? 0,
      (j['n'] as int?) ?? 0,
    );
  }

  @override
  Map<String, Object?> stateToJson(HokejState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(HokejResult r) => r.toJson();
}
