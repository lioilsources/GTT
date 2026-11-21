import 'dart:math' as math;
import 'dart:ui';

import 'package:drive_core/drive_core.dart';

/// On-screen hints for the active control scheme (screen space).
void paintControls(Canvas canvas, Size screen, ControlScheme scheme) {
  switch (scheme) {
    case SchemeA a when a.active:
      final p = Paint()
        ..color = const Color(0x55FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(Offset(a.origin.x, a.origin.y), 34, p);
      canvas.drawCircle(Offset(a.pos.x, a.pos.y), 18, p..style = PaintingStyle.fill);
    case SchemeB b:
      final p = Paint()..color = const Color(0x22FFFFFF);
      final top = screen.height * 0.6, h = screen.height * 0.4, w = screen.width / 2;
      if (b.leftHeld) canvas.drawRect(Rect.fromLTWH(0, top, w, h), p);
      if (b.rightHeld) canvas.drawRect(Rect.fromLTWH(w, top, w, h), p);
    case SchemeC c:
      final ctr = SchemeC.wheelCentre(screen.width, screen.height);
      final centre = Offset(ctr.x, ctr.y);
      final r = SchemeC.wheelRadius(screen.width);
      canvas.drawCircle(
          centre,
          r,
          Paint()
            ..color = const Color(0x88FFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.16);
      final spoke = Paint()
        ..color = const Color(0x88FFFFFF)
        ..strokeWidth = r * 0.1
        ..strokeCap = StrokeCap.round;
      for (final a in [-math.pi / 2, math.pi / 2, math.pi]) {
        final ang = a + c.wheelAngle - math.pi / 2;
        canvas.drawLine(centre, centre + Offset(math.cos(ang), math.sin(ang)) * r, spoke);
      }
      Rect rect(ScreenRect s) => Rect.fromLTWH(s.left, s.top, s.width, s.height);
      final fill = Paint()..color = Color(c.brakeHeld ? 0xAAFF5050 : 0x55FFFFFF);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect(SchemeC.pedal(screen.width, screen.height)), const Radius.circular(10)), fill);
      fill.color = Color(c.handHeld ? 0xAAFFC040 : 0x55FFFFFF);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect(SchemeC.handButton(screen.width, screen.height)), const Radius.circular(10)),
          fill);
    default:
  }
}
