import 'dart:io';
import 'dart:typed_data';

import 'package:drive_core/drive_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge2d/forge2d.dart';
import 'package:shared_gen/citypack_pb.dart' as pb;
import 'package:world_engine/core.dart';

/// Hop on a bridge deck (specs/hop.md v2): over a standing tram, back onto the deck; the same
/// track and numbers as web/test/hopBridge.test.ts (flat pack).

final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
CarSpec car(String id) => parseCarSpec(File('../../content/cars/$id.json').readAsStringSync());

Uint8List _gz(List<int> b) => Uint8List.fromList(gzip.encode(b));

class _MemPack implements PackSource {
  _MemPack(this.files);
  final Map<String, Uint8List> files;
  @override
  Future<Uint8List> read(String path) async => files[path] ?? (throw StateError('no $path in the pack'));
}

/// Ground −400…−100, ramp up −100…0 (layer 0→1), deck 0…100 (layer 1), ramp down to 200, ground to 500.
Future<City> bridgeCity() {
  const xs = [-400, -100, 0, 100, 200, 500];
  const layers = [(0, 0, false), (0, 1, true), (1, 1, true), (1, 0, true), (0, 0, false)];
  final edges = <pb.Edge>[];
  for (var i = 0; i < layers.length; i++) {
    final a = xs[i], b = xs[i + 1];
    final k = ((b - a) / 16).ceil();
    final pts = <int>[];
    for (var s = 0; s <= k; s++) {
      pts
        ..add(((a + (b - a) * s / k) * 10).round())
        ..add(0);
    }
    final (lf, lt, bridge) = layers[i];
    edges.add(pb.Edge(
      from: i,
      to: i + 1,
      points: pts,
      class_4: pb.RoadClass.PRIMARY,
      lanes: 2,
      oneway: 0,
      kept: true,
      widthM: 20,
      layerFrom: lf,
      layerTo: lt,
      bridge: bridge,
    ));
  }
  return City.load(
    _MemPack({
      'manifest.pb': _gz(
        pb.Manifest(
          formatVersion: 1,
          cityId: 'test',
          chunkM: 256,
          driveSide: 'right',
          units: 'metric',
          start: pb.Spawn(x: 0, y: 0, headingRad: 0),
        ).writeToBuffer(),
      ),
      'graph.pb': _gz(
        pb.Graph(names: [''], nodes: [for (final x in xs) pb.Node(x: x * 10, y: 0)], edges: edges).writeToBuffer(),
      ),
      'landmarks.pb': _gz(pb.Landmarks().writeToBuffer()),
      'spots.pb': _gz(pb.Spots().writeToBuffer()),
    }),
  );
}

void main() {
  setUpAll(initializeForge2D);
  final vega = car('vega_roadster'), coupe = car('m0_coupe');
  final dt = 1 / tuning.drive.stepHz;
  final cruise = tuning.speedMps.cruise;

  /// On the deck at x = 20 (layer 1) at cruise; a tram car stands 18 m ahead and a building under
  /// the deck just beyond it. Returns the world and the far / near edge of the tram for the car.
  Future<(DriveWorld, double, double)> onDeck(CarSpec spec) async {
    final city = await bridgeCity();
    final d = DriveWorld(city: city, spec: spec, tuning: tuning);
    for (var cx = -3; cx <= 2; cx++) {
      for (var cy = -1; cy <= 0; cy++) {
        d.addChunk(ChunkData(cx, cy, const [], const []));
      }
    }
    d.props.clear();
    d.traffic?.solid = false;
    d.traffic?.reset();
    d.spawn(-150, 0, 0);
    for (var i = 0; i < 60 * 20 && d.car.x < 20; i++) {
      d.input.reset();
      d.car.body.linearVelocity = Vector2(cruise, 0);
      d.update(dt);
    }
    expect(d.car.layer, 1);
    final tramX = d.car.x + 18, half = tuning.trams.carLengthM / 2;
    d.world.createBody(BodyDef(type: BodyType.static, position: Vector2(tramX, 0))).createShape(
      Polygon.box(half, tuning.trams.carWidthM / 2),
      ShapeDef(filter: Filter(categoryBits: catTram, maskBits: catCar)),
    );
    // A building under the deck (layer 0 only): the flight on layer 1 must not hit it.
    d.world.createBody(BodyDef(type: BodyType.static, position: Vector2(tramX + 8, 0))).createShape(
      Polygon.box(4, 4),
      ShapeDef(filter: Filter(categoryBits: catBuildings, maskBits: catCar)),
    );
    d.car.body.linearVelocity = Vector2(cruise, 0);
    return (d, tramX + half + d.car.halfLength, tramX - half - d.car.halfLength);
  }

  test('canHop on a bridge and in a tunnel (v2)', () {
    final v = tuning.hop.minSpeedMps;
    expect(canHop(vega, 3, 0, 1, v, tuning.hop), isTrue);
    expect(canHop(vega, 3, 0, -1, v, tuning.hop), isTrue);
    expect(canHop(vega, 3, 0, 1, v - 0.01, tuning.hop), isFalse);
  });

  test('flies over a tram on the deck and lands on the deck', () async {
    final (d, tramFar, _) = await onDeck(vega);
    expect(d.hopReady, isTrue);
    expect(d.startHop(), isTrue);
    expect(d.car.maskBits, 0);
    while (d.hop.airborne) {
      d.input.reset();
      d.update(dt);
      expect(d.car.layer, 1); // the layer is kept in the air
      expect(d.car.y.abs(), lessThan(10));
    }
    expect(d.car.x, greaterThan(tramFar));
    expect(d.car.layer, 1);
    expect(d.car.maskBits & catTram, catTram);
    expect(d.car.maskBits & catBuildings, 0);
    for (var i = 0; i < 60 * 3; i++) {
      d.input.reset();
      d.update(dt);
    }
    expect(d.car.y.abs(), lessThan(10));
    d.dispose();
  });

  test('rails hold a sideways flight on the deck (no fall into the river)', () async {
    final (d, _, _) = await onDeck(vega);
    d.car.body.linearVelocity = Vector2(cruise, 12);
    expect(d.startHop(), isTrue);
    var maxY = 0.0;
    while (d.hop.airborne) {
      d.input.reset();
      d.update(dt);
      if (d.car.y.abs() > maxY) maxY = d.car.y.abs();
    }
    expect(maxY, lessThan(10));
    expect(d.car.layer, 1);
    d.dispose();
  });

  test('a normal car stops at the tram', () async {
    final (d, _, tramNear) = await onDeck(coupe);
    expect(d.hopReady, isFalse);
    for (var i = 0; i < 60 * 3; i++) {
      d.input.reset();
      d.update(dt);
    }
    expect(d.car.x, lessThan(tramNear + 0.5));
    d.dispose();
  });
}
