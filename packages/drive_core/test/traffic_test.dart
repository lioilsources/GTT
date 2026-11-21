import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drive_core/drive_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/citypack_pb.dart' as pb;
import 'package:world_engine/core.dart';

final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
TuningTraffic get t => tuning.traffic;
CarSpec spec() => parseCarSpec(File('../../content/cars/m0_coupe.json').readAsStringSync());

/// The synthetic crossing of web/test/traffic.test.ts (same graph, same expected values).
RoadGraph crossing() {
  pb.Node n(int x, int y, [bool border = false]) => pb.Node(x: x * 10, y: y * 10, border: border);
  pb.Edge e(int from, int to, List<int> pts, pb.RoadClass cls, int lanes, int oneway, bool kept, double widthM) =>
      pb.Edge(
        from: from,
        to: to,
        points: pts.map((v) => v * 10),
        class_4: cls,
        lanes: lanes,
        oneway: oneway,
        kept: kept,
        widthM: widthM,
      );
  return RoadGraph.fromPb(
    pb.Graph(
      names: [''],
      nodes: [n(0, 0), n(100, 0), n(0, 40), n(-100, 0), n(0, -100, true), n(100, 100)],
      edges: [
        e(0, 1, [0, 0, 50, 0, 100, 0], pb.RoadClass.PRIMARY, 4, 0, true, 42),
        e(2, 0, [0, 40, 0, 0], pb.RoadClass.PRIMARY, 4, 0, true, 42),
        e(0, 3, [0, 0, -100, 0], pb.RoadClass.RESIDENTIAL, 2, 1, true, 26),
        e(4, 0, [0, -100, 0, 0], pb.RoadClass.SECONDARY, 2, 1, true, 26),
        e(1, 5, [100, 0, 100, 100], pb.RoadClass.SERVICE, 1, 0, false, 12),
        e(2, 5, [0, 40, 100, 100], pb.RoadClass.RESIDENTIAL, 2, 0, true, 26),
      ],
    ),
  );
}

// Recorded by client W (web/test/traffic.test.ts).
const offsets = [14417, 5153, 2912, 27192, 23321];
const picks = [0, 1, 0, 2, 0, 0, 0, 1, 1, 2, 1, 1];

class _FilePack implements PackSource {
  _FilePack(this.root);
  final String root;
  @override
  Future<Uint8List> read(String path) async => File('$root$path').readAsBytes();
}

void main() {
  group('traffic rules (specs/traffic.md)', () {
    test('signal offsets are a fixed function of the node id', () {
      expect(cycleMs(t), 2 * (t.greenMs + t.amberMs + t.allRedMs));
      expect([0, 1, 7, 12345, 987654].map((n) => signalOffset(n, 7919, 37000)).toList(), offsets);
    });

    test('two-phase light: group 1 is half a cycle behind group 0', () {
      final g = t.greenMs, a = t.amberMs, half = cycleMs(t) ~/ 2;
      expect(lightState(0, 0, 0, t), lightGreen);
      expect(lightState(0, 0, g - 1, t), lightGreen);
      expect(lightState(0, 0, g, t), lightAmber);
      expect(lightState(0, 0, g + a, t), lightRed);
      expect(lightState(0, 0, half, t), lightRed);
      expect(lightState(0, 1, 0, t), lightRed);
      expect(lightState(0, 1, half, t), lightGreen);
      expect(lightState(0, 1, half + g, t), lightAmber);
      expect(lightState(100, 0, g - 100, t), lightAmber);
      for (var ms = 0; ms < cycleMs(t); ms += 250) {
        expect(lightState(1234, 0, ms, t) == lightGreen && lightState(1234, 1, ms, t) == lightGreen, isFalse);
      }
      expect(signalClockMs(61, 60), 1016);
    });

    test('finds the signalled crossing and groups its approaches', () {
      final s = buildSignals(crossing(), tuning, leftHand: false);
      expect(s.nodes, [0]);
      expect(
        [
          for (final a in s.approaches) [a.edge, a.group],
        ],
        [
          [0, 0],
          [1, 1],
          [3, 1],
        ],
      );
      final a0 = s.approaches[0];
      expect(a0.stopM, closeTo(21 + t.stopMarginM, 1e-5));
      expect(a0.x, closeTo(a0.stopM, 1e-4));
      expect(a0.y, closeTo(16 + t.lightSideM, 1e-4));
      expect(s.approachFrom[0], 0);
      expect(s.approachTo[0], -1);
      expect(s.approachTo[3], 2);
      expect(s.approachFrom[5], 1);
      expect(s.extraFrom[5], closeTo(40, 1e-4));
      expect(s.approachTo[5], -1);
      final left = buildSignals(crossing(), tuning, leftHand: true).approaches[0];
      expect(left.y, closeTo(-(16 + t.lightSideM), 1e-4));
    });

    test('lane offsets follow the markings and the drive side', () {
      final g = crossing();
      expect(lanesPerDir(g.edges[0], tuning), 2);
      expect(laneOffset(g.edges[0], 0, tuning, leftHand: false), closeTo(4, 1e-6));
      expect(laneOffset(g.edges[0], 1, tuning, leftHand: false), closeTo(12, 1e-6));
      expect(lanesPerDir(g.edges[2], tuning), 2);
      expect(laneOffset(g.edges[2], 0, tuning, leftHand: false), closeTo(4, 1e-6));
      expect(laneOffset(g.edges[2], 1, tuning, leftHand: false), closeTo(-4, 1e-6));
      expect(laneOffset(g.edges[0], 1, tuning, leftHand: true), closeTo(-12, 1e-6));
    });

    test('chooses the next edge with the shared PRNG, never an alley', () {
      final g = crossing();
      final rng = Prng(42);
      expect([for (var i = 0; i < 12; i++) chooseNext(g, 0, 3, rng)], picks);
      expect(chooseNext(g, 1, 0, Prng(1)), 0);
      expect(chooseNext(g, 3, 2, Prng(1)), -1);
      expect(chooseNext(g, 4, 3, Prng(1)), -1);
      expect(chooseNext(g, 2, 1, Prng(7)), 5);
    });

    test('box overlap', () {
      expect(obbOverlap(0, 0, 1, 0, 5, 2, 9.9, 0, 1, 0, 5, 2, 0), isTrue);
      expect(obbOverlap(0, 0, 1, 0, 5, 2, 10.5, 0, 1, 0, 5, 2, 0), isFalse);
      expect(obbOverlap(0, 0, 1, 0, 5, 2, 10.5, 0, 1, 0, 5, 2, 0.6), isTrue);
      expect(obbOverlap(0, 0, 1, 0, 5, 2, 0, 6.9, 0, 1, 5, 2, 0), isTrue);
      expect(obbOverlap(0, 0, 1, 0, 5, 2, 0, 7.1, 0, 1, 5, 2, 0), isFalse);
    });
  });

  group('traffic in the NYC pack', () {
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
    DriveWorld world() {
      final d = DriveWorld(city: city, spec: spec(), tuning: tuning);
      for (final c in chunks) {
        d.addChunk(c);
      }
      return d;
    }

    test('fills to the cap, keeps kept edges, cars move', () {
      final d = world();
      final tr = d.traffic!;
      d.input.brake = 1;
      for (var i = 0; i < 20 * 60; i++) {
        d.update(1 / 60);
        expect(tr.cars.length, lessThanOrEqualTo(t.maxCars));
        if (i % 60 == 0) {
          for (final c in tr.cars) {
            expect(c.edge.kept, isTrue);
          }
        }
      }
      expect(tr.signals.nodes.length, greaterThan(200));
      expect(tr.cars.length, greaterThan(t.maxCars / 2));
      expect(tr.cars.where((c) => c.speed > 1), isNotEmpty);
      d.dispose();
    }, skip: !has);

    test('no car drives through a red light', () {
      final d = world();
      final tr = d.traffic!;
      d.update(1 / 60);
      tr.reset();
      final near = [
        for (var i = 0; i < tr.signals.approaches.length; i++)
          (
            i,
            math.sqrt(
              math.pow(tr.signals.approaches[i].x - d.car.x, 2) + math.pow(tr.signals.approaches[i].y - d.car.y, 2),
            ),
          ),
      ]..sort((p, q) => p.$2.compareTo(q.$2));
      for (final (i, dist) in near) {
        final ap = tr.signals.approaches[i];
        final e = city.graph.edges[ap.edge];
        if (dist < 200) tr.addCar(ap.edge, e.to == ap.node ? 1 : -1, 0, 0);
      }
      final added = tr.cars.length;
      final last = <int, (int, double)>{};
      var checked = 0;
      for (var i = 0; i < 40 * 60; i++) {
        d.update(1 / 60);
        for (final c in tr.cars) {
          final a = c.dir > 0 ? tr.signals.approachTo[c.edge.index] : tr.signals.approachFrom[c.edge.index];
          final prev = last[c.id];
          if (a >= 0 && prev != null && prev.$1 == c.edge.index && tr.light(a) == lightRed) {
            final extra = c.dir > 0 ? tr.signals.extraTo[c.edge.index] : tr.signals.extraFrom[c.edge.index];
            final line = c.edge.length + extra - tr.signals.approaches[a].stopM - c.halfLength;
            if (prev.$2 < line - 0.5) {
              checked++;
              expect(c.s, lessThan(line + 0.5));
            }
          }
          last[c.id] = (c.edge.index, c.s);
        }
      }
      expect(added, greaterThan(3));
      expect(checked, greaterThan(0));
      d.dispose();
    }, skip: !has);

    test('a car hit by the player stops and fires the hit event', () {
      final d = world();
      final tr = d.traffic!;
      final hit = city.graph.nearest(
        d.car.x,
        d.car.y,
        maxDist: 300,
        where: (e) => e.kept && e.isGround && e.oneway >= 0 && e.length > 80,
      )!;
      final e = hit.edge;
      d.spawn(hit.x, hit.y, 0);
      d.update(1 / 60);
      final s = math.min(e.length - 10, hit.t * e.length + 25);
      tr.reset();
      final target = tr.addCar(e.index, 1, s, 0)!;
      final hx = math.cos(target.heading), hy = math.sin(target.heading);
      d.spawn(target.x - hx * 25, target.y - hy * 25, target.heading);
      final events = <double>[];
      tr.onHit((c, v) {
        if (identical(c, target)) events.add(v);
      });
      for (var i = 0; i < 6 * 60 && events.isEmpty; i++) {
        d.input
          ..reset()
          ..boost = true;
        d.update(1 / 60);
      }
      expect(events, hasLength(1));
      expect(tr.hits, greaterThan(0));
      var stopped = false;
      for (var i = 0; i < 30; i++) {
        d.input
          ..reset()
          ..brake = 1;
        d.update(1 / 60);
        if (target.speed == 0) stopped = true;
      }
      expect(stopped, isTrue);
      expect(target.hitTimer, greaterThan(0));
      d.dispose();
    }, skip: !has);
  });
}
