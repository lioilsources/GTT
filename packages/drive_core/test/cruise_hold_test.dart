import 'dart:io';
import 'dart:math' as math;

import 'package:drive_core/drive_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge2d/forge2d.dart' show World, Vector2;
import 'package:world_engine/core.dart';

// Cruise hold (specs/drive.md v2 step 2), the same constant-grade checks as web/test/cruiseHold.test.ts.
// Client F has no relief yet (F-070): the slope force is applied here by hand, as client W does.

final _yaml = File('../../content/tuning.yaml').readAsStringSync();
final tuning = Tuning.fromYaml(_yaml);
final noHold = Tuning.fromYaml(_yaml.replaceFirst(RegExp(r'cruise_hold_mps2: [0-9.]+'), 'cruise_hold_mps2: 0.0'));
CarSpec spec() => parseCarSpec(File('../../content/cars/${tuning.cars.startCar}.json').readAsStringSync());

/// Car alone on a constant grade; speed band (lo, hi) after 5 s of 20 s.
(double, double) constantGrade(double grade, {bool hold = true, bool boost = false}) {
  final t = hold ? tuning : noHold;
  final d = t.drive, cruise = t.speedMps.cruise, dt = 1 / d.stepHz;
  final w = World(gravity: Vector2.zero());
  final car = Car(w, spec(), d, x: 0, y: 0, heading: 0, scale: t.carScale);
  car.body.linearVelocity = Vector2(cruise, 0);
  final sp = t.slopePhysics;
  final a = -sp.gravity * sp.slopeForceScale * grade / math.sqrt(1 + grade * grade); // along +x
  final input = ControlInput()..boost = boost;
  var lo = double.infinity, hi = double.negativeInfinity;
  for (var i = 0; i < 20 / dt; i++) {
    car.drive(input, dt, cruise: cruise, top: t.speedMps.topDefault, slopeF: a);
    car.body.applyForce(Vector2(a * car.body.mass, 0));
    w.step(dt, subStepCount: d.substeps);
    if (i * dt >= 5) {
      lo = math.min(lo, car.speed);
      hi = math.max(hi, car.speed);
    }
  }
  w.destroy();
  return (lo, hi);
}

void main() {
  setUpAll(() async => initializeForge2D());
  final cruise = tuning.speedMps.cruise;

  test('flat: steady at cruise', () {
    final (lo, hi) = constantGrade(0);
    expect(lo, greaterThan(cruise - 0.5));
    expect(hi, lessThan(cruise + 0.5));
  });
  for (final g in [-0.1, -0.2, -0.33]) {
    test('${(-g * 100).round()} % downhill: holds cruise (no overspeed band)', () {
      final (lo, hi) = constantGrade(g);
      expect(lo, greaterThan(cruise - 0.5));
      expect(hi, lessThan(cruise + 0.5));
    });
  }
  test('without the hold the car rides the overspeed band downhill', () {
    final (_, hi) = constantGrade(-0.3, hold: false);
    expect(hi, greaterThan(cruise + tuning.drive.overspeedMps * 0.8));
  });
  test('uphill unchanged: power-limited, no hold braking', () {
    final a = constantGrade(0.1), b = constantGrade(0.1, hold: false);
    expect(a.$1, closeTo(b.$1, 1e-6));
    expect(a.$2, closeTo(b.$2, 1e-6));
  });
  test('boost does not hold: it accelerates past cruise downhill', () {
    expect(constantGrade(-0.1, boost: true).$2, greaterThan(cruise + 5));
  });
}
