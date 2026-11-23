import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_gen/shared_gen.dart';

/// Canvas helpers for the batch C minigames (kulecnik, bowling, minigolf, had, cihly, krtek,
/// hokej), same as the web client's canvas.ts: a world rectangle (x right, y up, game units)
/// fitted into a widget, a fixed-rate tick loop and playback of recorded simulation frames.

/// Where the world rectangle [x0, x1] × [y0, y1] sits in a box of [size] (logical px, y flipped).
class WorldView {
  factory WorldView.fit(Size size, double x0, double y0, double x1, double y1, {double pad = 0}) {
    final k = math.max(1e-9, math.min((size.width - 2 * pad) / (x1 - x0), (size.height - 2 * pad) / (y1 - y0)));
    return WorldView._(k, (size.width - (x1 - x0) * k) / 2, (size.height - (y1 - y0) * k) / 2, x0, y1);
  }

  const WorldView._(this.k, this.ox, this.oy, this.x0, this.y1);

  /// Logical px per world unit.
  final double k;
  final double ox, oy, x0, y1;

  double sx(num x) => ox + (x - x0) * k;
  double sy(num y) => oy + (y1 - y) * k;
  Offset p(num x, num y) => Offset(sx(x), sy(y));

  /// Screen point → world coordinates (not rounded).
  ({double x, double y}) toWorld(Offset o) => (x: x0 + (o.dx - ox) / k, y: y1 - (o.dy - oy) / k);
}

/// Drag length → power 1–100 ([full] px = 100); below [minPx] there is no shot (0).
int dragPower(double dx, double dy, double full, {double minPx = 10}) {
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < minPx) return 0;
  return math.max(1, math.min(100, (len / full * 100).round()));
}

/// Longest real-time step fed to a simulation per frame (app switches, hiccups).
const maxFrameMs = 250;

/// A frame loop: while [running] and not [paused], [ticks] gets the whole ticks at [hz] elapsed
/// since the last frame; [frame] runs every frame (redraw).
class TickLoop {
  TickLoop(
    TickerProvider vsync, {
    required this.hz,
    required this.paused,
    required this.running,
    required this.ticks,
    required this.frame,
  }) {
    _ticker = vsync.createTicker(_onTick)..start();
  }

  final int hz;
  final bool Function() paused, running;
  final void Function(int n) ticks;
  final VoidCallback frame;
  late final Ticker _ticker;
  Duration? _last;
  double _acc = 0;

  void _onTick(Duration now) {
    if (paused() || !running()) {
      _last = null;
    } else {
      final last = _last;
      if (last != null) _acc += math.min((now - last).inMicroseconds / 1000, maxFrameMs.toDouble());
      _last = now;
      final n = (_acc * hz / 1000).floor();
      if (n > 0) {
        _acc -= n * 1000 / hz;
        ticks(n);
      }
    }
    frame();
  }

  void dispose() => _ticker.dispose();
}

/// Plays recorded simulation frames, one per display frame, waiting while [paused].
class FramePlayback {
  FramePlayback(this._vsync, this.paused);

  final TickerProvider _vsync;
  final bool Function() paused;
  Ticker? _ticker;

  bool get playing => _ticker != null;

  void play<F>(List<F> frames, void Function(F f) show, VoidCallback done) {
    cancel();
    var i = 0;
    _ticker = _vsync.createTicker((_) {
      if (paused()) return;
      if (i >= frames.length) {
        cancel();
        done();
        return;
      }
      show(frames[i++]);
    })..start();
  }

  void cancel() {
    _ticker?.dispose();
    _ticker = null;
  }
}

/// Runs [f] after [delay], waiting while [paused]; one pending call at a time.
class PausableTimer {
  PausableTimer(this.paused);

  final bool Function() paused;
  Timer? _t;

  void later(Duration delay, VoidCallback f) {
    _t?.cancel();
    _t = Timer(delay, () {
      if (paused()) {
        later(const Duration(milliseconds: 200), f);
        return;
      }
      _t = null;
      f();
    });
  }

  void cancel() {
    _t?.cancel();
    _t = null;
  }
}

/// A short floating message (foul, strike, goal…): [text] is null when nothing shows.
class Toast extends ChangeNotifier {
  String? text;
  Timer? _t;

  void show(String t, {int ms = 1200}) {
    text = t;
    _t?.cancel();
    _t = Timer(Duration(milliseconds: ms), () {
      text = null;
      notifyListeners();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }
}

/// Shows the [toast] text over the game body while it lasts.
class ToastView extends StatelessWidget {
  const ToastView({super.key, required this.toast});

  final Toast toast;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: toast,
    builder: (context, _) {
      final text = toast.text;
      if (text == null) return const SizedBox.shrink();
      return Align(
        alignment: const Alignment(0, -0.6),
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(Tokens.colorUiPill),
              borderRadius: BorderRadius.circular(Tokens.spaceMd),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceMd, vertical: Tokens.spaceSm),
              child: Text(
                text,
                style: const TextStyle(color: Color(Tokens.colorUiText), fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Shot power 0–100 as a thin bar under the table.
class PowerBar extends StatelessWidget {
  const PowerBar({super.key, required this.power});

  final int power;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 8,
    child: LayoutBuilder(
      builder: (context, c) => Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: const Color(Tokens.colorUiControlHalf))),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: c.maxWidth * power.clamp(0, 100) / 100,
            child: const ColoredBox(color: Color(Tokens.colorBrandAccent)),
          ),
        ],
      ),
    ),
  );
}

/// A dashed line (aim guides), [dash] px on and off.
void dashedLine(Canvas canvas, Offset from, Offset to, Paint paint, {double dash = 6}) {
  final d = to - from;
  final len = d.distance;
  if (len == 0) return;
  final u = d / len;
  for (var s = 0.0; s < len; s += 2 * dash) {
    canvas.drawLine(from + u * s, from + u * math.min(s + dash, len), paint);
  }
}
