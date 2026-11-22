import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drive_core/drive_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge2d/forge2d.dart' show World, Vector2;
import 'package:world_engine/core.dart';

final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());

/// The M0 coupe with its class swapped, so only the class differs between the two cars.
CarSpec specOf(String cls) {
  final j = jsonDecode(File('../../content/cars/m0_coupe.json').readAsStringSync()) as Map<String, Object?>;
  return CarSpec.fromJson({...j, 'class': cls});
}

/// A 20 × 20 m square zone from (10, -10) to (30, 10), two triangles.
GroundData squareZone(GroundKind kind) =>
    GroundData(kind, Float32List.fromList([10, -10, 30, -10, 30, 10, 10, 10]), Uint16List.fromList([0, 1, 2, 0, 2, 3]));

/// Chunk (0, 0) with one bollard line across the x axis at x = 10 (the zone's west edge).
ChunkData barrierChunk({bool zone = true}) => ChunkData(
  0,
  0,
  const [],
  [if (zone) squareZone(GroundKind.PEDESTRIAN)],
  [
    Float32List.fromList([10, -10, 10, 0, 10, 10]),
  ],
);

void main() {
  setUpAll(() async => initializeForge2D());

  test('zoneMask table (specs/zones.md)', () {
    for (final (cls, inside, bits) in [
      ('sedan', false, catZone),
      ('sedan', true, 0),
      ('coupe', false, catZone),
      ('bus', true, 0),
      ('micro', false, 0),
      ('micro', true, 0),
    ]) {
      expect(zoneMask(cls, inside), bits, reason: '$cls inside=$inside');
    }
  });

  test('point in zone on a small synthetic mesh', () {
    final z = squareZone(GroundKind.PEDESTRIAN);
    expect(pointInMesh(z.xy, z.indices, 20, 0), isTrue);
    expect(pointInMesh(z.xy, z.indices, 29, 9), isTrue);
    expect(pointInMesh(z.xy, z.indices, 11, -9), isTrue);
    expect(pointInMesh(z.xy, z.indices, 9, 0), isFalse);
    expect(pointInMesh(z.xy, z.indices, 20, 11), isFalse);

    final w = World(gravity: Vector2.zero());
    final zones = Zones(w, tuning)
      ..add(ChunkData(0, 0, const [], [squareZone(GroundKind.PARK)]))
      ..add(
        ChunkData(1, 0, const [], [
          GroundData(
            GroundKind.PEDESTRIAN,
            Float32List.fromList([110, 0, 120, 0, 110, 10]),
            Uint16List.fromList([0, 1, 2]),
          ),
        ]),
      );
    expect(zones.contains(20, 0), isFalse, reason: 'a park is not a pedestrian zone');
    expect(zones.contains(112, 2), isTrue);
    expect(zones.contains(119, 9), isFalse, reason: 'outside the triangle but inside its box');
    zones.remove(ChunkData(1, 0, const [], const []));
    expect(zones.contains(112, 2), isFalse);
    w.destroy();
  });

  test('a chunk with one barrier creates bollard fixtures; unloading removes them', () {
    final w = World(gravity: Vector2.zero());
    final zones = Zones(w, tuning);
    final c = barrierChunk();
    zones.add(c);
    final body = zones.bodyOf(0, 0)!;
    expect(body.shapes, hasLength(2));
    for (final s in body.shapes) {
      expect(s.filter.categoryBits, catZone);
      expect(s.filter.maskBits, catCar);
    }
    expect(zones.bodyCount, 1);
    final b = zones.bollards.single;
    final spacing = tuning.zones.bollardSpacingM;
    expect(b.length ~/ 2, greaterThanOrEqualTo((20 / spacing).floor()));
    for (var i = 0; i < b.length; i += 2) {
      expect(b[i], closeTo(10, 1e-4));
    }
    zones.remove(c);
    expect(body.isValid, isFalse);
    expect(zones.bodyOf(0, 0), isNull);
    expect(zones.bodyCount, 0);
    expect(zones.bollards, isEmpty);
    w.destroy();
  });

  group('driving into a barrier', () {
    final d = tuning.drive;

    /// Drives east from x = 0 for [seconds]; the barrier stands at x = 10.
    double drive(String cls, {bool zone = false, double seconds = 4}) {
      final w = World(gravity: Vector2.zero());
      final zones = Zones(w, tuning)..add(barrierChunk(zone: zone));
      final car = Car(w, specOf(cls), d, x: 0, y: 0, heading: 0, scale: tuning.carScale);
      final input = ControlInput();
      for (var i = 0; i < seconds * d.stepHz; i++) {
        car.drive(input, 1 / d.stepHz, cruise: tuning.speedMps.cruise, top: tuning.speedMps.topDefault);
        w.step(1 / d.stepHz, subStepCount: d.substeps);
        car.setInsideZone(zones.insideFor(car.x, car.y, car.boundingRadius, wasInside: car.zoneBits == 0));
      }
      final x = car.x;
      w.destroy();
      return x;
    }

    test('a non-micro car stops at the bollards', () {
      expect(drive('coupe'), lessThan(10));
    });

    test('a micro vehicle rides through', () {
      expect(drive('micro'), greaterThan(12));
    });

    test('a car whose centre is inside a zone is not stopped (it can always get out)', () {
      final w = World(gravity: Vector2.zero());
      final zones = Zones(w, tuning)..add(barrierChunk());
      // Parked inside the zone, facing west, out through the bollard line.
      final car = Car(w, specOf('coupe'), d, x: 14, y: 0, heading: math.pi, scale: tuning.carScale);
      car.setInsideZone(zones.insideFor(car.x, car.y, car.boundingRadius, wasInside: car.zoneBits == 0));
      expect(car.zoneBits, 0);
      for (var i = 0; i < 4 * d.stepHz; i++) {
        car.drive(ControlInput(), 1 / d.stepHz, cruise: tuning.speedMps.cruise, top: tuning.speedMps.topDefault);
        w.step(1 / d.stepHz, subStepCount: d.substeps);
        car.setInsideZone(zones.insideFor(car.x, car.y, car.boundingRadius, wasInside: car.zoneBits == 0));
      }
      expect(car.x, lessThan(6));
      expect(car.zoneBits, catZone, reason: 'outside again, bollards are back in the mask');
      w.destroy();
    });

    test('bollards are only in the mask on layer 0', () {
      final w = World(gravity: Vector2.zero());
      final car = Car(w, specOf('coupe'), d, x: 0, y: 0, heading: 0, scale: tuning.carScale);
      expect(car.maskBits & catZone, catZone);
      car.setLayer(1);
      expect(car.maskBits & catZone, 0);
      w.destroy();
    });
  });

  test('micro handbrake only slows down, no yaw kick', () {
    final d = tuning.drive;
    double yaw(String cls) {
      final w = World(gravity: Vector2.zero());
      final car = Car(w, specOf(cls), d, x: 0, y: 0, heading: 0, scale: tuning.carScale);
      for (var i = 0; i < 4 * d.stepHz; i++) {
        car.drive(ControlInput(), 1 / d.stepHz, cruise: tuning.speedMps.cruise, top: tuning.speedMps.topDefault);
        w.step(1 / d.stepHz, subStepCount: d.substeps);
      }
      // One step of handbrake straight ahead with full steer: only the yaw impulse turns the car
      // this fast, the tyres barely react in a single step.
      final w0 = car.body.angularVelocity;
      car.drive(
        ControlInput()
          ..steer = 1
          ..handbrake = true,
        1 / d.stepHz,
        cruise: tuning.speedMps.cruise,
        top: tuning.speedMps.topDefault,
      );
      final dw = (car.body.angularVelocity - w0).abs();
      w.destroy();
      return dw;
    }

    expect(yaw('micro'), lessThan(yaw('coupe') * 0.5));
  });
}
