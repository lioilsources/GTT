import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Border drawn around the course (u).
const _edge = 4000;

/// Minigolf (specs/minigames/minigolf.md): drag from the ball to aim, longer = harder; six holes
/// against par.
class MinigolfGame implements Minigame {
  const MinigolfGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.minigolf]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.minigolf;
    return MinigameShell(
      id: MinigameId.minigolf,
      env: env,
      rules: const [MessageKey.minigolfRules1, MessageKey.minigolfRules2, MessageKey.minigolfRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _MinigolfBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _MinigolfBody extends StatefulWidget {
  const _MinigolfBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_MinigolfBody> createState() => _MinigolfBodyState();
}

typedef _Aim = ({int x, int y, int power});

WorldView _viewOf(Size size, Hole h) =>
    WorldView.fit(size, -_edge.toDouble(), -_edge.toDouble(), h.w + _edge.toDouble(), h.h + _edge.toDouble(), pad: 8);

class _MinigolfBodyState extends State<_MinigolfBody> with TickerProviderStateMixin {
  final MinigolfRules _rules = MinigolfRules();
  late final TuningMinigamesMinigolf _tm = widget.env.tuning.minigames.minigolf;
  late final MinigolfConfig _cfg = MinigolfConfig.fromTuning(_tm, widget.ctx.difficulty);
  late MinigolfState _s = _rules.start(_cfg, widget.ctx.seed);
  late final FramePlayback _playback = FramePlayback(this, () => widget.shell.paused);
  late final PausableTimer _timer = PausableTimer(() => widget.shell.paused);
  final Toast _toast = Toast();
  late ({int x, int y}) _ball = (x: _s.x, y: _s.y);
  late int _shownHole = _s.hole;
  bool _busy = false;
  _Aim? _aim;
  Offset? _dragStart;
  Size _size = Size.zero;

  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  @override
  void initState() {
    super.initState();
    widget.hooks.onTimeout = _timeout;
    WidgetsBinding.instance.addPostFrameCallback((_) => _status());
  }

  @override
  void dispose() {
    _playback.cancel();
    _timer.cancel();
    _toast.dispose();
    super.dispose();
  }

  void _status() {
    if (mounted) widget.shell.status(t(MessageKey.minigolfStrokes, {'n': _s.strokes}));
  }

  bool get _canAim => !widget.shell.paused && !_busy && !_s.over;

  void _panStart(DragStartDetails d) {
    if (!_canAim) return;
    _dragStart = d.localPosition;
    _panTo(d.localPosition);
  }

  void _panUpdate(DragUpdateDetails d) {
    if (_dragStart != null) _panTo(d.localPosition);
  }

  void _panTo(Offset p) {
    final d = p - _dragStart!;
    final k = _viewOf(_size, _rules.holeAt(_shownHole)).k;
    final power = dragPower(d.dx, d.dy, math.min(_size.width, _size.height) * 0.45);
    final ax = _s.x + (d.dx / k).round(), ay = _s.y + (-d.dy / k).round();
    setState(() => _aim = power > 0 && (ax != _s.x || ay != _s.y) ? (x: ax, y: ay, power: power) : null);
  }

  void _panEnd(DragEndDetails _) {
    final a = _aim;
    _dragStart = null;
    setState(() => _aim = null);
    if (a == null || !_canAim) return;
    _putt(MinigolfAction.putt(a.x, a.y, a.power));
  }

  void _putt(MinigolfAction a) {
    if (!_rules.legal(_s, a)) return;
    setState(() => _busy = true);
    final vel = _rules.velocity(_s, a);
    final frames = <({int x, int y})>[];
    var n = 0;
    final out = simulatePutt(
      _cfg,
      _rules.holeAt(_s.hole),
      _s.x,
      _s.y,
      (vx: vel.vx, vy: vel.vy),
      onStep: (b) {
        if (++n % _tm.stepsPerFrame == 0) frames.add((x: b.x, y: b.y));
      },
    );
    frames.add((x: out.x, y: out.y));
    _playback.play<({int x, int y})>(frames, (f) => setState(() => _ball = f), () {
      if (!mounted) return;
      final before = _s;
      setState(() => _s = _rules.apply(_s, a));
      _status();
      if (out.end == PuttEnd.water) _toast.show(t(MessageKey.minigolfWater));
      if (out.end == PuttEnd.cup) _toast.show(t(MessageKey.minigolfHoled));
      final r = _rules.result(_s);
      if (r != null) {
        widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
        return;
      }
      final wait = _s.hole != before.hole || out.end == PuttEnd.water ? 700 : 0;
      _timer.later(Duration(milliseconds: wait), () {
        if (!mounted) return;
        setState(() {
          _shownHole = _s.hole;
          _ball = (x: _s.x, y: _s.y);
          _busy = false;
        });
      });
    });
  }

  void _timeout() {
    if (_s.over) return;
    _playback.cancel();
    _timer.cancel();
    setState(() => _s = _rules.apply(_s, const MinigolfAction.timeout()));
    final r = _rules.result(_s)!;
    widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
  }

  @override
  Widget build(BuildContext context) {
    final hole = math.min(_s.hole, 6);
    const muted = TextStyle(color: Color(Tokens.colorUiTextMuted));
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceSm),
      child: Column(
        children: [
          Text(t(MessageKey.minigolfHole, {'hole': hole, 'par': _rules.holeAt(hole).par}), style: muted),
          const SizedBox(height: Tokens.spaceXs),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                _size = c.biggest;
                return Stack(
                  children: [
                    GestureDetector(
                      key: const ValueKey('course'),
                      behavior: HitTestBehavior.opaque,
                      onPanStart: _panStart,
                      onPanUpdate: _panUpdate,
                      onPanEnd: _panEnd,
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _CoursePainter(
                          cfg: _cfg,
                          hole: _rules.holeAt(_shownHole),
                          ball: _ball,
                          aim: _busy ? null : _aim,
                        ),
                      ),
                    ),
                    ToastView(toast: _toast),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: Tokens.spaceXs),
          PowerBar(power: _busy ? 0 : _aim?.power ?? 0),
        ],
      ),
    );
  }
}

class _CoursePainter extends CustomPainter {
  _CoursePainter({required this.cfg, required this.hole, required this.ball, required this.aim});

  final MinigolfConfig cfg;
  final Hole hole;
  final ({int x, int y}) ball;
  final _Aim? aim;

  @override
  void paint(Canvas canvas, Size size) {
    final h = hole;
    final v = _viewOf(size, h);
    final k = v.k;
    void box(num x0, num y0, num x1, num y1, int color) =>
        canvas.drawRect(Rect.fromPoints(v.p(x0, y1), v.p(x1, y0)), Paint()..color = Color(color));
    box(-_edge, -_edge, h.w + _edge, h.h + _edge, Tokens.colorCarDetailBed);
    box(0, 0, h.w, h.h, Tokens.colorWorldDayPark);
    for (final b in h.water) {
      box(b.x0, b.y0, b.x1, b.y1, Tokens.colorWorldDayWater);
    }
    for (final b in h.sand) {
      box(b.x0, b.y0, b.x1, b.y1, Tokens.colorWorldDayFacades[5]);
    }
    for (final b in h.walls) {
      box(b.x0, b.y0, b.x1, b.y1, Tokens.colorShopsBar);
    }
    for (final b in h.bumpers) {
      canvas.drawCircle(v.p(b.x, b.y), b.r * k, Paint()..color = const Color(Tokens.colorBoothBody));
      canvas.drawCircle(
        v.p(b.x, b.y),
        b.r * k,
        Paint()
          ..color = const Color(Tokens.colorBoothRoof)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    final cup = v.p(h.cx, h.cy);
    canvas.drawCircle(
      cup,
      math.max(5, cfg.ballR * 1.6 * k),
      Paint()..color = const Color(Tokens.colorCarDetailLimoPillar),
    );
    canvas.drawLine(
      cup,
      cup.translate(0, -28),
      Paint()
        ..color = const Color(Tokens.colorWorldDayMarking)
        ..strokeWidth = 2,
    );
    canvas.drawPath(
      Path()
        ..moveTo(cup.dx, cup.dy - 28)
        ..lineTo(cup.dx + 14, cup.dy - 22)
        ..lineTo(cup.dx, cup.dy - 16)
        ..close(),
      Paint()..color = const Color(Tokens.colorTrafficLightRed),
    );
    final a = aim;
    if (a != null) {
      final dx = (a.x - ball.x).toDouble(), dy = (a.y - ball.y).toDouble();
      final l = math.max(math.sqrt(dx * dx + dy * dy), 1.0);
      final reach = a.power / 100 * h.h * 0.35;
      dashedLine(
        canvas,
        v.p(ball.x, ball.y),
        v.p(ball.x + dx / l * reach, ball.y + dy / l * reach),
        Paint()
          ..color = const Color(Tokens.colorUiControlWheel)
          ..strokeWidth = 2,
        dash: 5,
      );
    }
    final b = v.p(ball.x, ball.y);
    final r = math.max(4.0, cfg.ballR * k);
    canvas.drawCircle(b, r, Paint()..color = const Color(Tokens.colorWorldDayMarking));
    canvas.drawCircle(
      b,
      r,
      Paint()
        ..color = const Color(Tokens.colorUiLabelShadow)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_CoursePainter old) => old.hole != hole || old.ball != ball || old.aim != aim;
}
