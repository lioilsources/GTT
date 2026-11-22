import 'dart:io';
import 'dart:math' as math;

import 'package:drive_core/drive_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge2d/forge2d.dart' show World, Vector2;
import 'package:shared_gen/shared_gen.dart' show Tuning;

// specs/garage.md v1 "Účinek na jízdu": tunedSpec and the acceptance test (M2_NYC.md "tuning mění
// jízdu měřitelně") on the real car of specs/drive.md.
final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
CarSpec coupe() => parseCarSpec(File('../../content/cars/m0_coupe.json').readAsStringSync());

void main() {
  setUpAll(() async => initializeForge2D());
  final d = tuning.drive, g = tuning.garage;
  final dt = 1 / d.stepHz;

  group('tunedSpec', () {
    test('level 0 everywhere is the catalog car; the input spec is not changed', () {
      final s = coupe();
      final before = s.toJson().toString();
      expect(tunedSpec(s, const {}, g).toJson().toString(), before);
      expect(tunedSpec(s, const {'engine': 0, 'tyres': 0}, g).toJson().toString(), before);
      tunedSpec(s, const {'engine': 3, 'tyres': 3, 'weight': 3}, g);
      expect(s.toJson().toString(), before);
    });

    test('multipliers per slot; two multipliers of one parameter multiply', () {
      final s = coupe();
      final t = tunedSpec(s, const {'engine': 2, 'tyres': 3, 'brakes': 1, 'weight': 3, 'drift': 2}, g);
      expect(t.power, closeTo(s.power * (1 + g.enginePowerStep * 2) * (1 + g.weightPowerStep * 3), 1e-9));
      expect(t.topSpeed, closeTo(s.topSpeed * (1 + g.engineTopStep * 2), 1e-9));
      expect(t.gripFront, closeTo(s.gripFront * (1 + g.tyresStep * 3), 1e-9));
      expect(t.gripRear, closeTo(s.gripRear * (1 + g.tyresStep * 3), 1e-9));
      expect(t.brake, closeTo(s.brake * (1 + g.brakesStep), 1e-9));
      expect(t.mass, closeTo(s.mass * (1 - g.weightMassStep * 3), 1e-9));
      expect(t.steerSpeed, closeTo(s.steerSpeed * (1 + g.weightSteerStep * 3), 1e-9));
      expect(t.driftBias, closeTo(s.driftBias * (1 - g.driftStep * 2), 1e-9));
      expect((t.id, t.class_, t.lengthM, t.widthM, t.paint), (s.id, s.class_, s.lengthM, s.widthM, s.paint));
    });
  });

  group('acceptance (specs/garage.md)', () {
    void step(Car car, World w, ControlInput input) {
      car.drive(input, dt, cruise: tuning.speedMps.cruise, top: tuning.speedMps.topDefault);
      w.step(dt, subStepCount: d.substeps);
    }

    /// Full throttle from 0 on the flat: seconds to 25 m/s.
    double timeTo25(CarSpec spec) {
      final w = World(gravity: Vector2.zero());
      final car = Car(w, spec, d, x: 0, y: 0, heading: 0, scale: tuning.carScale);
      final input = ControlInput()
        ..throttle = 1
        ..boost = true;
      var t = 0.0;
      while (car.forwardSpeed < 25 && t < 60) {
        step(car, w, input);
        t += dt;
      }
      w.destroy();
      return t;
    }

    /// Full turn at 15 m/s held for 3 s: radius = v / yaw rate, and the mean lateral slip.
    ({double radius, double slip}) turn(CarSpec spec) {
      final w = World(gravity: Vector2.zero());
      final car = Car(w, spec, d, x: 0, y: 0, heading: 0, scale: tuning.carScale);
      car.body.linearVelocity = Vector2(15, 0);
      final input = ControlInput()..steer = 1;
      var slip = 0.0;
      final n = (3 * d.stepHz).round();
      for (var i = 0; i < n; i++) {
        // Hold 15 m/s: the auto-throttle aims at the cruise speed, so give it 15.
        car.drive(input, dt, cruise: 15, top: tuning.speedMps.topDefault);
        w.step(dt, subStepCount: d.substeps);
        slip += car.frontSlip + car.rearSlip;
      }
      final r = car.speed / math.max(car.body.angularVelocity.abs(), 1e-9);
      w.destroy();
      return (radius: r, slip: slip / n);
    }

    test('engine 3 reaches 25 m/s at least 10 % sooner', () {
      final base = timeTo25(coupe());
      final tuned = timeTo25(tunedSpec(coupe(), const {'engine': 3}, g));
      // ignore: avoid_print
      print('engine 3: 0–25 m/s ${base.toStringAsFixed(3)} s → ${tuned.toStringAsFixed(3)} s '
          '(${((1 - tuned / base) * 100).toStringAsFixed(1)} % sooner)');
      expect(base, lessThan(60), reason: 'the base car reaches 25 m/s');
      expect(tuned, lessThanOrEqualTo(base * 0.9));
    });

    test('tyres 3 hold a full turn at 15 m/s with at least 5 % smaller radius (or less slip)', () {
      final base = turn(coupe());
      final tuned = turn(tunedSpec(coupe(), const {'tyres': 3}, g));
      // ignore: avoid_print
      print('tyres 3: radius ${base.radius.toStringAsFixed(2)} m → ${tuned.radius.toStringAsFixed(2)} m '
          '(${((1 - tuned.radius / base.radius) * 100).toStringAsFixed(1)} % smaller), mean slip '
          '${base.slip.toStringAsFixed(3)} → ${tuned.slip.toStringAsFixed(3)} m/s');
      // At 15 m/s the turn of the coupe is limited by the steering lock (v²/r below the catalog
      // grip), so the radius barely moves; the spec's alternative, less lateral slip, measures it.
      expect(tuned.radius <= base.radius * 0.95 || tuned.slip < base.slip * 0.95, isTrue);
      expect(tuned.radius, lessThanOrEqualTo(base.radius * 1.001), reason: 'never a wider turn');
    });

    test('rain gripScale still multiplies the tuned grip', () {
      double slip(CarSpec s, double scale) {
        final w = World(gravity: Vector2.zero());
        final car = Car(w, s, d, x: 0, y: 0, heading: 0, scale: tuning.carScale)..gripScale = scale;
        car.body.linearVelocity = Vector2(20, 0);
        var sum = 0.0;
        for (var i = 0; i < 2 * d.stepHz; i++) {
          car.drive(ControlInput()..steer = 1, dt, cruise: 20, top: tuning.speedMps.topDefault);
          w.step(dt, subStepCount: d.substeps);
          sum += car.frontSlip + car.rearSlip;
        }
        w.destroy();
        return sum;
      }

      final tyres = tunedSpec(coupe(), const {'tyres': 3}, g);
      expect(slip(tyres, tuning.weather.rainGrip), greaterThan(slip(tyres, 1)));
    });
  });
}
