import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Lane layout in board millimetres (y up, rings centred at 0, 0); same as the web client.
class LaneLayout {
  factory LaneLayout.of(KoulenaConfig c) {
    final outer = c.ringR.isEmpty ? 0 : c.ringR.last;
    var halfW = outer.toDouble(), top = outer.toDouble();
    for (var i = 0; i + 1 < c.pockets.length; i += 2) {
      halfW = math.max(halfW, (c.pockets[i].abs() + c.pocketR).toDouble());
      top = math.max(top, (c.pockets[i + 1] + c.pocketR).toDouble());
    }
    final ballR = math.max(c.pocketR * 0.7, 1.0);
    final ballY = -outer * 3.5;
    return LaneLayout._(halfW * 1.1, top * 1.12, ballY, ballY - ballR * 3, ballR, -outer.toDouble());
  }

  const LaneLayout._(this.halfW, this.top, this.ballY, this.bottom, this.ballR, this.aimOriginY);

  final double halfW, top, ballY, bottom, ballR;

  /// A straight-up swipe starts aiming here (the board's lower edge).
  final double aimOriginY;

  double get width => 2 * halfW;
  double get height => top - bottom;

  /// Swipe in logical px (dx right, dy down) → integer aim point in mm on the board.
  ({int x, int y}) aim(double dx, double dy, double mmPerPx) =>
      (x: (dx * mmPerPx).round(), y: (aimOriginY - dy * mmPerPx).round());
}

const _tween = Duration(milliseconds: 450);
const _show = Duration(milliseconds: 700);
const _minSwipePx = 12.0;

/// Koulená (boardwalk roll): flick the ball up the lane into the rings.
class KoulenaGame implements Minigame {
  const KoulenaGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.koulena]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.koulena;
    return MinigameShell(
      id: MinigameId.koulena,
      env: env,
      rules: const [MessageKey.koulenaRules1, MessageKey.koulenaRules2, MessageKey.koulenaRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _KoulenaBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _KoulenaBody extends StatefulWidget {
  const _KoulenaBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_KoulenaBody> createState() => _KoulenaBodyState();
}

class _KoulenaBodyState extends State<_KoulenaBody> with SingleTickerProviderStateMixin {
  final KoulenaRules _rules = KoulenaRules();
  late final KoulenaConfig _cfg = KoulenaConfig.fromTuning(widget.env.tuning.minigames.koulena);
  late final LaneLayout _lay = LaneLayout.of(_cfg);
  late KoulenaState _s = _rules.start(_cfg, widget.ctx.seed);
  late final AnimationController _roll = AnimationController(vsync: this, duration: _tween)
    ..addStatusListener((st) {
      if (st == AnimationStatus.completed) _landed();
    });
  bool _rolling = false;
  bool _showHit = false;
  Offset? _dragStart;
  Offset _drag = Offset.zero;
  Timer? _toast;

  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  @override
  void initState() {
    super.initState();
    widget.hooks.onTimeout = _timeout;
    WidgetsBinding.instance.addPostFrameCallback((_) => _status());
  }

  @override
  void dispose() {
    _roll.dispose();
    _toast?.cancel();
    super.dispose();
  }

  void _status() {
    if (mounted) widget.shell.status(t(MessageKey.scoreValue, {'score': _s.score}));
  }

  bool get _blocked => widget.shell.paused || _s.over || _rolling;

  void _panStart(DragStartDetails d) {
    if (_blocked) return;
    setState(() {
      _dragStart = d.localPosition;
      _drag = Offset.zero;
    });
  }

  void _panUpdate(DragUpdateDetails d) {
    final start = _dragStart;
    if (start != null) setState(() => _drag = d.localPosition - start);
  }

  void _panEnd(DragEndDetails _) {
    if (_dragStart == null) return;
    final swipe = _drag;
    setState(() => _dragStart = null);
    if (_blocked || swipe.dy > -_minSwipePx) return;
    final aim = _lay.aim(swipe.dx, swipe.dy, widget.env.tuning.minigames.koulena.flickMmPerPx);
    setState(() {
      _s = _rules.apply(_s, KoulenaAction(aim.x, aim.y, widget.ctx.difficulty));
      _rolling = true;
      _showHit = false;
    });
    _roll.forward(from: 0);
  }

  void _landed() {
    if (!mounted) return;
    setState(() => _showHit = true);
    _status();
    _toast?.cancel();
    void next() {
      if (!mounted) return;
      if (widget.shell.paused) {
        _toast = Timer(const Duration(milliseconds: 200), next);
        return;
      }
      final r = _rules.result(_s);
      if (r != null) {
        widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
        return;
      }
      setState(() {
        _rolling = false;
        _roll.value = 0;
      });
    }

    _toast = Timer(_show, next);
  }

  void _timeout() {
    if (_s.over) return;
    _toast?.cancel();
    _roll.stop();
    setState(() => _s = _rules.apply(_s, const KoulenaAction.timeout()));
    _status();
    final r = _rules.result(_s)!;
    widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
  }

  @override
  Widget build(BuildContext context) {
    final hit = _s.lastHit;
    final series = math.min(_s.series, _cfg.series);
    final shown = _s.over ? _cfg.balls : _s.ball + 1;
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceMd),
      child: Column(
        children: [
          Text(
            t(MessageKey.koulenaSeries, {'series': series, 'ball': shown}),
            style: const TextStyle(color: Color(Tokens.colorUiTextMuted)),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: _panStart,
              onPanUpdate: _panUpdate,
              onPanEnd: _panEnd,
              child: AnimatedBuilder(
                animation: _roll,
                builder: (context, _) => CustomPaint(
                  size: Size.infinite,
                  painter: _LanePainter(
                    cfg: _cfg,
                    lay: _lay,
                    roll: _rolling ? Curves.easeOut.transform(_roll.value) : 0,
                    hit: hit,
                    showHit: _showHit && _rolling,
                    guide: _dragStart != null && _drag.dy < -_minSwipePx
                        ? _lay.aim(_drag.dx, _drag.dy, widget.env.tuning.minigames.koulena.flickMmPerPx)
                        : null,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 32,
            child: Text(
              _showHit && _rolling ? '${hit.points}' : '',
              style: TextStyle(
                color: Color(hit.points > 0 ? Tokens.colorBrandAccent : Tokens.colorUiText),
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lane, rings, pockets, aim guide and ball; mm → px with y flipped (same layout as the web client).
class _LanePainter extends CustomPainter {
  _LanePainter({
    required this.cfg,
    required this.lay,
    required this.roll,
    required this.hit,
    required this.showHit,
    required this.guide,
  });

  final KoulenaConfig cfg;
  final LaneLayout lay;
  final double roll;
  final KoulenaHit hit;
  final bool showHit;
  final ({int x, int y})? guide;

  @override
  void paint(Canvas canvas, Size size) {
    final k = math.min(size.width / lay.width, size.height / lay.height);
    final ox = (size.width - lay.width * k) / 2, oy = (size.height - lay.height * k) / 2;
    Offset p(num x, num y) => Offset(ox + (x + lay.halfW) * k, oy + (lay.top - y) * k);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(p(-lay.halfW, lay.top), p(lay.halfW, lay.bottom)),
        Radius.circular(lay.ballR * k),
      ),
      Paint()..color = Color(Tokens.colorWorldDayFacades[5]),
    );
    final edge = Paint()
      ..color = const Color(Tokens.colorWorldDayBridgeEdge)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 * k;
    for (var i = cfg.ringR.length - 1; i >= 0; i--) {
      final r = cfg.ringR[i] * k;
      canvas.drawCircle(p(0, 0), r, Paint()..color = Color(Tokens.colorWorldDayFacades[i.isOdd ? 0 : 1]));
      canvas.drawCircle(p(0, 0), r, edge);
      final inner = i > 0 ? cfg.ringR[i - 1] : 0;
      _label(
        canvas,
        '${i < cfg.ringPoints.length ? cfg.ringPoints[i] : 0}',
        p(0, (inner + cfg.ringR[i]) / 2),
        (cfg.ringR[i] - inner) * 0.5 * k,
        Tokens.colorUiText,
      );
    }
    for (var i = 0; i + 1 < cfg.pockets.length; i += 2) {
      final c = p(cfg.pockets[i], cfg.pockets[i + 1]);
      canvas.drawCircle(c, cfg.pocketR * k, Paint()..color = const Color(Tokens.colorWorldDayBridgeEdge));
      canvas.drawCircle(
        c,
        cfg.pocketR * k,
        Paint()
          ..color = const Color(Tokens.colorBrandAccent)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6 * k,
      );
      _label(canvas, '${cfg.pocketPoints}', c, cfg.pocketR * 0.7 * k, Tokens.colorBrandAccent);
    }
    final g = guide;
    if (g != null) {
      canvas.drawLine(
        p(0, lay.ballY),
        p(g.x, g.y),
        Paint()
          ..color = const Color(Tokens.colorUiControlHint)
          ..strokeWidth = 8 * k
          ..strokeCap = StrokeCap.round,
      );
    }
    if (showHit) {
      canvas.drawCircle(
        p(hit.x, hit.y),
        lay.ballR * 0.45 * k,
        Paint()..color = const Color(Tokens.colorUiControlBrake),
      );
    }
    final bx = hit.x * roll, by = lay.ballY + (hit.y - lay.ballY) * roll;
    final br = lay.ballR * (1 - 0.3 * roll) * k;
    canvas.drawCircle(p(bx, by), br, Paint()..color = Color(Tokens.colorWorldDayFacades[4]));
    canvas.drawCircle(
      p(bx, by),
      br,
      Paint()
        ..color = const Color(Tokens.colorUiText)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 * k,
    );
  }

  void _label(Canvas canvas, String text, Offset at, double size, int color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: Color(color), fontSize: size, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_LanePainter old) =>
      old.roll != roll || old.hit != hit || old.showHit != showHit || old.guide != guide;
}
