import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:mg_api/mg_api.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Swipe up: at least this many logical px upwards, faster than [swipeMs] (spec "UI").
const swipePx = 40.0, swipeMs = 300;

/// How long the jumper shows a trip and a rating word stays (UI only).
const _tripMs = 450, _toastMs = 600;

/// Game clock for timing: ms of unpaused time since start. [frame] once per frame with the ticker
/// time; [at] reads it at an input's time (frame time + real time since that frame), so a touch
/// between two frames gets its own time (port of web/src/minigames/clock.ts).
class GameClock {
  GameClock(this._paused);

  final bool Function() _paused;
  final Stopwatch _real = Stopwatch()..start();
  double _ms = 0;
  double _last = -1;
  double _realAtFrame = 0;

  double get now => _ms;
  double get _realMs => _real.elapsedMicroseconds / 1000;

  double frame(double tickerMs) {
    if (_paused()) {
      _last = -1;
    } else {
      if (_last >= 0) _ms += math.max(0, tickerMs - _last);
      _last = tickerMs;
      _realAtFrame = _realMs;
    }
    return _ms;
  }

  double at() => _last >= 0 && !_paused() ? _ms + math.max(0, _realMs - _realAtFrame) : _ms;
}

/// Double Dutch, specs/minigames/doubledutch.md: tap on the beat, swipe up on a trick beat.
class DoubledutchGame implements Minigame {
  const DoubledutchGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.doubledutch]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.doubledutch;
    return MinigameShell(
      id: MinigameId.doubledutch,
      env: env,
      rules: const [MessageKey.doubledutchRules1, MessageKey.doubledutchRules2, MessageKey.doubledutchRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _DoubledutchBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _Down {
  _Down(this.pointer, this.y, this.at);
  final int pointer;
  final double y;

  /// Game time of the touch-down (the input's time).
  final double at;
  bool sent = false;
}

class _DoubledutchBody extends StatefulWidget {
  const _DoubledutchBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_DoubledutchBody> createState() => _DoubledutchBodyState();
}

class _DoubledutchBodyState extends State<_DoubledutchBody> with SingleTickerProviderStateMixin {
  final DoubledutchRules _rules = DoubledutchRules();
  late final TuningMinigamesDoubledutch _tm = widget.env.tuning.minigames.doubledutch;
  late final DoubledutchConfig _cfg = DoubledutchConfig.fromTuning(_tm, widget.ctx.difficulty);
  late DoubledutchState _s = _rules.start(_cfg, widget.ctx.seed);
  late final List<int> _times = _cfg.beatTimes(_tm.leadInMs);
  late final GameClock _clock = GameClock(() => widget.shell.paused);
  late final Ticker _ticker = createTicker((e) => _frame(e.inMicroseconds / 1000));
  bool _finished = false;
  double _tripAt = -1e9;
  String? _toast;
  double _toastAt = -1e9;
  _Down? _down;

  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  @override
  void initState() {
    super.initState();
    widget.hooks.onTimeout = () => _play(const DoubledutchAction.timeout());
    _ticker.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _status());
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _status() {
    if (mounted) widget.shell.status(t(MessageKey.scoreValue, {'score': _s.score}));
  }

  void _play(DoubledutchAction a) {
    if (_finished || _s.over) return;
    final before = _s;
    setState(() {
      _s = _rules.apply(_s, a);
      if (a.by == 'player') {
        final tripped = _s.trips > before.trips;
        if (tripped) _tripAt = _clock.now;
        final word = tripped
            ? t(MessageKey.ddMiss)
            : _s.perfect > before.perfect
            ? t(MessageKey.ddPerfect)
            : _s.good > before.good
            ? t(MessageKey.ddGood)
            : t(MessageKey.ddOk);
        _toast = _s.combo >= 2 && !tripped ? '$word · ${t(MessageKey.ddCombo, {'n': _s.combo})}' : word;
        _toastAt = _clock.now;
      }
    });
    _status();
    final r = _rules.result(_s);
    if (r != null) {
      _finished = true;
      widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
    }
  }

  void _frame(double tickerMs) {
    final ms = _clock.frame(tickerMs);
    if (_finished || widget.shell.paused || _s.over) return;
    final d = _down;
    // A held finger that has not swiped up within swipeMs is a tap (its time is the touch).
    if (d != null && !d.sent) {
      if (ms - d.at >= swipeMs) {
        _send(0);
      } else if (d.at >= _times[_s.next] - _cfg.okMs) {
        // An undecided touch belongs to beat `next`: no miss yet.
        setState(() {});
        return;
      }
    }
    // No input until ok_ms after the beat: a miss.
    if (!_s.over && ms > _times[_s.next] + _cfg.okMs) _play(const DoubledutchAction.miss());
    if (mounted) setState(() {});
  }

  void _send(int input) {
    final d = _down;
    if (d == null || d.sent) return;
    d.sent = true;
    final err = inputErr(_times, _s.next, d.at, _cfg.okMs);
    if (err != null) _play(DoubledutchAction.hit(input, err));
  }

  void _onDown(PointerDownEvent e) {
    if (widget.shell.paused || _finished || _down != null) return;
    _down = _Down(e.pointer, e.localPosition.dy, _clock.at());
  }

  bool _swiped(_Down d, double y) => d.y - y >= swipePx && _clock.at() - d.at < swipeMs;

  void _onMove(PointerMoveEvent e) {
    final d = _down;
    if (d == null || e.pointer != d.pointer) return;
    if (_swiped(d, e.localPosition.dy)) _send(1);
  }

  void _onUp(PointerUpEvent e) {
    final d = _down;
    if (d == null || e.pointer != d.pointer) return;
    _send(_swiped(d, e.localPosition.dy) ? 1 : 0);
    _down = null;
  }

  void _onCancel(PointerCancelEvent e) {
    if (_down?.pointer == e.pointer) _down = null;
  }

  @override
  Widget build(BuildContext context) {
    final now = _clock.now;
    final toast = now - _toastAt < _toastMs ? _toast : null;
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceMd),
      child: Column(
        children: [
          Text(
            t(MessageKey.ddTrips, {'n': _s.trips, 'max': _cfg.maxTrips}),
            style: const TextStyle(color: Color(Tokens.colorUiTextMuted)),
          ),
          const SizedBox(height: Tokens.spaceSm),
          Expanded(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onDown,
              onPointerMove: _onMove,
              onPointerUp: _onUp,
              onPointerCancel: _onCancel,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    key: const ValueKey('doubledutch-field'),
                    painter: _RopesPainter(_s, _times, now, now - _tripAt < _tripMs),
                  ),
                  if (toast != null)
                    Align(
                      alignment: const Alignment(0, -0.85),
                      child: Text(
                        toast,
                        style: const TextStyle(
                          color: Color(Tokens.colorDoubledutchRing),
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RopesPainter extends CustomPainter {
  _RopesPainter(this.s, this.times, this.ms, this.tripped);

  final DoubledutchState s;
  final List<int> times;
  final double ms;
  final bool tripped;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(Tokens.colorStickballStreet));
    // Rope phase: 0 at the previous beat, 1 at the next one (one turn per gap).
    final i = math.min(s.next, times.length - 1);
    final t1 = times[i].toDouble();
    final t0 = i > 0 ? times[i - 1].toDouble() : t1 - (times.length > 1 ? times[1] - times[0] : 500);
    final ph = ((ms - t0) / math.max(1, t1 - t0)).clamp(0.0, 1.0);
    final x0 = w * 0.12, x1 = w * 0.88, ground = h * 0.62, top = h * 0.2, hand = h * 0.42;
    void rope(double phase, int color) {
      // The rope's lowest point is on the ground at the beat; it swings over the top at half way.
      final y = ground - (ground - top) * (0.5 - 0.5 * math.cos(2 * math.pi * phase));
      final path = Path()
        ..moveTo(x0, hand)
        ..quadraticBezierTo(w / 2, 2 * y - hand, x1, hand);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = Color(color),
      );
    }

    rope(ph, Tokens.colorDoubledutchRopeA);
    rope(ph + 0.5, Tokens.colorDoubledutchRopeB);
    final curb = Paint()..color = const Color(Tokens.colorStickballCurb);
    canvas.drawCircle(Offset(x0, hand), 10, curb);
    canvas.drawCircle(Offset(x1, hand), 10, curb);
    // Jumper: in the air around the beat, red after a trip.
    final near = math.min((ms - t1).abs(), (ms - t0).abs());
    final lift = math.max(0.0, 1 - near / 180) * h * 0.06;
    final jc = Color(tripped ? Tokens.colorDoubledutchMiss : Tokens.colorDoubledutchJumper);
    canvas.drawCircle(Offset(w / 2, ground - h * 0.12 - lift), math.min(w, h) * 0.045, Paint()..color = jc);
    canvas.drawLine(
      Offset(w / 2, ground - h * 0.08 - lift),
      Offset(w / 2, ground - lift),
      Paint()
        ..color = jc
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
    // Approaching beat: a ring that closes on the target at the beat time.
    final cy = h * 0.84, r0 = math.min(w, h) * 0.08;
    Paint ring(int color, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = Color(color);
    canvas.drawCircle(Offset(w / 2, cy), r0, ring(Tokens.colorDoubledutchRing, 3));
    if (!s.over) {
      final left = times[s.next] - ms;
      final trick = s.kinds[s.next] == 1;
      final col = trick ? Tokens.colorDoubledutchTrick : Tokens.colorDoubledutchRing;
      final r = r0 * (1 + math.max(0, left) / 400);
      if (left < 1200) canvas.drawCircle(Offset(w / 2, cy), r, ring(col, 4));
      if (trick) {
        final arrow = Path()
          ..moveTo(w / 2, cy - r0 * 0.6)
          ..lineTo(w / 2 + r0 * 0.45, cy + r0 * 0.3)
          ..lineTo(w / 2 - r0 * 0.45, cy + r0 * 0.3)
          ..close();
        canvas.drawPath(arrow, Paint()..color = Color(col));
      }
    }
  }

  @override
  bool shouldRepaint(_RopesPainter old) => true;
}
