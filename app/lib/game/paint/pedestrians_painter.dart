import 'dart:math' as math;

import 'package:drive_core/drive_core.dart';
import 'package:flutter/painting.dart';
import 'package:world_engine/world_engine.dart';

/// Draws pedestrians in world space (canvas already transformed to metres): shadow, shoulders
/// across the walking direction in a shirt colour by id, head (specs/pedestrians.md "Kreslení").
void paintPedestrians(Canvas canvas, PedestrianWorld w) {
  final p = Paint();
  final r = w.radius;
  const shirts = Tokens.colorPedestriansShirts;
  for (final o in w.peds) {
    canvas.save();
    canvas.translate(o.x, o.y);
    canvas.rotate(o.heading);
    canvas.scale(r);
    p.color = const Color(Tokens.colorPedestriansShadow);
    canvas.drawCircle(const Offset(0.18, -0.18), 1.05, p);
    p.color = Color(shirts[o.id % shirts.length]);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 0.76, height: 2.16),
        const Radius.circular(0.38),
      ),
      p,
    );
    p.color = const Color(Tokens.colorPedestriansHead);
    canvas.drawCircle(const Offset(0.06, 0), 0.42, p);
    canvas.restore();
  }
}

/// "!!" bubbles above pedestrians that just dodged, in screen space.
class PedBubblePainter {
  PedBubblePainter(String text, double px)
    : _px = px,
      _tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: px,
            fontWeight: FontWeight.w900,
            color: const Color(Tokens.colorPedestriansBubbleText),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  final double _px;
  final TextPainter _tp;

  void paint(Canvas canvas, Size size, PedestrianWorld w, CameraRig camera, Tuning tuning) {
    final t = tuning.pedestrians;
    final px = _px;
    final fill = Paint();
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final o in w.peds) {
      if (o.bubble <= 0) continue;
      final q = camera.toScreen(o.x, o.y, size, tuning);
      if (q.dx < -px || q.dy < -px || q.dx > size.width + px || q.dy > size.height + px) continue;
      final a = math.min(1.0, o.bubble / (t.bubbleS * 0.25));
      final y = q.dy - t.bubbleLiftPx;
      final bw = _tp.width + px * 0.9, bh = px * 1.5;
      final path = Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(q.dx, y), width: bw, height: bh),
            Radius.circular(bh / 2),
          ),
        )
        ..moveTo(q.dx - px * 0.25, y + bh / 2 - 0.5)
        ..lineTo(q.dx, y + bh / 2 + px * 0.45)
        ..lineTo(q.dx + px * 0.25, y + bh / 2 - 0.5)
        ..close();
      fill.color = _fade(Tokens.colorPedestriansBubble, a);
      stroke.color = _fade(Tokens.colorPedestriansBubbleOutline, a);
      canvas.drawPath(path, fill);
      canvas.drawPath(path, stroke);
      if (a < 1) canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, a));
      _tp.paint(canvas, Offset(q.dx - _tp.width / 2, y - _tp.height / 2));
      if (a < 1) canvas.restore();
    }
  }
}

Color _fade(int argb, double a) {
  final c = Color(argb);
  return c.withValues(alpha: c.a * a);
}
