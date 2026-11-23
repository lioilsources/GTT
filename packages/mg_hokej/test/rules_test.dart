import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_hokej/mg_hokej.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const cfg = {
  'level': 1,
  'w': 1200,
  'h': 2000,
  'puckR': 60,
  'malletR': 90,
  'goalHalf': 250,
  'eWall': 900,
  'eMallet': 900,
  'dec': 0,
  'maxPuck': 300,
  'malletSpeed': 150,
  'aiSpeed': [30, 45, 60, 75, 90],
  'aiReact': [8, 6, 4, 3, 2],
  'aiDefY': 300,
  'homeY': 300,
  'serveY': 400,
  'goals': 2,
  'goalPause': 5,
  'starMargins': [2, 1],
};

/// A state with the puck at (x, y) moving (vx, vy), mallets home.
HokejState puckAt(HokejRules r, int x, int y, int vx, int vy) {
  final s = r.init(cfg, 1);
  return HokejState(
    tick: 0,
    puck: Puck(x, y, vx, vy),
    me: s.me,
    ai: s.ai,
    playerGoals: 0,
    aiGoals: 0,
    pause: 0,
    aiClock: 0,
    over: false,
  );
}

void main() {
  test('face-off: puck below the centre, mallets home, targets clipped into the half', () {
    final r = HokejRules();
    final s = r.init(cfg, 1);
    expect(s.puck.toJson(), {'x': 600, 'y': 600, 'vx': 0, 'vy': 0});
    expect(s.me.toJson(), {'x': 600, 'y': 300, 'tx': 600, 'ty': 300});
    expect(s.ai.toJson(), {'x': 600, 'y': 1700, 'tx': 600, 'ty': 1700});
    final m = r.apply(s, const HokejAction.move(-50, 5000));
    expect([m.me.tx, m.me.ty, m.me.x], [90, 1000 - 90, 600]);
  });

  test('v2: crossing the top line inside the mouth scores', () {
    final r = HokejRules();
    final s = r.apply(puckAt(r, 600, 1990, 0, 30), const HokejAction.tick(1));
    expect([s.playerGoals, s.pause, s.puck.y], [1, 5, 1000 + 400]);
  });

  test('v2: a fast puck crossing outside the mouth bounces off the end wall', () {
    final r = HokejRules();
    // From x = 1000 (outside the mouth 350…850) the centre crosses y = 2000 at x = 1000 + 0.
    final s = r.apply(puckAt(r, 1000, 1950, 0, 100), const HokejAction.tick(1));
    expect(s.playerGoals, 0);
    expect([s.puck.y, s.puck.vy], [2 * 2000 - 2050, -90]);
    // Diagonal: crosses the line at x = 860 (just outside), ends above the mouth: still no goal.
    final d = r.apply(puckAt(r, 900, 1960, -200, 200), const HokejAction.tick(1));
    expect(d.playerGoals, 0);
    // Edge of the mouth counts as inside.
    final e = r.apply(puckAt(r, 850, 1990, 0, 20), const HokejAction.tick(1));
    expect(e.playerGoals, 1);
  });

  test('the automaton defends in front of its goal while the puck is on the far half', () {
    final c = HokejConfig.fromJson(cfg);
    expect(hokejAiTarget(c, (x: 100, y: 600), (x: 600, y: 1700)), (x: 350, y: 1700));
    expect(hokejAiTarget(c, (x: 600, y: 1200), (x: 600, y: 1700)), (x: 600, y: 1200));
    expect(hokejAiTarget(c, (x: 600, y: 1500), (x: 500, y: 1400)), (x: 350, y: 1750));
  });

  test('timeout only ends the game; then everything is illegal', () {
    final r = HokejRules();
    final s = r.apply(r.init(cfg, 1), const HokejAction.timeout());
    expect(r.result(s)!.toJson(), {'winner': 'draw', 'stars': 0, 'score': 0, 'playerGoals': 0, 'aiGoals': 0});
    expect(() => r.apply(s, const HokejAction.tick(1)), throwsA(isA<IllegalAction>()));
  });

  final vectors = File('$repoRoot/vectors/hokej.json').existsSync();
  test(
    'vectors/hokej.json',
    () => expect(checkVectors(HokejRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/hokej.json') ? 'pending in parity.yaml' : false,
  );
}
