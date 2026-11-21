import 'dart:math' as math;

import 'package:shared_gen/shared_gen.dart';

/// Roof scale for height [h] (METROPOLE_PLAN 6.2):
/// h_eff = h for h ≤ knee, knee + (h − knee)^exp above; s = min(1 + k·h_eff, max_scale).
double extrusionScale(double h, Tuning t) {
  final e = t.extrusion;
  final he = h <= e.kneeM ? h : e.kneeM + math.pow(h - e.kneeM, e.exp);
  return math.min(1 + e.k * he, e.maxScale);
}
