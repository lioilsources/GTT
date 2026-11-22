import 'dart:convert';

import 'package:shared_gen/shared_gen.dart';

/// Parses `content/cars/<id>.json` into the generated [CarSpec] (schema/car.schema.json).
///
/// Physical sizes are real-world; the simulation multiplies them by `car_scale`.
/// power is peak acceleration (m/s²), brake deceleration (m/s²), grips are the maximum
/// lateral acceleration per axle (m/s²), driftBias scales rear grip under handbrake.
CarSpec parseCarSpec(String json) => CarSpec.fromJson(jsonDecode(json) as Map<String, Object?>);

/// Body colour as 0xAARRGGBB: `paint` is a key of `color.carPaint` in design/tokens.json.
int paintArgb(CarSpec s) => Tokens.colorCarPaint[s.paint] ?? Tokens.colorCarPaint['comet_red']!;

/// Car classes in the order of schema/car.schema.json (`class` enum, plan 10).
const carClassOrder = [
  'mini', 'hatchback', 'sedan', 'kombi', 'coupe', 'muscle', 'supersport', 'veteran', //
  'offroad', 'pickup', 'van', 'taxi', 'limo', 'bus', 'micro', 'special',
];

/// The garage list of cars for sale (specs/cars.md v2 "Garáž"): every car of [specs] not in
/// [owned]; first those whose `tags` contain [cityId], then the rest; within each by class in
/// [carClassOrder], then price, then id.
List<CarSpec> saleOrder(Iterable<CarSpec> specs, Iterable<String> owned, String cityId) {
  final own = owned.toSet();
  int rank(String c) {
    final i = carClassOrder.indexOf(c);
    return i < 0 ? carClassOrder.length : i;
  }

  int key(CarSpec s) => s.tags.contains(cityId) ? 0 : 1;
  return [
    for (final s in specs)
      if (!own.contains(s.id)) s,
  ]..sort((a, b) {
    var c = key(a).compareTo(key(b));
    if (c == 0) c = rank(a.class_).compareTo(rank(b.class_));
    if (c == 0) c = a.price.compareTo(b.price);
    return c != 0 ? c : a.id.compareTo(b.id);
  });
}

/// Effective parameters of an owned car with tuning [levels] (slot → level, specs/garage.md "Účinek
/// na jízdu"): the catalog values × the multipliers of `garage` in tuning.yaml; several multipliers
/// of one parameter multiply. A missing slot is level 0. The drive rules stay those of
/// specs/drive.md; the client only builds the car body from the result. [spec] is not changed.
CarSpec tunedSpec(CarSpec spec, Map<String, int> levels, TuningGarage t) {
  double l(String slot) => (levels[slot] ?? 0).toDouble();
  final engine = l('engine'), tyres = l('tyres'), brakes = l('brakes'), weight = l('weight'), drift = l('drift');
  return CarSpec.fromJson({...spec.toJson(), 'tags': [...spec.tags], 'tuning_slots': [...spec.tuningSlots]})
    ..power = spec.power * (1 + t.enginePowerStep * engine) * (1 + t.weightPowerStep * weight)
    ..topSpeed = spec.topSpeed * (1 + t.engineTopStep * engine)
    ..gripFront = spec.gripFront * (1 + t.tyresStep * tyres)
    ..gripRear = spec.gripRear * (1 + t.tyresStep * tyres)
    ..brake = spec.brake * (1 + t.brakesStep * brakes)
    ..mass = spec.mass * (1 - t.weightMassStep * weight)
    ..steerSpeed = spec.steerSpeed * (1 + t.weightSteerStep * weight)
    ..driftBias = spec.driftBias * (1 - t.driftStep * drift);
}
