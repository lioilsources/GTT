import 'dart:io';
import 'dart:typed_data';

import 'package:drive_core/drive_core.dart' show RouteGraph;
import 'package:feed_hub/feed_hub.dart' show NavTarget, edgeLengthsDm;
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_taxi/mg_taxi.dart';
import 'package:rules_core/vector_test_support.dart';
import 'package:shared_gen/citypack_pb.dart' as pb;
import 'package:world_engine/core.dart';

/// Left-hand traffic (specs/cities.md v2): the taxi passenger waits on the sidewalk left of the edge
/// direction when `manifest.driveSide` is left, whatever the city id.

Uint8List _gz(List<int> b) => Uint8List.fromList(gzip.encode(b));

class _MemPack implements PackSource {
  _MemPack(this.files);
  final Map<String, Uint8List> files;
  @override
  Future<Uint8List> read(String path) async => files[path] ?? (throw StateError('no $path in the pack'));
}

/// One straight two-way road east along y = 0 from x = −200 to 400 m, 26 m wide.
Map<String, Uint8List> pack(String driveSide) => {
  'manifest.pb': _gz(
    pb.Manifest(
      formatVersion: 1,
      cityId: 'nyc',
      driveSide: driveSide,
      units: 'metric',
      chunkM: 256,
      start: pb.Spawn(x: 0, y: 0),
    ).writeToBuffer(),
  ),
  'graph.pb': _gz(
    pb.Graph(
      names: [''],
      nodes: [pb.Node(x: -2000, y: 0), pb.Node(x: 4000, y: 0)],
      edges: [
        pb.Edge(
          from: 0,
          to: 1,
          points: [-2000, 0, 4000, 0],
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

void main() {
  final tuning = Tuning.fromYaml(File('$repoRoot/content/tuning.yaml').readAsStringSync());
  final tt = tuning.minigames.taxi;
  const car = (x: 0.0, y: 0.0, heading: 0.0, speed: 0.0, layer: 0);

  late City right, left;
  setUpAll(() async {
    right = await City.load(_MemPack(pack('right')));
    left = await City.load(_MemPack(pack('left')));
  });

  test('spawnPassenger: right of the edge direction by default, left for left-hand traffic', () {
    final r = spawnPassenger(right.graph, car, tt, leftHand: right.leftHand)!;
    final l = spawnPassenger(left.graph, car, tt, leftHand: left.leftHand)!;
    // The edge runs east (+x): right is −y, left is +y; both half a corridor + curb_m from the axis.
    expect(r.y, closeTo(-(13 + tt.curbM), 1e-6));
    expect(l.y, closeTo(13 + tt.curbM, 1e-6));
    expect(l.x, r.x);
    // Navigation still leads to the road point.
    expect(l.target.parkY, 0);
  });

  test('the shift spawns on the side of TaxiWorld.leftHand from the manifest', () {
    TaxiShift shift(City c) => TaxiShift(
      TaxiWorld(
        graph: c.graph,
        route: RouteGraph.fromPb(c.graphPb, tuning.route.classCost),
        lensDm: edgeLengthsDm(c.graphPb),
        straightPct: tuning.feed.straightPct,
        searchM: tuning.nav.searchM,
        leftHand: c.leftHand,
      ),
      tt,
      const [NavTarget(id: 'far', name: 'Far', edge: 0, parkX: 3900, parkY: 0)],
      7,
    );
    final l = shift(left)..update(0.1, car, null);
    final r = shift(right)..update(0.1, car, null);
    expect(l.passenger!.y, greaterThan(0));
    expect(r.passenger!.y, lessThan(0));
  });
}
