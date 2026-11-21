import 'dart:math' as math;
import 'dart:typed_data';

import 'package:rules_core/rules_core.dart';
import 'package:world_engine/core.dart';

/// Deterministic parts of traffic (specs/traffic.md): traffic lights, lanes, the next-edge choice.
/// Port of web/src/traffic/roadRules.ts; both clients' unit tests check the same values.

const int lightGreen = 0;
const int lightAmber = 1;
const int lightRed = 2;

/// Length of one full two-phase cycle in ms.
int cycleMs(TuningTraffic t) => 2 * (t.greenMs + t.amberMs + t.allRedMs);

/// Per-node phase offset in [0, cycle): a deterministic function of the node id.
int signalOffset(int node, int seed, int cycle) => Prng((node * 2654435761 + seed) & 0xFFFFFFFF).nextInt(cycle);

/// Light shown to approach group 0 or 1 at integer time [tMs].
int lightState(int offset, int group, int tMs, TuningTraffic t) {
  final cycle = cycleMs(t);
  var p = (tMs + offset) % cycle;
  if (group == 1) p = (p + cycle ~/ 2) % cycle;
  if (p < t.greenMs) return lightGreen;
  if (p < t.greenMs + t.amberMs) return lightAmber;
  return lightRed;
}

/// Signal clock: ms since start from the integer fixed-step counter.
int signalClockMs(int step, int stepHz) => step * 1000 ~/ stepHz;

/// True when a car may leave [node] along [e] (one-way rule of specs/route.md).
bool canLeave(RoadEdge e, int node) {
  if (e.from == e.to) return false;
  if (e.oneway == 0) return e.from == node || e.to == node;
  return e.oneway > 0 ? e.from == node : e.to == node;
}

int _layerAtNode(RoadEdge e, int node) => e.from == node ? e.layerFrom : e.layerTo;

// Same as JS Math.round for these values (never exactly .5 away from an integer dm).
int _dm(double m) => (m * 10 + 0.5).floor();

/// Integer direction (dm) from [node] along [e] to its first point that differs from the node.
(int, int) _dirFromNode(RoadGraph g, RoadEdge e, int node) {
  final nx = _dm(g.nodeXY[2 * node]), ny = _dm(g.nodeXY[2 * node + 1]);
  final n = e.pointCount;
  for (var k = 1; k < n; k++) {
    final i = e.from == node ? k : n - 1 - k;
    final dx = _dm(e.pts[2 * i]) - nx, dy = _dm(e.pts[2 * i + 1]) - ny;
    if (dx != 0 || dy != 0) return (dx, dy);
  }
  return (1, 0);
}

/// Distinct, non-loop kept edges at a node in ascending index order.
List<int> keptEdgesAt(RoadGraph g, int node) {
  final out = <int>[];
  for (final ei in g.nodeEdges[node]) {
    final e = g.edges[ei];
    if (!e.kept || e.from == e.to || out.contains(ei)) continue;
    out.add(ei);
  }
  return out..sort();
}

/// One way into a signalled node.
class Approach {
  Approach(this.signal, this.edge, this.node, this.group, this.stopM, this.x, this.y);
  final int signal;
  final int edge;

  /// Node the approach leads into.
  final int node;
  final int group;

  /// Distance of the stop line from the node (m).
  final double stopM;

  /// Indicator position (m).
  final double x;
  final double y;
}

class Signals {
  Signals(this.nodes, this.offsets, this.approaches, this.approachTo, this.approachFrom, this.extraTo, this.extraFrom);
  final List<int> nodes;
  final List<int> offsets;
  final List<Approach> approaches;

  /// Per edge: approach index when driving from → to (into `to`), else −1.
  final Int32List approachTo;

  /// Per edge: approach index when driving to → from (into `from`), else −1.
  final Int32List approachFrom;

  /// Distance from the end of the edge to the signal node (m): 0 on the approach edge itself,
  /// more on an unbranched chain leading to it.
  final Float32List extraTo;
  final Float32List extraFrom;
}

/// Carriageway half width (m), the same as the road markings.
double carriageHalf(RoadEdge e, Tuning tuning) => math.max(e.width - 2 * tuning.sidewalkWidthM, tuning.laneWidthM) / 2;

/// Finds the signalled nodes and their approaches (specs/traffic.md "Semafory").
Signals buildSignals(RoadGraph g, Tuning tuning, {required bool leftHand}) {
  final t = tuning.traffic;
  final cycle = cycleMs(t);
  final nodes = <int>[], offsets = <int>[], approaches = <Approach>[];
  final approachTo = Int32List(g.edges.length)..fillRange(0, g.edges.length, -1);
  final approachFrom = Int32List(g.edges.length)..fillRange(0, g.edges.length, -1);
  final extraTo = Float32List(g.edges.length), extraFrom = Float32List(g.edges.length);
  final side = leftHand ? -1.0 : 1.0;
  for (var n = 0; n < g.nodeEdges.length; n++) {
    final kept = keptEdgesAt(g, n);
    if (kept.length < t.signalMinEdges) continue;
    var main = 0;
    var ground = true;
    for (final ei in kept) {
      final e = g.edges[ei];
      if (t.signalClasses.contains(e.roadClass.value)) main++;
      if (_layerAtNode(e, n) != 0) ground = false;
    }
    if (main < t.signalMinMain || !ground) continue;
    final signal = nodes.length;
    nodes.add(n);
    offsets.add(signalOffset(n, t.signalSeed, cycle));
    final (rx, ry) = _dirFromNode(g, g.edges[kept[0]], n);
    final nx = g.nodeXY[2 * n], ny = g.nodeXY[2 * n + 1];
    for (final ei in kept) {
      final e = g.edges[ei];
      final other = e.from == n ? e.to : e.from;
      if (!canLeave(e, other)) continue;
      final (vx, vy) = _dirFromNode(g, e, n);
      final group = (rx * vy - ry * vx).abs() < (rx * vx + ry * vy).abs() ? 0 : 1;
      var stop = 0.0;
      for (final oi in kept) {
        if (oi != ei) stop = math.max(stop, g.edges[oi].width / 2);
      }
      stop += t.stopMarginM;
      final l = math.sqrt((vx * vx + vy * vy).toDouble());
      final ux = vx / l, uy = vy / l; // from the node outwards; travel direction is −u
      final off = (carriageHalf(e, tuning) + t.lightSideM) * side;
      approaches.add(Approach(signal, ei, n, group, stop, nx + ux * stop - uy * off, ny + uy * stop + ux * off));
      if (e.to == n) {
        approachTo[ei] = approaches.length - 1;
      } else {
        approachFrom[ei] = approaches.length - 1;
      }
    }
  }
  // Upstream chains through nodes with exactly two kept edges (specs/traffic.md "Řetězy").
  final isSignal = Uint8List(g.nodeEdges.length);
  for (final n in nodes) {
    isSignal[n] = 1;
  }
  for (var a = 0; a < approaches.length; a++) {
    final ap = approaches[a];
    var cur = g.edges[ap.edge];
    var node = cur.from == ap.node ? cur.to : cur.from;
    var extra = cur.length;
    while (extra - ap.stopM < t.lookAheadM && isSignal[node] == 0 && !g.border[node]) {
      final kept = keptEdgesAt(g, node);
      if (kept.length != 2) break;
      final f = g.edges[kept[0] == cur.index ? kept[1] : kept[0]];
      final other = f.from == node ? f.to : f.from;
      if (!canLeave(f, other)) break;
      if (f.to == node) {
        if (approachTo[f.index] >= 0) break;
        approachTo[f.index] = a;
        extraTo[f.index] = extra;
      } else {
        if (approachFrom[f.index] >= 0) break;
        approachFrom[f.index] = a;
        extraFrom[f.index] = extra;
      }
      extra += f.length;
      cur = f;
      node = other;
    }
  }
  return Signals(nodes, offsets, approaches, approachTo, approachFrom, extraTo, extraFrom);
}

/// Lanes per travel direction (specs/traffic.md "Pruhy").
int lanesPerDir(RoadEdge e, Tuning tuning) {
  final c = carriageHalf(e, tuning);
  final l = math.max(1, (2 * c / tuning.laneWidthM).round());
  return e.oneway == 0 ? math.max(1, l ~/ 2) : l;
}

/// Lateral offset of lane [lane] from the centre line, + = right of the travel direction.
double laneOffset(RoadEdge e, int lane, Tuning tuning, {required bool leftHand}) {
  final c = carriageHalf(e, tuning);
  final l = math.max(1, (2 * c / tuning.laneWidthM).round());
  final off = e.oneway == 0 ? (lane + 0.5) * c / math.max(1, l ~/ 2) : c - (lane + 0.5) * 2 * c / l;
  return leftHand ? -off : off;
}

/// The next edge after arriving at [node] along [from] (specs/traffic.md "Volba další hrany"):
/// an edge index, or −1 when the car has to disappear. [scratch] avoids allocations.
int chooseNext(RoadGraph g, int node, int from, Prng rng, [List<int>? scratch]) {
  if (g.border[node]) return -1;
  final cands = scratch ?? <int>[];
  cands.clear();
  final list = g.nodeEdges[node];
  for (var k = 0; k < list.length; k++) {
    final ei = list[k];
    if (ei == from || (k > 0 && list[k - 1] == ei)) continue;
    final e = g.edges[ei];
    if (e.kept && canLeave(e, node)) cands.add(ei);
  }
  if (cands.isEmpty) return canLeave(g.edges[from], node) ? from : -1;
  return cands[rng.nextInt(cands.length)];
}
