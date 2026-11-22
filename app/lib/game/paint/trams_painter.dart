import 'dart:math' as math;
import 'dart:ui';

import 'package:drive_core/drive_core.dart';
import 'package:world_engine/core.dart';

/// Tram tracks, stops and articulated cars (specs/trams.md "Kreslení", P2). Canvas in world
/// metres, y north. Geometry is built once; a frame only culls, transforms and draws.
class TramsPainter {
  TramsPainter(TrackGraph graph, TuningTrams t) : _hl = t.carLengthM / 2, _hw = t.carWidthM / 2 {
    final g = t.railGaugeM / 2;
    _rail
      ..style = PaintingStyle.stroke
      ..strokeWidth = t.railGaugeM * 0.09
      ..color = const Color(Tokens.colorTramsRail);
    for (final e in graph.edges) {
      final n = e.pointCount;
      if (n < 2) continue;
      final path = Path();
      var x0 = double.infinity, y0 = double.infinity, x1 = -double.infinity, y1 = -double.infinity;
      for (final side in const [1.0, -1.0]) {
        for (var i = 0; i < n; i++) {
          // Normal averaged over the segments meeting at point i (left of from → to).
          final a = math.max(0, i - 1), b = math.min(n - 1, i + 1);
          var dx = e.pts[2 * b] - e.pts[2 * a], dy = e.pts[2 * b + 1] - e.pts[2 * a + 1];
          final l = math.sqrt(dx * dx + dy * dy);
          if (l > 0) {
            dx /= l;
            dy /= l;
          } else {
            dx = 1;
            dy = 0;
          }
          final x = e.pts[2 * i] - dy * g * side, y = e.pts[2 * i + 1] + dx * g * side;
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
          x0 = math.min(x0, x);
          y0 = math.min(y0, y);
          x1 = math.max(x1, x);
          y1 = math.max(y1, y);
        }
      }
      _paths.add(path);
      _boxes.add(Rect.fromLTRB(x0, y0, x1, y1));
      _layers.add(e.drawLayer);
    }
    // A stop: a platform beside the track (right of the edge's from → to direction) and a sign.
    final pw = _hw * 0.55;
    _platform = RRect.fromRectAndRadius(
      Rect.fromLTRB(-_hl, -(_hw + g * 0.2 + pw), _hl, -(_hw + g * 0.2)),
      Radius.circular(pw * 0.3),
    );
    _sign = Offset(_hl * 0.7, -(_hw + g * 0.2 + pw / 2));
    _signR = pw * 0.3;
    for (final s in graph.stops) {
      _stops.add(Offset(s.x, s.y));
      _stopAngles.add(math.atan2(s.dirY, s.dirX));
    }
    final hl = _hl, hw = _hw;
    _shadow = RRect.fromRectAndRadius(
      Rect.fromLTRB(-hl + 0.6, -hw - 0.6, hl + 0.6, hw - 0.6),
      Radius.circular(hw * 0.35),
    );
    _body = RRect.fromRectAndRadius(Rect.fromLTRB(-hl, -hw, hl, hw), Radius.circular(hw * 0.3));
    _stripeL = Rect.fromLTRB(-hl * 0.96, hw * 0.62, hl * 0.96, hw * 0.8);
    _stripeR = Rect.fromLTRB(-hl * 0.96, -hw * 0.8, hl * 0.96, -hw * 0.62);
    _roof = RRect.fromRectAndRadius(Rect.fromLTRB(-hl * 0.8, -hw * 0.3, hl * 0.8, hw * 0.3), Radius.circular(hw * 0.1));
    const panes = 4;
    final step = 2 * hl * 0.9 / panes;
    for (var i = 0; i < panes; i++) {
      final a = -hl * 0.9 + i * step + step * 0.12, b = -hl * 0.9 + (i + 1) * step - step * 0.12;
      _windows.add(Rect.fromLTRB(a, hw * 0.36, b, hw * 0.56));
      _windows.add(Rect.fromLTRB(a, -hw * 0.56, b, -hw * 0.36));
    }
    _windshield = RRect.fromRectAndRadius(
      Rect.fromLTRB(hl * 0.86, -hw * 0.7, hl * 0.97, hw * 0.7),
      Radius.circular(hw * 0.1),
    );
  }

  final double _hl;
  final double _hw;
  final _rail = Paint();
  final _p = Paint();
  final List<Path> _paths = [];
  final List<Rect> _boxes = [];
  final List<int> _layers = [];
  final List<Offset> _stops = [];
  final List<double> _stopAngles = [];
  late final RRect _platform;
  late final Offset _sign;
  late final double _signR;
  late final RRect _shadow;
  late final RRect _body;
  late final Rect _stripeL;
  late final Rect _stripeR;
  late final RRect _roof;
  final List<Rect> _windows = [];
  late final RRect _windshield;

  /// Rails of [layer] within [radius] of (x, y), and on the ground the stops. Above the road
  /// surface, below every vehicle.
  void paintTracks(Canvas canvas, int layer, double x, double y, double radius) {
    for (var i = 0; i < _paths.length; i++) {
      if (_layers[i] != layer) continue;
      final b = _boxes[i];
      if (b.left > x + radius || b.right < x - radius || b.top > y + radius || b.bottom < y - radius) continue;
      canvas.drawPath(_paths[i], _rail);
    }
    if (layer != 0) return;
    for (var i = 0; i < _stops.length; i++) {
      final o = _stops[i];
      if ((o.dx - x).abs() > radius || (o.dy - y).abs() > radius) continue;
      canvas.save();
      canvas.translate(o.dx, o.dy);
      canvas.rotate(_stopAngles[i]);
      _p.color = const Color(Tokens.colorTramsStop);
      canvas.drawRRect(_platform, _p);
      _p.color = const Color(Tokens.colorTramsStripe);
      canvas.drawCircle(_sign, _signR * 1.3, _p);
      _p.color = const Color(Tokens.colorTramsBody);
      canvas.drawCircle(_sign, _signR, _p);
      canvas.restore();
    }
  }

  /// Articulated tram cars of [layer]. [shadow] is the city's ground shadow by day (specs/style.md).
  void paintTrams(
    Canvas canvas,
    Trams trams,
    int layer, {
    required bool night,
    Color shadow = const Color(Tokens.colorCarShadow),
  }) {
    final window = night ? const Color(Tokens.colorTramsWindowLit) : const Color(Tokens.colorTramsWindow);
    for (final c in trams.items) {
      if (c.layer != layer) continue;
      canvas.save();
      canvas.translate(c.x, c.y);
      canvas.rotate(c.heading);
      _p.color = shadow;
      canvas.drawRRect(_shadow, _p);
      _p.color = const Color(Tokens.colorTramsBody);
      canvas.drawRRect(_body, _p);
      _p.color = const Color(Tokens.colorTramsStripe);
      canvas.drawRect(_stripeL, _p);
      canvas.drawRect(_stripeR, _p);
      canvas.drawRRect(_roof, _p);
      _p.color = window;
      for (final w in _windows) {
        canvas.drawRect(w, _p);
      }
      if (c.k == 0) canvas.drawRRect(_windshield, _p);
      canvas.restore();
    }
  }
}
