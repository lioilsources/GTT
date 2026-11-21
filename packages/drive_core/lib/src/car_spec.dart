import 'dart:convert';
import 'dart:ui';

/// Car definition from `content/cars/<id>.json` (METROPOLE_PLAN 7.2, 10).
///
/// Physical sizes are real-world; the simulation multiplies them by `car_scale`.
/// [power] is peak acceleration (m/s²), [brake] deceleration (m/s²), grips are the
/// maximum lateral acceleration per axle (m/s²), [driftBias] scales rear grip under
/// handbrake, [steerSpeed] is how fast the wheels turn (rad/s).
class CarSpec {
  CarSpec({
    required this.id,
    required this.name,
    required this.carClass,
    required this.lengthM,
    required this.widthM,
    required this.mass,
    required this.power,
    required this.brake,
    required this.gripFront,
    required this.gripRear,
    required this.driftBias,
    required this.steerSpeed,
    required this.topSpeed,
    required this.paint,
  });

  factory CarSpec.fromJson(String src) {
    final j = jsonDecode(src) as Map<String, dynamic>;
    double d(String k) => (j[k] as num).toDouble();
    final hex = (j['paint'] as String? ?? '#D7263D').replaceFirst('#', '');
    return CarSpec(
      id: j['id'] as String,
      name: j['name'] as String,
      carClass: j['class'] as String,
      lengthM: d('length_m'),
      widthM: d('width_m'),
      mass: d('mass'),
      power: d('power'),
      brake: d('brake'),
      gripFront: d('grip_front'),
      gripRear: d('grip_rear'),
      driftBias: d('drift_bias'),
      steerSpeed: d('steer_speed'),
      topSpeed: d('top_speed'),
      paint: Color(int.parse('FF$hex', radix: 16)),
    );
  }

  final String id;
  final String name;
  final String carClass;
  final double lengthM;
  final double widthM;
  double mass;
  double power;
  double brake;
  double gripFront;
  double gripRear;
  double driftBias;
  double steerSpeed;
  double topSpeed;
  Color paint;
}
