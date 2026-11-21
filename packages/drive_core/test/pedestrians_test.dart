import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drive_core/drive_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rules_core/rules_core.dart' show Prng;
import 'package:world_engine/core.dart';

// Same cases as web/test/pedestrians.test.ts (specs/pedestrians.md "Testy").
final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
final t = tuning.pedestrians;
final r = t.radiusM * tuning.carScale;

CarPose car(double x, double y, double heading, double vx, double vy) =>
    CarPose(x: x, y: y, heading: heading, halfLength: 5.5, halfWidth: 2.4, vx: vx, vy: vy);

/// Point vs the box swept from pose c over [0, T] at constant velocity (sampled).
bool hitsSwept(double px, double py, CarPose c, double T, double dt) {
  for (var s = 0.0; s <= T + 1e-9; s += dt) {
    if (overlapsBox(px, py, r, c.moved(c.vx * s, c.vy * s))) return true;
  }
  return false;
}

class _FilePack implements PackSource {
  _FilePack(this.root);
  final String root;
  @override
  Future<Uint8List> read(String path) async => File('$root$path').readAsBytes();
}

void main() {
  group('dodge', () {
    test('ignores a pedestrian outside the band', () {
      expect(dodge(0, 12, r, car(0, 0, 0, 20, 0), t), isNull);
      expect(dodge(-20, 0, r, car(0, 0, 0, 20, 0), t), isNull);
      expect(dodge(60, 0, r, car(0, 0, 0, 20, 0), t), isNull);
    });

    test('ignores a standing car', () {
      expect(dodge(8, 0, r, car(0, 0, 0, 0, 0), t), isNull);
    });

    test('leaps a pedestrian ahead out of the band, away from the axis', () {
      final d = dodge(20, 1, r, car(0, 0, 0, 20, 0), t)!;
      expect(d.dx, closeTo(0, 1e-9));
      expect(d.dy, greaterThan(0));
      expect(1 + d.dy, greaterThanOrEqualTo(2.4 + r + t.dodgeMarginM));
      expect(d.tc, closeTo((20 - 5.5 - r - t.dodgeMarginM) / 20, 1e-9));
      expect(d.dur, lessThanOrEqualTo(d.tc * t.leapFraction + 1e-12));
      expect(dodge(20, -1, r, car(0, 0, 0, 20, 0), t)!.dy, lessThan(0));
      expect(dodge(20, 0, r, car(0, 0, 0, 20, 0), t)!.dy, greaterThan(0));
    });

    test('uses the velocity, not the heading (reversing)', () {
      expect(dodge(10, 0, r, car(0, 0, 0, -8, 0), t), isNull);
      final d = dodge(-10, 0.5, r, car(0, 0, 0, -8, 0), t)!;
      expect(d.dy, greaterThan(0));
    });

    test('jumps at once when contact is imminent', () {
      final d = dodge(6, 0, r, car(0, 0, 0, 30, 0), t)!;
      expect(d.tc, 0);
      expect(d.dur, 0);
    });
  });

  test('the guarantee (R7): no approach in limits ever touches a pedestrian', () {
    final rnd = Prng(1);
    double u() => rnd.nextU32() / 4294967296;
    const dt = 1 / 60;
    var tested = 0, dodged = 0;
    for (var n = 0; n < 400; n++) {
      final h = u() * 2 * math.pi;
      final speed = t.dodgeMinMps + u() * (45 - t.dodgeMinMps);
      final slip = (u() * 2 - 1) * 0.6;
      final back = u() < 0.15 ? -1 : 1;
      final vx = math.cos(h + slip) * speed * back, vy = math.sin(h + slip) * speed * back;
      final c0 = car(0, 0, h, vx, vy);
      final ux = vx / speed, uy = vy / speed;
      final al = -6 + u() * 56, pe = (u() * 2 - 1) * 6;
      final p = Pedestrian(n + 1)
        ..bx = ux * al - uy * pe
        ..by = uy * al + ux * pe;
      p
        ..x = p.bx
        ..y = p.by;
      if (overlapsBox(p.x, p.y, r, c0)) continue;
      tested++;
      final stats = PedStats();
      const T = 2.5;
      var c = c0;
      for (var s = 0.0; s < T; s += dt) {
        c = c.moved(vx * dt, vy * dt);
        final was = p.mode;
        stepAvoid(p, [c], r, dt, t, stats);
        settle(p, [c], r, t, stats);
        expect(overlapsBox(p.x, p.y, r, c), isFalse);
        if (was != PedMode.stun && p.mode == PedMode.stun) {
          expect(hitsSwept(p.x, p.y, c, T - s, dt / 4), isFalse);
        }
      }
      expect(stats.clamps, 0);
      if (stats.dodges > 0) dodged++;
    }
    expect(tested, greaterThan(300));
    expect(dodged, greaterThan(100));
  });

  group('pedestrian world on NYC', () {
    const root = '../../build/packs/nyc/';
    final skip = !File('${root}manifest.pb').existsSync();
    late City city;
    setUpAll(() async {
      if (!skip) city = await City.load(_FilePack(root));
    });

    CarPose player() => CarPose(
      x: city.startX,
      y: city.startY,
      heading: city.startHeading,
      halfLength: 5.5,
      halfWidth: 2.4,
      vx: 0,
      vy: 0,
    );

    bool onSidewalk(PedestrianWorld w, double x, double y) {
      final hit = city.graph.nearest(x, y, maxDist: 40, where: w.walkable);
      if (hit == null) return false;
      return (hit.dist - w.offset(hit.edge)).abs() < 1.5 || hit.dist < hit.edge.width / 2 + 1.5;
    }

    test('fills the area with walkers on sidewalks, under the cap', () {
      final w = PedestrianWorld(city, tuning)..update(1 / 60, [player()], 60, night: false);
      expect(w.peds.length, greaterThan(5));
      expect(w.peds.length, lessThanOrEqualTo(t.maxCount));
      for (final p in w.peds) {
        expect(
          math.sqrt(math.pow(p.x - city.startX, 2) + math.pow(p.y - city.startY, 2)),
          greaterThanOrEqualTo(t.fillClearM),
        );
        expect(onSidewalk(w, p.x, p.y), isTrue);
      }
      expect(w.peds.map((p) => p.id).toSet().length, w.peds.length);
    }, skip: skip);

    test('keeps them on the sidewalks while walking', () {
      final w = PedestrianWorld(city, tuning);
      for (var i = 0; i < 60 * 30; i++) {
        w.update(1 / 60, [player()], 60, night: false);
      }
      expect(w.peds.length, greaterThan(5));
      for (final p in w.peds) {
        if (p.mode == PedMode.walk) expect(onSidewalk(w, p.x, p.y), isTrue);
      }
      expect(w.stats.clamps, 0);
    }, skip: skip);

    test('night lowers the cap; disabled means empty', () {
      final w = PedestrianWorld(city, tuning);
      for (var i = 0; i < 60 * 5; i++) {
        w.update(1 / 60, [player()], 60, night: true);
      }
      expect(w.peds.length, lessThanOrEqualTo((t.maxCount * t.nightFactor).round()));
      final off = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync())..pedestrians.enabled = false;
      final w2 = PedestrianWorld(city, off)..update(1 / 60, [player()], 60, night: false);
      expect(w2.peds, isEmpty);
    }, skip: skip);

    test('nearest and byId', () {
      final w = PedestrianWorld(city, tuning)..update(1 / 60, [player()], 60, night: false);
      final p = w.peds.first;
      expect(w.nearest(p.x + 0.1, p.y), same(p));
      expect(w.byId(p.id), same(p));
      expect(w.nearest(p.x, p.y, maxDist: -1), isNull);
    }, skip: skip);
  });
}
