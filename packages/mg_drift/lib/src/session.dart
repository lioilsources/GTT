import 'dart:math' as math;

import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Drift zone in the world (specs/minigames/drift.md "Svět", "Upřesnění v1"): sampling the car, the
/// zone and the session clock over the pure rules. Port of web/src/minigames/drift/session.ts; the
/// client feeds the car every frame.

/// The car as the session needs it (m, m/s, rad).
typedef DriftPose = ({double x, double y, double heading, double vx, double vy, int layer});

/// Below this speed β is 0 (spec "Vzorky").
const slipMinMps = 0.5;

/// |β| in mrad: the angle between the car's heading and its velocity (up to π reversing), floored.
int slipMrad(DriftPose p) {
  final sp = math.sqrt(p.vx * p.vx + p.vy * p.vy);
  if (sp < slipMinMps) return 0;
  final c = math.cos(p.heading), s = math.sin(p.heading);
  final f = p.vx * c + p.vy * s, l = -p.vx * s + p.vy * c;
  return (math.atan2(l, f).abs() * 1000).floor();
}

sealed class DriftEvent {
  const DriftEvent();
}

/// A chain was banked for [points].
class DriftBank extends DriftEvent {
  const DriftBank(this.points);
  final int points;
}

class DriftOver extends DriftEvent {
  const DriftOver(this.result);
  final DriftResult result;
}

/// One session around the zone centre ([cx], [cy]: the spot's parking point, m).
class DriftSession {
  DriftSession(this.t, int level, this.cx, this.cy) {
    state = rules.start(DriftConfig.fromTuning(t, level));
  }

  final TuningMinigamesDrift t;
  final double cx, cy;
  final rules = DriftRules();
  late DriftState state;

  /// Session time, seconds.
  double clock = 0;
  double _acc = 0;

  /// Every action applied, in order (debug, tests).
  final List<DriftAction> log = [];

  /// The last sample's inZone (HUD "back into the ring").
  bool inZone = true;

  bool get over => state.phase == 'over';
  double get left => math.max(0, t.sessionS - clock);
  int get ms => (clock * 1000).floor();

  void _act(DriftAction a) {
    state = rules.apply(state, a);
    log.add(a);
  }

  /// Ends the session now (timer, car switch, give-up); returns the result.
  DriftResult end() {
    if (!over) _act(const DriftAction.timeout());
    return rules.result(state)!;
  }

  /// Once per frame with the world dt; [hit] says whether the client reports a crash this frame at
  /// that session time (WorldHits.take). The hit goes before the frame's sample, at the same atMs; the
  /// frame that reaches session_s sends only the timeout.
  List<DriftEvent> update(double dt, DriftPose car, [bool Function(int atMs)? hit]) {
    final ev = <DriftEvent>[];
    if (over) return ev;
    clock += dt;
    if (clock >= t.sessionS) {
      final before = state.score;
      final r = end();
      if (r.score > before) ev.add(DriftBank(r.score - before));
      ev.add(DriftOver(r));
      return ev;
    }
    if (hit?.call(ms) ?? false) _act(DriftAction.hit(ms));
    final period = 1 / t.sampleHz;
    _acc += dt;
    if (_acc >= period) {
      _acc %= period;
      final before = state.score;
      final dx = car.x - cx, dy = car.y - cy;
      inZone = car.layer == 0 && math.sqrt(dx * dx + dy * dy) <= t.zoneM;
      final speed = (math.sqrt(car.vx * car.vx + car.vy * car.vy) * 100).floor();
      _act(DriftAction.sample(ms, slipMrad(car), speed, inZone));
      if (state.score > before) ev.add(DriftBank(state.score - before));
    }
    return ev;
  }
}
