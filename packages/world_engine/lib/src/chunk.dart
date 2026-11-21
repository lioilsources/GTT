import 'dart:math' as math;
import 'dart:typed_data';

import 'citypack.dart';
import 'package:shared_gen/citypack_pb.dart';

/// Render- and physics-ready building mass, in world metres.
class BuildingData {
  BuildingData({
    required this.xy,
    required this.ringEnds,
    required this.roof,
    required this.height,
    required this.minHeight,
    required this.landmark,
    required this.collide,
    required this.seed,
    required this.cx,
    required this.cy,
    required this.radius,
    required this.wallU,
  });

  /// Interleaved footprint vertices of all rings.
  final Float32List xy;

  /// Exclusive end vertex index per ring; ring 0 is the CCW outer ring.
  final Int32List ringEnds;
  final Uint16List roof;
  final double height;
  final double minHeight;
  final int landmark;
  final bool collide;
  final int seed;
  final double cx;
  final double cy;
  final double radius;

  /// Cumulative wall length at each vertex (texture u), per ring.
  final Float32List wallU;

  int get vertexCount => xy.length ~/ 2;
}

/// Ground polygons of one kind merged into a single mesh.
class GroundData {
  GroundData(this.kind, this.xy, this.indices);
  final GroundKind kind;
  final Float32List xy;
  final Uint16List indices;
}

class ChunkData {
  ChunkData(this.x, this.y, this.buildings, this.ground);
  final int x;
  final int y;
  final List<BuildingData> buildings;
  final List<GroundData> ground;
}

/// Decodes and prepares one chunk. Pure function so it can run in an isolate.
ChunkData prepareChunk(Uint8List gz) {
  final c = decodeChunk(gz);
  final buildings = <BuildingData>[];
  for (final b in c.buildings) {
    final n = b.rings.length ~/ 2;
    if (n < 3 || n > 65535) continue;
    final xy = Float32List(b.rings.length);
    var sx = 0.0, sy = 0.0;
    for (var i = 0; i < n; i++) {
      xy[2 * i] = b.rings[2 * i] / 10;
      xy[2 * i + 1] = b.rings[2 * i + 1] / 10;
    }
    final outerEnd = b.ringEnds.isEmpty ? n : b.ringEnds.first;
    for (var i = 0; i < outerEnd; i++) {
      sx += xy[2 * i];
      sy += xy[2 * i + 1];
    }
    final cx = sx / outerEnd, cy = sy / outerEnd;
    var r2 = 0.0;
    for (var i = 0; i < outerEnd; i++) {
      final dx = xy[2 * i] - cx, dy = xy[2 * i + 1] - cy;
      r2 = math.max(r2, dx * dx + dy * dy);
    }
    final ends = Int32List.fromList(b.ringEnds.isEmpty ? [n] : b.ringEnds);
    final wallU = Float32List(n);
    var start = 0;
    for (final end in ends) {
      var u = 0.0;
      for (var i = start; i < end; i++) {
        wallU[i] = u;
        final j = i + 1 < end ? i + 1 : start;
        final dx = xy[2 * j] - xy[2 * i], dy = xy[2 * j + 1] - xy[2 * i + 1];
        u += math.sqrt(dx * dx + dy * dy);
      }
      start = end;
    }
    buildings.add(BuildingData(
      xy: xy,
      ringEnds: ends,
      roof: Uint16List.fromList(b.roof),
      height: b.heightM,
      minHeight: b.minHeightM,
      landmark: b.landmark,
      collide: b.collide,
      seed: b.wallSeed,
      cx: cx,
      cy: cy,
      radius: math.sqrt(r2),
      wallU: wallU,
    ));
  }
  final byKind = <GroundKind, ({List<double> xy, List<int> idx})>{};
  for (final m in c.ground) {
    final acc = byKind.putIfAbsent(m.kind, () => (xy: <double>[], idx: <int>[]));
    final base = acc.xy.length ~/ 2;
    if (base + m.vertices.length ~/ 2 > 65535) continue;
    for (final v in m.vertices) {
      acc.xy.add(v / 10);
    }
    for (final i in m.indices) {
      acc.idx.add(base + i);
    }
  }
  final ground = [
    for (final e in byKind.entries) GroundData(e.key, Float32List.fromList(e.value.xy), Uint16List.fromList(e.value.idx)),
  ];
  return ChunkData(c.x, c.y, buildings, ground);
}
