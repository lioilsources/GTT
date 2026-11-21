import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_engine/src/pb/citypack.pb.dart' as pb;
import 'package:world_engine/world_engine.dart';

class FilePackSource implements PackSource {
  FilePackSource(this.root);
  final String root;
  @override
  Future<Uint8List> read(String path) => File('$root$path').readAsBytes();
}

Uint8List gz(List<int> b) => Uint8List.fromList(const GZipEncoder().encodeBytes(b));

/// A plus-shaped graph: a ground street along x and a bridge along y crossing above it.
pb.Graph crossingGraph() {
  pb.Node n(int x, int y) => pb.Node(x: x * 10, y: y * 10);
  pb.Edge e(int a, int b, List<int> pts, {int layer = 0, bool bridge = false}) => pb.Edge(
        from: a,
        to: b,
        points: pts.map((v) => v * 10),
        class_4: pb.RoadClass.PRIMARY,
        lanes: 2,
        layerFrom: layer,
        layerTo: layer,
        bridge: bridge,
        kept: true,
        widthM: 26,
      );
  return pb.Graph(
    names: ['', 'Street', 'Bridge'],
    nodes: [n(-100, 0), n(100, 0), n(0, -100), n(0, 100)],
    edges: [
      e(0, 1, [-100, 0, 100, 0])..name = 1,
      e(2, 3, [0, -100, 0, 100], layer: 1, bridge: true)..name = 2,
    ],
  );
}

final tuningSrc = File('../../content/tuning.yaml').readAsStringSync();
Tuning loadTuning() => Tuning.fromYaml(tuningSrc);

void main() {
  test('extrusion scale follows the knee curve and caps at max_scale', () {
    final t = loadTuning();
    final k = t.extrusionK, knee = t.extrusionKnee;
    expect(extrusionScale(0, t), 1);
    expect(extrusionScale(knee, t), closeTo(1 + k * knee, 1e-9));
    expect(extrusionScale(knee + 100, t), closeTo(1 + k * (knee + math.pow(100, t.extrusionExp)), 1e-9));
    expect(extrusionScale(1e6, t), t.extrusionMaxScale);
  });

  test('tuning is strict and the panel yaml round-trips', () {
    final t = loadTuning();
    expect(() => Tuning.fromYaml(tuningSrc.replaceFirst(RegExp(r'^car_scale:.*$', multiLine: true), '')),
        throwsFormatException);
    t.carScale = 3.25;
    final merged = tuningSrc
        .split('\n')
        .where((l) => !RegExp(r'^(car_scale|view_width_m|car_anchor|extrusion|speed_mps):').hasMatch(l))
        .join('\n');
    final again = Tuning.fromYaml('$merged\n${t.panelYaml()}');
    expect(again.carScale, 3.25);
    expect(again.viewWidthFast, t.viewWidthFast);
    expect(again.extrusionK, t.extrusionK);
    expect(again.drive.stepHz, t.drive.stepHz);
  });

  test('chunk window covers the 3×3 ring and looks ahead', () async {
    const root = '../../app/assets/cities/nyc/';
    if (!File('${root}manifest.pb').existsSync()) return;
    final t = loadTuning();
    final city = await City.load(FilePackSource(root));
    final w = ChunkWindow(city, t);
    final cm = city.chunkM;
    final x = city.startX, y = city.startY;
    final want = w.wanted(x, y, 0);
    final own = ((x / cm).floor(), (y / cm).floor());
    expect(want.first, own);
    expect(want, contains(((x / cm).floor() + t.streaming.ahead, (y / cm).floor())));
    expect(w.drop(own.$1 + t.streaming.keep + 1, own.$2, x, y), isTrue);
    expect(w.drop(own.$1 + t.streaming.keep, own.$2, x, y), isFalse);
  });

  test('road graph nearest and layers', () {
    final g = RoadGraph.fromPb(crossingGraph());
    final h = g.nearest(30, 2)!;
    expect(h.edge.name, anyOf('Street', 'Bridge'));
    final ground = g.nearest(30, 2, where: (e) => e.isGround)!;
    expect(ground.edge.name, 'Street');
    expect(ground.dist, closeTo(2, 1e-6));
    expect(ground.t, closeTo(0.65, 1e-6));
    expect(g.edges[1].drawLayer, 1);
    expect(g.near(0, 0, 5).length, 2);
  });

  test('prepareChunk decodes buildings and merges ground per kind', () {
    final chunk = pb.Chunk(
      x: 1,
      y: 2,
      buildings: [
        pb.Building(
          rings: [0, 0, 100, 0, 100, 100, 0, 100],
          ringEnds: [4],
          roof: [0, 1, 2, 0, 2, 3],
          heightM: 30,
          collide: true,
          wallSeed: 7,
        ),
      ],
      ground: [
        pb.Mesh(kind: pb.GroundKind.WATER, vertices: [0, 0, 10, 0, 0, 10], indices: [0, 1, 2]),
        pb.Mesh(kind: pb.GroundKind.WATER, vertices: [0, 0, 10, 0, 0, 10], indices: [0, 1, 2]),
      ],
    );
    final c = prepareChunk(gz(chunk.writeToBuffer()));
    expect(c.buildings.single.cx, closeTo(5, 1e-6));
    expect(c.buildings.single.wallU[3], closeTo(30, 1e-6));
    expect(c.ground.single.indices, [0, 1, 2, 3, 4, 5]);
  });

  test('camera keeps the car at the anchor and heading up', () {
    final t = loadTuning();
    final cam = CameraRig()..snap(100, 200, 0, t); // heading east
    const size = Size(400, 800);
    final car = cam.toScreen(100, 200, size, t);
    expect(car.dx, closeTo(200, 1e-6));
    expect(car.dy, closeTo(800 * t.anchorY, 1e-6));
    final ahead = cam.toScreen(110, 200, size, t);
    expect(ahead.dx, closeTo(200, 1e-6));
    expect(ahead.dy, lessThan(car.dy));
  });

  test('NYC citypack loads, every chunk decodes, start is on a kept road', () async {
    const root = '../../app/assets/cities/nyc/';
    if (!File('${root}manifest.pb').existsSync()) return; // pack not built
    final city = await City.load(FilePackSource(root));
    expect(city.id, 'nyc');
    expect(city.imperial, isTrue);
    final start = city.graph.nearest(city.startX, city.startY, maxDist: 5, where: (e) => e.kept);
    expect(start, isNotNull);
    expect(city.districtAt(city.startX, city.startY), isNotNull);
    var buildings = 0;
    for (final ref in city.manifest.chunks) {
      final c = prepareChunk(await File('$root${chunkPath(ref.x, ref.y)}').readAsBytes());
      buildings += c.buildings.length;
      for (final b in c.buildings) {
        expect(b.roof.every((i) => i < b.vertexCount), isTrue);
      }
    }
    expect(buildings, greaterThan(5000));
    final heroes = city.landmarks.items.where((l) => l.hero).map((l) => l.id).toSet();
    expect(heroes, containsAll(['empire_state', 'chrysler', 'grand_central', 'times_square', 'central_park']));
  });
}
