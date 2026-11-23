import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_minigolf/mg_minigolf.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  final tuning = Tuning.fromYaml(File('$repoRoot/content/tuning.yaml').readAsStringSync());
  MinigolfConfig cfg(int level) => MinigolfConfig.fromTuning(tuning.minigames.minigolf, level);

  test('every tuning hole parses; lengths are mm × 100', () {
    final c = cfg(1);
    for (final h in c.holes) {
      final p = Hole.parse(h);
      expect([p.w, p.h, p.par, p.sx, p.cx], [h[0] * 100, h[1] * 100, h[2], h[3] * 100, h[5] * 100]);
    }
    expect(() => Hole.parse([1000, 3000, 2, 500, 300, 500, 2600, 0, 0, 0]), throwsFormatException);
    expect(() => Hole.parse([1000, 3000, 2, 500, 300, 500, 2600, 0, 0, 0, 0, 7]), throwsFormatException);
  });

  test('starts on the first tee and rejects illegal putts', () {
    final r = MinigolfRules();
    final s = r.start(cfg(2), 3);
    final h = r.holeAt(1);
    expect([s.hole, s.strokes, s.scores, s.x, s.y, s.over], [1, 0, <int>[], h.sx, h.sy, false]);
    expect(() => r.apply(s, MinigolfAction.putt(s.x, s.y, 50)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, MinigolfAction.putt(0, 0, 0)), throwsA(isA<IllegalAction>()));
    final over = r.apply(s, const MinigolfAction.timeout());
    expect(r.result(over)!.toJson(), {'winner': 'ai', 'stars': 0, 'score': 0, 'scores': <int>[], 'par': 0});
  });

  test('water costs a stroke and returns the ball; a stopped ball in the cup counts', () {
    final c = cfg(1);
    // A 10 m lane with water across the middle and the cup at the far end.
    final h = Hole.parse([1000, 3000, 2, 500, 300, 500, 2600, 0, 0, 0, 1, 0, 1400, 1000, 1600]);
    final splash = simulatePutt(c, h, h.sx, h.sy, (vx: 0, vy: 800));
    expect(splash.end, PuttEnd.water);
    final r = MinigolfRules();
    final s = r.start(c, 1);
    final out = r.settle(s.copyWith(strokes: 1), s, splash);
    expect([out.strokes, out.x, out.y], [2, s.x, s.y]);
    final rest = simulatePutt(c, h, h.cx, h.cy - 1000, (vx: 0, vy: 1));
    expect(rest.end, PuttEnd.cup);
  });

  final vectors = File('$repoRoot/vectors/minigolf.json').existsSync();
  test(
    'vectors/minigolf.json',
    () => expect(checkVectors(MinigolfRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/minigolf.json') ? 'pending in parity.yaml' : false,
  );
}
