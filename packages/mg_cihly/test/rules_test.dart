import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_cihly/mg_cihly.dart';
import 'package:rules_core/vector_test_support.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  final tuning = Tuning.fromYaml(File('$repoRoot/content/tuning.yaml').readAsStringSync());
  CihlyConfig cfg(int level) => CihlyConfig.fromTuning(tuning.minigames.cihly, level);

  test('the ball waits on the paddle and launches when the serve runs out', () {
    final r = CihlyRules();
    final c = cfg(3);
    var s = r.start(c, 11);
    expect(
      [s.paddle, s.serve, s.ball.x, s.ball.y],
      [c.w ~/ 2, c.serveTicks, c.w ~/ 2, c.paddleY + c.paddleH + c.ballR],
    );
    s = r.apply(s, const CihlyAction.move(0));
    expect([s.paddle, s.ball.x], [c.halfWidth, c.w ~/ 2]);
    s = r.apply(s, const CihlyAction.tick(1));
    expect(s.ball.x, c.halfWidth);
    s = r.apply(s, CihlyAction.tick(c.serveTicks - 1));
    final sp = c.speed[2];
    expect(s.serve, 0);
    expect(s.ball.vx.abs() <= sp ~/ 2, isTrue);
    expect(s.ball.vy > 0, isTrue);
    expect(s.ball.y, c.paddleY + c.paddleH + c.ballR);
  });

  test('bricks are laid out row by row from the top', () {
    final c = cfg(1);
    final b = c.brick(c.cols + 1);
    expect(b.x0, c.brickX0 + c.brickW + c.brickGap);
    expect(b.y1, c.brickTop - c.brickH - c.brickGap);
    expect([b.x1 - b.x0, b.y1 - b.y0], [c.brickW, c.brickH]);
  });

  test('a missed ball costs a life; the last one ends the game', () {
    final r = CihlyRules();
    final c = cfg(1);
    var s = r.start(c, 2);
    for (var i = 0; i < 100000 && !s.over; i++) {
      // The paddle steps away while the ball flies.
      s = r.apply(s.copyWith(paddle: s.serve > 0 ? c.w ~/ 2 : -100000), const CihlyAction.tick(1));
    }
    expect([s.over, s.lives], [true, 0]);
    expect(r.result(s)!.toJson()['cleared'], isFalse);
  });

  final vectors = File('$repoRoot/vectors/cihly.json').existsSync();
  test(
    'vectors/cihly.json',
    () => expect(checkVectors(CihlyRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/cihly.json') ? 'pending in parity.yaml' : false,
  );
}
