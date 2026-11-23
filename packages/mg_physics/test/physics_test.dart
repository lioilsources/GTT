import 'dart:io';

import 'package:mg_physics/mg_physics.dart';
import 'package:test/test.dart';

void main() {
  test('trunc rounds toward zero, isqrt is exact', () {
    expect(trunc(-7, 2), -3);
    expect(trunc(7, -2), -3);
    expect(trunc(-1, 1000000), 0);
    expect(trunc(-1, 1000000).isNegative, isFalse);
    expect([isqrt(0), isqrt(1), isqrt(3), isqrt(4), isqrt(99), isqrt(100)], [0, 1, 1, 2, 9, 10]);
    const big = 94906265;
    expect(isqrt(big * big), big);
    expect(isqrt(big * big - 1), big - 1);
  });

  test('head-on equal masses bounce back (e = 1000, rounded toward zero)', () {
    final a = Body(x: 0, y: 0, vx: 10, r: 10);
    final b = Body(x: 15, y: 0, vx: -10, r: 10);
    expect(collideBodies(a, b, 1000), isTrue);
    expect([a.vx, a.vy, b.vx, b.vy], [-9, 0, 9, 0]);
    // Separating, touching at d2 = R², or concentric: nothing.
    expect(collideBodies(a, b, 1000), isFalse);
    expect(collideBodies(Body(x: 0, y: 0, vx: 5, r: 10), Body(x: 20, y: 0, r: 10), 1000), isFalse);
    expect(collideBodies(Body(x: 0, y: 0, vx: 5, r: 10), Body(x: 0, y: 0, r: 10), 1000), isFalse);
  });

  test('a collision happens even when every increment rounds to 0', () {
    final a = Body(x: 0, y: 0, vx: 1, r: 1000);
    final b = Body(x: 1999, y: 0, r: 1000);
    expect(collideBodies(a, b, 0), isTrue);
    expect([a.vx, b.vx], [1, 0]);
  });

  test('a flat wall reflects only the normal component', () {
    final b = Body(x: 5, y: 50, vx: -20, vy: 7, r: 10);
    collideStatic(b, const RectStatic(-100, 0, 0, 100, 1000));
    expect([b.vx, b.vy], [20, 7]);
    final c = Body(x: 0, y: 25, vy: -10, r: 10);
    collideStatic(c, const CircleStatic(0, 0, 20, 500));
    expect([c.vx, c.vy], [0, 5]);
  });

  test('friction stops slow bodies and keeps the direction', () {
    final b = Body(x: 0, y: 0, vx: 30, vy: -40, r: 1);
    friction(b, 5);
    expect([b.vx, b.vy], [27, -36]);
    final s = Body(x: 0, y: 0, vx: 3, vy: 4, r: 1);
    friction(s, 5);
    expect([s.vx, s.vy], [0, 0]);
  });

  test('simulate checks for motion before the first step and zeroes velocities', () {
    final still = World(bodies: [Body(x: 0, y: 0, r: 1)], statics: const [], eBody: 0, dec: (_, _) => 0);
    expect(simulate(still, 10).steps, 0);
    final b = Body(x: 0, y: 0, vx: 10, r: 1);
    final w = World(bodies: [b], statics: const [], eBody: 0, dec: (_, _) => 3);
    final r = simulate(w, 100);
    expect([r.steps, b.x, b.vx], [4, 10 + 7 + 4 + 1, 0]);
    final capped = Body(x: 0, y: 0, vx: 10, r: 1);
    final cw = World(bodies: [capped], statics: const [], eBody: 0, dec: (_, _) => 0);
    expect(simulate(cw, 3).steps, 3);
    expect([capped.x, capped.vx], [30, 0]);
  });

  test('capture ending the simulation skips steps 3–5', () {
    final b = Body(x: 0, y: 0, vx: 10, r: 1);
    final w = World(bodies: [b], statics: const [], eBody: 0, dec: (_, _) => 1000, capture: (w) => w.bodies[0].x >= 10);
    final r = simulate(w, 100);
    expect([r.steps, r.captured, b.x, b.vx], [1, true, 10, 0]);
  });

  test('shot and normalized aim', () {
    expect(shotVelocity(0, 0, 0, 0, 10), isNull);
    expect(shotVelocity(0, 0, 3, 4, 100), (vx: 60, vy: 80));
    expect(normalizedAim(10, 10, 10, 20), (x: 10, y: 10 + aimR));
  });

  test('pure Dart: no Flutter or dart:ui imports', () {
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final src = f.readAsStringSync();
      expect(src.contains('package:flutter'), isFalse, reason: f.path);
      expect(src.contains('dart:ui'), isFalse, reason: f.path);
    }
  });
}
