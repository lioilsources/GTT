import 'dart:math' as math;
import 'dart:typed_data';

import 'package:world_engine/core.dart';

import 'controls.dart';
import 'drive_world.dart';

/// A route polyline in world metres with cumulative distances (specs/bench.md).
class RoutePath {
  RoutePath(this.pts, this.legs) : cum = Float64List(pts.length ~/ 2) {
    for (var i = 1; i < count; i++) {
      cum[i] = cum[i - 1] + _hypot(pts[2 * i] - pts[2 * i - 2], pts[2 * i + 1] - pts[2 * i - 1]);
    }
  }

  /// Interleaved x, y.
  final Float64List pts;
  final int legs;
  final Float64List cum;

  int get count => pts.length ~/ 2;
  double get length => cum.isEmpty ? 0 : cum.last;

  /// Segment index containing distance [s].
  int segmentAt(double s) {
    var lo = 0, hi = count - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (cum[mid] <= s) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Point and direction at distance [s] (clamped to the route).
  ({double x, double y, double dir}) at(double s) {
    final c = s.clamp(0.0, length);
    final i = math.min(segmentAt(c), count - 2);
    final ax = pts[2 * i], ay = pts[2 * i + 1], bx = pts[2 * i + 2], by = pts[2 * i + 3];
    final l = cum[i + 1] - cum[i];
    final t = l > 0 ? (c - cum[i]) / l : 0.0;
    return (x: ax + (bx - ax) * t, y: ay + (by - ay) * t, dir: math.atan2(by - ay, bx - ax));
  }

  /// Distance along the route of the closest point to (x, y), searched within [s0, s1].
  double project(double x, double y, double s0, double s1) {
    final i0 = segmentAt(math.max(0, s0)), i1 = math.min(segmentAt(math.min(s1, length)), count - 2);
    var best = double.infinity, bestS = s0;
    for (var i = i0; i <= i1; i++) {
      final ax = pts[2 * i], ay = pts[2 * i + 1], bx = pts[2 * i + 2], by = pts[2 * i + 3];
      final dx = bx - ax, dy = by - ay;
      final l2 = dx * dx + dy * dy;
      final t = l2 == 0 ? 0.0 : (((x - ax) * dx + (y - ay) * dy) / l2).clamp(0.0, 1.0);
      final d = _hypot(ax + dx * t - x, ay + dy * t - y);
      if (d < best) {
        best = d;
        bestS = cum[i] + math.sqrt(l2) * t;
      }
    }
    return bestS;
  }

  /// Largest absolute change of direction between [s0] and [s1].
  double maxTurn(double s0, double s1) {
    final i0 = segmentAt(math.max(0, s0)), i1 = math.min(segmentAt(math.min(s1, length)), count - 2);
    double dir(int i) => math.atan2(pts[2 * i + 3] - pts[2 * i + 1], pts[2 * i + 2] - pts[2 * i]);
    final d0 = dir(i0);
    var max = 0.0;
    for (var i = i0 + 1; i <= i1; i++) {
      var d = dir(i) - d0;
      while (d > math.pi) {
        d -= 2 * math.pi;
      }
      while (d < -math.pi) {
        d += 2 * math.pi;
      }
      max = math.max(max, d.abs());
    }
    return max;
  }
}

double _hypot(double x, double y) => math.sqrt(x * x + y * y);

/// Node where an edge named `a` and one named `b` meet; the smallest index wins.
int crossingNode(RoadGraph g, Crossing c) {
  for (var n = 0; n < g.nodeEdges.length; n++) {
    var hasA = false, hasB = false;
    for (final ei in g.nodeEdges[n]) {
      final name = g.edges[ei].name;
      if (name == c.a) hasA = true;
      if (name == c.b) hasB = true;
    }
    if (hasA && hasB) return n;
  }
  throw StateError('bench route: no crossing of ${c.a} and ${c.b}');
}

/// Shortest path (edge length) over edges named in [via]; ties go to the smaller node index.
List<int> _leg(RoadGraph g, int from, int to, Set<String> via) {
  final n = g.nodeEdges.length;
  final dist = Float64List(n)..fillRange(0, n, double.infinity);
  final prevEdge = Int32List(n)..fillRange(0, n, -1);
  final done = Uint8List(n);
  dist[from] = 0;
  while (true) {
    var u = -1;
    for (var i = 0; i < n; i++) {
      if (done[i] == 0 && dist[i] < double.infinity && (u < 0 || dist[i] < dist[u])) u = i;
    }
    if (u < 0) throw StateError('bench route: no path over ${via.join(', ')}');
    if (u == to) break;
    done[u] = 1;
    for (final ei in g.nodeEdges[u]) {
      final e = g.edges[ei];
      if (!via.contains(e.name)) continue;
      final v = e.from == u ? e.to : e.from;
      final d = dist[u] + e.length;
      if (d < dist[v]) {
        dist[v] = d;
        prevEdge[v] = ei;
      }
    }
  }
  final edges = <int>[];
  for (var v = to; v != from;) {
    final ei = prevEdge[v];
    edges.add(ei);
    final e = g.edges[ei];
    v = e.from == v ? e.to : e.from;
  }
  return edges.reversed.toList();
}

/// Builds the route polyline of specs/bench.md.
RoutePath resolveRoute(RoadGraph g, BenchRoute r) {
  var node = crossingNode(g, r.start);
  final pts = <double>[g.nodeXY[2 * node], g.nodeXY[2 * node + 1]];
  for (final l in r.legs) {
    final to = crossingNode(g, l.to);
    for (final ei in _leg(g, node, to, l.via.toSet())) {
      final e = g.edges[ei];
      final forward = e.from == node;
      final k = e.pointCount;
      for (var j = 1; j < k; j++) {
        final i = forward ? j : k - 1 - j;
        pts.addAll([e.pts[2 * i], e.pts[2 * i + 1]]);
      }
      node = forward ? e.to : e.from;
    }
  }
  return RoutePath(Float64List.fromList(pts), r.legs.length);
}

/// Drives a route without a player (specs/bench.md). Pure logic, runs every fixed physics step.
class Autopilot {
  Autopilot(this.route, this.tuning);
  final RoutePath route;
  final Tuning tuning;
  double s = 0;
  int respawns = 0;
  bool finished = false;
  double _slowFor = 0;

  /// Puts the car at the route start, facing along it.
  void start(DriveWorld drive) {
    final p = route.at(0);
    drive.spawn(p.x, p.y, p.dir);
    s = 0;
  }

  void step(DriveWorld drive, ControlInput input, double dt) {
    final b = tuning.bench;
    final car = drive.car;
    s = route.project(car.x, car.y, s - b.searchBackM, s + b.searchAheadM);
    if (s >= route.length - b.arriveM) {
      finished = true;
      input
        ..reset()
        ..brake = 1;
      return;
    }
    final v = car.speed;
    final target = route.at(s + b.lookaheadM + b.lookaheadPerMps * v);
    var e = math.atan2(target.y - car.y, target.x - car.x) - car.heading;
    while (e > math.pi) {
      e -= 2 * math.pi;
    }
    while (e < -math.pi) {
      e += 2 * math.pi;
    }
    input
      ..reset()
      ..steer = (-b.steerGain * e).clamp(-1.0, 1.0);
    final want = route.maxTurn(s, s + b.cornerLookaheadM) > b.cornerTurnRad ? b.cornerSpeedMps : tuning.speedMps.cruise;
    input.brake = ((v - want) * b.brakePerMps).clamp(0.0, 1.0);

    _slowFor = v < b.stuckMps ? _slowFor + dt : 0;
    if (_slowFor >= b.stuckS) {
      final p = route.at(s + b.respawnAheadM);
      drive.spawn(p.x, p.y, p.dir);
      s += b.respawnAheadM;
      _slowFor = 0;
      respawns++;
    }
  }
}

/// Frame statistics of specs/bench.md (frame times in ms).
({double fpsAvg, double p50, double p99, double fps1Low}) frameStats(List<double> ms) {
  if (ms.isEmpty) return (fpsAvg: 0, p50: 0, p99: 0, fps1Low: 0);
  final sorted = [...ms]..sort();
  final total = ms.fold(0.0, (a, b) => a + b);
  double pick(double q) => sorted[math.min(sorted.length - 1, (q * sorted.length).floor())];
  final p99 = pick(0.99);
  return (fpsAvg: ms.length * 1000 / total, p50: pick(0.5), p99: p99, fps1Low: 1000 / p99);
}
