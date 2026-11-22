import 'package:shared_gen/shared_gen.dart';

/// Top-down vector shape of a car by class (specs/cars.md "Kreslení", P2). Rectangles in car
/// space: x forward, y left, metres after car_scale. Port of web/src/cars/shape.ts.
/// ComfyUI sprites (METROPOLE_PLAN 10) will replace this drawing later; sizes stay from the JSON.
/// [wheel] and [rider] are only used by class `micro` (scooter, bicycle); other classes get their
/// four wheels from the painter.
enum CarPart { shadow, body, cabin, glass, stripe, detail, head, tail, wheel, rider }

class CarRect {
  const CarRect(this.part, this.x0, this.y0, this.x1, this.y1, [this.color]);
  final CarPart part;
  final double x0, y0, x1, y1;

  /// 0xAARRGGBB for stripe/detail parts; other parts are coloured by the painter.
  final int? color;
}

const _cabins = <String, (double, double)>{
  'coupe': (-0.42, 0.3),
  'hatchback': (-0.7, 0.25),
  'muscle': (-0.5, 0.1),
  'taxi': (-0.45, 0.3),
  'pickup': (0.05, 0.45),
};

/// Micro vehicles shorter than this (spec `length_m`, before car_scale) draw as a scooter, longer
/// ones as a bicycle (specs/cars.md "Kreslení podle třídy").
const scooterMaxLengthM = 1.5;

/// [lengthM] is the car's `length_m` from the JSON; only class `micro` reads it.
List<CarRect> carShape(String cls, double hl, double hw, {double lengthM = 0}) {
  if (cls == 'micro') return _microShape(hl, hw, scooter: lengthM < scooterMaxLengthM);
  final (c0, c1) = _cabins[cls] ?? _cabins['coupe']!;
  final out = <CarRect>[
    CarRect(CarPart.shadow, -hl + 0.6, -hw - 0.6, hl + 0.6, hw - 0.6),
    CarRect(CarPart.body, -hl, -hw, hl, hw),
  ];
  if (cls == 'pickup') {
    out
      ..add(CarRect(CarPart.detail, -hl * 0.95, -hw * 0.85, -hl * 0.05, hw * 0.85, Tokens.colorCarDetailBedRim))
      ..add(CarRect(CarPart.detail, -hl * 0.9, -hw * 0.72, -hl * 0.1, hw * 0.72, Tokens.colorCarDetailBed));
  }
  if (cls == 'muscle') {
    // Each stripe as (y0, y1) with y0 < y1.
    for (final (a, b) in const [(-0.32, -0.12), (0.12, 0.32)]) {
      out.add(CarRect(CarPart.detail, -hl * 0.98, hw * a, hl * 0.98, hw * b, Tokens.colorCarDetailMuscleStripe));
    }
  }
  out.add(CarRect(CarPart.cabin, hl * c0, -hw * 0.78, hl * c1, hw * 0.78));
  final g0 = hl * c0 + hl * 0.12, g1 = hl * c1 - hl * 0.18;
  out.add(CarRect(CarPart.glass, g0, -hw * 0.66, g1 > g0 + hl * 0.08 ? g1 : g0 + hl * 0.08, hw * 0.66));
  if (cls == 'coupe') {
    out
      ..add(CarRect(CarPart.stripe, hl * 0.3, -hw * 0.12, hl * 0.98, hw * 0.12, Tokens.colorCarStripe))
      ..add(CarRect(CarPart.stripe, -hl * 0.98, -hw * 0.12, -hl * 0.42, hw * 0.12, Tokens.colorCarStripe));
  }
  if (cls == 'taxi') {
    out.add(CarRect(CarPart.detail, -hl * 0.15, -hw * 0.35, hl * 0.05, hw * 0.35, Tokens.colorCarDetailTaxiSign));
    for (var i = 0; i < 6; i += 2) {
      final x0 = -hl * 0.6 + i * hl * 0.2;
      out
        ..add(CarRect(CarPart.detail, x0, hw * 0.86, x0 + hl * 0.1, hw * 0.98, Tokens.colorCarDetailTaxiChecker))
        ..add(CarRect(CarPart.detail, x0, -hw * 0.98, x0 + hl * 0.1, -hw * 0.86, Tokens.colorCarDetailTaxiChecker));
    }
  }
  out
    ..add(CarRect(CarPart.head, hl * 0.9, hw * 0.5, hl, hw * 0.85))
    ..add(CarRect(CarPart.head, hl * 0.9, -hw * 0.85, hl, -hw * 0.5))
    ..add(CarRect(CarPart.tail, -hl, hw * 0.5, -hl * 0.92, hw * 0.85))
    ..add(CarRect(CarPart.tail, -hl, -hw * 0.85, -hl * 0.92, -hw * 0.5));
  return out;
}

/// Scooter or bicycle from above: deck / frame (paint), handlebar (tyre), two wheels and a rider
/// blob (cabin). No lights; everything but the shadow stays inside the body outline.
List<CarRect> _microShape(double hl, double hw, {required bool scooter}) {
  final out = <CarRect>[CarRect(CarPart.shadow, -hl + hw * 0.4, -hw * 1.2, hl + hw * 0.4, hw * 0.4)];
  if (scooter) {
    out
      ..add(CarRect(CarPart.wheel, -hl, -hw * 0.28, -hl * 0.74, hw * 0.28))
      ..add(CarRect(CarPart.wheel, hl * 0.74, -hw * 0.28, hl, hw * 0.28))
      ..add(CarRect(CarPart.body, -hl * 0.8, -hw * 0.45, hl * 0.6, hw * 0.45))
      ..add(CarRect(CarPart.body, hl * 0.55, -hw * 0.14, hl * 0.78, hw * 0.14))
      ..add(CarRect(CarPart.stripe, hl * 0.66, -hw * 0.95, hl * 0.76, hw * 0.95, Tokens.colorCarTyre))
      ..add(CarRect(CarPart.rider, -hl * 0.3, -hw * 0.7, hl * 0.3, hw * 0.7));
  } else {
    out
      ..add(CarRect(CarPart.wheel, -hl, -hw * 0.16, -hl * 0.5, hw * 0.16))
      ..add(CarRect(CarPart.wheel, hl * 0.5, -hw * 0.16, hl, hw * 0.16))
      ..add(CarRect(CarPart.body, -hl * 0.62, -hw * 0.2, hl * 0.62, hw * 0.2))
      ..add(CarRect(CarPart.stripe, hl * 0.48, -hw * 0.95, hl * 0.56, hw * 0.95, Tokens.colorCarTyre))
      ..add(CarRect(CarPart.rider, -hl * 0.34, -hw * 0.75, hl * 0.26, hw * 0.75));
  }
  return out;
}
