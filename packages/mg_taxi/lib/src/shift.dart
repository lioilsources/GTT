import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drive_core/drive_core.dart' show RouteGraph;
import 'package:feed_hub/feed_hub.dart' show NavTarget, feedDistDm, navGoal, navStart;
import 'package:shared_gen/shared_gen.dart';
import 'package:world_engine/core.dart' show EdgeHit, RoadGraph;

import 'rules.dart';

/// Taxi shift in the world (specs/minigames/taxi.md "Svět"): passengers, pickup, dropoff and the shift
/// clock over the pure rules. Port of web/src/minigames/taxi/shift.ts; the client feeds the car pose.

/// A landmark as the pack stores it (dm).
typedef TaxiLandmark = ({String id, String name, int x, int y, bool hero});

/// Hero landmarks with a kept road within dest_search_m, in pack order; parking point = projection (dm).
List<NavTarget> taxiDests(RoadGraph g, Iterable<TaxiLandmark> landmarks, double searchM) => [
  for (final l in landmarks)
    if (l.hero)
      if (g.nearest(l.x / 10, l.y / 10, maxDist: searchM, where: (e) => e.kept && e.isGround) case final h?)
        NavTarget(id: l.id, name: l.name, edge: h.edge.index, parkX: (h.x * 10).round(), parkY: (h.y * 10).round()),
];

typedef TaxiPose = ({double x, double y, double heading, double speed, int layer});

/// A waiting passenger: curb point (m) and the road point the navigation leads to.
class TaxiPassenger {
  const TaxiPassenger(this.x, this.y, this.halfWidth, this.target);
  final double x, y;

  /// Half the corridor width there: pickup within pickup_radius_m + this.
  final double halfWidth;
  final NavTarget target;
}

sealed class TaxiEvent {
  const TaxiEvent();
}

class TaxiSpawn extends TaxiEvent {
  const TaxiSpawn(this.passenger);
  final TaxiPassenger passenger;
}

class TaxiPickup extends TaxiEvent {
  const TaxiPickup(this.dest, this.line, this.distDm);
  final NavTarget dest;
  final int line, distDm;
}

class TaxiDropoff extends TaxiEvent {
  const TaxiDropoff(this.ride);
  final TaxiRide ride;
}

class TaxiOver extends TaxiEvent {
  const TaxiOver(this.result);
  final TaxiResult result;
}

/// What the shift needs from the city.
class TaxiWorld {
  const TaxiWorld({
    required this.graph,
    required this.route,
    required this.lensDm,
    required this.straightPct,
    required this.searchM,
  });
  final RoadGraph graph;
  final RouteGraph route;
  final Int32List lensDm;

  /// feed.straight_pct, nav.search_m.
  final int straightPct;
  final double searchM;
}

/// One 4-minute shift. [update] once per frame with the world dt (scaled like driving).
class TaxiShift {
  TaxiShift(this.world, this.t, this.dests, int seed) : _byId = {for (final d in dests) d.id: d} {
    state = rules.start(TaxiConfig.fromTuning(t, [for (final d in dests) d.id]), seed);
  }

  final TaxiWorld world;
  final TuningMinigamesTaxi t;
  final List<NavTarget> dests;
  final Map<String, NavTarget> _byId;
  final rules = TaxiRules();
  late TaxiState state;

  /// Shift time, seconds.
  double clock = 0;
  TaxiPassenger? passenger;

  /// The destination of the passenger aboard.
  NavTarget? dest;

  /// Route length (dm) from the pickup point, sent with the dropoff.
  int distDm = 0;

  /// Every action applied, in order (debug, tests).
  final List<TaxiAction> log = [];

  bool get over => state.phase == 'over';
  double get left => math.max(0, t.shiftS - clock);
  int get ms => (clock * 1000).floor();

  /// Where the navigation should lead now (the passenger or the destination).
  NavTarget? get target => state.phase == 'ride' ? dest : passenger?.target;

  void _act(TaxiAction a) {
    state = rules.apply(state, a);
    log.add(a);
  }

  /// Traffic onHit while a passenger is aboard reduces the tip.
  void hit() {
    if (state.phase == 'ride') _act(const TaxiAction.hit());
  }

  /// Ends the shift now (timer or the player boarded another car); returns the result.
  TaxiResult end() {
    if (!over) _act(const TaxiAction.timeout());
    return rules.result(state)!;
  }

  List<TaxiEvent> update(double dt, TaxiPose car, EdgeHit? hit) {
    final ev = <TaxiEvent>[];
    if (over) return ev;
    clock += dt;
    if (clock >= t.shiftS) {
      ev.add(TaxiOver(end()));
      return ev;
    }
    final stopped = car.speed <= t.stopSpeedMps && car.layer == 0;
    if (state.phase == 'wait') {
      if (passenger == null && dests.isNotEmpty) {
        passenger = spawnPassenger(world.graph, car, t);
        if (passenger case final p?) ev.add(TaxiSpawn(p));
      }
      final p = passenger;
      if (p != null && stopped && _dist(p.x, p.y, car) <= t.pickupRadiusM + p.halfWidth) {
        final allow = [
          for (final d in dests)
            if (_dist(d.parkX / 10, d.parkY / 10, car) case final s when s >= t.destMinM && s <= t.destMaxM) d.id,
        ];
        _act(TaxiAction.pickup(ms, allow));
        passenger = null;
        final d = dest = _byId[state.dest]!;
        final w = world;
        final start = navStart(w.graph, hit, car.x, car.y, car.heading, w.searchM);
        distDm = feedDistDm(w.route, w.lensDm, start, navGoal(w.graph, d), car.x, car.y, d, w.straightPct);
        ev.add(TaxiPickup(d, state.line, distDm));
      }
    } else if (state.phase == 'ride' && stopped) {
      final d = dest;
      if (d != null && _dist(d.parkX / 10, d.parkY / 10, car) <= t.dropRadiusM) {
        _act(TaxiAction.dropoff(math.max(ms, state.pickMs), distDm));
        dest = null;
        ev.add(TaxiDropoff(state.last));
      }
    }
    return ev;
  }

  static double _dist(double x, double y, TaxiPose c) => math.sqrt((x - c.x) * (x - c.x) + (y - c.y) * (y - c.y));
}

/// The next passenger: from the car's heading in 45° steps (0, +45, −45, +90 …), the nearest kept
/// ground edge to the point (pickup_min_m + pickup_max_m) / 2 away that lies pickup_min_m … pickup_max_m
/// from the car; the passenger stands curb_m beyond the corridor on the right of the edge direction.
TaxiPassenger? spawnPassenger(RoadGraph g, TaxiPose car, TuningMinigamesTaxi t) {
  final mid = (t.pickupMinM + t.pickupMaxM) / 2, search = (t.pickupMaxM - t.pickupMinM) / 2;
  for (final k in const [0, 1, -1, 2, -2, 3, -3, 4]) {
    final a = car.heading + k * math.pi / 4;
    final h = g.nearest(
      car.x + math.cos(a) * mid,
      car.y + math.sin(a) * mid,
      maxDist: search,
      where: (e) => e.kept && e.isGround,
    );
    if (h == null) continue;
    final d = math.sqrt((h.x - car.x) * (h.x - car.x) + (h.y - car.y) * (h.y - car.y));
    if (d < t.pickupMinM || d > t.pickupMaxM) continue;
    final half = h.edge.width / 2;
    // Right-hand normal of the segment direction.
    final nx = h.dirY, ny = -h.dirX;
    return TaxiPassenger(
      h.x + nx * (half + t.curbM),
      h.y + ny * (half + t.curbM),
      half,
      NavTarget(
        id: 'taxi:passenger',
        name: '',
        edge: h.edge.index,
        parkX: (h.x * 10).round(),
        parkY: (h.y * 10).round(),
      ),
    );
  }
  return null;
}
