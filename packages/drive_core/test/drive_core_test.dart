import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drive_core/drive_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge2d/forge2d.dart' show World, Vector2;
import 'package:world_engine/core.dart';
import 'package:shared_gen/citypack_pb.dart' as pb;

final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
CarSpec spec() => parseCarSpec(File('../../content/cars/m0_coupe.json').readAsStringSync());

/// Ground street along x, bridge along y crossing above it, ramp-free.
RoadGraph crossing() {
  pb.Node n(int x, int y) => pb.Node(x: x * 10, y: y * 10);
  pb.Edge e(int a, int b, List<int> pts, int layer) => pb.Edge(
      from: a,
      to: b,
      points: pts.map((v) => v * 10),
      lanes: 2,
      layerFrom: layer,
      layerTo: layer,
      kept: true,
      widthM: 26);
  return RoadGraph.fromPb(pb.Graph(
    names: [''],
    nodes: [n(-300, 0), n(300, 0), n(0, -300), n(0, 300)],
    edges: [
      e(0, 1, [-300, 0, 300, 0], 0),
      e(2, 3, [0, -300, 0, 300], 1)
    ],
  ));
}

void main() {
  setUpAll(() async => initializeForge2D());
  benchTests();

  group('car physics', () {
    final d = tuning.drive;
    late World world;
    setUp(() => world = World(gravity: Vector2.zero()));
    tearDown(() => world.destroy());

    Car newCar(World w) => Car(w, spec(), d, x: 0, y: 0, heading: 0, scale: tuning.carScale);

    void run(Car car, ControlInput input, double seconds, [World? w]) {
      for (var i = 0; i < seconds * d.stepHz; i++) {
        car.drive(input, (1 / d.stepHz), cruise: tuning.speedMps.cruise, top: tuning.speedMps.topDefault);
        (w ?? world).step((1 / d.stepHz), subStepCount: d.substeps);
      }
    }

    test('auto-throttle settles at cruise speed', () {
      final car = newCar(world);
      run(car, ControlInput(), 12);
      expect(car.forwardSpeed, closeTo(tuning.speedMps.cruise, tuning.speedMps.cruise * 0.06));
      expect(car.y.abs(), lessThan(0.5), reason: 'drives straight');
    });

    test('steer right turns clockwise', () {
      final car = newCar(world);
      run(car, ControlInput(), 3);
      run(car, ControlInput()..steer = 1, 1);
      expect(car.heading, lessThan(-0.3));
    });

    test('handbrake in a turn makes the rear slide', () {
      double slip(bool hand) {
        final w = World(gravity: Vector2.zero());
        final car = newCar(w);
        run(car, ControlInput(), 4, w);
        var maxSlip = 0.0;
        for (var i = 0; i < 2 * d.stepHz; i++) {
          final input = ControlInput()
            ..steer = 1
            ..handbrake = hand;
          car.drive(input, (1 / d.stepHz), cruise: tuning.speedMps.cruise, top: tuning.speedMps.topDefault);
          w.step((1 / d.stepHz), subStepCount: d.substeps);
          if (car.rearSlip > maxSlip) maxSlip = car.rearSlip;
        }
        w.destroy();
        return maxSlip;
      }

      expect(slip(true), greaterThan(slip(false) + 1));
    });

    test('gripScale (rain, specs/weather.md) caps the axle grip lower: more slip, 1 = unchanged', () {
      double slip(double scale) {
        final w = World(gravity: Vector2.zero());
        final car = newCar(w)..gripScale = scale;
        run(car, ControlInput(), 4, w);
        var sum = 0.0;
        for (var i = 0; i < 2 * d.stepHz; i++) {
          car.drive(ControlInput()..steer = 1, (1 / d.stepHz), cruise: tuning.speedMps.cruise, top: tuning.speedMps.topDefault);
          w.step((1 / d.stepHz), subStepCount: d.substeps);
          sum += car.rearSlip + car.frontSlip;
        }
        w.destroy();
        return sum;
      }

      final dry = slip(1);
      expect(slip(tuning.weather.rainGrip), greaterThan(dry));
      expect(slip(1), dry, reason: 'deterministic, scale 1 is the dry rule');
    });

    test('brake stops the car and then reverses', () {
      final car = newCar(world);
      run(car, ControlInput(), 6);
      run(car, ControlInput()..brake = 1, 5);
      expect(car.forwardSpeed, lessThan(-1));
      expect(car.forwardSpeed, greaterThanOrEqualTo(-d.reverseMaxMps - 0.5));
    });
  });

  group('controls', () {
    const w = 400.0, h = 800.0;
    final c = tuning.controls;

    test('scheme A: drag steers, drag down brakes, second finger is handbrake', () {
      final a = SchemeA(c);
      final out = ControlInput();
      a.down(1, (x: 200, y: 600), w, h);
      a.move(1, (x: 200 + c.aFullSteerWidth * w, y: 600), w, h);
      a.update(out);
      expect(out.steer, 1);
      expect(out.handbrake, isFalse);
      a.move(1, (x: 200, y: 600 + (c.aDeadZoneHeight + c.aFullBrakeHeight) * h), w, h);
      a.down(2, (x: 50, y: 100), w, h);
      a.update(out..reset());
      expect(out.brake, 1);
      expect(out.handbrake, isTrue);
      a
        ..up(2)
        ..up(1)
        ..update(out..reset());
      expect(out.steer, 0);
    });

    test('scheme B: halves steer, both brake', () {
      final b = SchemeB(c);
      final out = ControlInput();
      b.down(1, (x: 50, y: 700), w, h);
      b.update(out);
      expect(out.steer, -1);
      b.down(2, (x: 350, y: 700), w, h);
      b.update(out..reset());
      expect(out.brake, 1);
    });

    test('scheme C: turning the wheel steers, pedal brakes', () {
      final s = SchemeC(c);
      final out = ControlInput();
      final ctr = SchemeC.wheelCentre(w, h);
      s.down(1, (x: ctr.x, y: ctr.y - 60), w, h);
      s.move(1, (x: ctr.x + 60, y: ctr.y), w, h); // quarter turn right
      s.update(out);
      expect(out.steer, closeTo((3.141592653589793 / 2) / c.cMaxWheelRad, 1e-9));
      final p = SchemeC.pedal(w, h);
      s.down(2, (x: p.left + p.width / 2, y: p.top + p.height / 2), w, h);
      s.update(out..reset());
      expect(out.brake, 1);
    });
  });

  test('layer tracker never lifts a ground car onto a crossing bridge', () {
    final g = crossing();
    final ground = LayerTracker(g, tuning.layers)..reset(-100, 0);
    for (var x = -100.0; x <= 100; x += 2) {
      ground.update(x, 0);
    }
    expect(ground.layer, 0);
    final bridge = LayerTracker(g, tuning.layers)
      ..edge = g.edges[1]
      ..hit = g.nearest(0, -100, where: (e) => e.index == 1);
    for (var y = -100.0; y <= 100; y += 2) {
      bridge.update(0, y);
    }
    expect(bridge.layer, 1);
  });

  test('props are deterministic per chunk and follow the tuning mix', () {
    final g = crossing();
    final a = generateProps(g, 0, 0, tuning);
    final b = generateProps(g, 0, 0, tuning);
    expect(a.props, isNotEmpty);
    expect(a.props.map((p) => p.x), b.props.map((p) => p.x));
    for (final p in a.props) {
      expect(p.radius, tuning.props.radiusM[p.kind.name]! * tuning.carScale);
    }
  });

  test('logic modules import no Flutter or dart:ui', () {
    final files = [
      ...Directory('lib').listSync(recursive: true),
      for (final f in ['chunk.dart', 'chunk_window.dart', 'citypack.dart', 'model.dart', 'tuning.dart'])
        File('../world_engine/lib/src/$f'),
      File('../world_engine/lib/core.dart'),
    ].whereType<File>().where((f) => f.path.endsWith('.dart'));
    for (final f in files) {
      final ui = RegExp(r"^(import|export) '(package:flutter|dart:ui)", multiLine: true);
      expect(ui.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
    }
  });
}

class _FilePack implements PackSource {
  _FilePack(this.root);
  final String root;
  @override
  Future<Uint8List> read(String path) async => File('$root$path').readAsBytes();
}

void benchTests() {
  test('D1 benchmark: the NYC route resolves and the autopilot drives it (specs/bench.md)', () async {
    const root = '../../build/packs/nyc/';
    if (!File('${root}manifest.pb').existsSync()) return;
    await initializeForge2D();
    final src = _FilePack(root);
    final city = await City.load(src);
    final route = resolveRoute(city.graph,
        BenchRoute.fromJson(jsonDecode(File('../../content/bench/nyc.json').readAsStringSync()) as Map<String, Object?>));
    expect(route.legs, 5);
    expect(route.length, inInclusiveRange(3000, 5000));
    final d = DriveWorld(city: city, spec: spec(), tuning: tuning);
    for (final c in city.manifest.chunks) {
      d.addChunk(prepareChunk(await src.read(chunkPath(c.x, c.y))));
    }
    final pilot = Autopilot(route, tuning)..start(d);
    d.beforeStep = (step) => pilot.step(d, d.input, step);
    var t = 0.0;
    while (!pilot.finished && t < 600) {
      d.update(1 / 60);
      t += 1 / 60;
    }
    expect(pilot.finished, isTrue);
    expect(pilot.respawns, lessThanOrEqualTo(2));
    expect(t, lessThan(400));
    d.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
