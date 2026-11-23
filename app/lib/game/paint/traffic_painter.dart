import 'dart:ui';

import 'package:drive_core/drive_core.dart';
import 'package:shared_gen/shared_gen.dart';

import 'car_shape.dart' show carWheels;
import 'car_sprites.dart';

final _p = Paint();
final _bodies = [for (final c in Tokens.colorTrafficBodies) Color(c)];
const _lights = [
  Color(Tokens.colorTrafficLightGreen),
  Color(Tokens.colorTrafficLightAmber),
  Color(Tokens.colorTrafficLightRed),
];

/// Sprite id of the traffic cars (specs/art.md v2 "Auta": one generic shape for now).
const trafficSprite = 'traffic_sedan';

/// AI cars of [layer], top-down like the player's car (canvas in world metres, y north). With the
/// `traffic_sedan` sprite each car draws it in its random paint (specs/art.md v2 "Auta").
void paintTraffic(
  Canvas canvas,
  Traffic traffic,
  int layer, {
  required bool night,
  required Tuning tuning,
  Color shadow = const Color(Tokens.colorCarShadow),
}) {
  final sprite = carSprites.sprite(trafficSprite);
  final batch = CarSpriteBatch();
  for (final c in traffic.cars) {
    // Patrols are drawn by police_painter.dart.
    if (c.layer != layer || c.police) continue;
    final hl = c.halfLength, hw = c.halfWidth;
    canvas.save();
    canvas.translate(c.x, c.y);
    canvas.rotate(c.heading);
    _p.color = shadow;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(-hl + 0.6, -hw - 0.6, hl + 0.6, hw - 0.6), Radius.circular(hw * 0.5)),
      _p,
    );
    if (sprite != null) {
      canvas.restore();
      addTrafficSprite(
        batch,
        sprite,
        c,
        tuning,
        paint: _bodies[c.colour % _bodies.length].toARGB32(),
        night: night,
        braking: c.braking || c.hitTimer > 0,
      );
      continue;
    }
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
  batch.flush(canvas);
}

/// Adds a traffic car or a patrol [c] drawn by [sprite] to [b] (specs/art.md v2 "Auta"): the sprite
/// stretched to the tuning size × 1.1 (the canvas margin), straight wheels at the axle rule, the
/// lights (`lights.png` at night whole, by day the rear half when [braking]; without it the code's
/// lamps). [paint] null = not tinted (the patrol).
void addTrafficSprite(
  CarSpriteBatch b,
  CarSprite sprite,
  TrafficCar c,
  Tuning tuning, {
  required int? paint,
  required bool night,
  required bool braking,
}) {
  final hl = c.halfLength, hw = c.halfWidth;
  final along = 2 * hl * carSpriteCanvas, across = 2 * hw * carSpriteCanvas;
  final h = sprite.height;
  final w = (h * across / along).round();
  final k = along / h;
  final kWheel = tuning.carScale / carSpritePxPerM;
  for (final (fx, sy) in carWheels('sedan', hl, hw, hl * tuning.drive.axleOffset)) {
    b.addWheel(sprite, c.x, c.y, c.heading, fx, sy, 0, kWheel, null);
  }
  b.addBody(carSprites.body(sprite, paint, outW: w, outH: h), c.x, c.y, c.heading, k);
  final lights = sprite.lights;
  if (lights != null) {
    // The lights layer has the source width: scale it across like the body.
    if (night || braking) {
      b.addLights(carSprites.lightsFor(sprite, w, h), c.x, c.y, c.heading, k, rearOnly: !night);
    }
    return;
  }
  b.over((canvas) {
    canvas.save();
    canvas.translate(c.x, c.y);
    canvas.rotate(c.heading);
    _p.color = night ? const Color(Tokens.colorCarHeadlightNight) : const Color(Tokens.colorCarHeadlightDay);
    canvas.drawRect(Rect.fromLTRB(hl * 0.9, hw * 0.5, hl, hw * 0.85), _p);
    canvas.drawRect(Rect.fromLTRB(hl * 0.9, -hw * 0.85, hl, -hw * 0.5), _p);
    _p.color = braking ? const Color(Tokens.colorCarBrake) : const Color(Tokens.colorCarTail);
    canvas.drawRect(Rect.fromLTRB(-hl, hw * 0.5, -hl * 0.92, hw * 0.85), _p);
    canvas.drawRect(Rect.fromLTRB(-hl, -hw * 0.85, -hl * 0.92, -hw * 0.5), _p);
    canvas.restore();
  });
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
