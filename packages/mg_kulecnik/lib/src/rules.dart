import 'package:mg_physics/mg_physics.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/kulecnik.md, version 1 (physics: specs/minigames/fyzika.md v1). Pure Dart.
class KulecnikConfig {
  const KulecnikConfig({
    required this.tableW,
    required this.tableH,
    required this.ballR,
    required this.pockets,
    required this.rackDx,
    required this.rackDy,
    required this.rack,
    required this.maxSpeed,
    required this.dec,
    required this.eBall,
    required this.eCushion,
    required this.maxSteps,
    required this.aiCandidates,
    required this.aiScatter,
    required this.aiPowerBase,
    required this.aiPowerPerM,
    required this.starLeft,
  });

  factory KulecnikConfig.fromTuning(TuningMinigamesKulecnik t) => KulecnikConfig(
    tableW: t.tableW,
    tableH: t.tableH,
    ballR: t.ballR,
    pockets: List.unmodifiable(t.pockets),
    rackDx: t.rackDx,
    rackDy: t.rackDy,
    rack: List.unmodifiable(t.rack),
    maxSpeed: t.maxSpeed,
    dec: t.dec,
    eBall: t.eBall,
    eCushion: t.eCushion,
    maxSteps: t.maxSteps,
    aiCandidates: List.unmodifiable(t.aiCandidates),
    aiScatter: List.unmodifiable(t.aiScatter),
    aiPowerBase: t.aiPowerBase,
    aiPowerPerM: t.aiPowerPerM,
    starLeft: List.unmodifiable(t.starLeft),
  );

  factory KulecnikConfig.fromJson(Map<String, Object?> j) {
    List<int> l(String k) => List.unmodifiable((j[k] as List).cast<int>());
    return KulecnikConfig(
      tableW: j['tableW'] as int,
      tableH: j['tableH'] as int,
      ballR: j['ballR'] as int,
      pockets: l('pockets'),
      rackDx: j['rackDx'] as int,
      rackDy: j['rackDy'] as int,
      rack: l('rack'),
      maxSpeed: j['maxSpeed'] as int,
      dec: j['dec'] as int,
      eBall: j['eBall'] as int,
      eCushion: j['eCushion'] as int,
      maxSteps: j['maxSteps'] as int,
      aiCandidates: l('aiCandidates'),
      aiScatter: l('aiScatter'),
      aiPowerBase: j['aiPowerBase'] as int,
      aiPowerPerM: j['aiPowerPerM'] as int,
      starLeft: l('starLeft'),
    );
  }

  final int tableW, tableH, ballR, rackDx, rackDy, maxSpeed, dec, eBall, eCushion, maxSteps;
  final List<int> pockets, rack, aiCandidates, aiScatter, starLeft;
  final int aiPowerBase, aiPowerPerM;

  ({int x, int y}) get headSpot => (x: tableW ~/ 2, y: tableH ~/ 4);
  ({int x, int y}) get footSpot => (x: tableW ~/ 2, y: 3 * tableH ~/ 4);

  /// Pocket p (0–5): centre and capture radius.
  ({int x, int y, int r}) pocket(int p) => (x: pockets[3 * p], y: pockets[3 * p + 1], r: pockets[3 * p + 2]);
}

class Ball {
  const Ball(this.x, this.y, this.on);

  final int x, y;
  final bool on;

  Map<String, Object?> toJson() => {'x': x, 'y': y, 'on': on};
}

class LastShot {
  const LastShot({required this.by, required this.firstHit, required this.pots, required this.foul});

  static const none = LastShot(by: '', firstHit: -1, pots: [], foul: false);

  /// '', 'player' or 'ai'.
  final String by;
  final int firstHit;
  final List<int> pots;
  final bool foul;

  Map<String, Object?> toJson() => {'by': by, 'firstHit': firstHit, 'pots': pots, 'foul': foul};
}

/// '' (open table), 'solid' or 'stripe'.
String groupOf(int n) => n >= 1 && n <= 7
    ? 'solid'
    : n >= 9 && n <= 15
    ? 'stripe'
    : '';

String _other(String g) => g == 'solid'
    ? 'stripe'
    : g == 'stripe'
    ? 'solid'
    : '';

String _opp(String side) => side == 'player' ? 'ai' : 'player';

class KulecnikState {
  const KulecnikState({
    required this.balls,
    required this.turn,
    required this.playerGroup,
    required this.shots,
    required this.last,
    required this.winner,
    required this.over,
  });

  /// 16 balls, index = number (0 cue, 8 black).
  final List<Ball> balls;
  final String turn;
  final String playerGroup;
  final int shots;
  final LastShot last;

  /// '' until the end, then 'player', 'ai' or 'draw'.
  final String winner;
  final bool over;

  String groupOfSide(String side) => side == 'player' ? playerGroup : _other(playerGroup);

  /// Balls of group [g] still on the table.
  int leftOf(String g) {
    if (g == '') return 0;
    var n = 0;
    for (var i = 0; i < balls.length; i++) {
      if (balls[i].on && groupOf(i) == g) n++;
    }
    return n;
  }

  KulecnikState copyWith({String? winner, bool? over}) => KulecnikState(
    balls: balls,
    turn: turn,
    playerGroup: playerGroup,
    shots: shots,
    last: last,
    winner: winner ?? this.winner,
    over: over ?? this.over,
  );

  Map<String, Object?> toJson() => {
    'balls': [for (final b in balls) b.toJson()],
    'turn': turn,
    'playerGroup': playerGroup,
    'shots': shots,
    'last': last.toJson(),
    'winner': winner,
    'over': over,
  };
}

/// {by, op: shot, x, y, power} or {by: timeout}.
class KulecnikAction {
  const KulecnikAction.shot(this.by, this.x, this.y, this.power) : op = 'shot';
  const KulecnikAction.timeout() : by = 'timeout', op = '', x = 0, y = 0, power = 0;

  final String by, op;
  final int x, y, power;

  Map<String, Object?> toJson() => by == 'timeout' ? {'by': by} : {'by': by, 'op': op, 'x': x, 'y': y, 'power': power};

  @override
  bool operator ==(Object other) =>
      other is KulecnikAction &&
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

class KulecnikResult {
  const KulecnikResult({
    required this.winner,
    required this.stars,
    required this.score,
    required this.playerLeft,
    required this.aiLeft,
  });

  final String winner;
  final int stars, score, playerLeft, aiLeft;

  Map<String, Object?> toJson() => {
    'winner': winner,
    'stars': stars,
    'score': score,
    'playerLeft': playerLeft,
    'aiLeft': aiLeft,
  };
}

/// The break layout: cue on the head spot, the triangle from `rack` row by row.
List<Ball> rackBalls(KulecnikConfig c) {
  final balls = List<Ball>.filled(16, const Ball(0, 0, true));
  final hs = c.headSpot;
  balls[0] = Ball(hs.x, hs.y, true);
  var n = 0;
  for (var k = 0; k < 5; k++) {
    for (var j = 0; j <= k; j++) {
      balls[c.rack[n++]] = Ball(c.tableW ~/ 2 + (2 * j - k) * (c.rackDx ~/ 2), 3 * c.tableH ~/ 4 + k * c.rackDy, true);
    }
  }
  return List.unmodifiable(balls);
}

/// What one shot did, before the rules are applied.
typedef ShotOutcome = ({List<Ball> balls, int firstHit, List<int> pots});

/// Builds the world of a shot and simulates it; [onStep] (UI) sees the bodies after every step.
ShotOutcome simulateShot(
  KulecnikConfig c,
  List<Ball> balls,
  int ax,
  int ay,
  int power, {
  void Function(List<Body> bodies)? onStep,
}) {
  final w = c.tableW, h = c.tableH, e = c.eCushion;
  final bodies = [for (final b in balls) Body(x: b.x, y: b.y, r: c.ballR, on: b.on)];
  final v = shotVelocity(bodies[0].x, bodies[0].y, ax, ay, trunc(power * c.maxSpeed, 100))!;
  bodies[0]
    ..vx = v.vx
    ..vy = v.vy;
  final pots = <int>[];
  var firstHit = -1;
  final world = World(
    bodies: bodies,
    statics: [
      RectStatic(-20000, -20000, 0, h + 20000, e),
      RectStatic(w, -20000, w + 20000, h + 20000, e),
      RectStatic(0, -20000, w, 0, e),
      RectStatic(0, h, w, h + 20000, e),
    ],
    eBody: c.eBall,
    dec: (_, _) => c.dec,
    capture: (wd) {
      for (var i = 0; i < wd.bodies.length; i++) {
        final b = wd.bodies[i];
        if (!b.on) continue;
        for (var p = 0; p < 6; p++) {
          final pk = c.pocket(p);
          final dx = b.x - pk.x, dy = b.y - pk.y;
          if (dx * dx + dy * dy <= pk.r * pk.r) {
            off(b);
            pots.add(i);
            break;
          }
        }
      }
      return false;
    },
    onHit: (i, j) {
      if (firstHit < 0 && i == 0) firstHit = j;
    },
  );
  simulate(world, c.maxSteps, onStep: onStep == null ? null : (wd) => onStep(wd.bodies));
  return (balls: [for (final b in bodies) Ball(b.x, b.y, b.on)], firstHit: firstHit, pots: pots);
}

/// Step 7: the first free spot along the line (n = 0…8), else n = 0.
void _respot(KulecnikConfig c, List<Ball> balls, int id, int x, int y0, int dy) {
  final r2 = 4 * c.ballR * c.ballR;
  for (var n = 0; n <= 8; n++) {
    final y = y0 + n * dy;
    if (balls.every((b) => !b.on || (b.x - x) * (b.x - x) + (b.y - y) * (b.y - y) >= r2)) {
      balls[id] = Ball(x, y, true);
      return;
    }
  }
  balls[id] = Ball(x, y0, true);
}

/// A whole shot (simulation and rules 1–8) by [by], whoever's turn it is.
KulecnikState playShot(KulecnikConfig c, KulecnikState s, String by, int ax, int ay, int power) {
  final out = simulateShot(c, s.balls, ax, ay, power);
  final brk = s.shots == 0;
  final group = s.groupOfSide(by);
  final pots = out.pots;
  // Target balls before the shot: own group, or the eight once the group is cleared.
  final ownBefore = s.leftOf(group);
  var foul = pots.contains(0) || out.firstHit < 0;
  if (!brk && !foul) {
    if (group == '') {
      foul = out.firstHit == 8;
    } else {
      foul = ownBefore > 0 ? groupOf(out.firstHit) != group : out.firstHit != 8;
    }
  }
  final balls = [...out.balls];
  var over = s.over;
  var winner = s.winner;
  var playerGroup = s.playerGroup;
  if (pots.contains(8) && !brk) {
    over = true;
    final won = !foul && group != '' && ownBefore == 0;
    winner = won ? by : _opp(by);
  }
  if (playerGroup == '' && !brk && !foul) {
    for (final n in pots) {
      final g = groupOf(n);
      if (g == '') continue;
      playerGroup = by == 'player' ? g : _other(g);
      break;
    }
  }
  final shooterGroup = by == 'player' ? playerGroup : _other(playerGroup);
  final keeps =
      !foul && (brk ? pots.any((n) => n != 0) : shooterGroup != '' && pots.any((n) => groupOf(n) == shooterGroup));
  final hs = c.headSpot, fs = c.footSpot;
  if (pots.contains(0)) _respot(c, balls, 0, hs.x, hs.y, -c.rackDx);
  if (pots.contains(8) && brk) _respot(c, balls, 8, fs.x, fs.y, c.rackDy);
  return KulecnikState(
    balls: List.unmodifiable(balls),
    turn: keeps ? by : _opp(by),
    playerGroup: playerGroup,
    shots: s.shots + 1,
    last: LastShot(by: by, firstHit: out.firstHit, pots: List.unmodifiable(pots), foul: foul),
    winner: winner,
    over: over,
  );
}

typedef _Candidate = ({int x, int y, int power, int ease});

class KulecnikRules extends MgRules<KulecnikState, KulecnikAction, KulecnikResult> {
  KulecnikConfig? _cfg;

  KulecnikConfig get config => _cfg ?? (throw StateError('kulecnik: init first'));

  @override
  String get id => 'kulecnik';

  @override
  int get specVersion => 1;

  @override
  KulecnikState init(Map<String, Object?> config, int seed) => start(KulecnikConfig.fromJson(config));

  KulecnikState start(KulecnikConfig config) {
    _cfg = config;
    return KulecnikState(
      balls: rackBalls(config),
      turn: 'player',
      playerGroup: '',
      shots: 0,
      last: LastShot.none,
      winner: '',
      over: false,
    );
  }

  @override
  List<KulecnikAction> legalActions(KulecnikState s) => const [];

  @override
  KulecnikState apply(KulecnikState s, KulecnikAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return _timeout(s);
    final cue = s.balls[0];
    if (a.op != 'shot' || a.by != s.turn || a.power < 1 || a.power > 100 || (a.x == cue.x && a.y == cue.y)) {
      throw IllegalAction(id, a);
    }
    return playShot(config, s, a.by, a.x, a.y, a.power);
  }

  KulecnikState _timeout(KulecnikState s) {
    var winner = 'draw';
    if (s.playerGroup != '') {
      final p = s.leftOf(s.playerGroup), q = s.leftOf(_other(s.playerGroup));
      winner = p < q
          ? 'player'
          : q < p
          ? 'ai'
          : 'draw';
    }
    return s.copyWith(over: true, winner: winner);
  }

  /// The AI's candidate shots before sorting and its target list (spec "AI" 1–3).
  ({List<_Candidate> list, List<int> targets}) _candidates(KulecnikState s) {
    final c = config;
    final balls = s.balls;
    final cue = balls[0];
    if (s.shots == 0) {
      final t = balls[c.rack[0]];
      return (list: [(x: t.x, y: t.y, power: 100, ease: 0)], targets: [c.rack[0]]);
    }
    final g = s.groupOfSide('ai');
    var targets = <int>[];
    if (g != '') {
      for (var i = 0; i < balls.length; i++) {
        if (balls[i].on && groupOf(i) == g) targets.add(i);
      }
      if (targets.isEmpty) targets = [8];
    } else {
      for (var i = 1; i < balls.length; i++) {
        if (balls[i].on && i != 8) targets.add(i);
      }
    }
    final list = <_Candidate>[];
    final d = 2 * c.ballR;
    for (final ti in targets) {
      final t = balls[ti];
      for (var p = 0; p < 6; p++) {
        final pk = c.pocket(p);
        final l = isqrt((pk.x - t.x) * (pk.x - t.x) + (pk.y - t.y) * (pk.y - t.y));
        if (l == 0) continue;
        final gx = t.x - trunc((pk.x - t.x) * d, l), gy = t.y - trunc((pk.y - t.y) * d, l);
        final lc = isqrt((gx - cue.x) * (gx - cue.x) + (gy - cue.y) * (gy - cue.y));
        if (lc == 0) continue;
        final ease = lc + l;
        final power = clampInt(c.aiPowerBase + trunc(ease * c.aiPowerPerM, 100000), 15, 100);
        list.add((x: gx, y: gy, power: power, ease: ease));
      }
    }
    return (list: list, targets: targets);
  }

  /// Value of a simulated AI shot (spec "AI" 5).
  int _value(KulecnikState before, KulecnikState after) {
    if (after.over) return after.winner == 'ai' ? 100000 : -100000;
    if (after.last.foul) return -1000;
    final pots = after.last.pots;
    final g = after.groupOfSide('ai');
    final n = before.shots == 0
        ? pots.where((i) => i != 0).length
        : g == ''
        ? 0
        : pots.where((i) => groupOf(i) == g).length;
    return 100 * n + (after.turn == 'ai' ? 10 : 0);
  }

  @override
  KulecnikAction aiAction(KulecnikState s, int level, Prng ai) {
    final c = config;
    final cands = _candidates(s);
    // Stable sort by ease (Dart's List.sort is not stable: index breaks ties).
    final idx = List.generate(cands.list.length, (i) => i)
      ..sort((a, b) {
        final d = cands.list[a].ease - cands.list[b].ease;
        return d != 0 ? d : a - b;
      });
    final tried = [for (final i in idx.take(c.aiCandidates[level - 1])) cands.list[i]];
    ({int x, int y, int power}) best;
    if (tried.isEmpty) {
      final t = s.balls[cands.targets.isEmpty ? 8 : cands.targets.first];
      best = (x: t.x, y: t.y, power: 50);
    } else {
      int? bestV;
      best = (x: tried.first.x, y: tried.first.y, power: tried.first.power);
      for (final k in tried) {
        final v = _value(s, playShot(c, s, 'ai', k.x, k.y, k.power));
        if (bestV == null || v > bestV) {
          bestV = v;
          best = (x: k.x, y: k.y, power: k.power);
        }
      }
    }
    final cue = s.balls[0];
    final sc = c.aiScatter[level - 1];
    final n = normalizedAim(cue.x, cue.y, best.x, best.y) ?? (x: best.x, y: best.y);
    final ex = ai.nextInt(2 * sc + 1) - sc;
    final ey = ai.nextInt(2 * sc + 1) - sc;
    return KulecnikAction.shot('ai', n.x + ex, n.y + ey, best.power);
  }

  @override
  KulecnikResult? result(KulecnikState s) {
    if (!s.over) return null;
    final open = s.playerGroup == '';
    final playerLeft = open ? 7 : s.leftOf(s.playerGroup);
    final aiLeft = open ? 7 : s.leftOf(_other(s.playerGroup));
    final winner = s.winner == '' ? 'draw' : s.winner;
    final sl = config.starLeft;
    final stars = winner != 'player'
        ? 0
        : aiLeft >= sl[0]
        ? 3
        : aiLeft >= sl[1]
        ? 2
        : 1;
    return KulecnikResult(winner: winner, stars: stars, score: 7 - playerLeft, playerLeft: playerLeft, aiLeft: aiLeft);
  }

  @override
  KulecnikAction actionFromJson(Map<String, Object?> j) => j['by'] == 'timeout'
      ? const KulecnikAction.timeout()
      : KulecnikAction.shot(j['by'] as String, j['x'] as int, j['y'] as int, j['power'] as int);

  @override
  Map<String, Object?> stateToJson(KulecnikState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(KulecnikResult r) => r.toJson();
}
