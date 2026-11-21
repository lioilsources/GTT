import 'dart:ui';

import 'package:drive_core/drive_core.dart';
import 'package:shared_gen/shared_gen.dart';

final _p = Paint();
final _bodies = [for (final c in Tokens.colorTrafficBodies) Color(c)];
const _lights = [
  Color(Tokens.colorTrafficLightGreen),
  Color(Tokens.colorTrafficLightAmber),
  Color(Tokens.colorTrafficLightRed),
];

/// AI cars of [layer], top-down like the player's car (canvas in world metres, y north).
void paintTraffic(Canvas canvas, Traffic traffic, int layer, {required bool night}) {
  for (final c in traffic.cars) {
    if (c.layer != layer) continue;
    final hl = c.halfLength, hw = c.halfWidth;
    canvas.save();
    canvas.translate(c.x, c.y);
    canvas.rotate(c.heading);
    _p.color = const Color(Tokens.colorCarShadow);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(-hl + 0.6, -hw - 0.6, hl + 0.6, hw - 0.6), Radius.circular(hw * 0.5)),
      _p,
    );
    _p.color = _bodies[c.colour % _bodies.length];
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(-hl, -hw, hl, hw), Radius.circular(hw * 0.45)), _p);
    _p.color = const Color(Tokens.colorCarCabin);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(-hl * 0.42, -hw * 0.78, hl * 0.3, hw * 0.78), Radius.circular(hw * 0.25)),
      _p,
    );
    _p.color = night ? const Color(Tokens.colorCarHeadlightNight) : const Color(Tokens.colorCarHeadlightDay);
    canvas.drawRect(Rect.fromLTRB(hl * 0.9, hw * 0.5, hl, hw * 0.85), _p);
    canvas.drawRect(Rect.fromLTRB(hl * 0.9, -hw * 0.85, hl, -hw * 0.5), _p);
    _p.color = c.braking || c.hitTimer > 0 ? const Color(Tokens.colorCarBrake) : const Color(Tokens.colorCarTail);
    canvas.drawRect(Rect.fromLTRB(-hl, hw * 0.5, -hl * 0.92, hw * 0.85), _p);
    canvas.drawRect(Rect.fromLTRB(-hl, -hw * 0.85, -hl * 0.92, -hw * 0.5), _p);
    canvas.restore();
  }
}

/// Small light indicators at the stop lines of signalled crossings within [radius] of (x, y).
void paintTrafficLights(Canvas canvas, Traffic traffic, double x, double y, double radius, TuningTraffic t) {
  final ap = traffic.signals.approaches;
  final r2 = radius * radius, s = t.lightRadiusM;
  var n = 0;
  for (var a = 0; a < ap.length && n < t.lightDrawMax; a++) {
    final p = ap[a];
    final dx = p.x - x, dy = p.y - y;
    if (dx * dx + dy * dy > r2) continue;
    final o = Offset(p.x, p.y);
    _p.color = const Color(Tokens.colorTrafficLightHousing);
    canvas.drawCircle(o, s * 1.45, _p);
    _p.color = _lights[traffic.light(a)];
    canvas.drawCircle(o, s * 0.7, _p);
    n++;
  }
}
