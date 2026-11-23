import 'dart:math' as math;

import 'package:drive_core/drive_core.dart';
import 'package:flutter/painting.dart';
import 'package:shared_gen/shared_gen.dart';

/// On-screen hints for the active control scheme (screen space); [boostLabel] is the text of the
/// Boost button of schemes B and C (specs/controls.md v2).
void paintControls(Canvas canvas, Size screen, ControlScheme scheme, String boostLabel) {
  switch (scheme) {
    case SchemeA a when a.active:
      final p = Paint()
        ..color = const Color(Tokens.colorUiControlHint)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(Offset(a.origin.x, a.origin.y), 34, p);
      canvas.drawCircle(Offset(a.pos.x, a.pos.y), 18, p..style = PaintingStyle.fill);
    case SchemeB b:
      final p = Paint()..color = const Color(Tokens.colorUiControlHalf);
      final top = screen.height * 0.6, h = screen.height * 0.4, w = screen.width / 2;
      if (b.leftHeld) canvas.drawRect(Rect.fromLTWH(0, top, w, h), p);
      if (b.rightHeld) canvas.drawRect(Rect.fromLTWH(w, top, w, h), p);
      _boostButton(canvas, SchemeB.boostButton(screen.width, screen.height), b.boostHeld, boostLabel);
    case SchemeC c:
      final ctr = SchemeC.wheelCentre(screen.width, screen.height);
      final centre = Offset(ctr.x, ctr.y);
      final r = SchemeC.wheelRadius(screen.width);
      canvas.drawCircle(
        centre,
        r,
        Paint()
          ..color = const Color(Tokens.colorUiControlWheel)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.16,
      );
      final spoke = Paint()
        ..color = const Color(Tokens.colorUiControlWheel)
        ..strokeWidth = r * 0.1
        ..strokeCap = StrokeCap.round;
      for (final a in [-math.pi / 2, math.pi / 2, math.pi]) {
        final ang = a + c.wheelAngle - math.pi / 2;
        canvas.drawLine(centre, centre + Offset(math.cos(ang), math.sin(ang)) * r, spoke);
      }
      Rect rect(ScreenRect s) => Rect.fromLTWH(s.left, s.top, s.width, s.height);
      final fill = Paint()..color = Color(c.brakeHeld ? Tokens.colorUiControlBrake : Tokens.colorUiControlHint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect(SchemeC.pedal(screen.width, screen.height)), const Radius.circular(10)),
        fill,
      );
      fill.color = Color(c.handHeld ? Tokens.colorUiControlHand : Tokens.colorUiControlHint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect(SchemeC.handButton(screen.width, screen.height)), const Radius.circular(10)),
        fill,
      );
      _boostButton(canvas, SchemeC.boostButton(screen.width, screen.height), c.boostHeld, boostLabel);
    default:
  }
}

/// The Boost button: a rounded pad with its label, highlighted while held.
void _boostButton(Canvas canvas, ScreenRect s, bool held, String label) {
  final r = Rect.fromLTWH(s.left, s.top, s.width, s.height);
  canvas.drawRRect(
    RRect.fromRectAndRadius(r, const Radius.circular(10)),
    Paint()..color = Color(held ? Tokens.colorUiControlBoost : Tokens.colorUiControlHint),
  );
  final tp = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(
        fontSize: math.min(s.width * 0.22, 18),
        fontWeight: FontWeight.w600,
        color: const Color(Tokens.colorUiText),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: s.width);
  tp.paint(canvas, r.center - Offset(tp.width / 2, tp.height / 2));
  tp.dispose();
}
