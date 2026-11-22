import 'dart:typed_data';
import 'dart:ui';

import 'package:world_engine/world_engine.dart';

/// Draws pedestrian-zone bollards (specs/zones.md) in world space as small 2.5D cylinders:
/// one round-capped stroke from the foot to the extruded top, all in a single draw call.
/// The point buffer and paint are reused between frames.
class BollardPainter {
  final _paint = Paint()
    ..color = const Color(Tokens.colorPropsBollard)
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;
  Float32List _buf = Float32List(1024);

  /// [vpX], [vpY] is the vanishing point (camera centre); bollards farther than [radius] are skipped.
  void paint(
    Canvas canvas,
    Iterable<Float32List> bollards,
    Tuning t, {
    required double vpX,
    required double vpY,
    required double radius,
  }) {
    final z = t.zones;
    final s = extrusionScale(z.bollardHeightM, t);
    var n = 0;
    for (final pts in bollards) {
      for (var i = 0; i + 1 < pts.length; i += 2) {
        final x = pts[i], y = pts[i + 1];
        final dx = x - vpX, dy = y - vpY;
        if (dx.abs() > radius || dy.abs() > radius) continue;
        if (n + 4 > _buf.length) _buf = Float32List(_buf.length * 2)..setRange(0, n, _buf);
        _buf[n++] = x;
        _buf[n++] = y;
        _buf[n++] = vpX + dx * s;
        _buf[n++] = vpY + dy * s;
      }
    }
    if (n == 0) return;
    _paint.strokeWidth = 2 * z.bollardRadiusM;
    canvas.drawRawPoints(PointMode.lines, Float32List.sublistView(_buf, 0, n), _paint);
  }
}
