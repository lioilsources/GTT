import 'dart:math' as math;
import 'dart:typed_data';

import 'package:shared_gen/citypack_pb.dart' as pb;

/// One tram track edge in world metres (specs/trams.md "Data"). Always two-way.
class TrackEdge {
  TrackEdge({
    required this.index,
    required this.from,
    required this.to,
    required this.pts,
    required this.layerFrom,
    required this.layerTo,
    required this.bridge,
    required this.tunnel,
  }) : cum = Float64List(pts.length ~/ 2) {
    for (var s = 1; s < cum.length; s++) {
      final dx = pts[2 * s] - pts[2 * s - 2], dy = pts[2 * s + 1] - pts[2 * s - 1];
      cum[s] = cum[s - 1] + math.sqrt(dx * dx + dy * dy);
    }
    length = cum.isEmpty ? 0 : cum[cum.length - 1];
  }

  final int index;
  final int from;
  final int to;

  /// Interleaved x, y in metres, both end nodes included.
  final Float32List pts;
  final int layerFrom;
  final int layerTo;
  final bool bridge;
  final bool tunnel;

  /// Distance of every polyline point from the `from` end.
  final Float64List cum;
  late final double length;

  int get pointCount => pts.length ~/ 2;

  /// The layer at parameter [t] (0..1 along the edge); a ramp switches halfway (like roads).
  int layerAt(double t) => layerFrom == layerTo ? layerFrom : (t < 0.5 ? layerFrom : layerTo);

  /// The layer the edge is drawn in (−1 tunnel, 0 ground, +1 bridge), as RoadEdge.drawLayer.
  int get drawLayer => tunnel
      ? -1
      : math.max(layerFrom, layerTo) > 0
      ? 1
      : math.min(layerFrom, layerTo);

  /// Segment index holding distance [d] from the `from` end.
  int segmentAt(double d) {
    var lo = 0, hi = pointCount - 2;
    if (hi <= 0) return 0;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (cum[mid] <= d) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Point and unit direction (from → to) at distance [d] from the `from` end, written to
  /// [out] as x, y, dirX, dirY.
  void sample(double d, Float64List out) {
    final seg = segmentAt(d);
    final i = 2 * seg;
    final ax = pts[i], ay = pts[i + 1], bx = pts[i + 2], by = pts[i + 3];
    final len = cum[seg + 1] - cum[seg];
    final f = len > 0 ? ((d - cum[seg]) / len).clamp(0.0, 1.0) : 0.0;
    out[0] = ax + (bx - ax) * f;
    out[1] = ay + (by - ay) * f;
    out[2] = len > 0 ? (bx - ax) / len : 1.0;
    out[3] = len > 0 ? (by - ay) / len : 0.0;
  }
}

/// A generated tram stop: [sM] metres from the `from` end of [edge], with its point and the
/// edge direction there.
class TrackStop {
  TrackStop(this.index, this.edge, this.sM, this.x, this.y, this.dirX, this.dirY);
  final int index;
  final int edge;
  final double sM;
  final double x;
  final double y;
  final double dirX;
  final double dirY;
}

/// Nearest point on a track edge.
class TrackHit {
  TrackHit(this.edge, this.x, this.y, this.dist, this.d);
  final TrackEdge edge;
  final double x;
  final double y;
  final double dist;

  /// Distance from the `from` end.
  final double d;
}

/// The tram track graph of `trams.pb` (specs/trams.md). Empty for a city without trams and for
/// an old pack without the file.
class TrackGraph {
  TrackGraph._(this.nodeXY, this.border, this.edges, this.nodeEdges, this.stops, this.stopsByEdge);

  factory TrackGraph.empty() => TrackGraph._(Float32List(0), const [], const [], const [], const [], const []);

  factory TrackGraph.fromPb(pb.TramGraph g) {
    final xy = Float32List(g.nodes.length * 2);
    final border = List<bool>.filled(g.nodes.length, false);
    for (var i = 0; i < g.nodes.length; i++) {
      xy[2 * i] = g.nodes[i].x / 10;
      xy[2 * i + 1] = g.nodes[i].y / 10;
      border[i] = g.nodes[i].border;
    }
    final edges = <TrackEdge>[];
    final nodeEdges = List.generate(g.nodes.length, (_) => <int>[]);
    for (var i = 0; i < g.edges.length; i++) {
      final e = g.edges[i];
      final pts = Float32List(e.points.length);
      for (var j = 0; j < pts.length; j++) {
        pts[j] = e.points[j] / 10;
      }
      edges.add(
        TrackEdge(
          index: i,
          from: e.from,
          to: e.to,
          pts: pts,
          layerFrom: e.layerFrom,
          layerTo: e.layerTo,
          bridge: e.bridge,
          tunnel: e.tunnel,
        ),
      );
      nodeEdges[e.from].add(i);
      nodeEdges[e.to].add(i);
    }
    final stops = <TrackStop>[];
    final byEdge = List.generate(edges.length, (_) => <int>[]);
    final tmp = Float64List(4);
    for (final s in g.stops) {
      if (s.edge >= edges.length) continue;
      final e = edges[s.edge];
      final d = s.sM.clamp(0.0, e.length);
      e.sample(d, tmp);
      byEdge[s.edge].add(stops.length);
      stops.add(TrackStop(stops.length, s.edge, d, tmp[0], tmp[1], tmp[2], tmp[3]));
    }
    for (final l in byEdge) {
      l.sort((a, b) => stops[a].sM.compareTo(stops[b].sM));
    }
    return TrackGraph._(xy, border, edges, nodeEdges, stops, byEdge);
  }

  final Float32List nodeXY;
  final List<bool> border;
  final List<TrackEdge> edges;

  /// Edges at each node in ascending index order (a loop edge appears twice).
  final List<List<int>> nodeEdges;
  final List<TrackStop> stops;

  /// Stop indices per edge, ascending by `sM`.
  final List<List<int>> stopsByEdge;

  bool get isEmpty => edges.isEmpty;

  /// Nearest track point to (x, y) over edges accepted by [where]; null when there is none.
  TrackHit? nearest(double x, double y, {bool Function(TrackEdge e, double d)? where}) {
    TrackHit? best;
    for (final e in edges) {
      for (var s = 0; s + 1 < e.pointCount; s++) {
        final ax = e.pts[2 * s], ay = e.pts[2 * s + 1], bx = e.pts[2 * s + 2], by = e.pts[2 * s + 3];
        final dx = bx - ax, dy = by - ay;
        final l2 = dx * dx + dy * dy;
        final t = l2 == 0 ? 0.0 : (((x - ax) * dx + (y - ay) * dy) / l2).clamp(0.0, 1.0);
        final px = ax + dx * t, py = ay + dy * t;
        final dist = math.sqrt((px - x) * (px - x) + (py - y) * (py - y));
        if (best != null && dist >= best.dist) continue;
        final d = e.cum[s] + (e.cum[s + 1] - e.cum[s]) * t;
        if (where != null && !where(e, d)) continue;
        best = TrackHit(e, px, py, dist, d);
      }
    }
    return best;
  }
}
