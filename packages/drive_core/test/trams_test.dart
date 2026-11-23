import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drive_core/drive_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge2d/forge2d.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/citypack_pb.dart' as pb;
import 'package:world_engine/core.dart';

final _src = File('../../content/tuning.yaml').readAsStringSync();
Tuning freshTuning() => Tuning.fromYaml(_src);
CarSpec spec() => parseCarSpec(File('../../content/cars/m0_coupe.json').readAsStringSync());

pb.Node _n(int x, int y, [bool border = false]) => pb.Node(x: x * 10, y: y * 10, border: border);

pb.TramEdge _e(int from, int to, List<int> pts, {int layer = 0}) =>
    pb.TramEdge(from: from, to: to, points: pts.map((v) => v * 10), layerFrom: layer, layerTo: layer);

/// A tiny track net: a junction at node 0, a border node 3 and a terminus at node 4.
///
///   2
///   |e1
///   0 --e0-- 1
///  e2         |e3
///   3(border) 4 (terminus)
TrackGraph tinyNet() => TrackGraph.fromPb(
  pb.TramGraph(
    nodes: [_n(0, 0), _n(100, 0), _n(0, 100), _n(-100, 0, true), _n(100, 100)],
    edges: [
      _e(0, 1, [0, 0, 50, 0, 100, 0]),
      _e(2, 0, [0, 100, 0, 0]),
      _e(0, 3, [0, 0, -100, 0]),
      _e(1, 4, [100, 0, 100, 100]),
    ],
    // Listed out of order on purpose: stopsByEdge sorts them by s_m.
    stops: [pb.TramStop(edge: 0, sM: 70), pb.TramStop(edge: 0, sM: 30)],
  ),
);

/// One straight track from (0, y) to (len, y), both ends plain termini, with optional stops.
TrackGraph straightTrack({double y = 0, int len = 600, List<double> stops = const []}) => TrackGraph.fromPb(
  pb.TramGraph(
    nodes: [
      pb.Node(x: 0, y: (y * 10).round()),
      pb.Node(x: len * 10, y: (y * 10).round()),
    ],
    edges: [
      pb.TramEdge(from: 0, to: 1, points: [0, (y * 10).round(), len * 10, (y * 10).round()]),
    ],
    stops: [for (final s in stops) pb.TramStop(edge: 0, sM: s)],
  ),
);

Uint8List _gz(List<int> b) => Uint8List.fromList(gzip.encode(b));

/// A citypack held in memory; a file not in [files] fails like a missing asset.
class _MemPack implements PackSource {
  _MemPack(this.files);
  final Map<String, Uint8List> files;
  @override
  Future<Uint8List> read(String path) async => files[path] ?? (throw StateError('no $path in the pack'));
}

/// A pack with one straight two-way road along x (0..600 m) and, when given, a tram track.
Map<String, Uint8List> roadPack({pb.TramGraph? trams}) => {
  'manifest.pb': _gz(
    pb.Manifest(
      formatVersion: 1,
      cityId: 'test',
      driveSide: 'right',
      units: 'metric',
      chunkM: 256,
      start: pb.Spawn(x: 3000, y: 1500),
    ).writeToBuffer(),
  ),
  'graph.pb': _gz(
    pb.Graph(
      names: [''],
      nodes: [_n(0, 0), _n(600, 0)],
      edges: [
        pb.Edge(
          from: 0,
          to: 1,
          points: [0, 0, 6000, 0],
          class_4: pb.RoadClass.PRIMARY,
          lanes: 2,
          kept: true,
          widthM: 26,
        ),
      ],
    ).writeToBuffer(),
  ),
  'landmarks.pb': _gz(pb.Landmarks().writeToBuffer()),
  'spots.pb': _gz(pb.Spots().writeToBuffer()),
  if (trams != null) 'trams.pb': _gz(trams.writeToBuffer()),
};

void main() {
  group('tram rules (specs/trams.md)', () {
    test('next edge: ascending candidates without the arrival edge, shared PRNG', () {
      final g = tinyNet();
      final rng = Prng(42), ref = Prng(42);
      // At junction 0 arriving along e0 the candidates are [1, 2]; along e1 they are [0, 2].
      for (var i = 0; i < 12; i++) {
        expect(chooseNextTrack(g, 0, 0, rng), [1, 2][ref.nextInt(2)]);
      }
      for (var i = 0; i < 12; i++) {
        expect(chooseNextTrack(g, 0, 1, rng), [0, 2][ref.nextInt(2)]);
      }
      // A single candidate still draws from the PRNG (nextInt(1)).
      expect(chooseNextTrack(g, 1, 0, rng), 3);
      ref.nextInt(1);
      expect(rng.state, ref.state);
    });

    test('next edge: a terminus turns back without drawing, a border node despawns', () {
      final g = tinyNet();
      final rng = Prng(7);
      final before = rng.state;
      expect(chooseNextTrack(g, 4, 3, rng), 3);
      expect(chooseNextTrack(g, 2, 1, rng), 1);
      expect(rng.state, before);
      expect(chooseNextTrack(g, 3, 2, rng), -1);
    });

    test('articulate: straight trail', () {
      final trail = TramTrail(8, carM: 14, gapM: 0.6)
        ..push(0, 0, 0)
        ..push(50, 0, 0)
        ..setNose(100, 0, 1, 0, 0);
      final p = [for (var k = 0; k < 3; k++) articulate(trail, k)];
      expect(p[0].x, closeTo(93, 1e-9));
      expect(p[1].x, closeTo(78.4, 1e-9));
      expect(p[2].x, closeTo(63.8, 1e-9));
      for (final c in p) {
        expect(c.y, closeTo(0, 1e-9));
        expect(c.heading, closeTo(0, 1e-9));
      }
    });

    test('articulate: bent trail follows the corner, then extrapolates straight', () {
      final trail = TramTrail(8, carM: 14, gapM: 0.6)
        ..push(-100, 0, 0)
        ..push(0, 0, 0)
        ..setNose(0, 10, 0, 1, 0);
      final c0 = articulate(trail, 0);
      // Front joint at the nose (0, 10), rear joint 14 m back: 10 m down, 4 m along −x.
      expect(c0.x, closeTo(-2, 1e-9));
      expect(c0.y, closeTo(5, 1e-9));
      expect(c0.heading, closeTo(math.atan2(10, 4), 1e-9));
      final c1 = articulate(trail, 1);
      expect(c1.x, closeTo(-11.6, 1e-9));
      expect(c1.y, closeTo(0, 1e-9));
      expect(c1.heading, closeTo(0, 1e-9));
      // Nothing stored: the cars line up straight behind the nose.
      final empty = TramTrail(8, carM: 14, gapM: 0.6)..setNose(0, 0, 1, 0, 0);
      expect(articulate(empty, 1).x, closeTo(-21.6, 1e-9));
      // The ring keeps only the newest points.
      final ring = TramTrail(2, carM: 14, gapM: 0.6)
        ..push(-100, 0, 0)
        ..push(-50, 0, 0)
        ..push(-20, 0, 0);
      expect(ring.count, 2);
      expect(ring.xAt(0), -20);
      expect(ring.xAt(1), -50);
    });

    test('stop ahead skips stops closer than the commit distance', () {
      final g = tinyNet();
      const commit = 4.0;
      // Stop 0 is at s_m 70, stop 1 at s_m 30.
      expect(g.stopsByEdge[0], [1, 0]);
      expect(nextStopAhead(g, 0, 1, 0, commit), 1);
      expect(nextStopAhead(g, 0, 1, 25, commit), 1);
      expect(nextStopAhead(g, 0, 1, 27, commit), 0);
      expect(nextStopAhead(g, 0, 1, 67, commit), -1);
      expect(nextStopAhead(g, 0, 1, 0, commit, skip: 1), 0);
      // Driving to → from: s counts from the `to` end, so s_m 70 comes first (30 m in).
      expect(nextStopAhead(g, 0, -1, 0, commit), 0);
      expect(nextStopAhead(g, 0, -1, 27, commit), 1);
      expect(nextStopAhead(g, 0, -1, 80, commit), -1);
      expect(nextStopAhead(g, 1, 1, 0, commit), -1);
      expect(stopTravelS(g, 0, -1), closeTo(30, 1e-9));
    });
  });

  group('trams world', () {
    setUpAll(() async => initializeForge2D());

    test('a tram dwells at a stop, then leaves', () {
      final tuning = freshTuning();
      final t = tuning.trams..maxTrams = 1; // no random spawns next to the test tram
      final world = World(gravity: Vector2.zero());
      final player = Car(world, spec(), tuning.drive, x: 300, y: 200, heading: 0, scale: tuning.carScale);
      final trams = Trams(world, straightTrack(stops: [100]), tuning);
      final tram = trams.addTram(0, 1, 20)!;
      expect(tram.cars, hasLength(t.carsPerTram));
      const dt = 1 / 60;
      var dwellSteps = 0;
      double? dwellAt;
      for (var i = 0; i < 60 * 60 && (dwellAt == null || tram.dwell > 0 || tram.s < 130); i++) {
        trams.preStep(dt, player);
        world.step(dt, subStepCount: tuning.drive.substeps);
        trams.postStep(player);
        if (tram.dwell > 0) {
          dwellAt ??= tram.s;
          dwellSteps++;
          expect(tram.speed, 0);
        }
      }
      expect(dwellAt, isNotNull);
      expect(dwellAt!, closeTo(100, t.stopCommitM));
      expect(dwellSteps * dt, closeTo(t.dwellS, 2 * dt));
      expect(tram.served, 0);
      expect(tram.s, greaterThan(130));
      expect(tram.speed, greaterThan(0));
      expect(trams.trams, contains(tram));
      trams.dispose();
      world.destroy();
    });

    test('a tram stops behind the player on the track; the player cannot push it', () {
      final tuning = freshTuning();
      final t = tuning.trams..maxTrams = 1;
      final world = World(gravity: Vector2.zero());
      final player = Car(world, spec(), tuning.drive, x: 200, y: 0, heading: 0, scale: tuning.carScale);
      final trams = Trams(world, straightTrack(), tuning);
      final tram = trams.addTram(0, 1, 40)!;
      final hits = <double>[];
      trams.onHit((tr, v) {
        if (identical(tr, tram)) hits.add(v);
      });
      const dt = 1 / 60;
      void step() {
        trams.preStep(dt, player);
        world.step(dt, subStepCount: tuning.drive.substeps);
        trams.postStep(player);
      }

      for (var i = 0; i < 40 * 60; i++) {
        player.body.linearVelocity = Vector2.zero();
        step();
      }
      // Waiting behind the player's rear, at least min_gap_m away, not touching.
      expect(tram.speed, lessThan(1e-6));
      expect(tram.x, lessThan(player.x - player.halfLength - t.minGapM + 0.5));
      expect(tram.x, greaterThan(player.x - player.halfLength - t.minGapM - 2));
      expect(hits, isEmpty);

      // The player reverses into the tram's nose: it bounces, the tram does not move.
      final x0 = [for (final c in tram.cars) c.body.position.x];
      final front = tram.cars.first;
      for (var i = 0; i < 3 * 60; i++) {
        if (i < 2 * 60) player.body.linearVelocity = Vector2(-8, 0);
        step();
        expect(player.x - player.halfLength, greaterThan(front.x + front.halfLength - 0.5));
      }
      for (var k = 0; k < tram.cars.length; k++) {
        expect(tram.cars[k].body.position.x, closeTo(x0[k], 1e-6));
      }
      expect(hits, hasLength(1));
      expect(hits.first, greaterThanOrEqualTo(t.hitMinMps));
      expect(trams.hits, 1);
      trams.dispose();
      world.destroy();
    });
  });

  group('trams in a city', () {
    setUpAll(() async => initializeForge2D());

    test('an old pack without trams.pb loads with an empty track graph', () async {
      final city = await City.load(_MemPack(roadPack()));
      expect(city.trams.isEmpty, isTrue);
      expect(city.trams.stops, isEmpty);
      expect(city.graph.edges, hasLength(1));
      final d = DriveWorld(city: city, spec: spec(), tuning: freshTuning());
      expect(d.trams, isNull);
      d.update(1 / 60);
      d.dispose();
    });

    test('a pack with trams.pb exposes its tracks and stops', () async {
      final city = await City.load(
        _MemPack(
          roadPack(
            trams: pb.TramGraph(
              nodes: [_n(0, -4), _n(600, -4)],
              edges: [
                _e(0, 1, [0, -4, 600, -4]),
              ],
              stops: [pb.TramStop(edge: 0, sM: 225)],
            ),
          ),
        ),
      );
      expect(city.trams.edges, hasLength(1));
      expect(city.trams.edges.first.length, closeTo(600, 1e-6));
      expect(city.trams.stops.single.x, closeTo(225, 1e-4));
      expect(city.trams.stops.single.y, closeTo(-4, 1e-4));
    });

    test('a traffic car stops behind a tram in its lane (traffic v3)', () async {
      // The track runs in the +x lane of the road (lane 0 is 4 m right of the centre line).
      final city = await City.load(
        _MemPack(
          roadPack(
            trams: pb.TramGraph(
              nodes: [_n(0, -4), _n(600, -4)],
              edges: [
                _e(0, 1, [0, -4, 600, -4]),
              ],
            ),
          ),
        ),
      );
      final tuning = freshTuning();
      tuning.trams.maxTrams = 1;
      tuning.traffic.maxCars = 1;
      final d = DriveWorld(city: city, spec: spec(), tuning: tuning);
      final tr = d.traffic!, tm = d.trams!;
      final tram = tm.addTram(0, 1, 300)!..hitTimer = 1e9; // stands still
      final car = tr.addCar(0, 1, 100, 0)!;
      expect(car.y, closeTo(-4, 1e-3));
      // The player stays put (it would cruise or reverse otherwise), and is not rescued for it
      // (specs/flow.md "Vyproštění").
      d.beforeStep = (_) => d.car.body
        ..linearVelocity = Vector2.zero()
        ..angularVelocity = 0;
      d.flowBlocked = () => true;
      for (var i = 0; i < 40 * 60; i++) {
        d.update(1 / 60);
      }
      final rear = tram.cars.last;
      expect(tr.cars, contains(car));
      expect(car.x, greaterThan(150));
      expect(car.speed, lessThan(0.1));
      expect(car.x + car.halfLength, lessThanOrEqualTo(rear.x - rear.halfLength));
      expect(tram.x, closeTo(300, 1e-6));
      d.dispose();
    });
  });
}
