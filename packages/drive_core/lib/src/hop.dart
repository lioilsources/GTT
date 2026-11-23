import 'package:world_engine/core.dart';

/// Hops per full air tank of [spec] (`hop.charges`, specs/hop.md), or null for cars that cannot hop.
int? hopCharges(CarSpec spec) {
  final c = spec.hop?['charges'];
  return c is num ? c.toInt() : null;
}

/// Whether a hop can start now (specs/hop.md "Pravidla"): the car has `hop`, the tank is not
/// empty, the car is on the ground and at least `hop.min_speed_mps` fast, on any layer (v2: bridges
/// and tunnels too; [layer] stays in the signature of the spec).
bool canHop(CarSpec spec, int charges, double air, int layer, double speed, TuningHop t) =>
    hopCharges(spec) != null && charges > 0 && air <= 0 && speed >= t.minSpeedMps;

/// Height of the arc (metres) [t] seconds into a hop of [airS] seconds peaking at [heightM].
double hopArc(double t, double airS, double heightM) {
  if (airS <= 0) return 0;
  final u = (t / airS).clamp(0.0, 1.0);
  return 4 * heightM * u * (1 - u);
}

/// Hop state of the driven car for one session (not saved).
class HopState {
  /// Hops left in the tank.
  int charges = 0;

  /// Flight time left (s); 0 = on the ground.
  double air = 0;

  /// Time since take-off (s).
  double t = 0;

  bool get airborne => air > 0;

  /// Full tank for [spec] (0 for cars without `hop`); lands the car.
  void fill(CarSpec spec) {
    charges = hopCharges(spec) ?? 0;
    air = 0;
    t = 0;
  }

  /// Whether the garage offers the free refill (specs/hop.md "Doplnění").
  bool canRefill(CarSpec spec) {
    final full = hopCharges(spec);
    return full != null && charges < full;
  }

  /// Spends a charge and takes off; false when [canHop] says no.
  bool start(CarSpec spec, int layer, double speed, TuningHop tuning) {
    if (!canHop(spec, charges, air, layer, speed, tuning)) return false;
    charges--;
    air = tuning.airS;
    t = 0;
    return true;
  }

  /// Advances the flight by one fixed step; true on the step the car lands.
  bool step(double dt) {
    if (air <= 0) return false;
    t += dt;
    air -= dt;
    if (air > 0) return false;
    air = 0;
    t = 0;
    return true;
  }
}
