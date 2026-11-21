import 'package:shared_gen/shared_gen.dart';

/// Top-down vector shape of a car by class (specs/cars.md "Kreslení", P2). Rectangles in car
/// space: x forward, y left, metres after car_scale. Port of web/src/cars/shape.ts.
/// ComfyUI sprites (METROPOLE_PLAN 10) will replace this drawing later; sizes stay from the JSON.
enum CarPart { shadow, body, cabin, glass, stripe, detail, head, tail }

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

List<CarRect> carShape(String cls, double hl, double hw) {
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
    for (final s in [-1.0, 1.0]) {
      out.add(
        CarRect(CarPart.detail, -hl * 0.98, s * hw * 0.12, hl * 0.98, s * hw * 0.32, Tokens.colorCarDetailMuscleStripe),
      );
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
