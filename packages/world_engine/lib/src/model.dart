import 'dart:math' as math;
import 'dart:typed_data';

import 'citypack.dart';
import 'pb/citypack.pb.dart' as pb;

/// A drivable road edge in world metres.
class RoadEdge {
  RoadEdge({
    required this.index,
    required this.from,
    required this.to,
    required this.pts,
    required this.roadClass,
    required this.name,
    required this.lanes,
    required this.oneway,
    required this.layerFrom,
    required this.layerTo,
    required this.bridge,
    required this.tunnel,
    required this.kept,
    required this.width,
  }) {
    var l = 0.0;
    for (var i = 2; i < pts.length; i += 2) {
      l += _dist(pts[i - 2], pts[i - 1], pts[i], pts[i + 1]);
    }
    length = l;
  }

  final int index;
  final int from;
  final int to;

  /// Interleaved x, y in metres, both end nodes included.
  final Float32List pts;
  final pb.RoadClass roadClass;
  final String name;
  final int lanes;
  final int oneway;
  final int layerFrom;
  final int layerTo;
  final bool bridge;
  final bool tunnel;

  /// false = alley: drivable, no traffic, no GPS.
  final bool kept;

  /// Full corridor width incl. sidewalks.
  final double width;
  late final double length;

  int get pointCount => pts.length ~/ 2;
  bool get isGround => !tunnel && layerFrom == 0 && layerTo == 0;
  bool get isRamp => layerFrom != layerTo;

  /// The layer at parameter [t] (0..1 along the edge); a ramp switches halfway.
  int layerAt(double t) => layerFrom == layerTo ? layerFrom : (t < 0.5 ? layerFrom : layerTo);

  /// The highest layer the edge touches; used to pick its draw pass.
  int get drawLayer => tunnel ? -1 : math.max(layerFrom, layerTo) > 0 ? 1 : math.min(layerFrom, layerTo);
}

/// Result of a nearest-edge query.
class EdgeHit {
  EdgeHit(this.edge, this.segment, this.x, this.y, this.dist, this.t, this.dirX, this.dirY);
  final RoadEdge edge;
  final int segment;
  final double x;
  final double y;
  final double dist;

  /// Parameter along the whole edge, 0..1.
  final double t;

  /// Unit direction of the segment, from → to.
  final double dirX;
  final double dirY;
}

double _dist(double ax, double ay, double bx, double by) {
  final dx = bx - ax, dy = by - ay;
  return math.sqrt(dx * dx + dy * dy);
}

class RoadGraph {
  RoadGraph._(this.nodeXY, this.border, this.edges, this.nodeEdges);

  factory RoadGraph.fromPb(pb.Graph g) {
    final xy = Float32List(g.nodes.length * 2);
    final border = List<bool>.filled(g.nodes.length, false);
    for (var i = 0; i < g.nodes.length; i++) {
      xy[2 * i] = g.nodes[i].x / 10;
      xy[2 * i + 1] = g.nodes[i].y / 10;
      border[i] = g.nodes[i].border;
    }
    final edges = <RoadEdge>[];
    final nodeEdges = List.generate(g.nodes.length, (_) => <int>[]);
    for (var i = 0; i < g.edges.length; i++) {
      final e = g.edges[i];
      final pts = Float32List(e.points.length);
      for (var j = 0; j < pts.length; j++) {
        pts[j] = e.points[j] / 10;
      }
      edges.add(RoadEdge(
        index: i,
        from: e.from,
        to: e.to,
        pts: pts,
        roadClass: e.class_4,
        name: g.names[e.name],
        lanes: e.lanes,
        oneway: e.oneway,
        layerFrom: e.layerFrom,
        layerTo: e.layerTo,
        bridge: e.bridge,
        tunnel: e.tunnel,
        kept: e.kept,
        width: e.widthM,
      ));
      nodeEdges[e.from].add(i);
      nodeEdges[e.to].add(i);
    }
    return RoadGraph._(xy, border, edges, nodeEdges).._index();
  }

  final Float32List nodeXY;
  final List<bool> border;
  final List<RoadEdge> edges;
  final List<List<int>> nodeEdges;

  static const double cell = 32;
  final Map<int, List<int>> _grid = {};
  late final List<Float64List> _cumLen;

  static int _key(int cx, int cy) => (cx + 32768) << 16 | (cy + 32768);

  void _index() {
    _cumLen = [];
    for (final e in edges) {
      final cum = Float64List(e.pointCount);
      for (var s = 1; s < e.pointCount; s++) {
        final ax = e.pts[2 * s - 2], ay = e.pts[2 * s - 1], bx = e.pts[2 * s], by = e.pts[2 * s + 1];
        cum[s] = cum[s - 1] + _dist(ax, ay, bx, by);
        final r = e.width / 2;
        final x0 = ((math.min(ax, bx) - r) / cell).floor(), x1 = ((math.max(ax, bx) + r) / cell).floor();
        final y0 = ((math.min(ay, by) - r) / cell).floor(), y1 = ((math.max(ay, by) + r) / cell).floor();
        for (var cx = x0; cx <= x1; cx++) {
          for (var cy = y0; cy <= y1; cy++) {
            (_grid[_key(cx, cy)] ??= []).add(e.index << 12 | (s - 1));
          }
        }
      }
      _cumLen.add(cum);
    }
  }

  /// Edges sharing a node with [edge] (including itself).
  Iterable<int> neighbours(int edge) sync* {
    final e = edges[edge];
    yield* nodeEdges[e.from];
    yield* nodeEdges[e.to];
  }

  /// Nearest edge segment to (x, y) within [maxDist], optionally filtered.
  EdgeHit? nearest(double x, double y, {double maxDist = 40, bool Function(RoadEdge)? where}) {
    EdgeHit? best;
    final r = (maxDist / cell).ceil();
    final cx = (x / cell).floor(), cy = (y / cell).floor();
    final seen = <int>{};
    for (var ix = cx - r; ix <= cx + r; ix++) {
      for (var iy = cy - r; iy <= cy + r; iy++) {
        final list = _grid[_key(ix, iy)];
        if (list == null) continue;
        for (final code in list) {
          if (!seen.add(code)) continue;
          final e = edges[code >> 12];
          if (where != null && !where(e)) continue;
          final hit = _project(e, code & 0xfff, x, y);
          if (hit.dist <= maxDist && (best == null || hit.dist < best.dist)) best = hit;
        }
      }
    }
    return best;
  }

  /// All edges with a segment within [radius] of (x, y), each with its closest hit.
  List<EdgeHit> near(double x, double y, double radius) {
    final out = <int, EdgeHit>{};
    final r = (radius / cell).ceil();
    final cx = (x / cell).floor(), cy = (y / cell).floor();
    for (var ix = cx - r; ix <= cx + r; ix++) {
      for (var iy = cy - r; iy <= cy + r; iy++) {
        final list = _grid[_key(ix, iy)];
        if (list == null) continue;
        for (final code in list) {
          final e = edges[code >> 12];
          final hit = _project(e, code & 0xfff, x, y);
          if (hit.dist > radius) continue;
          final prev = out[e.index];
          if (prev == null || hit.dist < prev.dist) out[e.index] = hit;
        }
      }
    }
    return out.values.toList();
  }

  /// Projects (x, y) onto one segment of an edge.
  EdgeHit project(RoadEdge e, int seg, double x, double y) => _project(e, seg, x, y);

  EdgeHit _project(RoadEdge e, int seg, double x, double y) {
    final ax = e.pts[2 * seg], ay = e.pts[2 * seg + 1], bx = e.pts[2 * seg + 2], by = e.pts[2 * seg + 3];
    final dx = bx - ax, dy = by - ay;
    final l2 = dx * dx + dy * dy;
    var t = l2 == 0 ? 0.0 : ((x - ax) * dx + (y - ay) * dy) / l2;
    t = t.clamp(0.0, 1.0);
    final px = ax + dx * t, py = ay + dy * t;
    final l = math.sqrt(l2);
    final along = e.length == 0 ? 0.0 : (_cumLen[e.index][seg] + l * t) / e.length;
    return EdgeHit(e, seg, px, py, _dist(px, py, x, y), along, l == 0 ? 1 : dx / l, l == 0 ? 0 : dy / l);
  }
}

class District {
  District(this.name, this.ring);
  final String name;
  final Float32List ring;

  bool contains(double x, double y) => pointInRing(x, y, ring);
}

/// Even-odd point in polygon over an interleaved ring.
bool pointInRing(double x, double y, Float32List ring) {
  var inside = false;
  final n = ring.length ~/ 2;
  for (var i = 0, j = n - 1; i < n; j = i++) {
    final xi = ring[2 * i], yi = ring[2 * i + 1], xj = ring[2 * j], yj = ring[2 * j + 1];
    if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

Float32List _ringM(List<int> dm) {
  final out = Float32List(dm.length);
  for (var i = 0; i < dm.length; i++) {
    out[i] = dm[i] / 10;
  }
  return out;
}

/// The static, always-loaded part of a citypack.
class City {
  City._(this.manifest, this.graph, this.landmarks, this.spots, this.districts, this.area);

  final pb.Manifest manifest;
  final RoadGraph graph;
  final pb.Landmarks landmarks;
  final pb.Spots spots;
  final List<District> districts;
  final Float32List area;
  late final Set<int> chunkKeys = {for (final c in manifest.chunks) chunkKey(c.x, c.y)};

  String get id => manifest.cityId;
  double get chunkM => manifest.chunkM.toDouble();
  bool get imperial => manifest.units == 'imperial';
  bool get leftHand => manifest.driveSide == 'left';
  double get startX => manifest.start.x / 10;
  double get startY => manifest.start.y / 10;
  double get startHeading => manifest.start.headingRad;

  static int chunkKey(int x, int y) => (x + 32768) << 16 | (y + 32768);

  bool hasChunk(int x, int y) => chunkKeys.contains(chunkKey(x, y));

  String? districtAt(double x, double y) {
    for (final d in districts) {
      if (d.contains(x, y)) return d.name;
    }
    return null;
  }

  static Future<City> load(PackSource src) async {
    final files = await Future.wait([
      src.read('manifest.pb'),
      src.read('graph.pb'),
      src.read('landmarks.pb'),
      src.read('spots.pb'),
    ]);
    final m = decodeManifest(files[0]);
    if (m.formatVersion != 1) {
      throw StateError('citypack format ${m.formatVersion} is not supported');
    }
    return City._(
      m,
      RoadGraph.fromPb(decodeGraph(files[1])),
      decodeLandmarks(files[2]),
      decodeSpots(files[3]),
      [for (final d in m.districts) District(d.name, _ringM(d.ring))],
      _ringM(m.area),
    );
  }
}
