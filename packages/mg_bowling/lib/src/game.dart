import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Gutter drawn beside the lane (u).
const _gutter = 14000;

/// Lane view: x at one scale; y split into a magnified pin deck (top) and a squeezed approach.
class _LaneView {
  factory _LaneView(Size s, BowlingConfig c) {
    final k = math.min((s.width - 16) / (c.laneW + 2 * _gutter), (s.height * 0.4) / (c.deckY1 - c.deckY0));
    final deckFrom = (c.deckY0 - 30000).toDouble(), deckTo = c.deckY1.toDouble();
    const top = 12.0;
    return _LaneView._(
      k,
      (s.width - c.laneW * k) / 2,
      top,
      top + (deckTo - deckFrom) * k * 0.75,
      s.height - c.ballR * k * 3,
      deckFrom,
      deckTo,
    );
  }

  _LaneView._(this.k, this.ox, this.top, this.seam, this.foul, this.deckFrom, this.deckTo);

  final double k, ox, top, seam, foul, deckFrom, deckTo;

  double x(num v) => ox + v * k;
  double y(num v) =>
      v >= deckFrom ? seam - (v - deckFrom) / (deckTo - deckFrom) * (seam - top) : foul - v / deckFrom * (foul - seam);
  Offset p(num px, num py) => Offset(x(px), y(py));
}

typedef _Disc = ({int x, int y, bool on});
typedef _Shown = ({_Disc ball, List<_Disc> pins});

/// Bowling (specs/minigames/bowling.md): slide the ball sideways along the line, then swipe up
/// towards the pins; ten frames alone on the score.
class BowlingGame implements Minigame {
  const BowlingGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.bowling]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.bowling;
    return MinigameShell(
      id: MinigameId.bowling,
      env: env,
      rules: const [MessageKey.bowlingRules1, MessageKey.bowlingRules2, MessageKey.bowlingRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _BowlingBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _BowlingBody extends StatefulWidget {
  const _BowlingBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_BowlingBody> createState() => _BowlingBodyState();
}

/// Frame sheet text: X for a strike, "a /" for a spare, the tenth frame roll by roll.
String frameSheet(List<int> rolls) {
  final cells = <String>[];
  var i = 0;
  for (var f = 1; f <= 10 && i < rolls.length; f++) {
    final a = rolls[i];
    final b = i + 1 < rolls.length ? rolls[i + 1] : null;
    if (f < 10) {
      cells.add(
        a == 10
            ? 'X'
            : b == null
            ? '$a'
            : a + b == 10
            ? '$a /'
            : '$a $b',
      );
      i += a == 10 ? 1 : 2;
    } else {
      cells.add([for (final r in rolls.sublist(i)) r == 10 ? 'X' : '$r'].join(' '));
      i = rolls.length;
    }
  }
  return cells.join(' · ');
}

class _BowlingBodyState extends State<_BowlingBody> with TickerProviderStateMixin {
  final BowlingRules _rules = BowlingRules();
  late final TuningMinigamesBowling _tm = widget.env.tuning.minigames.bowling;
  late final BowlingConfig _cfg = BowlingConfig.fromTuning(_tm, widget.ctx.difficulty);
  late BowlingState _s = _rules.start(_cfg, widget.ctx.seed);
  late final FramePlayback _playback = FramePlayback(this, () => widget.shell.paused);
  late final PausableTimer _timer = PausableTimer(() => widget.shell.paused);
  final Toast _toast = Toast();
  late int _x = _cfg.laneW ~/ 2;
  late _Shown _shown = _rest();
  bool _busy = false;
  String _mode = '';
  int _slideFrom = 0;
  Offset? _dragStart;
  ({int aim, int power})? _aim;
  Size _size = Size.zero;

  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  _Shown _rest() => (
    ball: (x: _x, y: 0, on: true),
    pins: [for (var i = 0; i < 10; i++) (x: _cfg.pinSpot(i).x, y: _cfg.pinSpot(i).y, on: _s.standing[i])],
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
    if (mounted) widget.shell.status(t(MessageKey.scoreValue, {'score': _s.score}));
  }

  bool get _canDrag => !widget.shell.paused && !_busy && !_s.over;

  void _panStart(DragStartDetails d) {
    if (!_canDrag) return;
    _dragStart = d.localPosition;
    _mode = '';
  }

  void _panUpdate(DragUpdateDetails d) {
    final start = _dragStart;
    if (start == null) return;
    final delta = d.localPosition - start;
    final v = _LaneView(_size, _cfg);
    if (_mode == '') {
      if (delta.distance < 12) return;
      _mode = delta.dx.abs() > delta.dy.abs() ? 'slide' : 'throw';
      _slideFrom = _x;
    }
    setState(() {
      if (_mode == 'slide') {
        _x = (_slideFrom + delta.dx / v.k).round().clamp(_cfg.ballR, _cfg.laneW - _cfg.ballR);
        _shown = _rest();
        _aim = null;
      } else {
        final p = delta.dy < -12 ? dragPower(0, delta.dy, _size.height * 0.55) : 0;
        _aim = p > 0 ? (aim: (_x + delta.dx / v.k).round(), power: p) : null;
      }
    });
  }

  void _panEnd(DragEndDetails _) {
    final a = _aim, m = _mode;
    _dragStart = null;
    _mode = '';
    setState(() => _aim = null);
    if (m != 'throw' || a == null || !_canDrag) return;
    _roll(BowlingAction.roll(_x, a.aim, a.power));
  }

  void _roll(BowlingAction a) {
    if (!_rules.legal(_s, a)) return;
    setState(() => _busy = true);
    final vel = _rules.velocity(_s, a);
    final frames = <_Shown>[];
    var n = 0;
    simulateRoll(
      _cfg,
      _s.standing,
      a.x,
      (vx: vel.vx, vy: vel.vy),
      onStep: (bodies) {
        if (++n % _tm.stepsPerFrame != 0) return;
        final d = [for (final b in bodies) (x: b.x, y: b.y, on: b.on)];
        frames.add((ball: d.first, pins: d.sublist(1)));
      },
    );
    _playback.play<_Shown>(frames, (f) => setState(() => _shown = f), () {
      if (!mounted) return;
      final before = _s;
      setState(() => _s = _rules.apply(_s, a));
      _status();
      final k = _s.lastKnocked;
      final up = before.standing.where((s) => s).length;
      if (k == 10 && up == 10) {
        _toast.show(t(MessageKey.bowlingStrike));
      } else if (k > 0 && k == up) {
        _toast.show(t(MessageKey.bowlingSpare));
      }
      final r = _rules.result(_s);
      if (r != null) {
        widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
        return;
      }
      _timer.later(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _busy = false;
            _shown = _rest();
          });
        }
      });
    });
  }

  void _timeout() {
    if (_s.over) return;
    _playback.cancel();
    _timer.cancel();
    setState(() => _s = _rules.apply(_s, const BowlingAction.timeout()));
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
          Text(frameSheet(_s.rolls), style: const TextStyle(color: Color(Tokens.colorUiText))),
          Text(_s.over ? '' : t(MessageKey.bowlingFrame, {'frame': _s.frame}), style: muted),
          const SizedBox(height: Tokens.spaceXs),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                _size = c.biggest;
                return Stack(
                  children: [
                    GestureDetector(
                      key: const ValueKey('lane'),
                      behavior: HitTestBehavior.opaque,
                      onPanStart: _panStart,
                      onPanUpdate: _panUpdate,
                      onPanEnd: _panEnd,
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _LanePainter(cfg: _cfg, shown: _shown, x: _x, aim: _busy ? null : _aim),
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

class _LanePainter extends CustomPainter {
  _LanePainter({required this.cfg, required this.shown, required this.x, required this.aim});

  final BowlingConfig cfg;
  final _Shown shown;
  final int x;
  final ({int aim, int power})? aim;

  @override
  void paint(Canvas canvas, Size size) {
    final v = _LaneView(size, cfg);
    final k = v.k;
    final bottom = v.foul + cfg.ballR * k * 2;
    canvas.drawRect(
      Rect.fromLTRB(v.x(-_gutter), v.top, v.x(cfg.laneW + _gutter), bottom),
      Paint()..color = const Color(Tokens.colorWorldDayAsphalt),
    );
    canvas.drawRect(
      Rect.fromLTRB(v.x(0), v.top, v.x(cfg.laneW), bottom),
      Paint()..color = Color(Tokens.colorWorldDayFacades[5]),
    );
    canvas.drawRect(
      Rect.fromLTRB(v.x(0), v.top, v.x(cfg.laneW), v.y(cfg.deckY0)),
      Paint()..color = Color(Tokens.colorWorldDayFacades[0]),
    );
    canvas.drawLine(
      Offset(v.x(0), v.foul),
      Offset(v.x(cfg.laneW), v.foul),
      Paint()
        ..color = const Color(Tokens.colorUiControlHalf)
        ..strokeWidth = 1,
    );
    // Arrows on the approach as aiming marks.
    final arrow = Paint()..color = const Color(Tokens.colorShopsBar);
    for (var j = 1; j < 7; j++) {
      final ax = v.x(cfg.laneW * j / 7), ay = (v.seam + v.foul) / 2 + (j - 3.5).abs() * 6;
      canvas.drawPath(
        Path()
          ..moveTo(ax, ay - 8)
          ..lineTo(ax - 4, ay + 4)
          ..lineTo(ax + 4, ay + 4)
          ..close(),
        arrow,
      );
    }
    final a = aim;
    if (a != null) {
      dashedLine(
        canvas,
        v.p(x, 0),
        v.p(a.aim, cfg.headY),
        Paint()
          ..color = const Color(Tokens.colorUiControlWheel)
          ..strokeWidth = 2,
      );
    }
    final edge = Paint()
      ..color = const Color(Tokens.colorUiLabelShadow)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final p in shown.pins) {
      if (!p.on) continue;
      final c = v.p(p.x, p.y);
      canvas.drawCircle(c, cfg.pinR * k * 1.15, Paint()..color = const Color(Tokens.colorWorldDayMarking));
      canvas.drawCircle(c, cfg.pinR * k * 1.15, edge);
      canvas.drawCircle(c, cfg.pinR * k * 0.4, Paint()..color = const Color(Tokens.colorBoothBody));
    }
    final b = shown.ball;
    if (b.on) {
      final r = math.max(5.0, cfg.ballR * k * (b.y >= v.deckFrom ? 1 : 0.9));
      final c = v.p(b.x, b.y);
      canvas.drawCircle(c, r, Paint()..color = const Color(Tokens.colorPoliceBody));
      canvas.drawCircle(c, r, edge);
    }
  }

  @override
  bool shouldRepaint(_LanePainter old) => old.shown != shown || old.x != x || old.aim != aim;
}
