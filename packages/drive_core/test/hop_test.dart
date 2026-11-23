import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drive_core/drive_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge2d/forge2d.dart' show Vector2;
import 'package:world_engine/core.dart';

final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
TuningHop get h => tuning.hop;
CarSpec car(String id) => parseCarSpec(File('../../content/cars/$id.json').readAsStringSync());

class _FilePack implements PackSource {
  _FilePack(this.root);
  final String root;
  @override
  Future<Uint8List> read(String path) async => File('$root$path').readAsBytes();
}

void main() {
  final roadster = car('vega_roadster'), coupe = car('m0_coupe');

  group('hop rules (specs/hop.md)', () {
    test('only the Roadster carries an air tank', () {
      expect(hopCharges(roadster), 3);
      expect(hopCharges(coupe), isNull);
      for (final f in Directory('../../content/cars').listSync().whereType<File>()) {
        final s = parseCarSpec(f.readAsStringSync());
        if (s.id != 'vega_roadster') expect(hopCharges(s), isNull, reason: s.id);
      }
    });

    test('canHop table', () {
      final v = h.minSpeedMps;
      final rows = <(CarSpec, int, double, int, double, bool)>[
        (roadster, 3, 0, 0, v, true),
        (roadster, 1, 0, 0, v + 10, true),
        (roadster, 0, 0, 0, v, false), // empty tank
        (roadster, 3, 0.5, 0, v, false), // already in the air
        (roadster, 3, 0, 1, v, true), // bridge (v2)
        (roadster, 3, 0, -1, v, true), // tunnel (v2)
        (roadster, 3, 0, 1, v - 0.01, false), // bridge, too slow
        (roadster, 3, 0, 0, v - 0.01, false), // too slow
        (coupe, 3, 0, 0, v, false), // no hop
      ];
      for (final (s, charges, air, layer, speed, want) in rows) {
        expect(canHop(s, charges, air, layer, speed, h), want, reason: '${s.id} $charges $air $layer $speed');
      }
    });

    test('hopArc is a parabola: 0 at both ends, heightM at the top, clamped outside', () {
      const air = 1.4, top = 7.0;
      expect(hopArc(0, air, top), 0);
      expect(hopArc(air, air, top), closeTo(0, 1e-12));
      expect(hopArc(air / 2, air, top), closeTo(top, 1e-12));
      expect(hopArc(air / 4, air, top), closeTo(4 * top * 0.25 * 0.75, 1e-12));
      expect(hopArc(air / 4, air, top), closeTo(hopArc(3 * air / 4, air, top), 1e-12));
      expect(hopArc(-1, air, top), 0);
      expect(hopArc(air + 1, air, top), 0);
      expect(hopArc(0.3, 0, top), 0);
    });

    test('session state: full tank, a charge per hop, flight time, blocked at 0, refill', () {
      final s = HopState()..fill(roadster);
      expect(s.charges, 3);
      expect(s.canRefill(roadster), isFalse);
      for (var i = 0; i < 3; i++) {
        expect(s.start(roadster, 0, h.minSpeedMps, h), isTrue);
        expect(s.airborne, isTrue);
        expect(s.air, h.airS);
        // No second hop while in the air.
        expect(s.start(roadster, 0, h.minSpeedMps, h), isFalse);
        var landed = false;
        var steps = 0;
        while (!landed) {
          landed = s.step(1 / 60);
          steps++;
        }
        expect(steps, (h.airS * 60).ceil());
        expect(s.airborne, isFalse);
      }
      expect(s.charges, 0);
      expect(s.start(roadster, 0, h.minSpeedMps * 2, h), isFalse);
      expect(s.canRefill(roadster), isTrue);
      expect(s.canRefill(coupe), isFalse);
      s.fill(coupe);
      expect(s.charges, 0);
    });
  });

  group('hop in the NYC pack', () {
    const root = '../../build/packs/nyc/';
    final has = File('${root}manifest.pb').existsSync();
    late City city;
    final chunks = <ChunkData>[];
    setUpAll(() async {
      if (!has) return;
      await initializeForge2D();
      final src = _FilePack(root);
      city = await City.load(src);
      final cx = (city.startX / city.chunkM).floor(), cy = (city.startY / city.chunkM).floor();
      for (final c in city.manifest.chunks) {
        if ((c.x - cx).abs() > 2 || (c.y - cy).abs() > 2) continue;
        chunks.add(prepareChunk(await src.read(chunkPath(c.x, c.y))));
      }
    });
    DriveWorld world(CarSpec spec) {
      final d = DriveWorld(city: city, spec: spec, tuning: tuning);
      for (final c in chunks) {
        d.addChunk(c);
      }
      return d;
    }

    /// A stopped traffic car 12 m ahead on a straight stretch, the player coming at 20 m/s.
    /// Returns how far past the target (along its heading) the player ends, and the hit count.
    (double, int, DriveWorld) run(CarSpec spec, {required bool hop}) {
      final d = world(spec);
      final tr = d.traffic!;
      final hit = city.graph.nearest(
        d.car.x,
        d.car.y,
        maxDist: 300,
        where: (e) => e.kept && e.isGround && e.oneway >= 0 && e.length > 120,
      )!;
      final e = hit.edge;
      d.spawn(hit.x, hit.y, 0);
      d.update(1 / 60);
      tr.reset();
      final target = tr.addCar(e.index, 1, math.min(e.length - 15, hit.t * e.length + 30), 0)!;
      final hx = math.cos(target.heading), hy = math.sin(target.heading);
      d.spawn(target.x - hx * 12, target.y - hy * 12, target.heading);
      d.car.body.linearVelocity = Vector2(hx * 20, hy * 20);
      var hits = 0;
      tr.onHit((c, _) {
        if (identical(c, target)) hits++;
      });
      if (hop) {
        expect(d.startHop(), isTrue);
        expect(d.car.maskBits, catBuildings);
        expect(d.hop.charges, 2);
      }
      for (var i = 0; i < (h.airS * 60).ceil() + 2; i++) {
        target.speed = 0;
        d.input
          ..reset()
          ..boost = true;
        d.update(1 / 60);
        if (hop && d.hop.airborne) expect(d.car.layer, 0);
      }
      final along = (d.car.x - target.x) * hx + (d.car.y - target.y) * hy;
      return (along - target.halfLength - d.car.halfLength, hits, d);
    }

    test('the Roadster hops over a car in its path and lands beyond; a normal car stops at it', () {
      final (past, hits, d) = run(roadster, hop: true);
      expect(hits, 0);
      expect(past, greaterThan(0));
      expect(d.hop.airborne, isFalse);
      // Back on the ground the mask follows the layer again (traffic, trams, parked cars).
      expect(d.car.maskBits & catTraffic, catTraffic);
      d.dispose();

      final (pastC, hitsC, dc) = run(coupe, hop: false);
      expect(hitsC, 1);
      expect(pastC, lessThan(0));
      expect(dc.startHop(), isFalse);
      dc.dispose();
    }, skip: !has);

    test('switching cars refills the tank; the free refill tops it up', () {
      final d = world(roadster);
      expect(d.hop.charges, 3);
      d.hop.charges = 0;
      expect(d.refillHop(), isTrue);
      expect(d.hop.charges, 3);
      expect(d.refillHop(), isFalse);
      d.hop.charges = 1;
      d.replaceCar(coupe, d.car.x, d.car.y, d.car.heading);
      expect(d.hop.charges, 0);
      expect(d.refillHop(), isFalse);
      d.replaceCar(roadster, d.car.x, d.car.y, d.car.heading);
      expect(d.hop.charges, 3);
      d.dispose();
    }, skip: !has);
  });
}
