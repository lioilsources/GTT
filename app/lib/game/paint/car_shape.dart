import 'package:shared_gen/shared_gen.dart';

/// Top-down vector shape of a car by class (specs/cars.md v2 "Kreslení", P2). Rectangles in car
/// space: x forward, y left, metres after car_scale. Port of web/src/cars/shape.ts.
/// ComfyUI sprites (METROPOLE_PLAN 10) will replace this drawing later; sizes stay from the JSON.
/// [CarPart.wheel] parts are wheels the shape carries itself (micro: both, trike and rickshaw: the
/// front one); the painter draws the others at [carWheels]. [CarPart.rider] is a rider blob (micro,
/// rickshaw), [CarPart.spare] a disc (the off-road spare wheel, it sticks out behind the tail).
enum CarPart { shadow, body, cabin, glass, stripe, detail, spare, head, tail, wheel, rider }

class CarRect {
  const CarRect(this.part, this.x0, this.y0, this.x1, this.y1, [this.color]);
  final CarPart part;
  final double x0, y0, x1, y1;

  /// 0xAARRGGBB for stripe/detail/spare parts; other parts are coloured by the painter.
  final int? color;
}

/// Cabin from/to along the length (fractions of hl) by class.
const _cabins = <String, (double, double)>{
  'coupe': (-0.42, 0.3),
  'hatchback': (-0.7, 0.25),
  'muscle': (-0.5, 0.1),
  'taxi': (-0.45, 0.3),
  'pickup': (0.05, 0.45),
  'mini': (-0.55, 0.35),
  'sedan': (-0.45, 0.25),
  'kombi': (-0.75, 0.25),
  'supersport': (-0.3, 0.15),
  'veteran': (-0.4, 0.15),
  'offroad': (-0.6, 0.3),
  'limo': (-0.55, 0.35),
};

/// Micro vehicles shorter than this (spec `length_m`, before car_scale) draw as a scooter, longer
/// ones as a bicycle (specs/cars.md "Kreslení podle třídy").
const scooterMaxLengthM = 1.5;

/// Class `special` by `length_m` (before car_scale): from [foodTruckMinLengthM] a food truck, from
/// [trikeMinLengthM] a trike, shorter a rickshaw.
const foodTruckMinLengthM = 5.0;
const trikeMinLengthM = 2.8;

/// How a car of class [cls] and [lengthM] is drawn: its class, or for `special` one of
/// `foodTruck`, `trike`, `rickshaw`.
String drawKind(String cls, double lengthM) => cls != 'special'
    ? cls
    : lengthM >= foodTruckMinLengthM
    ? 'foodTruck'
    : lengthM >= trikeMinLengthM
    ? 'trike'
    : 'rickshaw';

/// Front wheel of the trike and the rickshaw, centred at this fraction of hl on the centre line.
const _frontWheelX = 0.75;

/// Wheel centres the painter draws (tyre rectangles, the front ones steer): four wheels at ±[axle]
/// and ±0.92 hw; the bus at 0.60 and −0.70 hl; the trike and the rickshaw only the two rear ones
/// (the front wheel is in the shape); micro none.
List<(double, double)> carWheels(String cls, double hl, double hw, double axle, {double lengthM = 0}) {
  final xs = switch (drawKind(cls, lengthM)) {
    'micro' => const <double>[],
    'bus' => [hl * 0.6, -hl * 0.7],
    'trike' || 'rickshaw' => [-axle],
    _ => [axle, -axle],
  };
  return [
    for (final x in xs) ...[(x, hw * 0.92), (x, -hw * 0.92)],
  ];
}

/// [lengthM] is the car's `length_m` from the JSON; classes `micro` and `special` read it. [axle]
/// is the axle distance from the centre (the veteran's fenders sit over the wheels), by default
/// 0.62 hl.
List<CarRect> carShape(String cls, double hl, double hw, {double lengthM = 0, double? axle}) {
  final kind = drawKind(cls, lengthM);
  if (kind == 'micro') return _microShape(hl, hw, scooter: lengthM < scooterMaxLengthM);
  final ax = axle ?? hl * 0.62;
  // Half widths of the body at the nose and at the tail: the lights sit at 0.5…0.85 of them.
  var front = hw, back = hw;
  final out = <CarRect>[CarRect(CarPart.shadow, -hl + 0.6, -hw - 0.6, hl + 0.6, hw - 0.6)];
  void detail(double x0, double y0, double x1, double y1, int color) =>
      out.add(CarRect(CarPart.detail, x0, y0, x1, y1, color));
  void cabin((double, double) c, {double w = 0.78}) {
    final (c0, c1) = c;
    out.add(CarRect(CarPart.cabin, hl * c0, -hw * w, hl * c1, hw * w));
    final g0 = hl * c0 + hl * 0.12, g1 = hl * c1 - hl * 0.18, gw = w - 0.12;
    out.add(CarRect(CarPart.glass, g0, -hw * gw, g1 > g0 + hl * 0.08 ? g1 : g0 + hl * 0.08, hw * gw));
  }

  switch (kind) {
    case 'veteran':
      front = back = hw * 0.8;
      out.add(CarRect(CarPart.body, -hl, -front, hl, front));
      // A fender over each wheel on its outer side.
      for (final x in [ax, -ax]) {
        detail(x - hl * 0.16, hw * 0.7, x + hl * 0.16, hw, Tokens.colorCarDetailFender);
        detail(x - hl * 0.16, -hw, x + hl * 0.16, -hw * 0.7, Tokens.colorCarDetailFender);
      }
      cabin(_cabins['veteran']!);
    case 'trike':
      front = hw * 0.45;
      out
        ..add(CarRect(CarPart.body, -hl, -hw, hl * 0.3, hw))
        ..add(CarRect(CarPart.body, hl * 0.3, -front, hl, front));
      _frontWheel(out, hl, hw);
      cabin(const (-0.35, 0.1));
    case 'rickshaw':
      // A bicycle in front (frame, wheel, handlebar, rider) pulling the seat under a canopy.
      front = hw * 0.3;
      out
        ..add(CarRect(CarPart.body, -hl, -hw, hl * 0.1, hw))
        ..add(CarRect(CarPart.body, hl * 0.1, -hw * 0.1, hl * 0.95, hw * 0.1));
      _frontWheel(out, hl, hw, width: 0.12);
      detail(-hl * 0.9, -hw, hl * 0.1, hw, Tokens.colorCarDetailCanopy);
      out
        ..add(CarRect(CarPart.stripe, hl * 0.82, -hw * 0.45, hl * 0.88, hw * 0.45, Tokens.colorCarTyre))
        ..add(CarRect(CarPart.rider, hl * 0.28, -hw * 0.35, hl * 0.62, hw * 0.35));
    case 'van' || 'foodTruck':
      out
        ..add(CarRect(CarPart.body, -hl, -hw, hl, hw))
        ..add(CarRect(CarPart.glass, hl * 0.62, -hw * 0.8, hl * 0.85, hw * 0.8));
      detail(-hl * 0.98, -hw * 0.88, hl * 0.55, hw * 0.88, Tokens.colorCarDetailCargoRoof);
      if (kind == 'foodTruck') {
        // The awning on the right side: stripes of 0.15 hl, alternating A and B.
        for (var i = 0; i < 6; i++) {
          final x0 = -hl * 0.6 + i * hl * 0.15;
          detail(
            x0,
            -hw,
            x0 + hl * 0.15,
            -hw * 0.8,
            i.isEven ? Tokens.colorCarDetailAwningA : Tokens.colorCarDetailAwningB,
          );
        }
      }
    case 'bus':
      out
        ..add(CarRect(CarPart.body, -hl, -hw, hl, hw))
        ..add(CarRect(CarPart.glass, hl * 0.92, -hw * 0.85, hl, hw * 0.85));
      detail(-hl * 0.3, -hw * 0.4, -hl * 0.1, hw * 0.4, Tokens.colorCarDetailBusRoofUnit);
      detail(hl * 0.2, -hw * 0.4, hl * 0.4, hw * 0.4, Tokens.colorCarDetailBusRoofUnit);
    default:
      out.add(CarRect(CarPart.body, -hl, -hw, hl, hw));
      if (kind == 'pickup') {
        detail(-hl * 0.95, -hw * 0.85, -hl * 0.05, hw * 0.85, Tokens.colorCarDetailBedRim);
        detail(-hl * 0.9, -hw * 0.72, -hl * 0.1, hw * 0.72, Tokens.colorCarDetailBed);
      }
      if (kind == 'muscle') {
        // Each stripe as (y0, y1) with y0 < y1.
        for (final (a, b) in const [(-0.32, -0.12), (0.12, 0.32)]) {
          detail(-hl * 0.98, hw * a, hl * 0.98, hw * b, Tokens.colorCarDetailMuscleStripe);
        }
      }
      cabin(_cabins[kind] ?? _cabins['coupe']!, w: kind == 'supersport' ? 0.7 : 0.78);
      switch (kind) {
        case 'coupe':
          out
            ..add(CarRect(CarPart.stripe, hl * 0.3, -hw * 0.12, hl * 0.98, hw * 0.12, Tokens.colorCarStripe))
            ..add(CarRect(CarPart.stripe, -hl * 0.98, -hw * 0.12, -hl * 0.42, hw * 0.12, Tokens.colorCarStripe));
        case 'taxi':
          detail(-hl * 0.15, -hw * 0.35, hl * 0.05, hw * 0.35, Tokens.colorCarDetailTaxiSign);
          for (var i = 0; i < 6; i += 2) {
            final x0 = -hl * 0.6 + i * hl * 0.2;
            detail(x0, hw * 0.86, x0 + hl * 0.1, hw * 0.98, Tokens.colorCarDetailTaxiChecker);
            detail(x0, -hw * 0.98, x0 + hl * 0.1, -hw * 0.86, Tokens.colorCarDetailTaxiChecker);
          }
        case 'kombi':
          for (final c in const [0.7, -0.7]) {
            detail(-hl * 0.7, hw * (c - 0.03), hl * 0.2, hw * (c + 0.03), Tokens.colorCarDetailRoofRail);
          }
        case 'supersport':
          detail(-hl, -hw * 0.95, -hl * 0.9, hw * 0.95, Tokens.colorCarDetailSpoiler);
        case 'limo':
          for (final x in const [-0.25, 0.05]) {
            detail(hl * (x - 0.02), -hw * 0.66, hl * (x + 0.02), hw * 0.66, Tokens.colorCarDetailLimoPillar);
          }
        case 'offroad':
          final r = hw * 0.45;
          out.add(CarRect(CarPart.spare, -hl * 0.98 - r, -r, -hl * 0.98 + r, r, Tokens.colorCarDetailSpare));
      }
  }
  out
    ..add(CarRect(CarPart.head, hl * 0.9, front * 0.5, hl, front * 0.85))
    ..add(CarRect(CarPart.head, hl * 0.9, -front * 0.85, hl, -front * 0.5))
    ..add(CarRect(CarPart.tail, -hl, back * 0.5, -hl * 0.92, back * 0.85))
    ..add(CarRect(CarPart.tail, -hl, -back * 0.85, -hl * 0.92, -back * 0.5));
  return out;
}

/// The single front wheel of the trike and the rickshaw at 0.75 hl on the centre line, drawn over
/// the nose (it steers like the painter's wheels); [width] is its half width in hw.
void _frontWheel(List<CarRect> out, double hl, double hw, {double width = 0.16}) =>
    out.add(CarRect(CarPart.wheel, hl * (_frontWheelX - 0.18), -hw * width, hl * (_frontWheelX + 0.18), hw * width));

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
