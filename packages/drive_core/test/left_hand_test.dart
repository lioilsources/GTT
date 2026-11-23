import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drive_core/drive_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_gen/citypack_pb.dart' as pb;
import 'package:world_engine/core.dart';

/// Left-hand traffic (specs/cities.md v2): parked cars mirror by `manifest.driveSide`, never by id.

final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
final specs = {
  for (final f in Directory('../../content/cars').listSync().whereType<File>())
    for (final s in [parseCarSpec(f.readAsStringSync())]) s.id: s,
};

Uint8List _gz(List<int> b) => Uint8List.fromList(gzip.encode(b));

class _MemPack implements PackSource {
  _MemPack(this.files);
  final Map<String, Uint8List> files;
  @override
  Future<Uint8List> read(String path) async => files[path] ?? (throw StateError('no $path in the pack'));
}

pb.Node _n(int x, int y) => pb.Node(x: x * 10, y: y * 10);

/// One straight two-way primary road east along y = 100 inside chunk (0, 0), points every 50 m.
/// The city id is `nyc` (so its parked models apply) whatever [driveSide] says.
Map<String, Uint8List> pack(String driveSide) => {
  'manifest.pb': _gz(
    pb.Manifest(
      formatVersion: 1,
      cityId: 'nyc',
      driveSide: driveSide,
      units: 'metric',
      chunkM: tuning.chunkM,
      start: pb.Spawn(x: 0, y: 1000),
    ).writeToBuffer(),
  ),
  'graph.pb': _gz(
    pb.Graph(
      names: [''],
      nodes: [_n(0, 100), _n(250, 100)],
      edges: [
        pb.Edge(
          from: 0,
          to: 1,
          points: [
            for (var x = 0; x <= 250; x += 50) ...[x * 10, 1000],
          ],
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
};

/// Heading normalised to (−π, π].
double _norm(double a) => math.atan2(math.sin(a), math.cos(a));

void main() {
  late City right, left;
  setUpAll(() async {
    right = await City.load(_MemPack(pack('right')));
    left = await City.load(_MemPack(pack('left')));
  });

  List<ParkedCar> parked(City c) =>
      generateParked(c.graph, 0, 0, 1, tuning, specs, const [], (x: 1e9, y: 1e9), cityId: c.id, leftHand: c.leftHand);

  test('leftHand comes from manifest.driveSide', () {
    expect(right.id, left.id);
    expect(right.leftHand, isFalse);
    expect(left.leftHand, isTrue);
  });

  test('driveSide = left: same curb spots, a car left of the segment faces along it, right +π', () {
    final r = parked(right), l = parked(left);
    expect(l, isNotEmpty);
    expect(l.length, r.length);
    final sides = <bool>{};
    for (var i = 0; i < l.length; i++) {
      // The side is still drawn from the stream: positions are identical.
      expect(l[i].x, r[i].x);
      expect(l[i].y, r[i].y);
      // The segment runs east (+x); left of it is +y.
      final onLeft = l[i].y > 100;
      sides.add(onLeft);
      expect(_norm(l[i].heading), closeTo(onLeft ? 0 : math.pi, 1e-9), reason: '$i left-hand');
      expect(_norm(r[i].heading), closeTo(onLeft ? math.pi : 0, 1e-9), reason: '$i right-hand');
    }
    expect(sides, {true, false}, reason: 'both curbs are used');
  });

  test('the fleet parks by the city it drives in', () async {
    await initializeForge2D();
    final d = DriveWorld(city: left, spec: specs[tuning.cars.startCar]!, tuning: tuning);
    final fleet = CarFleet(d, specs, tuning, (id: 'g', x: d.car.x, y: d.car.y, heading: d.car.heading));
    fleet.addChunk(ChunkData(0, 0, const [], const []));
    expect(fleet.parked, isNotEmpty);
    for (final p in fleet.parked) {
      expect(_norm(p.heading), closeTo(p.y > 100 ? 0 : math.pi, 1e-9));
    }
    d.dispose();
  });
}
