import 'dart:ui';

import 'package:drive_core/drive_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// Draws street furniture in world space (canvas already transformed to metres).
void paintProps(Canvas canvas, Iterable<Prop> props, {required bool night}) {
  final p = Paint();
  for (final o in props) {
    canvas.save();
    canvas.translate(o.x + o.ox, o.y + o.oy);
    canvas.rotate(o.angle + o.rot);
    final r = o.radius;
    final a = o.knocked ? 0.75 : 1.0;
    switch (o.kind) {
      case PropKind.lamp:
        if (night && !o.knocked) {
          p.color = const Color(Tokens.colorPropsLampGlow);
          canvas.drawCircle(Offset.zero, r * 10, p);
        }
        p.color = _a(Tokens.colorPropsLamp, a);
        if (o.knocked) {
          canvas.drawRect(Rect.fromLTWH(0, -r * 0.5, r * 7.2, r), p); // the fallen pole
        } else {
          canvas.drawCircle(Offset.zero, r, p);
          p.color = const Color(Tokens.colorPropsLampBulb);
          canvas.drawCircle(Offset.zero, r * 0.5, p);
        }
      case PropKind.hydrant:
        p.color = _a(Tokens.colorPropsHydrant, a);
        canvas.drawCircle(Offset.zero, r, p);
      case PropKind.bin:
        p.color = _a(Tokens.colorPropsBin, a);
        canvas.drawCircle(Offset.zero, r, p);
        p.color = _a(Tokens.colorPropsBinInner, a);
        canvas.drawCircle(Offset.zero, r * 0.6, p);
      case PropKind.newsbox:
        p.color = _a(Tokens.colorPropsNewsbox, a);
        canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: r * 1.6, height: r * 1.2), p);
      case PropKind.planter:
        p.color = _a(Tokens.colorPropsPlanter, a);
        canvas.drawCircle(Offset.zero, r, p);
        p.color = _a(Tokens.colorPropsPlanterGreen, a);
        canvas.drawCircle(Offset.zero, r * 0.75, p);
    }
    canvas.restore();
  }
}

Color _a(int argb, double alpha) => Color(argb).withValues(alpha: alpha);
