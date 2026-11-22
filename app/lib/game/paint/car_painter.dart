import 'dart:math' as math;
import 'dart:ui';

import 'package:drive_core/drive_core.dart';
import 'package:shared_gen/shared_gen.dart';
import 'package:world_engine/world_engine.dart' show extrusionScale;

import 'car_shape.dart';

/// How a car in a hop is drawn (specs/hop.md "Kreslení"): centre lifted towards the viewer,
/// size [scale] (like an extruded height), and [flip] = cos of the roll angle (1 upright, −1 upside
/// down) that scales the body width.
typedef CarLift = ({double x, double y, double scale, double flip});

/// Lift of a car [heightM] above the ground at (x, y), seen from the vanishing point (vpX, vpY).
CarLift carLift(double x, double y, double vpX, double vpY, double heightM, double rollRad, Tuning t) {
  final s = extrusionScale(heightM, t);
  return (x: vpX + (x - vpX) * s, y: vpY + (y - vpY) * s, scale: s, flip: math.cos(rollRad));
}

/// Top-down car drawn in world space (canvas transformed to metres, y north). With [lift] the car
/// is in the air: no shadow here ([paintHopShadow] draws it on the ground), lifted and rolled.
void paintCar(Canvas canvas, Car car, {required bool night, CarLift? lift}) {
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
  );
}

/// The shadow of a car in a hop: stays on the ground under the car and shrinks with the height
/// (inverse of the lift scale).
void paintHopShadow(Canvas canvas, Car car, CarLift lift) {
  final hl = car.halfLength, hw = car.halfWidth;
  final r = carShape(car.spec.class_, hl, hw, lengthM: car.spec.lengthM).first;
  final k = 1 / lift.scale;
  canvas.save();
  canvas.translate(car.x, car.y);
  canvas.rotate(car.heading);
  canvas.scale(k, k);
  canvas.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTRB(r.x0, r.y0, r.x1, r.y1), Radius.circular(hw * 0.5)),
    Paint()..color = const Color(Tokens.colorCarShadow),
  );
  canvas.restore();
}

/// Parked cars (specs/cars.md): same shape, straight wheels, lights off.
void paintParked(Canvas canvas, Iterable<ParkedCar> cars, Map<String, CarSpec> specs, Tuning t) {
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
}) {
  final p = Paint();
  final paint = Color(paintArgb(spec));
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
    // Shadow first, then the headlight cone and the wheels under the body.
    p.color = const Color(Tokens.colorCarShadow);
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
      canvas.restore();
    }
  }
  for (final r in shape.skip(1)) {
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
        canvas.save();
        canvas.translate(cx, cy);
        if (cx > 0) canvas.rotate(wheelAngle);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: r.x1 - r.x0, height: r.y1 - r.y0),
            Radius.circular((r.y1 - r.y0) / 2),
          ),
          p,
        );
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
