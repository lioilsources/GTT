import 'dart:convert';
import 'dart:math' as math;

import 'package:world_engine/core.dart';

/// Smooth driving (specs/flow.md v1, F-069): wall slide and bounce, the trail, automatic and
/// manual rescue, stuck metering. Pure rules (no Box2D, no Flutter); [DriveWorld] applies them.
/// The literal numbers below are fixed by the spec text (not tuning values).

/// Trail sample period, minimum speed, age and length (5 s / 0.25 s), specs/flow.md "Stopa".
const double trailDtS = 0.25;
const double trailMinMps = 3;
const double trailKeepS = 5;
const int trailMax = 20;

/// Rescues counted for the next attempt: within 5 s of the previous one, within 25 m of the first.
const double rescueWindowS = 5;
const double rescueNearM = 25;

/// The move: 0.4 s animation (speed 0), then 1 s more of grace.
const double rescueAnimS = 0.4;
const double rescueGraceS = 1.4;

/// Slide: heading eases to the wall at 6 rad/s (exponential), spin × 0.5.
const double slideEasePerS = 6;
const double slideSpinKeep = 0.5;

/// Head-on bounce: the car is moved 1 m away from the wall along n.
const double unstickM = 1;

/// Debug overlay window: stuck events in the last 10 minutes of driving.
const double stuckWindowS = 600;

/// Kind of a stuck event (the `kind` of a stuck.log line).
enum StuckKind { auto1, auto2, road, button }

class TrailPoint {
  const TrailPoint(this.x, this.y, this.heading, this.t);
  final double x;
  final double y;
  final double heading;

  /// Driving time of the sample (s): points older than 5 s are dropped.
  final double t;
}

class WallResponse {
  const WallResponse(this.vx, this.vy, {required this.slide, this.tx = 0, this.ty = 0});
  final double vx;
  final double vy;

  /// true = oblique (slide along t), false = head-on bounce.
  final bool slide;

  /// Unit wall direction along the velocity (slide only).
  final double tx;
  final double ty;
}

/// The response to a static contact (specs/flow.md "Náraz do pevné překážky"): v = velocity before
/// the contact, n = unit normal from the wall to the car. Null when the car does not move into it.
WallResponse? wallResponse(double vx, double vy, double nx, double ny, TuningFlowWall t) {
  final sp = math.sqrt(vx * vx + vy * vy);
  final vn = vx * nx + vy * ny;
  if (sp < 1e-6 || vn >= 0) return null;
  final alpha = math.asin(math.min(1.0, -vn / sp));
  final vtx = vx - vn * nx, vty = vy - vn * ny;
  final vt = math.sqrt(vtx * vtx + vty * vty);
  if (alpha < t.slideAngleDeg * math.pi / 180 && vt > 1e-9) {
    final tx = vtx / vt, ty = vty / vt;
    final mag = math.max(vt, sp * t.slideSpeedKeep * math.cos(alpha));
    return WallResponse(tx * mag, ty * mag, slide: true, tx: tx, ty: ty);
  }
  return WallResponse(-vn * nx * t.restitution + vtx, -vn * ny * t.restitution + vty, slide: false);
}

double _wrap(double a) {
  while (a > math.pi) {
    a -= 2 * math.pi;
  }
  while (a < -math.pi) {
    a += 2 * math.pi;
  }
  return a;
}

/// Slide heading: eases towards the wall direction (t or −t, whichever the nose is closer to) at
/// [slideEasePerS], exponentially.
double easeHeading(double heading, double tx, double ty, double dt) {
  var target = math.atan2(ty, tx);
  if (math.cos(heading - target) < 0) target += math.pi;
  return heading + _wrap(target - heading) * (1 - math.exp(-slideEasePerS * dt));
}

/// The rewind point (specs/flow.md "Vyproštění" 3): the trail point whose length along the trail,
/// counted from (x, y) through the newest point backwards, is closest to [dist]; when the trail is
/// shorter, the oldest point. Returns its index, or −1 for an empty trail.
int rewindIndex(List<TrailPoint> trail, double x, double y, double dist) {
  if (trail.isEmpty) return -1;
  var best = trail.length - 1;
  var bestErr = double.infinity;
  var s = 0.0, px = x, py = y;
  for (var i = trail.length - 1; i >= 0; i--) {
    final p = trail[i];
    final dx = p.x - px, dy = p.y - py;
    s += math.sqrt(dx * dx + dy * dy);
    px = p.x;
    py = p.y;
    final err = (s - dist).abs();
    if (err < bestErr) {
      bestErr = err;
      best = i;
    }
  }
  return s < dist ? 0 : best;
}

class RoadSpot {
  const RoadSpot(this.x, this.y, this.heading, this.node);
  final double x;
  final double y;
  final double heading;
  final int node;
}

/// "Přesun na silnici": the nearest node of a kept ground (layer 0) road; ties by the smaller node
/// index. Heading along the GPS [route] (interleaved metres) when its polyline passes within
/// [routeM] of the node (the route's direction there), else along the node's first kept ground
/// edge, away from the node.
RoadSpot? roadSpot(RoadGraph g, double x, double y, List<double>? route, double routeM) {
  var node = -1;
  var bd = double.infinity;
  for (final e in g.edges) {
    if (!e.kept || !e.isGround) continue;
    for (final n in [e.from, e.to]) {
      final dx = g.nodeXY[2 * n] - x, dy = g.nodeXY[2 * n + 1] - y;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d < bd || (d == bd && n < node)) {
        bd = d;
        node = n;
      }
    }
  }
  if (node < 0) return null;
  final nx = g.nodeXY[2 * node].toDouble(), ny = g.nodeXY[2 * node + 1].toDouble();
  if (route != null && route.length >= 4) {
    var rd = double.infinity, rh = 0.0;
    for (var i = 0; i + 3 < route.length; i += 2) {
      final ax = route[i], ay = route[i + 1], bx = route[i + 2], by = route[i + 3];
      final dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy;
      if (l2 < 1e-9) continue;
      final t = (((nx - ax) * dx + (ny - ay) * dy) / l2).clamp(0.0, 1.0);
      final ex = ax + dx * t - nx, ey = ay + dy * t - ny;
      final d = math.sqrt(ex * ex + ey * ey);
      if (d < rd) {
        rd = d;
        rh = math.atan2(dy, dx);
      }
    }
    if (rd <= routeM) return RoadSpot(nx, ny, rh, node);
  }
  final list = g.nodeEdges[node];
  int? ei;
  for (final i in list) {
    if (g.edges[i].kept && g.edges[i].isGround) {
      ei = i;
      break;
    }
  }
  ei ??= list.isEmpty ? null : list.first;
  var heading = 0.0;
  if (ei != null) {
    final e = g.edges[ei], p = e.pts, k = p.length;
    heading = e.from == node ? math.atan2(p[3] - p[1], p[2] - p[0]) : math.atan2(p[k - 3] - p[k - 1], p[k - 4] - p[k - 2]);
  }
  return RoadSpot(nx, ny, heading, node);
}

/// The car as the flow rules see it after a step.
class FlowCar {
  const FlowCar({
    required this.x,
    required this.y,
    required this.heading,
    required this.speed,
    required this.braking,
    required this.airborne,
  });
  final double x;
  final double y;
  final double heading;
  final double speed;

  /// The player brakes (brake pedal or reverse, handbrake).
  final bool braking;
  final bool airborne;
}

class StuckEvent {
  const StuckEvent(this.t, this.kind, this.x, this.y);

  /// Driving time (s, the DriveWorld clock: pause and minigames excluded).
  final double t;
  final StuckKind kind;
  final double x;
  final double y;
}

/// What the automatic rescue decided this step: [point] for auto1 / auto2, null for the road.
class RescuePlan {
  const RescuePlan(this.kind, [this.point]);
  final StuckKind kind;
  final TrailPoint? point;
}

/// Trail, stuck timers and the stuck log of one session (specs/flow.md "Stav").
class FlowState {
  FlowState(this.t);
  final TuningFlowRescue t;

  List<TrailPoint> trail = [];
  double stuckT = 0;
  double slowT = 0;

  /// The current series of automatic rescues at one place (see [_decide]).
  List<({double t, double x, double y})> rescues = [];
  double graceT = 0;

  /// Rescue animation left (s); the car stands while > 0.
  double animT = 0;
  final List<StuckEvent> events = [];
  double _trailAcc = 0;

  /// Called for every stuck event (the debug stuck.log).
  void Function(StuckEvent e)? onStuck;

  /// The "Na silnici" button is shown.
  bool get buttonShown => slowT >= t.buttonAfterS;

  /// One fixed step after physics at driving time [now]. [blocked] = an open context menu that does
  /// not pause (pause and minigames do not step at all). Returns the automatic rescue, or null.
  RescuePlan? step(double dt, double now, FlowCar car, bool blocked) {
    graceT = math.max(0, graceT - dt);
    animT = math.max(0, animT - dt);
    // Trail: every 0.25 s while faster than 3 m/s, on the ground and not in the rescue animation.
    _trailAcc += dt;
    if (_trailAcc >= trailDtS - 1e-9) {
      _trailAcc -= trailDtS;
      if (car.speed > trailMinMps && !car.airborne && animT == 0) {
        trail.add(TrailPoint(car.x, car.y, car.heading, now));
        if (trail.length > trailMax) trail.removeAt(0);
      }
    }
    // Only the last 5 s: a car crawling along a wall for long has no stale point far behind.
    while (trail.isNotEmpty && trail.first.t < now - trailKeepS - 1e-9) {
      trail.removeAt(0);
    }
    final slow = car.speed < t.stuckSpeedMps;
    slowT = slow && animT == 0 ? slowT + dt : 0;
    if (graceT > 0 || blocked) {
      stuckT = 0;
      return null;
    }
    stuckT = slow && !car.braking ? stuckT + dt : 0;
    if (stuckT < t.stuckTimeS) return null;
    return _decide(now, car.x, car.y);
  }

  RescuePlan _decide(double now, double x, double y) {
    // The series of attempts at one place: each within 5 s of the previous one (the shortest gap is
    // grace + stuck_time_s = 2.9 s, so "the last 5 s" counted from now could never reach a third),
    // all within 25 m of the first. Otherwise this is a first attempt again.
    if (rescues.isNotEmpty) {
      final last = rescues.last, first = rescues.first;
      final dx = first.x - x, dy = first.y - y;
      if (now - last.t > rescueWindowS || math.sqrt(dx * dx + dy * dy) > rescueNearM) rescues = [];
    }
    final n = rescues.length;
    rescues.add((t: now, x: x, y: y));
    stuckT = 0;
    slowT = 0;
    graceT = rescueGraceS;
    animT = rescueAnimS;
    if (n < 2) {
      final i = rewindIndex(trail, x, y, t.rewindM[n]);
      if (i >= 0) {
        final point = trail[i];
        // The car stands on that point now; the newer part of the trail is behind it.
        trail.removeRange(i + 1, trail.length);
        final kind = n == 0 ? StuckKind.auto1 : StuckKind.auto2;
        _log(now, kind, x, y);
        return RescuePlan(kind, point);
      }
    }
    trail = [];
    _log(now, StuckKind.road, x, y);
    return const RescuePlan(StuckKind.road);
  }

  /// The manual "Na silnici" (button or pause menu): counted as stuck, starts the animation; not
  /// part of the automatic series.
  void manual(double now, double x, double y) {
    trail = [];
    stuckT = 0;
    slowT = 0;
    graceT = rescueGraceS;
    animT = rescueAnimS;
    _log(now, StuckKind.button, x, y);
  }

  /// A respawn or teleport outside the flow rules: the trail and timers start over.
  void reset() {
    trail = [];
    stuckT = 0;
    slowT = 0;
    _trailAcc = 0;
  }

  /// Stuck events in the last 10 minutes of driving (debug overlay `flowStuck10`).
  int count10(double now) => events.where((e) => e.t > now - stuckWindowS).length;

  void _log(double t, StuckKind kind, double x, double y) {
    final e = StuckEvent(t, kind, x, y);
    events.add(e);
    while (events.isNotEmpty && events.first.t <= t - stuckWindowS) {
      events.removeAt(0);
    }
    onStuck?.call(e);
  }
}

/// The stuck.log line (specs/flow.md "Měření zaseknutí"), unix seconds.
String stuckLine(double unixS, String city, StuckEvent e) {
  num r(double v) {
    final q = (v * 10).round() / 10;
    return q == q.roundToDouble() ? q.round() : q;
  }

  return jsonEncode({'t': unixS.floor(), 'city': city, 'x': r(e.x), 'y': r(e.y), 'kind': e.kind.name});
}
