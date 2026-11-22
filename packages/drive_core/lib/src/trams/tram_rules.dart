import 'dart:math' as math;
import 'dart:typed_data';

import 'package:rules_core/rules_core.dart';
import 'package:world_engine/core.dart';

/// Deterministic parts of trams (specs/trams.md "Deterministické funkce"): the next track edge,
/// articulated car poses along the travelled trail and the stop ahead.

/// The next track edge after arriving at [node] along [from]: candidates are the node's edges in
/// ascending index order without [from], picked with `rng.nextInt(count)`. No candidate = turn back
/// along [from] (a terminus); a border node = −1, the tram disappears. [scratch] avoids allocations.
int chooseNextTrack(TrackGraph g, int node, int from, Prng rng, [List<int>? scratch]) {
  if (g.border[node]) return -1;
  final cands = scratch ?? <int>[];
  cands.clear();
  final list = g.nodeEdges[node];
  for (var k = 0; k < list.length; k++) {
    final ei = list[k];
    if (ei == from || (k > 0 && list[k - 1] == ei)) continue;
    cands.add(ei);
  }
  if (cands.isEmpty) return from;
  return cands[rng.nextInt(cands.length)];
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
