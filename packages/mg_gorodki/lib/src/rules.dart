import 'package:mg_physics/mg_physics.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/gorodki.md, version 1 (physics: specs/minigames/fyzika.md v1). Pure Dart.
class GorodkiConfig {
  const GorodkiConfig({
    required this.level,
    required this.gorodW,
    required this.gorodY0,
    required this.gorodY1,
    required this.polukonY,
    required this.batR,
    required this.batM,
    required this.batDec,
    required this.pieceR,
    required this.pieceM,
    required this.pieceDec,
    required this.minSpeed,
    required this.maxSpeed,
    required this.eBody,
    required this.fieldPad,
    required this.maxSteps,
    required this.bats,
    required this.scatter,
    required this.starFigs,
    required this.figures,
  });

  factory GorodkiConfig.fromTuning(TuningMinigamesGorodki t, int level) => GorodkiConfig(
    level: level,
    gorodW: t.gorodW,
    gorodY0: t.gorodY0,
    gorodY1: t.gorodY1,
    polukonY: t.polukonY,
    batR: t.batR,
    batM: t.batM,
    batDec: t.batDec,
    pieceR: t.pieceR,
    pieceM: t.pieceM,
    pieceDec: t.pieceDec,
    minSpeed: t.minSpeed,
    maxSpeed: t.maxSpeed,
    eBody: t.eBody,
    fieldPad: t.fieldPad,
    maxSteps: t.maxSteps,
    bats: List.unmodifiable(t.bats),
    scatter: List.unmodifiable(t.scatter),
    starFigs: List.unmodifiable(t.starFigs),
    figures: List.unmodifiable([t.fig1, t.fig2, t.fig3, t.fig4, t.fig5].map(List<int>.unmodifiable)),
  );

  factory GorodkiConfig.fromJson(Map<String, Object?> j) {
    List<int> ints(String k) => List.unmodifiable((j[k] as List).cast<int>());
    return GorodkiConfig(
      level: j['level'] as int,
      gorodW: j['gorodW'] as int,
      gorodY0: j['gorodY0'] as int,
      gorodY1: j['gorodY1'] as int,
      polukonY: j['polukonY'] as int,
      batR: j['batR'] as int,
      batM: j['batM'] as int,
      batDec: j['batDec'] as int,
      pieceR: j['pieceR'] as int,
      pieceM: j['pieceM'] as int,
      pieceDec: j['pieceDec'] as int,
      minSpeed: j['minSpeed'] as int,
      maxSpeed: j['maxSpeed'] as int,
      eBody: j['eBody'] as int,
      fieldPad: j['fieldPad'] as int,
      maxSteps: j['maxSteps'] as int,
      bats: ints('bats'),
      scatter: ints('scatter'),
      starFigs: ints('starFigs'),
      figures: List.unmodifiable((j['figures'] as List).map((f) => List<int>.unmodifiable((f as List).cast<int>()))),
    );
  }

  final int level, gorodW, gorodY0, gorodY1, polukonY, batR, batM, batDec, pieceR, pieceM, pieceDec;
  final int minSpeed, maxSpeed, eBody, fieldPad, maxSteps;
  final List<int> bats, scatter, starFigs;

  /// Five figures, each [dx, dy] × 5 from the middle of the front line.
  final List<List<int>> figures;

  /// Pieces of figure [fig] (1–5) at their start spots.
  ({List<int> px, List<int> py, List<bool> up}) figure(int fig) {
    final f = figures[fig - 1];
    final mid = gorodW ~/ 2;
    return (
      px: [for (var k = 0; k < 5; k++) mid + f[2 * k]],
      py: [for (var k = 0; k < 5; k++) gorodY0 + f[2 * k + 1]],
      up: List.filled(5, true),
    );
  }

  bool inGorod(Body b) => b.on && b.x >= 0 && b.x <= gorodW && b.y >= gorodY0 && b.y <= gorodY1;
}

class GorodkiState {
  const GorodkiState({
    required this.fig,
    required this.px,
    required this.py,
    required this.up,
    required this.bats,
    required this.throws,
    required this.cleared,
    required this.knocked,
    required this.polukon,
    required this.lastOut,
    required this.over,
    required this.rng,
  });

  final int fig;
  final List<int> px, py;
  final List<bool> up;
  final int bats, throws, cleared, knocked;
  final bool polukon;
  final int lastOut;
  final bool over;
  final int rng;

  GorodkiState copyWith({
    int? fig,
    List<int>? px,
    List<int>? py,
    List<bool>? up,
    int? bats,
    int? throws,
    int? cleared,
    int? knocked,
    bool? polukon,
    int? lastOut,
    bool? over,
    int? rng,
  }) => GorodkiState(
    fig: fig ?? this.fig,
    px: px ?? this.px,
    py: py ?? this.py,
    up: up ?? this.up,
    bats: bats ?? this.bats,
    throws: throws ?? this.throws,
    cleared: cleared ?? this.cleared,
    knocked: knocked ?? this.knocked,
    polukon: polukon ?? this.polukon,
    lastOut: lastOut ?? this.lastOut,
    over: over ?? this.over,
    rng: rng ?? this.rng,
  );

  Map<String, Object?> toJson() => {
    'fig': fig,
    'px': px,
    'py': py,
    'up': up,
    'bats': bats,
    'throws': throws,
    'cleared': cleared,
    'knocked': knocked,
    'polukon': polukon,
    'lastOut': lastOut,
    'over': over,
    'rng': rng,
  };
}

/// {by: player, op: throw, x, aim, power} or {by: timeout}.
class GorodkiAction {
  const GorodkiAction.hurl(this.x, this.aim, this.power) : by = 'player';
  const GorodkiAction.timeout() : by = 'timeout', x = 0, aim = 0, power = 0;

  final String by;
  final int x, aim, power;

  Map<String, Object?> toJson() =>
      by == 'timeout' ? {'by': by} : {'by': by, 'op': 'throw', 'x': x, 'aim': aim, 'power': power};

  @override
  String toString() => toJson().toString();
}

class GorodkiResult {
  const GorodkiResult({
    required this.winner,
    required this.stars,
    required this.score,
    required this.cleared,
    required this.knocked,
    required this.throws,
  });

  final String winner;
  final int stars, score, cleared, knocked, throws;

  Map<String, Object?> toJson() => {
    'winner': winner,
    'stars': stars,
    'score': score,
    'cleared': cleared,
    'knocked': knocked,
    'throws': throws,
  };
}

int gorodkiThrowLine(GorodkiConfig c, GorodkiState s) => s.polukon ? c.polukonY : 0;

/// Bat velocity of a throw: normalized aim, scatter from [rng] (ex, then ey), then the speed.
({int vx, int vy}) gorodkiVelocity(GorodkiConfig c, int ly, int x, int aim, int power, Prng rng) {
  final n = normalizedAim(x, ly, aim, c.gorodY0)!;
  final s = c.scatter[c.level - 1];
  final ex = rng.nextInt(2 * s + 1) - s;
  final ey = rng.nextInt(2 * s + 1) - s;
  final sp = c.minSpeed + trunc((c.maxSpeed - c.minSpeed) * power, 100);
  return shotVelocity(x, ly, n.x + ex, n.y + ey, sp)!;
}

/// Simulates one throw; returns the bodies after it (0 = bat, 1–5 = pieces). [onStep] (UI) sees each step.
List<Body> simulateThrow(
  GorodkiConfig c,
  GorodkiState s,
  int x,
  ({int vx, int vy}) v, {
  void Function(List<Body> bodies)? onStep,
}) {
  final bodies = [
    Body(x: x, y: gorodkiThrowLine(c, s), vx: v.vx, vy: v.vy, r: c.batR, m: c.batM),
    for (var k = 0; k < 5; k++) Body(x: s.px[k], y: s.py[k], r: c.pieceR, m: c.pieceM, on: s.up[k]),
  ];
  final world = World(
    bodies: bodies,
    statics: const [],
    eBody: c.eBody,
    capture: (w) {
      for (final b in w.bodies) {
        if (b.on && (b.x < -c.fieldPad || b.x > c.gorodW + c.fieldPad || b.y > c.gorodY1 + c.fieldPad)) off(b);
      }
      return false;
    },
    dec: (i, b) => i == 0 ? c.batDec : c.pieceDec,
  );
  simulate(world, c.maxSteps, onStep: onStep == null ? null : (w) => onStep(w.bodies));
  return bodies;
}

class GorodkiRules extends MgRules<GorodkiState, GorodkiAction, GorodkiResult> {
  GorodkiConfig? _cfg;
  GorodkiConfig get config => _cfg ?? (throw StateError('gorodki: init first'));

  @override
  String get id => 'gorodki';

  @override
  int get specVersion => 1;

  @override
  GorodkiState init(Map<String, Object?> config, int seed) => start(GorodkiConfig.fromJson(config), seed);

  GorodkiState start(GorodkiConfig c, int seed) {
    _cfg = c;
    final f = c.figure(1);
    return GorodkiState(
      fig: 1,
      px: f.px,
      py: f.py,
      up: f.up,
      bats: c.bats[c.level - 1],
      throws: 0,
      cleared: 0,
      knocked: 0,
      polukon: false,
      lastOut: 0,
      over: false,
      rng: Prng(seed).state,
    );
  }

  @override
  List<GorodkiAction> legalActions(GorodkiState s) => const [];

  bool legal(GorodkiState s, GorodkiAction a) =>
      !s.over && a.by == 'player' && a.x >= 0 && a.x <= config.gorodW && a.power >= 1 && a.power <= 100;

  /// The bat velocity this throw will get (draws the scatter from a copy of the state's rng).
  ({int vx, int vy, int rng}) velocity(GorodkiState s, GorodkiAction a) {
    final r = withRng(s.rng, (p) => gorodkiVelocity(config, gorodkiThrowLine(config, s), a.x, a.aim, a.power, p));
    return (vx: r.value.vx, vy: r.value.vy, rng: r.rng);
  }

  @override
  GorodkiState apply(GorodkiState s, GorodkiAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(over: true);
    if (!legal(s, a)) throw IllegalAction(id, a);
    final c = config;
    final v = velocity(s, a);
    final bodies = simulateThrow(c, s, a.x, (vx: v.vx, vy: v.vy));
    final px = [...s.px], py = [...s.py], up = [...s.up];
    var out = 0;
    for (var k = 0; k < 5; k++) {
      if (!up[k]) continue;
      final b = bodies[k + 1];
      if (c.inGorod(b)) {
        px[k] = b.x;
        py[k] = b.y;
      } else {
        up[k] = false;
        out++;
      }
    }
    var n = s.copyWith(
      px: px,
      py: py,
      up: up,
      bats: s.bats - 1,
      throws: s.throws + 1,
      knocked: s.knocked + out,
      lastOut: out,
      polukon: s.polukon || out > 0,
      rng: v.rng,
    );
    if (up.every((u) => !u)) {
      n = n.copyWith(cleared: n.cleared + 1);
      if (s.fig == 5) return n.copyWith(over: true);
      final f = c.figure(s.fig + 1);
      n = n.copyWith(fig: s.fig + 1, px: f.px, py: f.py, up: f.up, polukon: false);
    }
    if (n.bats == 0) n = n.copyWith(over: true);
    return n;
  }

  @override
  GorodkiAction aiAction(GorodkiState s, int level, Prng ai) {
    final m = config.gorodW ~/ 2;
    return GorodkiAction.hurl(m, m, 60);
  }

  @override
  GorodkiResult? result(GorodkiState s) {
    if (!s.over) return null;
    final sf = config.starFigs;
    final stars = s.cleared >= sf[0]
        ? 3
        : s.cleared >= sf[1]
        ? 2
        : s.cleared >= sf[2]
        ? 1
        : 0;
    final score = s.knocked * 10 + s.cleared * 50 + (s.cleared == 5 ? s.bats * 20 : 0);
    return GorodkiResult(
      winner: stars >= 1 ? 'player' : 'ai',
      stars: stars,
      score: score,
      cleared: s.cleared,
      knocked: s.knocked,
      throws: s.throws,
    );
  }

  @override
  GorodkiAction actionFromJson(Map<String, Object?> j) {
    if (j['by'] == 'timeout') return const GorodkiAction.timeout();
    if (j['by'] != 'player' || j['op'] != 'throw') throw IllegalAction(id, j);
    return GorodkiAction.hurl(j['x'] as int, j['aim'] as int, j['power'] as int);
  }

  @override
  Map<String, Object?> stateToJson(GorodkiState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(GorodkiResult r) => r.toJson();
}
