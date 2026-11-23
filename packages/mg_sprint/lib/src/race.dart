import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drive_core/drive_core.dart' show GpsRoute, RouteGraph, findRoute;
import 'package:feed_hub/feed_hub.dart' show NavTarget, navGoal, navStart;
import 'package:shared_gen/shared_gen.dart';
import 'package:world_engine/core.dart' show EdgeHit, RoadGraph;

import 'rules.dart';

/// Sprint A→B in the world (specs/minigames/sprint.md "Svět", "Upřesnění v1"): destination, route,
/// checkpoints, countdown and the race clock over the pure rules. Port of
/// web/src/minigames/sprint/race.ts; the client feeds the car pose.

/// What the race needs from the city.
class SprintWorld {
  const SprintWorld({required this.graph, required this.route, required this.lensDm, required this.searchM});
  final RoadGraph graph;
  final RouteGraph route;
  final Int32List lensDm;

  /// nav.search_m: start edge search radius.
  final double searchM;
}

typedef SprintPose = ({double x, double y, double heading, int layer});

/// Where the race starts: the car's edge hit and pose.
typedef SprintStart = ({EdgeHit? hit, double x, double y, double heading});

/// A checkpoint (or the finish): point (m), road direction (unit), half the corridor width, distance
/// along the route (dm) and where the navigation leads for it.
class SprintGate {
  const SprintGate({
    required this.x,
    required this.y,
    required this.dirX,
    required this.dirY,
    required this.halfWidth,
    required this.atDm,
    required this.target,
  });
  final double x, y, dirX, dirY, halfWidth;
  final int atDm;
  final NavTarget target;
}

class SprintPlan {
  const SprintPlan(this.dest, this.route, this.distDm, this.gates, this.finish);
  final NavTarget dest;
  final GpsRoute route;
  final int distDm;
  final List<SprintGate> gates;
  final SprintGate finish;
}

/// Route from the start to the destination by specs/route.md; null when no road route exists.
GpsRoute? sprintRoute(SprintWorld w, SprintStart start, NavTarget dest) {
  final s = navStart(w.graph, start.hit, start.x, start.y, start.heading, w.searchM);
  if (s == null) return null;
  final r = findRoute(w.route, s.node, navGoal(w.graph, dest).node);
  return r.cost >= 0 ? r : null;
}

/// Checkpoints along the route: cum[i] = length of the first i route edges, every =
/// round(cp_every_m × 10) dm; node i ≥ 1 gets checkpoint k when cum[i] ≥ k × every and
/// 2 × (distDm − cum[i]) > every (then k += 1). Half corridor = half the width of the edge into it.
SprintPlan sprintPlan(SprintWorld w, TuningMinigamesSprint t, NavTarget dest, GpsRoute route) {
  final g = w.graph;
  final every = (t.cpEveryM * 10).round();
  final cum = [0];
  for (final e in route.edges) {
    cum.add(cum.last + w.lensDm[e]);
  }
  final distDm = cum.last;
  final gates = <SprintGate>[];
  var k = 1;
  for (var i = 1; i < route.nodes.length; i++) {
    if (cum[i] < k * every || (distDm - cum[i]) * 2 <= every) continue;
    final node = route.nodes[i], ei = route.edges[i - 1], e = g.edges[ei];
    final x = g.nodeXY[2 * node], y = g.nodeXY[2 * node + 1];
    // Direction of travel into the node along the edge's last (or first) segment.
    final pts = e.pts, n = e.pointCount;
    final (ax, ay) = e.to == node ? (pts[2 * (n - 2)], pts[2 * (n - 2) + 1]) : (pts[2], pts[3]);
    var len = math.sqrt((x - ax) * (x - ax) + (y - ay) * (y - ay));
    if (len == 0) len = 1;
    gates.add(
      SprintGate(
        x: x,
        y: y,
        dirX: (x - ax) / len,
        dirY: (y - ay) / len,
        halfWidth: e.width / 2,
        atDm: cum[i],
        target: NavTarget(id: 'sprint:cp$k', name: '', edge: ei, parkX: (x * 10).round(), parkY: (y * 10).round()),
      ),
    );
    k++;
  }
  final de = g.edges[dest.edge];
  final fp = de.pts;
  final fdx = fp[fp.length - 2] - fp[0], fdy = fp[fp.length - 1] - fp[1];
  var fl = math.sqrt(fdx * fdx + fdy * fdy);
  if (fl == 0) fl = 1;
  final finish = SprintGate(
    x: dest.parkX / 10,
    y: dest.parkY / 10,
    dirX: fdx / fl,
    dirY: fdy / fl,
    halfWidth: de.width / 2,
    atDm: distDm,
    target: dest,
  );
  return SprintPlan(dest, route, distDm, gates, finish);
}

sealed class SprintEvent {
  const SprintEvent();
}

class SprintPicked extends SprintEvent {
  const SprintPicked(this.dest);
  final NavTarget dest;
}

class SprintGo extends SprintEvent {
  const SprintGo();
}

/// Checkpoint [index] passed at [splitMs] from the start; [parAtMs] = par prorated to its distance.
class SprintCp extends SprintEvent {
  const SprintCp(this.index, this.splitMs, this.parAtMs);
  final int index, splitMs, parAtMs;
}

class SprintOver extends SprintEvent {
  const SprintOver(this.result);
  final SprintResult result;
}

/// One race. [update] once per frame with the world dt (scaled like driving).
class SprintRace {
  SprintRace(this.world, this.t, this.dests, int level, int seed) : _byId = {for (final d in dests) d.id: d} {
    state = rules.start(SprintConfig.fromTuning(t, [for (final d in dests) d.id], level), seed);
  }

  final SprintWorld world;
  final TuningMinigamesSprint t;
  final List<NavTarget> dests;
  final Map<String, NavTarget> _byId;
  final rules = SprintRules();
  late SprintState state;

  /// Time since the start of the minigame, seconds.
  double clock = 0;
  SprintPlan? plan;

  /// Every action applied, in order (debug, tests).
  final List<SprintAction> log = [];

  bool get over => state.phase == 'over';
  int get ms => (clock * 1000).floor();

  /// Countdown left (s) while ready.
  double get countdown => state.phase == 'ready' ? math.max(0, t.countdownS - clock) : 0;

  /// Race time (s) since go.
  double get raceS => state.phase == 'run' ? clock - state.goMs / 1000 : state.timeMs / 1000;

  /// The gate the car must pass next (a checkpoint, then the finish).
  SprintGate? get next {
    final p = plan;
    if (p == null) return null;
    if (state.phase == 'ready') return p.gates.firstOrNull ?? p.finish;
    if (state.phase != 'run') return null;
    return state.passed < p.gates.length ? p.gates[state.passed] : p.finish;
  }

  void _act(SprintAction a) {
    state = rules.apply(state, a);
    log.add(a);
  }

  /// Ends the race now (time cap, give-up, car switch); returns the result.
  SprintResult end() {
    if (!over) _act(const SprintAction.timeout());
    return rules.result(state)!;
  }

  /// pick: allow = destinations dest_min_m … dest_max_m from the start with a road route ([] when
  /// none = all). A picked destination without a route ends the race (timeout).
  List<SprintEvent> begin(SprintStart start) {
    final routes = <String, GpsRoute>{};
    final allow = <String>[];
    for (final d in dests) {
      final dx = d.parkX / 10 - start.x, dy = d.parkY / 10 - start.y;
      final s = math.sqrt(dx * dx + dy * dy);
      if (s < t.destMinM || s > t.destMaxM) continue;
      if (sprintRoute(world, start, d) case final r?) {
        routes[d.id] = r;
        allow.add(d.id);
      }
    }
    _act(SprintAction.pick(allow));
    if (over) return [SprintOver(rules.result(state)!)];
    final dest = _byId[state.dest]!;
    final route = routes[dest.id] ?? sprintRoute(world, start, dest);
    if (route == null) return [SprintOver(end())];
    plan = sprintPlan(world, t, dest, route);
    return [SprintPicked(dest)];
  }

  /// One frame: go on the first frame with clock ≥ countdown_s; then the time cap from go, a crash
  /// (before the gate, same atMs) and at most one gate per frame.
  List<SprintEvent> update(double dt, SprintPose car, [bool Function(int atMs)? hit]) {
    final ev = <SprintEvent>[];
    final p = plan;
    if (over || p == null) return ev;
    clock += dt;
    if (state.phase == 'ready') {
      if (clock >= t.countdownS) {
        _act(SprintAction.go(ms, p.distDm, p.gates.length));
        ev.add(const SprintGo());
      }
      return ev;
    }
    if (clock - state.goMs / 1000 >= t.timeCapS) {
      ev.add(SprintOver(end()));
      return ev;
    }
    if (hit?.call(ms) ?? false) _act(SprintAction.hit(ms));
    final g = next!;
    final dx = car.x - g.x, dy = car.y - g.y;
    if (car.layer == 0 && math.sqrt(dx * dx + dy * dy) <= t.cpRadiusM + g.halfWidth) {
      if (state.passed < state.cps) {
        final index = state.passed;
        _act(SprintAction.cp(ms, index));
        final parAt = p.distDm > 0 ? state.parMs * g.atDm ~/ p.distDm : 0;
        ev.add(SprintCp(index, state.splits[index], parAt));
      } else {
        _act(SprintAction.finish(ms));
        ev.add(SprintOver(rules.result(state)!));
      }
    }
    return ev;
  }
}
