import 'dart:io';
import 'dart:ui';

import 'package:drive_core/drive_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge2d/forge2d.dart' show World, Vector2;
import 'package:world_engine/src/pb/citypack.pb.dart' as pb;
import 'package:world_engine/world_engine.dart';

CarSpec spec() => CarSpec.fromJson(File('../../content/cars/m0_coupe.json').readAsStringSync());

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

  group('car physics', () {
    late World world;
    setUp(() => world = World(gravity: Vector2.zero()));
    tearDown(() => world.destroy());

    void run(Car car, ControlInput input, double seconds) {
      for (var i = 0; i < seconds * 60; i++) {
        car.drive(input, 1 / 60, cruise: 25, top: 40);
        world.step(1 / 60);
      }
    }

    test('auto-throttle settles at cruise speed', () {
      final car = Car(world, spec(), x: 0, y: 0, heading: 0, scale: 2.5);
      run(car, ControlInput(), 12);
      expect(car.forwardSpeed, closeTo(25, 1.5));
      expect(car.y.abs(), lessThan(0.5), reason: 'drives straight');
    });

    test('steer right turns clockwise', () {
      final car = Car(world, spec(), x: 0, y: 0, heading: 0, scale: 2.5);
      run(car, ControlInput(), 3);
      run(car, ControlInput()..steer = 1, 1);
      expect(car.heading, lessThan(-0.3));
    });

    test('handbrake in a turn makes the rear slide', () {
      double slip(bool hand) {
        final w = World(gravity: Vector2.zero());
        final car = Car(w, spec(), x: 0, y: 0, heading: 0, scale: 2.5);
        var maxSlip = 0.0;
        for (var i = 0; i < 6 * 60; i++) {
          final input = ControlInput();
          if (i > 4 * 60) {
            input
              ..steer = 1
              ..handbrake = hand;
          }
          car.drive(input, 1 / 60, cruise: 25, top: 40);
          w.step(1 / 60);
          if (car.rearSlip > maxSlip) maxSlip = car.rearSlip;
        }
        w.destroy();
        return maxSlip;
      }

      expect(slip(true), greaterThan(slip(false) + 1));
    });

    test('brake stops the car and then reverses', () {
      final car = Car(world, spec(), x: 0, y: 0, heading: 0, scale: 2.5);
      run(car, ControlInput(), 6);
      run(car, ControlInput()..brake = 1, 5);
      expect(car.forwardSpeed, lessThan(-1));
    });
  });

  group('controls', () {
    const screen = Size(400, 800);

    test('scheme A: drag steers, drag down brakes, second finger is handbrake', () {
      final a = SchemeA();
      final out = ControlInput();
      a.down(1, const Offset(200, 600), screen);
      a.move(1, const Offset(200 + 0.22 * 400, 600), screen);
      a.update(out);
      expect(out.steer, 1);
      expect(out.handbrake, isFalse);
      a.move(1, const Offset(200, 700), screen);
      a.down(2, const Offset(50, 100), screen);
      a.update(out..reset());
      expect(out.brake, greaterThan(0.5));
      expect(out.handbrake, isTrue);
      a.up(2);
      a.up(1);
      a.update(out..reset());
      expect(out.steer, 0);
    });

    test('scheme B: halves steer, both brake', () {
      final b = SchemeB();
      final out = ControlInput();
      b.down(1, const Offset(50, 700), screen);
      b.update(out);
      expect(out.steer, -1);
      b.down(2, const Offset(350, 700), screen);
      b.update(out..reset());
      expect(out.brake, 1);
    });

    test('scheme C: turning the wheel steers, pedal brakes', () {
      final c = SchemeC();
      final out = ControlInput();
      final centre = Offset(200, 800 - 400 * 0.26);
      c.down(1, centre + const Offset(0, -60), screen);
      c.move(1, centre + const Offset(60, 0), screen); // quarter turn right
      c.update(out);
      expect(out.steer, greaterThan(0.5));
      c.down(2, const Offset(400 * 0.88, 800 - 400 * 0.3), screen);
      c.update(out..reset());
      expect(out.brake, 1);
    });
  });

  test('layer tracker never lifts a ground car onto a crossing bridge', () {
    final g = crossing();
    final ground = LayerTracker(g)..reset(-100, 0);
    for (var x = -100.0; x <= 100; x += 2) {
      ground.update(x, 0);
    }
    expect(ground.layer, 0);
    final bridge = LayerTracker(g);
    bridge
      ..edge = g.edges[1]
      ..hit = g.nearest(0, -100, where: (e) => e.index == 1);
    for (var y = -100.0; y <= 100; y += 2) {
      bridge.update(0, y);
    }
    expect(bridge.layer, 1);
  });

  test('props are deterministic per chunk', () {
    final g = crossing();
    final a = generateProps(g, 0, -1, 256, 5, 2.5);
    final b = generateProps(g, 0, -1, 256, 5, 2.5);
    expect(a.props.length, b.props.length);
    expect(a.props.map((p) => p.x), b.props.map((p) => p.x));
  });
}
