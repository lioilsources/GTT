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

/// The junction of the W test (web/test/trams.test.ts), metres:
///
///                 3 (100,100) terminus
///                 | e2 3→1 (90° to e0 and e1: not a track connection, v2)
///  0 ──e0── 1 (100,0) ──e1── 2 (200,0) border
///  (0,0)      \ e3 1→4 (200,-40), 21.8° off e0 (a switch)     e4: loop at 1
TrackGraph junction() => TrackGraph.fromPb(
  pb.TramGraph(
    nodes: [_n(0, 0), _n(100, 0), _n(200, 0, true), _n(100, 100), _n(200, -40)],
    edges: [
      _e(0, 1, [0, 0, 100, 0]),
      _e(1, 2, [100, 0, 200, 0]),
      _e(3, 1, [100, 100, 100, 0]),
      _e(1, 4, [100, 0, 200, -40]),
      _e(1, 1, [100, 0, 120, 20, 80, 20, 100, 0]),
    ],
  ),
);

// Recorded by client W (web/test/trams.test.ts PICKS_42, PICKS_7).
const picks42 = [1, 1, 3, 1, 1, 1, 1, 1, 3, 3, 1, 3];
const picks7 = [3, 3, 3, 3, 3, 1];

final _tun = freshTuning().trams;
final cosMin = math.cos(_tun.maxSwitchDeg * math.pi / 180);
final probeM = _tun.turnProbeM;

/// Change of a car's axis (heading modulo π), radians in [0, π/2].
double axisDelta(double a, double b) {
  var d = (b - a) % math.pi;
  if (d < 0) d += math.pi;
  return math.min(d, math.pi - d);
}

/// Edge [ei] as travel-order points leaving [node].
List<double> leaving(TrackGraph g, int ei, int node) {
  final e = g.edges[ei];
  final n = e.pointCount;
  return [
    for (var j = 0; j < n; j++) ...[e.pts[2 * (e.from == node ? j : n - 1 - j)], e.pts[2 * (e.from == node ? j : n - 1 - j) + 1]],
  ];
}

/// Drives an articulated tram (TramTrail + articulate) along [path] in [ds] steps: the largest
/// axis change of any car per metre of the nose's path, in degrees.
double worstRate(List<double> path, double ds, TuningTrams t) {
  final cum = <double>[0];
  for (var i = 2; i < path.length; i += 2) {
    final dx = path[i] - path[i - 2], dy = path[i + 1] - path[i - 1];
    cum.add(cum.last + math.sqrt(dx * dx + dy * dy));
  }
  final total = cum.last;
  final trail = TramTrail(t.trailPoints, carM: t.carLengthM, gapM: t.jointGapM)..push(path[0], path[1], 0);
  final prev = List<double>.filled(t.carsPerTram, double.nan);
  final pose = TramCarPose();
  var seg = 0;
  var worst = 0.0;
  // Travel direction: the first non-degenerate segment, then the last one walked.
  var ux = 1.0, uy = 0.0;
  for (var i = 2; i < path.length; i += 2) {
    final dx = path[i] - path[i - 2], dy = path[i + 1] - path[i - 1], l = math.sqrt(dx * dx + dy * dy);
    if (l > 1e-9) {
      ux = dx / l;
      uy = dy / l;
      break;
    }
  }
  for (var s = 0.0; s <= total; s += ds) {
    while (seg < cum.length - 2 && s > cum[seg + 1]) {
      seg++;
      trail.push(path[2 * seg], path[2 * seg + 1], 0);
    }
    final l = cum[seg + 1] - cum[seg];
    final f = l > 0 ? (s - cum[seg]) / l : 0.0;
    final dx = path[2 * seg + 2] - path[2 * seg], dy = path[2 * seg + 3] - path[2 * seg + 1];
    if (l > 1e-9) {
      ux = dx / l;
      uy = dy / l;
    }
    trail.setNose(path[2 * seg] + dx * f, path[2 * seg + 1] + dy * f, ux, uy, 0);
    for (var k = 0; k < t.carsPerTram; k++) {
      final h = articulate(trail, k, pose).heading;
      if (!prev[k].isNaN) worst = math.max(worst, axisDelta(prev[k], h) * 180 / math.pi / ds);
      prev[k] = h;
    }
  }
  return worst;
}

class _DirPack implements PackSource {
  _DirPack(this.root);
  final String root;
  @override
  Future<Uint8List> read(String path) async => File('$root$path').readAsBytes();
}

void main() {
  group('tram rules (specs/trams.md)', () {
    test('turn at a node: only feasible connections (v2)', () {
      final g = junction();
      expect(turnCos(g, 1, 0, 1, probeM), closeTo(1, 1e-9));
      expect(turnCos(g, 1, 0, 3, probeM), closeTo(100 / math.sqrt(100 * 100 + 40 * 40), 1e-6));
      expect(turnCos(g, 1, 0, 2, probeM), closeTo(0, 1e-6)); // 90°
      expect(turnCos(g, 1, 1, 3, probeM), closeTo(-100 / math.sqrt(100 * 100 + 40 * 40), 1e-6)); // hairpin
      expect(feasibleNext(g, 1, 0, cosMin, probeM, []), [1, 3]);
      expect(feasibleNext(g, 1, 1, cosMin, probeM, []), [0]);
      expect(feasibleNext(g, 1, 3, cosMin, probeM, []), [0]);
      expect(feasibleNext(g, 1, 2, cosMin, probeM, []), isEmpty);
      expect(feasibleNext(g, 2, 1, cosMin, probeM, []), isEmpty); // border
      expect(straightestPrev(g, 1, 1, cosMin, probeM), 0);
      expect(straightestPrev(g, 1, 3, cosMin, probeM), 0);
      expect(straightestPrev(g, 1, 0, cosMin, probeM), 1);
      expect(straightestPrev(g, 1, 2, cosMin, probeM), -1);
      expect(straightestPrev(g, 2, 1, cosMin, probeM), -1);
    });

    test('next edge: shared PRNG over feasible candidates, never a loop or a sharp turn', () {
      final g = junction();
      final r42 = Prng(42);
      expect([for (var i = 0; i < 12; i++) chooseNextTrack(g, 1, 0, r42, cosMin, probeM)], picks42);
      final r7 = Prng(7);
      expect([for (var i = 0; i < 6; i++) chooseNextTrack(g, 1, 0, r7, cosMin, probeM)], picks7);
      expect(chooseNextTrack(g, 1, 3, Prng(1), cosMin, probeM), 0);
      // No feasible way = terminus (change ends), without drawing.
      final rng = Prng(1);
      final before = rng.state;
      expect(chooseNextTrack(g, 1, 2, rng, cosMin, probeM), 2);
      expect(chooseNextTrack(g, 3, 2, rng, cosMin, probeM), 2);
      expect(chooseNextTrack(g, 0, 0, rng, cosMin, probeM), 0);
      expect(rng.state, before);
      expect(chooseNextTrack(g, 2, 1, rng, cosMin, probeM), -1); // border: the tram disappears
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

    test('a tram changes ends at a terminus: stops on the end node, cars stay, axis unchanged (v2)', () {
      final tuning = freshTuning();
      final t = tuning.trams..maxTrams = 1;
      final world = World(gravity: Vector2.zero());
      final player = Car(world, spec(), tuning.drive, x: 150, y: 60, heading: 0, scale: tuning.carScale);
      // 0 (border) ── 1 ── 2 (terminus), bent at 1.
      final g = TrackGraph.fromPb(
        pb.TramGraph(
          nodes: [_n(0, 0, true), _n(100, 0), _n(160, 30)],
          edges: [
            _e(0, 1, [0, 0, 50, 0, 100, 0]),
            _e(1, 2, [100, 0, 130, 10, 160, 30]),
          ],
        ),
      );
      final trams = Trams(world, g, tuning);
      final tram = trams.addTram(0, 1, 70)!;
      expect(tram.histCount, 0); // nothing behind the border node
      const dt = 1 / 60;
      void step() {
        trams.preStep(dt, player);
        world.step(dt, subStepCount: tuning.drive.substeps);
        trams.postStep(player);
      }

      var before = <List<double>>[];
      var at = -1;
      for (var i = 0; i < 40 * 60 && at < 0; i++) {
        before = [for (final c in tram.cars) [c.x, c.y, c.heading]];
        step();
        if (tram.reversals > 0) at = i;
      }
      expect(at, greaterThan(0));
      expect(trams.trams, contains(tram));
      expect(tram.edge.index, 1);
      expect(tram.dir, -1);
      expect(tram.s, closeTo(trams.tramLength, 1e-6));
      expect(tram.speed, 0);
      expect(tram.dwell, closeTo(t.dwellS, 1e-9));
      final n = tram.cars.length;
      for (var k = 0; k < n; k++) {
        final c = tram.cars[k], b = before[n - 1 - k];
        expect(c.k, k);
        expect(math.sqrt((c.x - b[0]) * (c.x - b[0]) + (c.y - b[1]) * (c.y - b[1])), lessThan(t.speedMps * dt + 1e-6));
        expect(axisDelta(b[2], c.heading), lessThan(0.05));
        final d = c.heading - b[2] - math.pi;
        expect(math.atan2(math.sin(d), math.cos(d)).abs(), lessThan(0.05));
      }
      // It waits dwell_s, then drives back and disappears at the border node.
      var gone = -1;
      for (var i = 0; i < 60 * 60 && gone < 0; i++) {
        step();
        if (!trams.trams.contains(tram)) gone = i;
      }
      expect(gone, greaterThan(t.dwellS / dt - 2));
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

  group('L-S10: smooth trams on the whole Prague network (specs/trams.md v2 "Plynulost")', () {
    const root = '../../build/packs/prague/';
    final has = File('${root}trams.pb').existsSync();
    setUpAll(() async => initializeForge2D());

    test('every feasible connection and every edge stays under max_turn_deg_per_m', () async {
      final t = freshTuning().trams;
      final g = (await City.load(_DirPack(root))).trams;
      expect(g.edges.length, greaterThan(1000));
      var pairs = 0;
      var worst = 0.0;
      final out = <int>[];
      for (var node = 0; node < g.nodeEdges.length; node++) {
        for (final a in g.nodeEdges[node].toSet()) {
          if (g.edges[a].from == g.edges[a].to) continue;
          final inPts = leaving(g, a, node);
          final arrive = <double>[for (var i = inPts.length - 2; i >= 0; i -= 2) ...[inPts[i], inPts[i + 1]]];
          for (final b in feasibleNext(g, node, a, cosMin, probeM, out)) {
            worst = math.max(worst, worstRate([...arrive, ...leaving(g, b, node).skip(2)], 0.1, t));
            pairs++;
          }
        }
      }
      for (final e in g.edges) {
        if (e.from == e.to || e.pointCount < 2) continue;
        for (final node in [e.from, e.to]) {
          worst = math.max(worst, worstRate(leaving(g, e.index, node), 0.1, t));
        }
      }
      // ignore: avoid_print
      print('L-S10 F: $pairs connections, max ${worst.toStringAsFixed(2)} deg/m');
      expect(pairs, greaterThan(g.edges.length));
      expect(worst, lessThanOrEqualTo(t.maxTurnDegPerM));
    }, skip: !has, timeout: const Timeout(Duration(minutes: 5)));

    test('live trams (spawn, switches, stops, termini) stay under max_turn_deg_per_m', () async {
      final tuning = freshTuning();
      final t = tuning.trams;
      final g = (await City.load(_DirPack(root))).trams;
      var worst = 0.0, metres = 0.0;
      var changes = 0;
      const dt = 1 / 60;
      final step = math.max(1, g.stops.length ~/ 12);
      for (var si = 0; si < g.stops.length; si += step) {
        final st = g.stops[si];
        final world = World(gravity: Vector2.zero());
        final player = Car(world, spec(), tuning.drive, x: st.x - st.dirY * 30, y: st.y + st.dirX * 30, heading: 0, scale: tuning.carScale);
        final trams = Trams(world, g, tuning)..solid = false;
        final last = <TramCar, List<double>>{};
        for (var i = 0; i < 120 * 60; i++) {
          player.body.linearVelocity = Vector2.zero();
          trams.preStep(dt, player);
          world.step(dt, subStepCount: tuning.drive.substeps);
          trams.postStep(player);
          for (final tr in trams.trams) {
            for (final c in tr.cars) {
              final prev = last[c];
              last[c] = [c.heading, tr.x, tr.y, tr.reversals.toDouble()];
              if (prev == null) continue;
              final d = axisDelta(prev[0], c.heading) * 180 / math.pi;
              if (tr.reversals != prev[3].round()) {
                changes++;
                expect(d, lessThanOrEqualTo(t.maxTurnDegPerM * t.speedMps * dt));
                continue;
              }
              final nose = math.sqrt((tr.x - prev[1]) * (tr.x - prev[1]) + (tr.y - prev[2]) * (tr.y - prev[2]));
              if (nose < 1e-3) {
                expect(d, lessThan(0.01));
                continue;
              }
              worst = math.max(worst, d / nose);
            }
            metres += tr.speed * dt;
          }
        }
        trams.dispose();
        world.destroy();
      }
      // ignore: avoid_print
      print('L-S10 F live: ${metres.round()} m, ${changes ~/ t.carsPerTram} changes of ends, max ${worst.toStringAsFixed(2)} deg/m');
      expect(metres, greaterThan(5000));
      expect(worst, lessThanOrEqualTo(t.maxTurnDegPerM));
    }, skip: !has, timeout: const Timeout(Duration(minutes: 10)));
  });
}
