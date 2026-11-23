import 'dart:math' as math;
import 'dart:typed_data';

import 'package:rules_core/rules_core.dart';
import 'package:world_engine/core.dart';

/// Deterministic parts of trams (specs/trams.md "Deterministické funkce"): the next track edge,
/// articulated car poses along the travelled trail and the stop ahead.

final Float64List _probeA = Float64List(4);
final Float64List _probeB = Float64List(4);

/// The point [probeM] metres along edge [ei] away from its end at [node] (or its far end when the
/// edge is shorter), into [out].
void _probe(TrackGraph g, int ei, int node, double probeM, Float64List out) {
  final e = g.edges[ei];
  final d = math.min(probeM, e.length);
  e.sample(e.from == node ? d : e.length - d, out);
}

/// Cosine of the turn at [node] from arriving along edge [from] to leaving along edge [to]
/// (specs/trams.md v2 "Sjízdnost"): arrival = from the point [probeM] along [from] to the node,
/// departure = from the node to the point [probeM] along [to]. 1 when a direction is degenerate.
double turnCos(TrackGraph g, int node, int from, int to, double probeM) {
  final nx = g.nodeXY[2 * node], ny = g.nodeXY[2 * node + 1];
  _probe(g, from, node, probeM, _probeA);
  _probe(g, to, node, probeM, _probeB);
  final ax = nx - _probeA[0], ay = ny - _probeA[1];
  final bx = _probeB[0] - nx, by = _probeB[1] - ny;
  final la = math.sqrt(ax * ax + ay * ay), lb = math.sqrt(bx * bx + by * by);
  if (la <= 1e-6 || lb <= 1e-6) return 1;
  return (ax * bx + ay * by) / (la * lb);
}

/// Track edges a tram arriving at [node] along [from] can go on to, into [out] in ascending index
/// order: the node's edges without [from], duplicates and loops whose turn cosine is at least
/// [cosMin] (cos of `trams.max_switch_deg`). Empty at a border node.
List<int> feasibleNext(TrackGraph g, int node, int from, double cosMin, double probeM, List<int> out) {
  out.clear();
  if (g.border[node]) return out;
  final list = g.nodeEdges[node];
  for (var k = 0; k < list.length; k++) {
    final ei = list[k];
    if (ei == from || (k > 0 && list[k - 1] == ei)) continue;
    final e = g.edges[ei];
    if (e.from != e.to && turnCos(g, node, from, ei, probeM) >= cosMin) out.add(ei);
  }
  return out;
}

/// The next track edge after arriving at [node] along [from]: one of [feasibleNext], picked with
/// `rng.nextInt(count)`. No candidate = a terminus: returns [from] without drawing (the tram
/// changes ends); a border node (or a loop as the only way) = −1, the tram disappears.
int chooseNextTrack(TrackGraph g, int node, int from, Prng rng, double cosMin, double probeM, [List<int>? scratch]) {
  if (g.border[node]) return -1;
  final cands = feasibleNext(g, node, from, cosMin, probeM, scratch ?? <int>[]);
  if (cands.isEmpty) {
    final back = g.edges[from];
    return back.from != back.to ? from : -1;
  }
  return cands[rng.nextInt(cands.length)];
}

/// The straightest edge a tram could have come from into [node] before leaving along [to]
/// (seeding the path behind a new tram, specs/trams.md v2): the largest turn cosine of at least
/// [cosMin], the lower index on a tie; −1 at a border node or without one.
int straightestPrev(TrackGraph g, int node, int to, double cosMin, double probeM) {
  if (g.border[node]) return -1;
  final list = g.nodeEdges[node];
  var best = -1;
  var bestCos = double.negativeInfinity;
  for (var k = 0; k < list.length; k++) {
    final ei = list[k];
    if (ei == to || (k > 0 && list[k - 1] == ei)) continue;
    final e = g.edges[ei];
    if (e.from == e.to) continue;
    final c = turnCos(g, node, ei, to, probeM);
    if (c >= cosMin && c > bestCos) {
      best = ei;
      bestCos = c;
    }
  }
  return best;
}

/// The nearest stop on [edge] ahead in travel direction [dir] (+1 from → to, −1 to → from) that is
/// more than [commitM] beyond [s] (metres along the travel direction); −1 when there is none.
/// [skip] excludes one stop (the one just served).
int nextStopAhead(TrackGraph g, int edge, int dir, double s, double commitM, {int skip = -1}) {
  final list = g.stopsByEdge[edge];
  final len = g.edges[edge].length;
  if (dir > 0) {
    for (var i = 0; i < list.length; i++) {
      final st = list[i];
      if (st != skip && g.stops[st].sM - s > commitM) return st;
    }
  } else {
    for (var i = list.length - 1; i >= 0; i--) {
      final st = list[i];
      if (st != skip && len - g.stops[st].sM - s > commitM) return st;
    }
  }
  return -1;
}

/// Distance of stop [stop] along travel direction [dir] of its edge.
double stopTravelS(TrackGraph g, int stop, int dir) {
  final st = g.stops[stop];
  return dir > 0 ? st.sM : g.edges[st.edge].length - st.sM;
}

/// The path a tram has driven: its nose and the last `trams.trail_points` track points it passed,
/// newest first. Cars stand along it (specs/trams.md "Odstup článků").
class TramTrail {
  TramTrail(this.capacity, {required this.carM, required this.gapM})
    : _xy = Float64List(2 * capacity),
      _layer = Int8List(capacity);

  final int capacity;

  /// Car length and the gap between cars (m).
  final double carM;
  final double gapM;
  final Float64List _xy;
  final Int8List _layer;
  int _head = -1;
  int count = 0;

  double noseX = 0;
  double noseY = 0;

  /// Unit travel direction at the nose.
  double dirX = 1;
  double dirY = 0;
  int noseLayer = 0;

  /// Forgets the path; the nose stays where it is.
  void clear() {
    _head = -1;
    count = 0;
  }

  void setNose(double x, double y, double dx, double dy, int layer) {
    noseX = x;
    noseY = y;
    dirX = dx;
    dirY = dy;
    noseLayer = layer;
  }

  /// Adds a passed track point (newest); a repeat of the newest point is ignored.
  void push(double x, double y, int layer) {
    if (count > 0 && _xy[2 * _head] == x && _xy[2 * _head + 1] == y) return;
    _head = (_head + 1) % capacity;
    _xy[2 * _head] = x;
    _xy[2 * _head + 1] = y;
    _layer[_head] = layer;
    if (count < capacity) count++;
  }

  int _slot(int i) => (_head - i + capacity) % capacity;

  /// Stored point [i], 0 = newest.
  double xAt(int i) => _xy[2 * _slot(i)];
  double yAt(int i) => _xy[2 * _slot(i) + 1];
  int layerAt(int i) => _layer[_slot(i)];
}

/// Pose of one articulated car.
class TramCarPose {
  double x = 0;
  double y = 0;
  double heading = 0;
  int layer = 0;
}

final Float64List _front = Float64List(3);
final Float64List _rear = Float64List(3);

/// The point [dist] metres back from the nose along [trail], written to [out] as x, y, layer.
/// Past the oldest stored point the trail goes on straight.
void trailPointBack(TramTrail trail, double dist, Float64List out) {
  var px = trail.noseX, py = trail.noseY;
  var pl = trail.noseLayer;
  // Backward direction of the last walked piece (for extrapolation).
  var bx = -trail.dirX, by = -trail.dirY;
  var left = dist;
  for (var i = 0; i < trail.count; i++) {
    final qx = trail.xAt(i), qy = trail.yAt(i);
    final dx = qx - px, dy = qy - py;
    final l = math.sqrt(dx * dx + dy * dy);
    if (l <= 0) continue;
    if (left <= l) {
      final f = left / l;
      out[0] = px + dx * f;
      out[1] = py + dy * f;
      out[2] = (f < 0.5 ? pl : trail.layerAt(i)).toDouble();
      return;
    }
    left -= l;
    bx = dx / l;
    by = dy / l;
    px = qx;
    py = qy;
    pl = trail.layerAt(i);
  }
  out[0] = px + bx * left;
  out[1] = py + by * left;
  out[2] = pl.toDouble();
}

/// Pose of car [k] (0 = front): its front joint stands `k · (car + gap)` back from the nose along
/// the trail, its rear joint one car length further; the centre is between them and the heading
/// points from the rear joint to the front one.
TramCarPose articulate(TramTrail trail, int k, [TramCarPose? out]) {
  final p = out ?? TramCarPose();
  final d = k * (trail.carM + trail.gapM);
  trailPointBack(trail, d, _front);
  trailPointBack(trail, d + trail.carM, _rear);
  final dx = _front[0] - _rear[0], dy = _front[1] - _rear[1];
  p
    ..x = (_front[0] + _rear[0]) / 2
    ..y = (_front[1] + _rear[1]) / 2
    ..heading = dx == 0 && dy == 0 ? math.atan2(trail.dirY, trail.dirX) : math.atan2(dy, dx)
    ..layer = _front[2].round();
  return p;
}
