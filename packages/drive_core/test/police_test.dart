import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drive_core/drive_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rules_core/vector_test_support.dart';
import 'package:shared_gen/citypack_pb.dart' as pb;
import 'package:world_engine/core.dart';

final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
CarSpec spec() => parseCarSpec(File('../../content/cars/m0_coupe.json').readAsStringSync());

/// The synthetic crossing of web/test/police.test.ts (same graph, same expected values).
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

/// A square building from (x0, y0) to (x1, y1).
BuildingData box(double x0, double y0, double x1, double y1, {bool collide = true}) {
  final cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
  return BuildingData(
    xy: Float32List.fromList([x0, y0, x1, y0, x1, y1, x0, y1]),
    ringEnds: Int32List.fromList([4]),
    roof: Uint16List(0),
    height: 10,
    minHeight: 0,
    landmark: 0,
    collide: collide,
    seed: 0,
    cx: cx,
    cy: cy,
    radius: math.sqrt((x1 - cx) * (x1 - cx) + (y1 - cy) * (y1 - cy)),
    wallU: Float32List(4),
  );
}

class _FilePack implements PackSource {
  _FilePack(this.root);
  final String root;
  @override
  Future<Uint8List> read(String path) async => File('$root$path').readAsBytes();
}

void main() {
  group('police rules (specs/police.md)', () {
    final cfg = PoliceConfig.fromTuning(tuning.police);

    test('config turns seconds into ticks', () {
      final p = tuning.police;
      expect(cfg.escapeTicks, (p.escapeS * p.tickHz).round());
      expect(cfg.captureTicks, (p.captureS * p.tickHz).round());
      expect(cfg.maxLevel, 2);
      expect(cfg.levels.keys.toList(), offenceKinds);
    });

    test('fine by level, clamped to the table', () {
      expect(fine(0, [0, 100, 250]), 0);
      expect(fine(2, [0, 100, 250]), 250);
      expect(fine(5, [0, 100, 250]), 250);
      expect(fine(1, []), 0);
    });

    test('escape from level 2 takes two escape windows', () {
      final r = PoliceRules();
      var s = r.start(cfg);
      s = r.apply(s, const PoliceAction.offence('hitrun', seen: true));
      expect(s.level, 2);
      const tick = PoliceAction.tick(seen: false, near: false, away: false);
      for (var i = 0; i < cfg.escapeTicks; i++) {
        s = r.apply(s, tick);
      }
      expect(s.level, 1);
      for (var i = 0; i < cfg.escapeTicks; i++) {
        s = r.apply(s, tick);
      }
      expect(s.level, 0);
    });

    test('legal actions: 8 offences then 8 ticks; unknown kind is illegal', () {
      final r = PoliceRules();
      final s = r.start(cfg);
      final a = r.legalActions(s);
      expect(a, hasLength(16));
      expect(a.first, const PoliceAction.offence('crash', seen: false));
      expect(a.last, const PoliceAction.tick(seen: true, near: true, away: true));
      expect(() => r.apply(s, const PoliceAction.offence('speeding', seen: true)), throwsA(anything));
    });

    test(
      'vectors/police.json',
      () => expect(checkVectors(PoliceRules()), isEmpty),
      skip: !flutterDone('vectors/police.json') ? 'pending in parity.yaml' : false,
    );
  });

  group('police geometry', () {
    final g = crossing();

    test('sidewalk band of a kept edge, not the carriageway, not an alley', () {
      expect(onSidewalk(g.near(50, 10, 30), tuning), isFalse);
      expect(onSidewalk(g.near(50, 18, 30), tuning), isTrue);
      expect(onSidewalk(g.near(50, 22, 30), tuning), isFalse);
      expect(onSidewalk(g.near(100, 50, 30), tuning), isFalse);
    });

    test('sight blocked by a colliding building between the cars', () {
      expect(segmentsCross(0, 0, 10, 0, 5, -1, 5, 1), isTrue);
      expect(segmentsCross(0, 0, 10, 0, 11, -1, 11, 1), isFalse);
      final b = [box(20, -5, 30, 5)];
      expect(sightBlocked(0, 0, 50, 0, b), isTrue);
      expect(sightBlocked(0, 10, 50, 10, b), isFalse);
      expect(sightBlocked(0, 0, 50, 0, [box(20, -5, 30, 5, collide: false)]), isFalse);
      expect(inView(0, 0, 0, 60, 0, 0, 70), isTrue);
      expect(inView(0, 0, 0, 71, 0, 0, 70), isFalse);
      expect(inView(0, 0, -1, 10, 0, 0, 70), isFalse);
      expect(inView(0, 0, 1, 10, 0, 0, 70), isTrue);
    });

    test('chooseToward heads for the goal, may U-turn, ignores one-way, stops at the border', () {
      expect(chooseToward(g, 0, 0, 100, 5), 0);
      expect(chooseToward(g, 0, 1, 100, 5), 0);
      expect(chooseToward(g, 0, 0, -100, 0), 2);
      expect(chooseToward(g, 0, 0, 0, -100), 3);
      expect(chooseToward(g, 0, 0, 0, 50), 1);
      expect(chooseToward(g, 4, 3, 0, 0), -1);
    });

    test('light bar phase', () {
      expect(lightPhase(false, 1, 0.25), -1);
      expect(lightPhase(true, 0.1, 0.25), 0);
      expect(lightPhase(true, 0.3, 0.25), 1);
      expect(lightPhase(true, 0.55, 0.25), 0);
    });
  });

  group('police in the NYC pack', () {
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
    (DriveWorld, Police) world() {
      final d = DriveWorld(city: city, spec: spec(), tuning: tuning);
      final p = Police(d, tuning);
      for (final c in chunks) {
        d.addChunk(c);
        p.addChunk(c);
      }
      return (d, p);
    }

    test('flags patrols among the traffic, far from the player', () {
      final (d, p) = world();
      d.input.brake = 1;
      for (var i = 0; i < 5 * 60; i++) {
        d.update(1 / 60);
        p.update(1 / 60);
      }
      final patrols = d.traffic!.cars.where((c) => c.police).toList();
      expect(patrols, hasLength(tuning.police.patrols[0]));
      expect(patrols.every((c) => !c.pursuing), isTrue);
    }, skip: !has);

    test('a crash seen by a patrol raises the level, the patrol catches the stopped player', () {
      final (d, p) = world();
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
      tr.addCar(e.index, 1, math.max(0, s - 55), 1)!.police = true;
      final levels = <int>[];
      final fines = <int>[];
      p.onWantedChanged.add((w) => levels.add(w.level));
      p.onFined.add(fines.add);
      for (var i = 0; i < 6 * 60 && tr.hits == 0; i++) {
        d.input
          ..reset()
          ..boost = true;
        d.update(1 / 60);
        p.update(1 / 60);
      }
      expect(tr.hits, greaterThan(0));
      expect(p.wantedLevel, greaterThanOrEqualTo(1));
      for (var i = 0; i < 20 * 60 && fines.isEmpty; i++) {
        d.input
          ..reset()
          ..brake = 1
          ..handbrake = true;
        d.update(1 / 60);
        p.update(1 / 60);
      }
      expect(levels.first, 1);
      expect(fines, hasLength(1));
      expect(fines.first, greaterThan(0));
      expect(p.wantedLevel, 0);
    }, skip: !has);
  });
}
