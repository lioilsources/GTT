import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drive_core/drive_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_gen/citypack_pb.dart' as pb;
import 'package:world_engine/core.dart';

/// Roadblock (specs/roadblock.md): the spot ahead on the road graph and the standing patrols.

final _src = File('../../content/tuning.yaml').readAsStringSync();
CarSpec spec() => parseCarSpec(File('../../content/cars/m0_coupe.json').readAsStringSync());

/// Fresh tuning with the wanted cap at 3, so the roadblock level can be reached.
Tuning tuning3() => Tuning.fromYaml(_src)..police.maxLevel = 3;

/// [tuning3] without random traffic: addCar still works, nothing spawns on its own.
Tuning quiet() => tuning3()
  ..traffic.initialTries = 0
  ..traffic.spawnTries = 0
  ..police.patrols = [0, 0, 0, 0];

pb.Node _n(int x, int y, [bool border = false]) => pb.Node(x: x * 10, y: y * 10, border: border);

pb.Edge _e(int from, int to, List<int> pts, {int layer = 0, int oneway = 0}) => pb.Edge(
  from: from,
  to: to,
  points: pts.map((v) => v * 10),
  class_4: pb.RoadClass.PRIMARY,
  lanes: 2,
  oneway: oneway,
  kept: true,
  widthM: 26,
  layerFrom: layer,
  layerTo: layer,
  bridge: layer > 0,
);

/// Along x: node 0 (0, 0) – e0 – node 1 (200, 0) – e1 (bridge, layer 1) – node 2 (400, 0);
/// node 3 (0, −100) is a border node, e2 goes from node 0 down to it.
RoadGraph net() => RoadGraph.fromPb(
  pb.Graph(
    names: [''],
    nodes: [_n(0, 0), _n(200, 0), _n(400, 0), _n(0, -100, true)],
    edges: [
      _e(0, 1, [0, 0, 100, 0, 200, 0]),
      _e(1, 2, [200, 0, 400, 0], layer: 1),
      _e(0, 3, [0, 0, 0, -100]),
    ],
  ),
);

Uint8List _gz(List<int> b) => Uint8List.fromList(gzip.encode(b));

class _MemPack implements PackSource {
  _MemPack(this.files);
  final Map<String, Uint8List> files;
  @override
  Future<Uint8List> read(String path) async => files[path] ?? (throw StateError('no $path in the pack'));
}

/// One straight two-way road along x from 0 to 1600 m, start at (400, 0).
Map<String, Uint8List> roadPack() => {
  'manifest.pb': _gz(
    pb.Manifest(
      formatVersion: 1,
      cityId: 'test',
      driveSide: 'right',
      units: 'metric',
      chunkM: 256,
      start: pb.Spawn(x: 4000, y: 0),
    ).writeToBuffer(),
  ),
  'graph.pb': _gz(
    pb.Graph(
      names: [''],
      nodes: [_n(0, 0), _n(1600, 0)],
      edges: [
        _e(0, 1, [0, 0, 1600, 0]),
      ],
    ).writeToBuffer(),
  ),
  'landmarks.pb': _gz(pb.Landmarks().writeToBuffer()),
  'spots.pb': _gz(pb.Spots().writeToBuffer()),
};

void main() {
  group('roadblock spot', () {
    final g = net();

    test('ahead_m along the road in the driving direction, across the next node', () {
      final s = roadblockSpot(g, 30, 2, 0, 0, 40, 140, 600)!;
      expect(s.edge, 0);
      expect(s.d, closeTo(170, 1e-6));
      expect(s.x, closeTo(170, 1e-4));
      expect(s.y, closeTo(0, 1e-4));
      expect((s.ux, s.uy), (1.0, 0.0));
      // Facing back: the other way along e0.
      final b = roadblockSpot(g, 150, 0, math.pi, 0, 40, 100, 600)!;
      expect(b.edge, 0);
      expect(b.x, closeTo(50, 1e-4));
      // Back past node 0: chooseToward to the goal (−450, 0) takes e2 (straight down beats e0 back).
      final c = roadblockSpot(g, 150, 0, math.pi, 0, 40, 200, 600)!;
      expect(c.edge, 2);
      expect((c.x, c.y), (0.0, -50.0));
    });

    test('gives up at a border node, on a bridge, without a road of the layer', () {
      // Down e2 towards the border node 3 (100 m away).
      expect(roadblockSpot(g, 0, -20, -math.pi / 2, 0, 40, 140, 600), isNull);
      // The spot lands on the bridge e1 (layer 1).
      expect(roadblockSpot(g, 100, 0, 0, 0, 40, 140, 600), isNull);
      // No kept edge of the player's layer nearby.
      expect(roadblockSpot(g, 100, 0, 0, 1, 40, 140, 600), isNull);
      expect(roadblockSpot(g, 100, 500, 0, 0, 40, 140, 600), isNull);
    });
  });

  group('roadblock in the game', () {
    late City city;
    setUpAll(() async {
      await initializeForge2D();
      city = await City.load(_MemPack(roadPack()));
    });

    (DriveWorld, Police) world(Tuning t) {
      final d = DriveWorld(city: city, spec: spec(), tuning: t);
      d.spawn(400, 0, 0);
      return (d, Police(d, t));
    }

    /// Runs [s] seconds standing on the handbrake; [hold] keeps the wanted level up.
    void run(DriveWorld d, Police p, double s, {bool hold = true, bool Function()? until}) {
      for (var i = 0; i < (s * 60).round(); i++) {
        if (until != null && until()) return;
        if (hold) {
          p.state
            ..level = 3
            ..unseen = 0;
        }
        // Brake alone reverses at a standstill; the handbrake keeps the car put.
        d.input
          ..reset()
          ..handbrake = true;
        d.update(1 / 60);
        p.update(1 / 60);
      }
    }

    test('level 3 puts two standing patrols across the road ahead_m in front', () {
      final t = quiet();
      final (d, p) = world(t);
      var toasts = 0;
      var carX = 0.0;
      p.onRoadblock.add((x, y) {
        toasts++;
        carX = d.car.x;
        expect((x, y), (p.roadblockX, p.roadblockY));
      });
      run(d, p, 0.5, hold: false);
      expect(p.roadblock, isEmpty);
      run(d, p, 0.5);
      expect(toasts, 1);
      final b = p.roadblock;
      expect(b, hasLength(2));
      final rb = t.police.roadblock;
      expect(p.roadblockX, closeTo(carX + rb.aheadM, 1e-3));
      final ys = b.map((c) => c.y).toList()..sort();
      expect(ys[0], closeTo(p.roadblockY - rb.lateralM, 1e-3));
      expect(ys[1], closeTo(p.roadblockY + rb.lateralM, 1e-3));
      final poses = [for (final c in b) (c.x, c.y)];
      run(d, p, 3);
      for (var i = 0; i < 2; i++) {
        final c = b[i];
        expect(c.police && c.blocking, isTrue);
        expect(c.pursuing, isFalse);
        expect(c.speed, 0);
        expect(math.cos(c.heading).abs(), closeTo(0, 1e-6));
        expect((c.x, c.y), poses[i]);
        expect(d.traffic!.cars, contains(c));
      }
      expect(toasts, 1);
    });

    test('gives up at a dead end (U-turn)', () {
      // 1550 m on the 1600 m road: ahead_m runs past its dead end, chooseToward turns back.
      expect(roadblockSpot(city.graph, 1550, 0, 0, 0, 40, 140, 600), isNull);
      expect(roadblockSpot(city.graph, 1400, 0, 0, 0, 40, 140, 600), isNotNull);
    });

    test('does not count towards patrols[level]', () {
      final t = quiet()..police.patrols = [0, 0, 0, 1];
      final (d, p) = world(t);
      run(d, p, 0.2);
      expect(p.roadblock, hasLength(2));
      // One ordinary traffic car past pick_min_m, behind the player, driving away.
      expect(d.traffic!.addCar(0, -1, 1600 - 200, 0), isNotNull);
      run(d, p, 2);
      final police = d.traffic!.cars.where((c) => c.police).toList();
      expect(police.where((c) => c.blocking), hasLength(2));
      expect(police.where((c) => !c.blocking), hasLength(1));
    });

    test('cleared when the level drops below 3 (escape)', () {
      final t = quiet();
      final (d, p) = world(t);
      run(d, p, 1);
      final b = p.roadblock;
      expect(b, hasLength(2));
      run(d, p, t.police.escapeS + 1, hold: false, until: () => p.roadblock.isEmpty);
      expect(p.wantedLevel, 2);
      expect(p.roadblock, isEmpty);
      for (final c in b) {
        expect(d.traffic!.cars, isNot(contains(c)));
      }
    });

    test('cleared after ttl_s, rebuilt only after cooldown_s', () {
      final t = quiet();
      final rb = t.police.roadblock;
      final (d, p) = world(t);
      run(d, p, 0.2);
      expect(p.roadblock, hasLength(2));
      run(d, p, rb.ttlS - 0.5);
      expect(p.roadblock, hasLength(2));
      run(d, p, 1);
      expect(p.roadblock, isEmpty);
      run(d, p, rb.cooldownS - 1);
      expect(p.roadblock, isEmpty);
      run(d, p, 1.5);
      expect(p.roadblock, hasLength(2));
    });

    test('cleared when the player is farther than clear_m, and by a traffic reset or respawn', () {
      final t = quiet();
      final (d, p) = world(t);
      run(d, p, 0.2);
      expect(p.roadblock, hasLength(2));
      t.police.roadblock.clearM = t.police.roadblock.aheadM - 20;
      run(d, p, 0.2);
      expect(p.roadblock, isEmpty);

      final t2 = quiet();
      final (d2, p2) = world(t2);
      run(d2, p2, 0.2);
      expect(p2.roadblock, hasLength(2));
      d2.traffic!.reset();
      run(d2, p2, 0.2);
      expect(p2.roadblock, isEmpty);
      // Cooldown runs, then a respawn-style explicit clear.
      run(d2, p2, t2.police.roadblock.cooldownS + 0.5);
      expect(p2.roadblock, hasLength(2));
      final b = p2.roadblock;
      p2.clearRoadblock();
      expect(p2.roadblock, isEmpty);
      for (final c in b) {
        expect(d2.traffic!.cars, isNot(contains(c)));
      }
    });

    test('below the level, or with the cap under it, no roadblock', () {
      final t = Tuning.fromYaml(_src)..police.patrols = [0, 0, 0, 0];
      final (d, p) = world(t);
      for (var i = 0; i < 120; i++) {
        p.state.level = 2;
        d.update(1 / 60);
        p.update(1 / 60);
      }
      expect(p.roadblock, isEmpty);
    });
  });
}
