import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drive_core/drive_core.dart' show RouteGraph, GpsRoute, findRoute, polylineDm;
import 'package:world_engine/core.dart';

/// GPS navigation glue (specs/phone.md "Navigace"); mirrors web/src/phone/nav.ts. Metres.
class NavTarget {
  const NavTarget({required this.id, required this.name, required this.edge, required this.parkX, required this.parkY});

  factory NavTarget.fromSpot(Spot s) => NavTarget(id: s.id, name: s.name, edge: s.edge, parkX: s.parkX, parkY: s.parkY);

  final String id, name;
  final int edge;

  /// Parking point, dm (as in spots.pb).
  final int parkX, parkY;
}

class NavEnd {
  const NavEnd(this.node, this.hit);
  final int node;
  final EdgeHit hit;

  NavEnd withNode(int n) => NavEnd(n, hit);
}

/// Start: the car's edge (or the nearest kept one) and its end in the driving direction.
NavEnd? navStart(RoadGraph g, EdgeHit? hit, double x, double y, double heading, double searchM) {
  final h = hit != null && hit.edge.kept ? hit : g.nearest(x, y, maxDist: searchM, where: (e) => e.kept);
  if (h == null) return null;
  final e = h.edge;
  final int node;
  if (e.oneway == 1) {
    node = e.to;
  } else if (e.oneway == -1) {
    node = e.from;
  } else {
    node = math.cos(heading) * h.dirX + math.sin(heading) * h.dirY >= 0 ? e.to : e.from;
  }
  return NavEnd(node, h);
}

/// Projection of a point onto the closest segment of one edge.
EdgeHit projectOnEdge(RoadGraph g, int edge, double x, double y) {
  final e = g.edges[edge];
  var best = g.project(e, 0, x, y);
  for (var s = 1; s < e.pointCount - 1; s++) {
    final h = g.project(e, s, x, y);
    if (h.dist < best.dist) best = h;
  }
  return best;
}

/// Goal: the entry end of the spot's edge (one-way) or the end nearer the parking point.
NavEnd navGoal(RoadGraph g, NavTarget t) {
  final hit = projectOnEdge(g, t.edge, t.parkX / 10, t.parkY / 10);
  final e = hit.edge;
  final node = e.oneway == 1
      ? e.from
      : e.oneway == -1
      ? e.to
      : hit.t < 0.5
      ? e.from
      : e.to;
  return NavEnd(node, hit);
}

void _pushPt(List<double> out, double x, double y) {
  final n = out.length;
  if (n >= 2 && out[n - 2] == x && out[n - 1] == y) return;
  out
    ..add(x)
    ..add(y);
}

void _pushRange(List<double> out, Float32List pts, int a, int b, bool fwd) {
  if (fwd) {
    for (var i = a; i <= b; i++) {
      _pushPt(out, pts[2 * i], pts[2 * i + 1]);
    }
  } else {
    for (var i = a; i >= b; i--) {
      _pushPt(out, pts[2 * i], pts[2 * i + 1]);
    }
  }
}

/// The route polyline: car → start node → route edges → goal node → parking point.
List<double> navPath(RoadGraph g, NavEnd start, GpsRoute route, NavEnd goal, double parkX, double parkY) {
  final out = <double>[];
  final sh = start.hit, gh = goal.hit, se = sh.edge;
  _pushPt(out, sh.x, sh.y);
  final forward = start.node == se.to;
  if (se.index == gh.edge.index && (forward ? gh.t >= sh.t : gh.t <= sh.t)) {
    if (forward) {
      _pushRange(out, se.pts, sh.segment + 1, gh.segment, true);
    } else {
      _pushRange(out, se.pts, sh.segment, gh.segment + 1, false);
    }
  } else {
    if (forward) {
      _pushRange(out, se.pts, sh.segment + 1, se.pointCount - 1, true);
    } else {
      _pushRange(out, se.pts, sh.segment, 0, false);
    }
    for (var i = 0; i < route.edges.length; i++) {
      final e = g.edges[route.edges[i]];
      if (e.from == route.nodes[i]) {
        _pushRange(out, e.pts, 0, e.pointCount - 1, true);
      } else {
        _pushRange(out, e.pts, e.pointCount - 1, 0, false);
      }
    }
    final ge = gh.edge;
    if (goal.node == ge.from) {
      _pushRange(out, ge.pts, 0, gh.segment, true);
    } else {
      _pushRange(out, ge.pts, ge.pointCount - 1, gh.segment + 1, false);
    }
  }
  _pushPt(out, gh.x, gh.y);
  _pushPt(out, parkX, parkY);
  return out;
}

/// Edge lengths in dm (sum of floor segment lengths, specs/route.md).
Int32List edgeLengthsDm(Graph pb) => Int32List.fromList([for (final e in pb.edges) polylineDm(e.points)]);

/// Integer distance for the feed (specs/feed.md "Kandidáti").
int feedDistDm(
  RouteGraph rg,
  Int32List lensDm,
  NavEnd? start,
  NavEnd goal,
  double carX,
  double carY,
  NavTarget t,
  int straightPct,
) {
  final r = start == null ? null : findRoute(rg, start.node, goal.node);
  if (r != null && r.cost >= 0) return r.edges.fold(0, (s, e) => s + lensDm[e]);
  final dx = t.parkX - (carX * 10 + 0.5).floor(), dy = t.parkY - (carY * 10 + 0.5).floor();
  return math.sqrt((dx * dx + dy * dy).toDouble()).floor() * straightPct ~/ 100;
}

enum NavEvent { arrived, rerouted }

/// Follows the car along the active route: progress, reroute, arrival.
class Navigator {
  Navigator(this.g, this.rg, this.route, this.nav);

  final RoadGraph g;
  final RouteGraph rg;
  final TuningRoute route;
  final TuningNav nav;

  NavTarget? target;

  /// Interleaved x, y (m); empty when no road route was found.
  List<double> path = const [];
  List<double> _cum = const [0];
  int _seg = 0;
  double _offS = 0;
  double px = 0, py = 0, remaining = 0, off = 0;

  bool get active => target != null;
  bool get hasRoute => path.length >= 4;
  double get parkX => (target?.parkX ?? 0) / 10;
  double get parkY => (target?.parkY ?? 0) / 10;

  /// Starts navigation; false when no road route exists (the arrow still guides).
  bool start(NavTarget t, double x, double y, double heading, EdgeHit? hit) {
    target = t;
    _plan(x, y, heading, hit);
    return hasRoute;
  }

  void cancel() {
    target = null;
    path = const [];
    _cum = const [0];
  }

  void _plan(double x, double y, double heading, EdgeHit? hit) {
    final t = target!;
    final s = navStart(g, hit, x, y, heading, nav.searchM);
    final goal = navGoal(g, t);
    final r = s == null ? null : findRoute(rg, s.node, goal.node);
    path = s != null && r != null && r.cost >= 0 ? navPath(g, s, r, goal, t.parkX / 10, t.parkY / 10) : const [];
    final cum = <double>[0];
    for (var i = 2; i < path.length; i += 2) {
      cum.add(cum.last + _hypot(path[i] - path[i - 2], path[i + 1] - path[i - 1]));
    }
    _cum = cum;
    _seg = 0;
    _offS = 0;
    _track(x, y);
  }

  static double _hypot(double a, double b) => math.sqrt(a * a + b * b);

  void _track(double x, double y) {
    final p = path;
    if (p.length < 4) {
      px = x;
      py = y;
      off = 0;
      remaining = _hypot(parkX - x, parkY - y);
      return;
    }
    var best = double.infinity, bi = _seg;
    var bt = 0.0;
    for (var i = math.max(0, _seg - 2); 2 * i + 3 < p.length; i++) {
      final ax = p[2 * i], ay = p[2 * i + 1], dx = p[2 * i + 2] - ax, dy = p[2 * i + 3] - ay;
      final l2 = dx * dx + dy * dy;
      final t = l2 == 0 ? 0.0 : (((x - ax) * dx + (y - ay) * dy) / l2).clamp(0.0, 1.0);
      final d = _hypot(ax + dx * t - x, ay + dy * t - y);
      if (d < best) {
        best = d;
        bi = i;
        bt = t;
      }
    }
    _seg = bi;
    final ax = p[2 * bi], ay = p[2 * bi + 1];
    px = ax + (p[2 * bi + 2] - ax) * bt;
    py = ay + (p[2 * bi + 3] - ay) * bt;
    off = best;
    remaining = _cum.last - (_cum[bi] + (_cum[bi + 1] - _cum[bi]) * bt);
  }

  /// Call every frame with the real (unscaled) dt.
  NavEvent? update(double x, double y, double heading, EdgeHit? hit, double dt) {
    if (target == null) return null;
    if (_hypot(parkX - x, parkY - y) <= route.arriveM) return NavEvent.arrived;
    _track(x, y);
    if (hasRoute && off > route.rerouteM) {
      _offS += dt;
    } else {
      _offS = 0;
    }
    if (_offS > route.rerouteS) {
      _plan(x, y, heading, hit);
      return NavEvent.rerouted;
    }
    return null;
  }

  /// The polyline still ahead of the car (for drawing).
  List<double> ahead() => hasRoute ? [px, py, ...path.sublist(2 * _seg + 2)] : const [];
}

/// HUD distance (specs/phone.md "Formát vzdálenosti"): the i18n key and its arguments.
({MessageKey key, Map<String, Object> args}) formatDistance(double m, bool imperial, TuningNav nav) {
  if (!imperial) {
    if (m < nav.kmFromM) return (key: MessageKey.distanceM, args: {'m': (m / nav.roundM).round() * nav.roundM});
    return (key: MessageKey.distanceKm, args: {'km': (m / 1000).toStringAsFixed(1)});
  }
  final mi = m / 1609.344;
  if (mi < nav.miFrom) {
    return (key: MessageKey.distanceFt, args: {'ft': (m * 3.28084 / nav.roundFt).round() * nav.roundFt});
  }
  return (key: MessageKey.distanceMi, args: {'mi': mi.toStringAsFixed(1)});
}

/// Drive minutes on a feed card.
int driveMinutes(int driveS) => math.max(1, (driveS + 30) ~/ 60);

/// Edge-of-screen arrow towards an off-screen target (see the web twin); null when visible.
({double x, double y, double angle})? edgeArrow(
  double tx,
  double ty,
  double w,
  double h,
  double margin,
  double ax,
  double ay,
) {
  final x0 = margin, x1 = w - margin, y0 = margin, y1 = h - margin;
  if (tx >= x0 && tx <= x1 && ty >= y0 && ty <= y1) return null;
  final dx = tx - ax, dy = ty - ay;
  var s = double.infinity;
  if (dx > 0) s = math.min(s, (x1 - ax) / dx);
  if (dx < 0) s = math.min(s, (x0 - ax) / dx);
  if (dy > 0) s = math.min(s, (y1 - ay) / dy);
  if (dy < 0) s = math.min(s, (y0 - ay) / dy);
  if (!s.isFinite) return null;
  return (x: ax + dx * s, y: ay + dy * s, angle: math.atan2(dy, dx));
}

/// Fits the bounds of a ring into w × h with padding; screen = (x·s + ox, −y·s + oy), north up.
({double s, double ox, double oy}) mapFit(List<double> ring, double w, double h, double pad) {
  var x0 = double.infinity, y0 = double.infinity, x1 = -double.infinity, y1 = -double.infinity;
  for (var i = 0; i + 1 < ring.length; i += 2) {
    x0 = math.min(x0, ring[i]);
    x1 = math.max(x1, ring[i]);
    y0 = math.min(y0, ring[i + 1]);
    y1 = math.max(y1, ring[i + 1]);
  }
  if (!x0.isFinite) return (s: 1, ox: w / 2, oy: h / 2);
  final s = math.min((w - 2 * pad) / math.max(1, x1 - x0), (h - 2 * pad) / math.max(1, y1 - y0));
  return (s: s, ox: w / 2 - (x0 + x1) / 2 * s, oy: h / 2 + (y0 + y1) / 2 * s);
}
