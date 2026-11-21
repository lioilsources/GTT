import 'dart:convert';

import 'package:shared_gen/shared_gen.dart';

/// Parses `content/cars/<id>.json` into the generated [CarSpec] (schema/car.schema.json).
///
/// Physical sizes are real-world; the simulation multiplies them by `car_scale`.
/// power is peak acceleration (m/s²), brake deceleration (m/s²), grips are the maximum
/// lateral acceleration per axle (m/s²), driftBias scales rear grip under handbrake.
CarSpec parseCarSpec(String json) => CarSpec.fromJson(jsonDecode(json) as Map<String, Object?>);

/// Body colour as 0xAARRGGBB.
int paintArgb(CarSpec s) => 0xFF000000 | int.parse(s.paint.substring(1), radix: 16);
