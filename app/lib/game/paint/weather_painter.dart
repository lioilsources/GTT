import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:game_loop/game_loop.dart';
import 'package:shared_gen/shared_gen.dart';

/// Rain streaks and the fog edge tint of specs/weather.md, in screen space over the world and the
/// cars (after the risograph pass), under the HUD. Nothing is allocated per frame: the streaks
/// are one preallocated [Float32List] drawn by one `drawRawPoints`, and the fog gradient is
/// rebuilt only on a resize or a step of the blend.
class WeatherPainter {
  WeatherPainter(this.t, {int seed = 0}) : _pts = Float32List(4 * math.max(0, t.rainDrops)) {
    // Pseudorandom, cycling streak positions (P2, need not match client W).
    final r = math.Random(seed);
    final n = math.max(0, t.rainDrops);
    _fx = Float32List(n);
    _fy = Float32List(n);
    for (var i = 0; i < n; i++) {
      _fx[i] = r.nextDouble();
      _fy[i] = r.nextDouble();
    }
  }

  final TuningWeather t;
  final Float32List _pts;
  late final Float32List _fx, _fy;
  double _rainAmount = -1;

  final _rain = ui.Paint()
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 1
    ..strokeCap = ui.StrokeCap.butt;
  final _fog = ui.Paint();

  ui.Size _fogSize = ui.Size.zero;
  int _fogLevel = -1;

  /// Blend steps of the fog gradient (a rebuild per step while the fog fades).
  static const _levels = 64;

  /// Gradient stops sampling the smoothstep ramp.
  static const _stops = 16;

  /// Rain streaks at [amount] (0..1 of the blend), [timeS] = game seconds (stand while paused).
  void paintRain(ui.Canvas c, ui.Size size, double amount, double timeS) {
    if (amount <= 0 || _pts.isEmpty || size.isEmpty) return;
    final a = t.rainAngleDeg * math.pi / 180;
    final dx = math.sin(a), dy = math.cos(a);
    final len = t.rainLenPx;
    // Each streak cycles through a box one streak larger than the screen on every side.
    final w = size.width + 2 * len, h = size.height + 2 * len;
    final run = timeS * t.rainSpeedPxS;
    for (var i = 0, j = 0; i < _fx.length; i++, j += 4) {
      final x = (_fx[i] * w + dx * run) % w - len;
      final y = (_fy[i] * h + dy * run) % h - len;
      _pts[j] = x;
      _pts[j + 1] = y;
      _pts[j + 2] = x - dx * len;
      _pts[j + 3] = y - dy * len;
    }
    if (amount != _rainAmount) {
      _rainAmount = amount;
      const base = ui.Color(Tokens.colorWeatherRain);
      _rain.color = base.withValues(alpha: base.a * amount.clamp(0.0, 1.0));
    }
    c.drawRawPoints(ui.PointMode.lines, _pts, _rain);
  }

  /// Fog tint at [amount]: `fog_center_alpha` in the middle up to `fog_edge_alpha` at the corners.
  void paintFog(ui.Canvas c, ui.Size size, double amount) {
    if (amount <= 0 || size.isEmpty) return;
    final level = (amount.clamp(0.0, 1.0) * _levels).round();
    if (level == 0) return;
    if (level != _fogLevel || size != _fogSize) {
      _fogLevel = level;
      _fogSize = size;
      final k = level / _levels;
      const fog = ui.Color(Tokens.colorWeatherFog);
      final half = math.sqrt(size.width * size.width + size.height * size.height) / 2;
      _fog.shader = ui.Gradient.radial(
        ui.Offset(size.width / 2, size.height / 2),
        half,
        [for (var i = 0; i <= _stops; i++) fog.withValues(alpha: fog.a * k * fogAlpha(i / _stops, t))],
        [for (var i = 0; i <= _stops; i++) i / _stops],
      );
    }
    c.drawRect(ui.Offset.zero & size, _fog);
  }
}
