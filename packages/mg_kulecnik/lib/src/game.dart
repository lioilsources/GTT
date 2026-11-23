import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Cushion margin drawn around the playing surface (u).
const _rail = 7000;

/// Ball colours by number (1–7 solids, 8 black; 9–15 reuse 1–7 with a white band), as on web.
final List<int> _ballColors = [
  Tokens.colorGaragePaints[0],
  Tokens.colorGaragePaints[4],
  Tokens.colorGaragePaints[2],
  Tokens.colorPedestriansShirts[0],
  Tokens.colorGaragePaints[6],
  Tokens.colorGaragePaints[5],
  Tokens.colorGaragePaints[3],
  Tokens.colorGaragePaints[9],
  Tokens.colorGaragePaints[1],
];

/// Kulečník 8-ball (specs/minigames/kulecnik.md): drag from the cue ball to aim and set the power;
/// the NPC plays its shots after `ai_think_s`.
class KulecnikGame implements Minigame {
  const KulecnikGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.kulecnik]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.kulecnik;
    return MinigameShell(
      id: MinigameId.kulecnik,
      env: env,
      rules: const [MessageKey.kulecnikRules1, MessageKey.kulecnikRules2, MessageKey.kulecnikRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _KulecnikBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _KulecnikBody extends StatefulWidget {
  const _KulecnikBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_KulecnikBody> createState() => _KulecnikBodyState();
}

typedef _Aim = ({int x, int y, int power});

class _KulecnikBodyState extends State<_KulecnikBody> with TickerProviderStateMixin {
  final KulecnikRules _rules = KulecnikRules();
  late final TuningMinigamesKulecnik _tm = widget.env.tuning.minigames.kulecnik;
  late final KulecnikConfig _cfg = KulecnikConfig.fromTuning(_tm);
  late KulecnikState _s = _rules.start(_cfg);
  late final Prng _ai = aiPrng(widget.ctx.seed);
  late final FramePlayback _playback = FramePlayback(this, () => widget.shell.paused);
  late final PausableTimer _timer = PausableTimer(() => widget.shell.paused);
  final Toast _toast = Toast();
  late List<Ball> _shown = _s.balls;
  bool _busy = false;
  _Aim? _aim;
  Offset? _dragStart;
  Size _size = Size.zero;

  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  WorldView get _view => WorldView.fit(
    _size,
    -_rail.toDouble(),
    -_rail.toDouble(),
    _cfg.tableW + _rail.toDouble(),
    _cfg.tableH + _rail.toDouble(),
    pad: 8,
  );

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
    if (!mounted) return;
    final g = _s.playerGroup;
    widget.shell.status(
      t(
        g == 'solid'
            ? MessageKey.kulecnikSolids
            : g == 'stripe'
            ? MessageKey.kulecnikStripes
            : MessageKey.kulecnikOpen,
      ),
    );
  }

  bool get _canAim => !widget.shell.paused && !_busy && !_s.over && _s.turn == 'player';

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
    final k = _view.k;
    final cue = _s.balls[0];
    final power = dragPower(d.dx, d.dy, math.min(_size.width, _size.height) * 0.45);
    final ax = cue.x + (d.dx / k).round(), ay = cue.y + (-d.dy / k).round();
    setState(() => _aim = power > 0 && (ax != cue.x || ay != cue.y) ? (x: ax, y: ay, power: power) : null);
  }

  void _panEnd(DragEndDetails _) {
    final a = _aim;
    _dragStart = null;
    setState(() => _aim = null);
    if (a == null || !_canAim) return;
    _play(KulecnikAction.shot('player', a.x, a.y, a.power));
  }

  /// Animates a shot from the recorded steps, then applies it through the rules.
  void _play(KulecnikAction a) {
    setState(() {
      _busy = true;
      _aim = null;
    });
    final frames = <List<Ball>>[];
    var n = 0;
    simulateShot(
      _cfg,
      _s.balls,
      a.x,
      a.y,
      a.power,
      onStep: (bodies) {
        if (++n % _tm.stepsPerFrame == 0) frames.add([for (final b in bodies) Ball(b.x, b.y, b.on)]);
      },
    );
    _playback.play<List<Ball>>(frames, (f) => setState(() => _shown = f), () {
      if (!mounted) return;
      setState(() {
        _s = _rules.apply(_s, a);
        _shown = _s.balls;
      });
      _status();
      if (_s.last.foul && _s.last.by == 'player') _toast.show(t(MessageKey.kulecnikFoul));
      final r = _rules.result(_s);
      if (r != null) {
        widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
        return;
      }
      if (_s.turn == 'ai') {
        _timer.later(Duration(milliseconds: (_tm.aiThinkS * 1000).round()), () {
          if (mounted && !_s.over) _play(_rules.aiAction(_s, widget.ctx.difficulty, _ai));
        });
      } else {
        setState(() => _busy = false);
      }
    });
  }

  void _timeout() {
    if (_s.over) return;
    _playback.cancel();
    _timer.cancel();
    setState(() => _s = _rules.apply(_s, const KulecnikAction.timeout()));
    final r = _rules.result(_s)!;
    widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
  }

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: Color(Tokens.colorUiTextMuted));
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceSm),
      child: Column(
        children: [
          Text(_s.over ? '' : t(_s.turn == 'player' ? MessageKey.yourTurn : MessageKey.opponentTurn), style: muted),
          const SizedBox(height: Tokens.spaceXs),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                _size = c.biggest;
                return Stack(
                  children: [
                    GestureDetector(
                      key: const ValueKey('table'),
                      behavior: HitTestBehavior.opaque,
                      onPanStart: _panStart,
                      onPanUpdate: _panUpdate,
                      onPanEnd: _panEnd,
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _TablePainter(cfg: _cfg, balls: _shown, aim: _busy ? null : _aim),
                      ),
                    ),
                    ToastView(toast: _toast),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: Tokens.spaceXs),
          PowerBar(power: _aim?.power ?? 0),
        ],
      ),
    );
  }
}

/// Table, pockets, guide to the first ball, balls and the cue stick (same look as the web client).
class _TablePainter extends CustomPainter {
  _TablePainter({required this.cfg, required this.balls, required this.aim});

  final KulecnikConfig cfg;
  final List<Ball> balls;
  final _Aim? aim;

  @override
  void paint(Canvas canvas, Size size) {
    final w = cfg.tableW.toDouble(), h = cfg.tableH.toDouble();
    final v = WorldView.fit(size, -_rail.toDouble(), -_rail.toDouble(), w + _rail, h + _rail, pad: 8);
    final k = v.k;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(v.p(-_rail, h + _rail), v.p(w + _rail, -_rail)),
        Radius.circular(_rail * k * 0.6),
      ),
      Paint()..color = const Color(Tokens.colorShopsBar),
    );
    canvas.drawRect(Rect.fromPoints(v.p(0, h), v.p(w, 0)), Paint()..color = const Color(Tokens.colorCarDetailCanopy));
    canvas.drawLine(
      v.p(0, h / 4),
      v.p(w, h / 4),
      Paint()
        ..color = const Color(Tokens.colorUiControlHalf)
        ..strokeWidth = 1,
    );
    for (var p = 0; p < 6; p++) {
      final pk = cfg.pocket(p);
      canvas.drawCircle(v.p(pk.x, pk.y), pk.r * k, Paint()..color = const Color(Tokens.colorCarDetailLimoPillar));
    }
    final a = aim;
    final cue = balls[0];
    if (a != null) {
      final e = _guideEnd(a.x - cue.x.toDouble(), a.y - cue.y.toDouble());
      final line = Paint()
        ..color = const Color(Tokens.colorUiControlWheel)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      dashedLine(canvas, v.p(cue.x, cue.y), v.p(e.dx, e.dy), line);
      canvas.drawCircle(v.p(e.dx, e.dy), cfg.ballR * k, line);
    }
    final shadow = Paint()
      ..color = const Color(Tokens.colorUiLabelShadow)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < balls.length; i++) {
      final b = balls[i];
      if (!b.on) continue;
      final c = v.p(b.x, b.y);
      final r = math.max(cfg.ballR * k, 0.5);
      canvas.drawCircle(c, r, Paint()..color = Color(_ballColors[i <= 8 ? i : i - 8]));
      if (i >= 9) {
        canvas.save();
        canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
        final white = Paint()..color = Color(_ballColors[0]);
        canvas.drawRect(Rect.fromLTWH(c.dx - r, c.dy - r, 2 * r, r * 0.55), white);
        canvas.drawRect(Rect.fromLTWH(c.dx - r, c.dy + r * 0.45, 2 * r, r * 0.55), white);
        canvas.restore();
      }
      canvas.drawCircle(c, r, shadow);
    }
    if (a != null) {
      // The cue stick behind the ball, pulled back with the power.
      final dx = (a.x - cue.x).toDouble(), dy = (a.y - cue.y).toDouble();
      final l = math.max(math.sqrt(dx * dx + dy * dy), 1.0);
      final u = Offset(dx / l, -dy / l);
      final back = (cfg.ballR * 1.6 + a.power * 120) * k;
      final len = w * 0.9 * k;
      final p0 = v.p(cue.x, cue.y) - u * back;
      canvas.drawLine(
        p0,
        p0 - u * len,
        Paint()
          ..color = const Color(Tokens.colorCarDetailAwningA)
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(3, cfg.ballR * 0.5 * k),
      );
    }
  }

  /// First ball the cue would touch along the aim (straight, no cushions), as a ghost-ball centre.
  Offset _guideEnd(double dx, double dy) {
    final c = balls[0];
    final l = math.sqrt(dx * dx + dy * dy);
    final ux = l == 0 ? 0.0 : dx / l, uy = l == 0 ? 0.0 : dy / l;
    var best = double.infinity;
    final rr = 2.0 * cfg.ballR;
    for (var i = 1; i < balls.length; i++) {
      final b = balls[i];
      if (!b.on) continue;
      final ox = (b.x - c.x).toDouble(), oy = (b.y - c.y).toDouble();
      final along = ox * ux + oy * uy;
      final perp2 = ox * ox + oy * oy - along * along;
      if (along <= 0 || perp2 > rr * rr) continue;
      best = math.min(best, along - math.sqrt(rr * rr - perp2));
    }
    final r = cfg.ballR;
    final wall = math.min(
      ux > 0
          ? (cfg.tableW - r - c.x) / ux
          : ux < 0
          ? (r - c.x) / ux
          : double.infinity,
      uy > 0
          ? (cfg.tableH - r - c.y) / uy
          : uy < 0
          ? (r - c.y) / uy
          : double.infinity,
    );
    final d = math.max(0.0, math.min(best, wall));
    return Offset(c.x + ux * d, c.y + uy * d);
  }

  @override
  bool shouldRepaint(_TablePainter old) => old.balls != balls || old.aim != aim;
}
