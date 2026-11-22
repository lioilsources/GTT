import 'dart:math' as math;
import 'dart:ui';

import 'package:drive_core/drive_core.dart';
import 'package:game_loop/game_loop.dart' show CarLook;
import 'package:shared_gen/shared_gen.dart';
import 'package:world_engine/world_engine.dart' show extrusionScale;

import 'car_shape.dart';

/// How a car in a hop is drawn (specs/hop.md "Kreslení"): centre lifted towards the viewer,
/// size [scale] (like an extruded height), and [flip] = cos of the roll angle (1 upright, −1 upside
/// down) that scales the body width.
typedef CarLift = ({double x, double y, double scale, double flip});

/// A car's look as drawn (specs/garage.md "Kreslení"): the resolved [look], the underglow margin
/// `garage.glow_margin_m` and its strength [glow] (1 at night or in a tunnel, `garage.glow_day` by day).
typedef LookPaint = ({CarLook look, double glowMarginM, double glow});

/// The look of an owned car in the world: full glow at night or in a tunnel (layer < 0).
LookPaint lookPaint(CarLook look, TuningGarage t, {required bool night, int layer = 0}) =>
    (look: look, glowMarginM: t.glowMarginM, glow: night || layer < 0 ? 1.0 : t.glowDay);

/// Lift of a car [heightM] above the ground at (x, y), seen from the vanishing point (vpX, vpY).
CarLift carLift(double x, double y, double vpX, double vpY, double heightM, double rollRad, Tuning t) {
  final s = extrusionScale(heightM, t);
  return (x: vpX + (x - vpX) * s, y: vpY + (y - vpY) * s, scale: s, flip: math.cos(rollRad));
}

/// Top-down car drawn in world space (canvas transformed to metres, y north). With [lift] the car
/// is in the air: no shadow here ([paintHopShadow] draws it on the ground), lifted and rolled.
/// [shadow] is the city's ground shadow by day (specs/style.md).
void paintCar(
  Canvas canvas,
  Car car, {
  required bool night,
  CarLift? lift,
  Color shadow = const Color(Tokens.colorCarShadow),
  LookPaint? look,
}) {
  _paintShape(
    canvas,
    car.spec,
    lift?.x ?? car.x,
    lift?.y ?? car.y,
    car.heading,
    car.halfLength,
    car.halfWidth,
    car.axleOffset,
    wheelAngle: car.wheelAngle,
    night: night,
    cone: night && lift == null,
    rear: car.braking || car.reversing
        ? (car.reversing ? const Color(Tokens.colorCarReverse) : const Color(Tokens.colorCarBrake))
        : null,
    lift: lift,
    shadow: shadow,
    look: look,
  );
}

/// A car from above for the garage preview (specs/garage.md "Vzhled"): drawn like in the world
/// with [look], nose up, centred in [size] and scaled to fit; straight wheels, lights off.
void paintCarPreview(Canvas canvas, Size size, CarSpec spec, Tuning t, LookPaint? look) {
  final hl = spec.lengthM * t.carScale / 2, hw = spec.widthM * t.carScale / 2;
  final margin = (look?.glowMarginM ?? 0) + 0.6;
  final k = math.min(size.height / (2 * (hl + margin)), size.width / (2 * (hw + margin)));
  canvas.save();
  canvas.translate(size.width / 2, size.height / 2);
  // World space is y north: flip so the car's left is on the screen's left, then turn the nose up.
  canvas.scale(k, -k);
  _paintShape(
    canvas,
    spec,
    0,
    0,
    math.pi / 2,
    hl,
    hw,
    hl * t.drive.axleOffset,
    wheelAngle: 0,
    night: false,
    cone: false,
    look: look,
  );
  canvas.restore();
}

/// The shadow of a car in a hop: stays on the ground under the car and shrinks with the height
/// (inverse of the lift scale).
void paintHopShadow(Canvas canvas, Car car, CarLift lift, {Color shadow = const Color(Tokens.colorCarShadow)}) {
  final hl = car.halfLength, hw = car.halfWidth;
  final r = carShape(car.spec.class_, hl, hw, lengthM: car.spec.lengthM).first;
  final k = 1 / lift.scale;
  canvas.save();
  canvas.translate(car.x, car.y);
  canvas.rotate(car.heading);
  canvas.scale(k, k);
  canvas.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTRB(r.x0, r.y0, r.x1, r.y1), Radius.circular(hw * 0.5)),
    Paint()..color = shadow,
  );
  canvas.restore();
}

/// Parked cars (specs/cars.md): same shape, straight wheels, lights off. [lookOf] gives the look of
/// a car the player left parked (specs/garage.md); null = the catalog drawing.
void paintParked(
  Canvas canvas,
  Iterable<ParkedCar> cars,
  Map<String, CarSpec> specs,
  Tuning t, {
  Color shadow = const Color(Tokens.colorCarShadow),
  LookPaint? Function(ParkedCar p)? lookOf,
}) {
  for (final p in cars) {
    final s = specs[p.carId];
    if (s == null) continue;
    final hl = s.lengthM * t.carScale / 2, hw = s.widthM * t.carScale / 2;
    _paintShape(
      canvas,
      s,
      p.x,
      p.y,
      p.heading,
      hl,
      hw,
      hl * t.drive.axleOffset,
      wheelAngle: 0,
      night: false,
      cone: false,
      shadow: shadow,
      look: lookOf?.call(p),
    );
  }
}

void _paintShape(
  Canvas canvas,
  CarSpec spec,
  double x,
  double y,
  double heading,
  double hl,
  double hw,
  double axle, {
  required double wheelAngle,
  required bool night,
  required bool cone,
  Color? rear,
  CarLift? lift,
  Color shadow = const Color(Tokens.colorCarShadow),
  LookPaint? look,
}) {
  final p = Paint();
  final lk = look?.look;
  final paint = Color(lk?.paint ?? paintArgb(spec));
  final micro = spec.class_ == 'micro';
  final shape = carShape(spec.class_, hl, hw, lengthM: spec.lengthM);
  canvas.save();
  canvas.translate(x, y);
  canvas.rotate(heading);
  RRect rr(CarRect r, double radius) =>
      RRect.fromRectAndRadius(Rect.fromLTRB(r.x0, r.y0, r.x1, r.y1), Radius.circular(radius));
  if (lift != null) {
    canvas.scale(lift.scale, lift.scale * lift.flip);
    if (lift.flip < 0) {
      // Past the quarter turn the underside faces up: the body outline as a dark floor.
      p.color = const Color(Tokens.colorCarTyre);
      canvas.drawRRect(rr(shape.firstWhere((r) => r.part == CarPart.body), hw * 0.45), p);
      canvas.restore();
      return;
    }
  } else {
    // Underglow under the shadow (specs/garage.md "glow"), then the shadow, the headlight cone and
    // the wheels under the body.
    final glow = lk?.glow;
    if (glow != null && look!.glow > 0) {
      final body = shape.firstWhere((r) => r.part == CarPart.body);
      final m = look.glowMarginM;
      final c = Color(glow);
      p.color = c.withValues(alpha: c.a * look.glow.clamp(0.0, 1.0));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(body.x0 - m, body.y0 - m, body.x1 + m, body.y1 + m),
          Radius.circular(hw * 0.5 + m),
        ),
        p,
      );
    }
    p.color = shadow;
    canvas.drawRRect(rr(shape.first, hw * 0.5), p);
  }
  if (cone && !micro) {
    final path = Path()
      ..moveTo(hl, hw * 0.6)
      ..lineTo(hl + 14 * hw, hw * 4)
      ..lineTo(hl + 14 * hw, -hw * 4)
      ..lineTo(hl, -hw * 0.6)
      ..close();
    p.color = const Color(Tokens.colorCarHeadlightCone);
    canvas.drawPath(path, p);
  }
  p.color = const Color(Tokens.colorCarTyre);
  final ww = hl * 0.36, wt = hw * 0.32;
  // Micro vehicles carry their two wheels in the shape.
  for (final fx in micro ? const <double>[] : [axle, -axle]) {
    for (final sy in [hw * 0.92, -hw * 0.92]) {
      canvas.save();
      canvas.translate(fx, sy);
      if (fx > 0) canvas.rotate(wheelAngle);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: ww, height: wt), p);
      final rim = lk?.rim;
      if (rim != null) {
        p.color = Color(rim);
        canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: ww * 0.5, height: wt * 0.55), p);
        p.color = const Color(Tokens.colorCarTyre);
      }
      canvas.restore();
    }
  }
  var decalDone = (lk?.decal ?? 0) == 0;
  for (final r in shape.skip(1)) {
    // The decal goes over the body, the cabin and the class details (muscle stripes, taxi checker),
    // under the lights (and a micro rider), as client W.
    if (!decalDone && (r.part == CarPart.head || r.part == CarPart.tail || r.part == CarPart.rider)) {
      decalDone = true;
      _paintDecal(canvas, lk!.decal, shape.firstWhere((q) => q.part == CarPart.body), hw);
    }
    switch (r.part) {
      case CarPart.body:
        p.color = paint;
        canvas.drawRRect(rr(r, hw * 0.45), p);
      case CarPart.cabin:
        p.color = const Color(Tokens.colorCarCabin);
        canvas.drawRRect(rr(r, hw * 0.25), p);
      case CarPart.glass:
        p.color = Color.lerp(paint, const Color(Tokens.colorUiText), 0.12)!;
        canvas.drawRRect(rr(r, hw * 0.2), p);
      case CarPart.head:
        p.color = night ? const Color(Tokens.colorCarHeadlightNight) : const Color(Tokens.colorCarHeadlightDay);
        canvas.drawRect(Rect.fromLTRB(r.x0, r.y0, r.x1, r.y1), p);
      case CarPart.tail:
        p.color = rear ?? const Color(Tokens.colorCarTail);
        canvas.drawRect(Rect.fromLTRB(r.x0, r.y0, r.x1, r.y1), p);
      case CarPart.wheel:
        // The front wheel steers about its centre.
        p.color = const Color(Tokens.colorCarTyre);
        final cx = (r.x0 + r.x1) / 2, cy = (r.y0 + r.y1) / 2;
        final w = r.x1 - r.x0, h = r.y1 - r.y0;
        canvas.save();
        canvas.translate(cx, cy);
        if (cx > 0) canvas.rotate(wheelAngle);
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: w, height: h), Radius.circular(h / 2)),
          p,
        );
        // Micro vehicles get no rims (as client W).
        final rim = micro ? null : lk?.rim;
        if (rim != null) {
          p.color = Color(rim);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: w * 0.5, height: h * 0.5),
              Radius.circular(h / 4),
            ),
            p,
          );
        }
        canvas.restore();
      case CarPart.rider:
        p.color = const Color(Tokens.colorCarCabin);
        canvas.drawOval(Rect.fromLTRB(r.x0, r.y0, r.x1, r.y1), p);
      case CarPart.shadow || CarPart.stripe || CarPart.detail:
        p.color = Color(r.color ?? Tokens.colorCarStripe);
        canvas.drawRect(Rect.fromLTRB(r.x0, r.y0, r.x1, r.y1), p);
    }
  }
  canvas.restore();
}

/// Procedural decal in `color.garage.decal`, clipped to the body (specs/garage.md "Kreslení"):
/// 1 two lengthwise stripes at ±0.22 hw over the whole car, 2 three flames from the nose back to
/// 0.35 hl, 3 a band of checker squares along both sides.
void _paintDecal(Canvas canvas, int decal, CarRect body, double hw) {
  final hl = body.x1, w = body.y1 - body.y0;
  final p = Paint()..color = const Color(Tokens.colorGarageDecal);
  canvas.save();
  canvas.clipRRect(
    RRect.fromRectAndRadius(Rect.fromLTRB(body.x0, body.y0, body.x1, body.y1), Radius.circular(hw * 0.45)),
  );
  switch (decal) {
    case 1:
      final half = w * 0.04;
      for (final c in [0.22 * w / 2, -0.22 * w / 2]) {
        canvas.drawRect(Rect.fromLTRB(body.x0, c - half, body.x1, c + half), p);
      }
    case 2:
      // Three flame tongues side by side, the middle one reaching furthest back.
      final tip = 0.35 * hl;
      final bands = [(-0.42, -0.12, 0.12), (-0.15, 0.15, 0.0), (0.12, 0.42, 0.12)];
      for (final (a, b, back) in bands) {
        final y0 = body.y0 + (a + 0.5) * w, y1 = body.y0 + (b + 0.5) * w;
        final x = tip + back * hl;
        canvas.drawPath(
          Path()
            ..moveTo(body.x1, y0)
            ..lineTo(body.x1, y1)
            ..lineTo(x, (y0 + y1) / 2)
            ..close(),
          p,
        );
      }
    case 3:
      final sq = w * 0.1;
      final len = body.x1 - body.x0;
      final n = (len * 0.7 / sq).floor();
      final x0 = body.x0 + (len - n * sq) / 2;
      for (var i = 0; i < n; i++) {
        for (var row = 0; row < 2; row++) {
          if ((i + row).isOdd) continue;
          final x = x0 + i * sq;
          final inner = w / 2 - sq * (row + 1) - w * 0.03;
          canvas
            ..drawRect(Rect.fromLTWH(x, inner, sq, sq), p)
            ..drawRect(Rect.fromLTWH(x, -inner - sq, sq, sq), p);
        }
      }
  }
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
