import 'dart:ui';

import 'package:drive_core/drive_core.dart';
import 'package:shared_gen/shared_gen.dart';

final _p = Paint();

/// Patrol cars of [layer] (specs/police.md "Kreslení"): police livery and a light bar whose two
/// lamps blink every `light_blink_s` while chasing. paintTraffic skips police cars.
void paintPolice(
  Canvas canvas,
  Traffic traffic,
  int layer, {
  required double timeS,
  required double blinkS,
  required bool night,
}) {
  for (final c in traffic.cars) {
    if (!c.police || c.layer != layer) continue;
    final hl = c.halfLength, hw = c.halfWidth;
    canvas.save();
    canvas.translate(c.x, c.y);
    canvas.rotate(c.heading);
    _p.color = const Color(Tokens.colorCarShadow);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(-hl + 0.6, -hw - 0.6, hl + 0.6, hw - 0.6), Radius.circular(hw * 0.5)),
      _p,
    );
    _p.color = const Color(Tokens.colorPoliceBody);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(-hl, -hw, hl, hw), Radius.circular(hw * 0.45)), _p);
    _p.color = const Color(Tokens.colorPoliceDoor);
    canvas.drawRect(Rect.fromLTRB(-hl * 0.45, -hw, hl * 0.2, hw), _p);
    _p.color = const Color(Tokens.colorCarCabin);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(-hl * 0.42, -hw * 0.78, hl * 0.3, hw * 0.78), Radius.circular(hw * 0.25)),
      _p,
    );
    _p.color = const Color(Tokens.colorPoliceBar);
    canvas.drawRect(Rect.fromLTRB(-hl * 0.12, -hw * 0.85, hl * 0.04, hw * 0.85), _p);
    // A roadblock patrol blinks always (specs/roadblock.md "Kreslení").
    final ph = lightPhase(c.pursuing || c.blocking, timeS, blinkS);
    const off = Color(Tokens.colorPoliceLightOff);
    _p.color = ph == 0 ? const Color(Tokens.colorPoliceLightRed) : off;
    canvas.drawRect(Rect.fromLTRB(-hl * 0.1, hw * 0.1, hl * 0.02, hw * 0.8), _p);
    _p.color = ph == 1 ? const Color(Tokens.colorPoliceLightBlue) : off;
    canvas.drawRect(Rect.fromLTRB(-hl * 0.1, -hw * 0.8, hl * 0.02, -hw * 0.1), _p);
    _p.color = night ? const Color(Tokens.colorCarHeadlightNight) : const Color(Tokens.colorCarHeadlightDay);
    canvas.drawRect(Rect.fromLTRB(hl * 0.9, hw * 0.5, hl, hw * 0.85), _p);
    canvas.drawRect(Rect.fromLTRB(hl * 0.9, -hw * 0.85, hl, -hw * 0.5), _p);
    _p.color = c.braking || c.hitTimer > 0 ? const Color(Tokens.colorCarBrake) : const Color(Tokens.colorCarTail);
    canvas.drawRect(Rect.fromLTRB(-hl, hw * 0.5, -hl * 0.92, hw * 0.85), _p);
    canvas.drawRect(Rect.fromLTRB(-hl, -hw * 0.85, -hl * 0.92, -hw * 0.5), _p);
    canvas.restore();
  }
}
