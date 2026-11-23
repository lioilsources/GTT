import 'package:mg_physics/mg_physics.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/cihly.md, version 1 (arithmetic and closest point: specs/minigames/fyzika.md
/// v1). Pure Dart: no Flutter imports here.
class CihlyConfig {
  const CihlyConfig({
    required this.level,
    required this.w,
    required this.h,
    required this.ballR,
    required this.paddleY,
    required this.paddleH,
    required this.paddleW,
    required this.speed,
    required this.maxVxPct,
    required this.serveTicks,
    required this.lives,
    required this.rows,
    required this.cols,
    required this.brickX0,
    required this.brickTop,
    required this.brickW,
    required this.brickH,
    required this.brickGap,
    required this.rowPoints,
    required this.livesBonus,
    required this.starScores,
  });

  factory CihlyConfig.fromTuning(TuningMinigamesCihly t, int level) => CihlyConfig(
    level: level,
    w: t.w,
    h: t.h,
    ballR: t.ballR,
    paddleY: t.paddleY,
    paddleH: t.paddleH,
    paddleW: List.unmodifiable(t.paddleW),
    speed: List.unmodifiable(t.speed),
    maxVxPct: t.maxVxPct,
    serveTicks: t.serveTicks,
    lives: t.lives,
    rows: t.rows,
    cols: t.cols,
    brickX0: t.brickX0,
    brickTop: t.brickTop,
    brickW: t.brickW,
    brickH: t.brickH,
    brickGap: t.brickGap,
    rowPoints: List.unmodifiable(t.rowPoints),
    livesBonus: t.livesBonus,
    starScores: List.unmodifiable(t.starScores),
  );

  factory CihlyConfig.fromJson(Map<String, Object?> j) {
    int i(String k) => j[k] as int;
    List<int> l(String k) => List.unmodifiable((j[k] as List).cast<int>());
    return CihlyConfig(
      level: i('level'),
      w: i('w'),
      h: i('h'),
      ballR: i('ballR'),
      paddleY: i('paddleY'),
      paddleH: i('paddleH'),
      paddleW: l('paddleW'),
      speed: l('speed'),
      maxVxPct: i('maxVxPct'),
      serveTicks: i('serveTicks'),
      lives: i('lives'),
      rows: i('rows'),
      cols: i('cols'),
      brickX0: i('brickX0'),
      brickTop: i('brickTop'),
      brickW: i('brickW'),
      brickH: i('brickH'),
      brickGap: i('brickGap'),
      rowPoints: l('rowPoints'),
      livesBonus: i('livesBonus'),
      starScores: l('starScores'),
    );
  }

  final int level, w, h, ballR, paddleY, paddleH, maxVxPct, serveTicks, lives, rows, cols;
  final int brickX0, brickTop, brickW, brickH, brickGap, livesBonus;
  final List<int> paddleW, speed, rowPoints, starScores;

  /// Half width of the paddle at this level.
  int get halfWidth => paddleW[level - 1];

  /// Brick i = row × cols + col (row 0 at the top).
  ({int x0, int y0, int x1, int y1}) brick(int i) {
    final row = i ~/ cols, col = i % cols;
    final x0 = brickX0 + col * (brickW + brickGap);
    final y1 = brickTop - row * (brickH + brickGap);
    return (x0: x0, y0: y1 - brickH, x1: x0 + brickW, y1: y1);
  }
}

class CihlyBall {
  const CihlyBall(this.x, this.y, this.vx, this.vy);

  final int x, y, vx, vy;

  Map<String, Object?> toJson() => {'x': x, 'y': y, 'vx': vx, 'vy': vy};
}

class CihlyState {
  const CihlyState({
    required this.ball,
    required this.paddle,
    required this.serve,
    required this.bricks,
    required this.score,
    required this.lives,
    required this.over,
    required this.rng,
  });

  final CihlyBall ball;
  final int paddle, serve;
  final List<bool> bricks;
  final int score, lives;
  final bool over;
  final int rng;

  CihlyState copyWith({int? paddle, bool? over}) => CihlyState(
    ball: ball,
    paddle: paddle ?? this.paddle,
    serve: serve,
    bricks: bricks,
    score: score,
    lives: lives,
    over: over ?? this.over,
    rng: rng,
  );

  Map<String, Object?> toJson() => {
    'ball': ball.toJson(),
    'paddle': paddle,
    'serve': serve,
    'bricks': bricks,
    'score': score,
    'lives': lives,
    'over': over,
    'rng': rng,
  };
}

/// {by: player, op: move, x}, {by: player, op: tick, n} or {by: timeout}.
class CihlyAction {
  const CihlyAction.move(this.x) : by = 'player', op = 'move', n = 0;
  const CihlyAction.tick(this.n) : by = 'player', op = 'tick', x = 0;
  const CihlyAction.timeout() : by = 'timeout', op = '', x = 0, n = 0;
  const CihlyAction._(this.by, this.op, this.x, this.n);

  final String by, op;
  final int x, n;

  Map<String, Object?> toJson() => by == 'timeout'
      ? {'by': by}
      : op == 'move'
      ? {'by': by, 'op': op, 'x': x}
      : {'by': by, 'op': op, 'n': n};

  @override
  bool operator ==(Object other) =>
      other is CihlyAction && other.by == by && other.op == op && other.x == x && other.n == n;

  @override
  int get hashCode => Object.hash(by, op, x, n);

  @override
  String toString() => toJson().toString();
}

class CihlyResult {
  const CihlyResult({
    required this.winner,
    required this.stars,
    required this.score,
    required this.lives,
    required this.cleared,
  });

  final String winner;
  final int stars, score, lives;
  final bool cleared;

  Map<String, Object?> toJson() => {
    'winner': winner,
    'stars': stars,
    'score': score,
    'lives': lives,
    'cleared': cleared,
  };
}

/// Mutable working copy of one apply.
class _Run {
  _Run(CihlyState s)
    : x = s.ball.x,
      y = s.ball.y,
      vx = s.ball.vx,
      vy = s.ball.vy,
      paddle = s.paddle,
      serve = s.serve,
      bricks = [...s.bricks],
      score = s.score,
      lives = s.lives,
      over = s.over,
      rng = s.rng;

  int x, y, vx, vy;
  final int paddle;
  int serve;
  final List<bool> bricks;
  int score, lives;
  bool over;
  int rng;

  CihlyState freeze() => CihlyState(
    ball: CihlyBall(x, y, vx, vy),
    paddle: paddle,
    serve: serve,
    bricks: List.unmodifiable(bricks),
    score: score,
    lives: lives,
    over: over,
    rng: rng,
  );
}

class CihlyRules extends MgRules<CihlyState, CihlyAction, CihlyResult> {
  CihlyConfig? _cfg;

  CihlyConfig get config => _cfg ?? (throw StateError('cihly: init first'));

  @override
  String get id => 'cihly';

  @override
  int get specVersion => 1;

  @override
  CihlyState init(Map<String, Object?> config, int seed) => start(CihlyConfig.fromJson(config), seed);

  CihlyState start(CihlyConfig config, int seed) {
    _cfg = config;
    final paddle = config.w ~/ 2;
    return CihlyState(
      ball: _onPaddle(paddle),
      paddle: paddle,
      serve: config.serveTicks,
      bricks: List.unmodifiable(List.filled(config.rows * config.cols, true)),
      score: 0,
      lives: config.lives,
      over: false,
      rng: Prng(seed).state,
    );
  }

  CihlyBall _onPaddle(int paddle) => CihlyBall(paddle, config.paddleY + config.paddleH + config.ballR, 0, 0);

  @override
  List<CihlyAction> legalActions(CihlyState s) => const [];

  @override
  CihlyState apply(CihlyState s0, CihlyAction a) {
    if (s0.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s0.copyWith(over: true);
    if (a.by != 'player') throw IllegalAction(id, a);
    final c = config;
    if (a.op == 'move') {
      final hw = c.halfWidth;
      return s0.copyWith(paddle: clampInt(a.x, hw, c.w - hw));
    }
    if (a.op != 'tick' || a.n < 1) throw IllegalAction(id, a);
    final s = _Run(s0);
    for (var k = 0; k < a.n && !s.over; k++) {
      _tick(s);
    }
    return s.freeze();
  }

  void _toPaddle(_Run s) {
    final b = _onPaddle(s.paddle);
    s
      ..x = b.x
      ..y = b.y
      ..vx = 0
      ..vy = 0;
  }

  void _tick(_Run s) {
    final c = config;
    final sp = c.speed[c.level - 1], hw = c.halfWidth, r = c.ballR;
    if (s.serve > 0) {
      s.serve -= 1;
      _toPaddle(s);
      if (s.serve == 0) {
        final sv = sp ~/ 2;
        final g = withRng(s.rng, (p) => p.nextInt(2 * sv + 1) - sv);
        s.vx = g.value;
        s.rng = g.rng;
        s.vy = isqrt(sp * sp - s.vx * s.vx);
      }
      return;
    }
    s.x += s.vx;
    s.y += s.vy;
    if ((s.x - r < 0 && s.vx < 0) || (s.x + r > c.w && s.vx > 0)) s.vx = 0 - s.vx;
    if (s.y + r > c.h && s.vy > 0) s.vy = 0 - s.vy;
    for (var i = 0; i < s.bricks.length; i++) {
      if (!s.bricks[i]) continue;
      final q = c.brick(i);
      final dx = s.x - clampInt(s.x, q.x0, q.x1), dy = s.y - clampInt(s.y, q.y0, q.y1);
      final d2 = dx * dx + dy * dy;
      if (d2 >= r * r) continue;
      if (d2 == 0) {
        s.vy = 0 - s.vy;
      } else if (s.vx * dx + s.vy * dy >= 0) {
        continue;
      } else if (dx.abs() > dy.abs()) {
        s.vx = 0 - s.vx;
      } else if (dy.abs() > dx.abs()) {
        s.vy = 0 - s.vy;
      } else {
        s.vx = 0 - s.vx;
        s.vy = 0 - s.vy;
      }
      s.bricks[i] = false;
      s.score += c.rowPoints[i ~/ c.cols];
      break;
    }
    if (s.vy < 0 && s.y >= c.paddleY) {
      final dx = s.x - clampInt(s.x, s.paddle - hw, s.paddle + hw);
      final dy = s.y - clampInt(s.y, c.paddleY - c.paddleH, c.paddleY + c.paddleH);
      if (dx * dx + dy * dy < r * r) {
        final mx = trunc(sp * c.maxVxPct, 100);
        s.vx = clampInt(trunc(mx * (s.x - s.paddle), hw), -mx, mx);
        s.vy = isqrt(sp * sp - s.vx * s.vx);
      }
    }
    if (s.y + r < 0) {
      s.lives -= 1;
      if (s.lives == 0) {
        s.over = true;
      } else {
        s.serve = c.serveTicks;
        _toPaddle(s);
      }
    }
    if (s.bricks.every((b) => !b)) {
      s.score += s.lives * c.livesBonus;
      s.over = true;
    }
  }

  @override
  CihlyAction aiAction(CihlyState s, int level, Prng ai) => const CihlyAction.tick(1);

  @override
  CihlyResult? result(CihlyState s) {
    if (!s.over) return null;
    final ss = config.starScores;
    final stars = s.score >= ss[0]
        ? 3
        : s.score >= ss[1]
        ? 2
        : s.score >= ss[2]
        ? 1
        : 0;
    return CihlyResult(
      winner: stars >= 1 ? 'player' : 'ai',
      stars: stars,
      score: s.score,
      lives: s.lives,
      cleared: s.bricks.every((b) => !b),
    );
  }

  @override
  CihlyAction actionFromJson(Map<String, Object?> j) {
    if (j['by'] == 'timeout') return const CihlyAction.timeout();
    return CihlyAction._(j['by'] as String, j['op'] as String, (j['x'] as int?) ?? 0, (j['n'] as int?) ?? 0);
  }

  @override
  Map<String, Object?> stateToJson(CihlyState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(CihlyResult r) => r.toJson();
}
