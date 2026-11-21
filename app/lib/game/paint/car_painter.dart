import 'dart:ui';

import 'package:drive_core/drive_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// Top-down car drawn in world space (canvas transformed to metres, y north).
void paintCar(Canvas canvas, Car car, {required bool night}) {
  final hl = car.halfLength, hw = car.halfWidth;
  final p = Paint();
  canvas.save();
  canvas.translate(car.x, car.y);
  canvas.rotate(car.heading);
  // Shadow.
  p.color = const Color(Tokens.colorCarShadow);
  canvas.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTRB(-hl + 0.6, -hw - 0.6, hl + 0.6, hw - 0.6), Radius.circular(hw * 0.5)),
    p,
  );
  if (night) {
    // Headlight cones.
    final cone = Path()
      ..moveTo(hl, hw * 0.6)
      ..lineTo(hl + 14 * hw, hw * 4)
      ..lineTo(hl + 14 * hw, -hw * 4)
      ..lineTo(hl, -hw * 0.6)
      ..close();
    p.color = const Color(Tokens.colorCarHeadlightCone);
    canvas.drawPath(cone, p);
  }
  // Wheels (front ones steer).
  p.color = const Color(Tokens.colorCarTyre);
  final ww = hl * 0.36, wt = hw * 0.32;
  for (final fx in [car.axleOffset, -car.axleOffset]) {
    for (final sy in [hw * 0.92, -hw * 0.92]) {
      canvas.save();
      canvas.translate(fx, sy);
      if (fx > 0) canvas.rotate(car.wheelAngle);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: ww, height: wt), p);
      canvas.restore();
    }
  }
  // Body.
  p.color = Color(paintArgb(car.spec));
  canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(-hl, -hw, hl, hw), Radius.circular(hw * 0.45)), p);
  // Cabin and glass.
  p.color = const Color(Tokens.colorCarCabin);
  canvas.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTRB(-hl * 0.42, -hw * 0.78, hl * 0.3, hw * 0.78), Radius.circular(hw * 0.25)),
    p,
  );
  p.color = Color.lerp(Color(paintArgb(car.spec)), const Color(Tokens.colorUiText), 0.12)!;
  canvas.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTRB(-hl * 0.3, -hw * 0.66, hl * 0.12, hw * 0.66), Radius.circular(hw * 0.2)),
    p,
  );
  // Racing stripe.
  p.color = const Color(Tokens.colorCarStripe);
  canvas.drawRect(Rect.fromLTRB(hl * 0.3, -hw * 0.12, hl * 0.98, hw * 0.12), p);
  canvas.drawRect(Rect.fromLTRB(-hl * 0.98, -hw * 0.12, -hl * 0.42, hw * 0.12), p);
  // Lights.
  p.color = night ? const Color(Tokens.colorCarHeadlightNight) : const Color(Tokens.colorCarHeadlightDay);
  canvas.drawRect(Rect.fromLTRB(hl * 0.9, hw * 0.5, hl, hw * 0.85), p);
  canvas.drawRect(Rect.fromLTRB(hl * 0.9, -hw * 0.85, hl, -hw * 0.5), p);
  p.color = car.braking || car.reversing
      ? (car.reversing ? const Color(Tokens.colorCarReverse) : const Color(Tokens.colorCarBrake))
      : const Color(Tokens.colorCarTail);
  canvas.drawRect(Rect.fromLTRB(-hl, hw * 0.5, -hl * 0.92, hw * 0.85), p);
  canvas.drawRect(Rect.fromLTRB(-hl, -hw * 0.85, -hl * 0.92, -hw * 0.5), p);
  canvas.restore();
}

/// Skid marks as thin dark quads; [segs] holds x0, y0, x1, y1 per segment.
void paintSkids(Canvas canvas, List<double> segs, double width) {
  final p = Paint()
    ..color = const Color(Tokens.colorCarSkid)
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  final n = segs.length ~/ 4;
  if (n == 0) return;
  final pts = <Offset>[];
  for (var i = 0; i < n; i++) {
    final x0 = segs[4 * i], y0 = segs[4 * i + 1], x1 = segs[4 * i + 2], y1 = segs[4 * i + 3];
    if ((x1 - x0).abs() + (y1 - y0).abs() > 30) continue; // teleports
    pts
      ..add(Offset(x0, y0))
      ..add(Offset(x1, y1));
  }
  canvas.drawPoints(PointMode.lines, pts, p);
}
