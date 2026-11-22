import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'model.dart';
import 'palette.dart';
import 'style_geometry.dart';

/// Draw passes for road geometry; each pass is one colour, drawn across all visible chunks
/// before the next pass so neighbouring chunks overlap correctly.
enum RoadPass {
  sidewalk,
  alley,
  asphalt,
  laneLines,
  centerLines,

  /// Zebra crossings at junctions (specs/style.md v2), above the lane markings; day only.
  crosswalks,
  bridgeEdge,
  bridgeDeck,
  bridgeLaneLines,
  bridgeCenterLines,
  tunnel,
  tunnelLaneLines,
}

const groundPasses = [
  RoadPass.sidewalk,
  RoadPass.alley,
  RoadPass.asphalt,
  RoadPass.laneLines,
  RoadPass.centerLines,
  RoadPass.crosswalks,
];
const bridgePasses = [RoadPass.bridgeEdge, RoadPass.bridgeDeck, RoadPass.bridgeLaneLines, RoadPass.bridgeCenterLines];
const tunnelPasses = [RoadPass.tunnel, RoadPass.tunnelLaneLines];

ui.Color passColor(RoadPass p, Palette pal) => switch (p) {
  RoadPass.sidewalk => pal.sidewalk,
  RoadPass.alley => pal.alley,
  RoadPass.asphalt => pal.asphalt,
  RoadPass.laneLines || RoadPass.bridgeLaneLines || RoadPass.tunnelLaneLines || RoadPass.crosswalks => pal.marking,
  RoadPass.centerLines || RoadPass.bridgeCenterLines => pal.centerLine,
  RoadPass.bridgeEdge => pal.bridgeEdge,
  RoadPass.bridgeDeck => pal.bridgeDeck,
  RoadPass.tunnel => pal.tunnel,
};

class _Tris {
  final pos = <double>[];
  final idx = <int>[];

  int get vertexCount => pos.length ~/ 2;

  void quad(double ax, double ay, double bx, double by, double hw, [double offset = 0]) {
    final dx = bx - ax, dy = by - ay;
    final l = math.sqrt(dx * dx + dy * dy);
    if (l < 1e-3) return;
    final nx = -dy / l, ny = dx / l;
    final o0 = offset - hw, o1 = offset + hw;
    final b = vertexCount;
    pos.addAll([
      ax + nx * o0, ay + ny * o0, //
      bx + nx * o0, by + ny * o0,
      bx + nx * o1, by + ny * o1,
      ax + nx * o1, ay + ny * o1,
    ]);
    idx.addAll([b, b + 1, b + 2, b, b + 2, b + 3]);
  }

  /// A convex polygon of [n] points starting at float [at] of [xy].
  void polygon(List<double> xy, int at, int n) {
    final b = vertexCount;
    for (var k = 0; k < 2 * n; k++) {
      pos.add(xy[at + k]);
    }
    for (var k = 1; k + 1 < n; k++) {
      idx.addAll([b, b + k, b + k + 1]);
    }
  }

  void disc(double cx, double cy, double r, [int segs = 10]) {
    final b = vertexCount;
    pos.addAll([cx, cy]);
    for (var i = 0; i < segs; i++) {
      final a = i * 2 * math.pi / segs;
      pos.addAll([cx + r * math.cos(a), cy + r * math.sin(a)]);
    }
    for (var i = 0; i < segs; i++) {
      idx.addAll([b, b + 1 + i, b + 1 + (i + 1) % segs]);
    }
  }

  ui.Vertices? build() {
    if (idx.isEmpty || vertexCount > 65535) return null;
    return ui.Vertices.raw(ui.VertexMode.triangles, Float32List.fromList(pos), indices: Uint16List.fromList(idx));
  }
}

/// Static road meshes bucketed by chunk, built once per city (and per palette switch).
class RoadMeshes {
  RoadMeshes._(this._meshes);

  final Map<int, Map<RoadPass, ui.Vertices>> _meshes;

  Map<RoadPass, ui.Vertices>? chunk(int key) => _meshes[key];

  /// [crosswalks] = zebra parameters when the city has them (`style.crosswalks`), else null.
  static RoadMeshes build(
    RoadGraph graph,
    double chunkM, {
    required double sidewalkM,
    required double laneM,
    CrosswalkParams? crosswalks,
  }) {
    final acc = <int, Map<RoadPass, _Tris>>{};
    _Tris tris(int key, RoadPass p) => (acc[key] ??= {})[p] ??= _Tris();

    for (final e in graph.edges) {
      final layer = e.drawLayer;
      final hw = e.width / 2;
      final carriage = e.kept ? carriageHalfWidth(e, sidewalkM, laneM) : hw;
      final n = e.pointCount;
      for (var s = 0; s + 1 < n; s++) {
        final ax = e.pts[2 * s], ay = e.pts[2 * s + 1], bx = e.pts[2 * s + 2], by = e.pts[2 * s + 3];
        final key = _chunkKey((ax + bx) / 2, (ay + by) / 2, chunkM);
        final last = s + 2 == n;
        void stroke(RoadPass p, double r, {bool joints = true}) {
          final t = tris(key, p);
          t.quad(ax, ay, bx, by, r);
          if (joints) {
            t.disc(ax, ay, r);
            if (last) t.disc(bx, by, r);
          }
        }

        if (layer < 0) {
          stroke(RoadPass.tunnel, carriage);
        } else if (layer > 0) {
          stroke(RoadPass.bridgeEdge, hw + 1.2);
          stroke(RoadPass.bridgeDeck, carriage + 1.0);
        } else if (e.kept) {
          stroke(RoadPass.sidewalk, hw);
          stroke(RoadPass.asphalt, carriage);
        } else {
          stroke(RoadPass.alley, hw);
        }
      }
      if (e.kept) _markings(e, layer, carriage, laneM, chunkM, tris);
    }
    if (crosswalks != null) {
      final q = crosswalkQuads(graph, crosswalks);
      for (var i = 0; i + 8 <= q.length; i += 8) {
        final key = _chunkKey((q[i] + q[i + 4]) / 2, (q[i + 1] + q[i + 5]) / 2, chunkM);
        tris(key, RoadPass.crosswalks).polygon(q, i, 4);
      }
    }
    final out = <int, Map<RoadPass, ui.Vertices>>{};
    acc.forEach((key, passes) {
      final m = <RoadPass, ui.Vertices>{};
      passes.forEach((p, t) {
        final v = t.build();
        if (v != null) m[p] = v;
      });
      out[key] = m;
    });
    return RoadMeshes._(out);
  }

  static void _markings(
    RoadEdge e,
    int layer,
    double carriage,
    double laneM,
    double chunkM,
    _Tris Function(int, RoadPass) tris,
  ) {
    final lanePass = layer < 0
        ? RoadPass.tunnelLaneLines
        : layer > 0
        ? RoadPass.bridgeLaneLines
        : RoadPass.laneLines;
    final centerPass = layer > 0 ? RoadPass.bridgeCenterLines : RoadPass.centerLines;
    final lanes = math.max(1, (2 * carriage / laneM).round());
    final laneW = 2 * carriage / lanes;
    const lineHw = 0.3;
    var dist = 0.0;
    for (var s = 0; s + 1 < e.pointCount; s++) {
      final ax = e.pts[2 * s], ay = e.pts[2 * s + 1], bx = e.pts[2 * s + 2], by = e.pts[2 * s + 3];
      final key = _chunkKey((ax + bx) / 2, (ay + by) / 2, chunkM);
      final dx = bx - ax, dy = by - ay;
      final l = math.sqrt(dx * dx + dy * dy);
      if (l < 1e-3) continue;
      final twoWay = e.oneway == 0 && lanes >= 2;
      if (twoWay && layer >= 0) {
        tris(key, centerPass)
          ..quad(ax, ay, bx, by, lineHw, -0.5)
          ..quad(ax, ay, bx, by, lineHw, 0.5);
      }
      // Dashed lane dividers: 6 m paint, 9 m gap.
      for (var k = 1; k < lanes; k++) {
        final off = -carriage + k * laneW;
        if (twoWay && (off.abs() < laneW / 2)) continue;
        var t = (15 - dist % 15) % 15;
        while (t < l) {
          final t1 = math.min(t + 6, l);
          tris(key, lanePass).quad(ax + dx * t / l, ay + dy * t / l, ax + dx * t1 / l, ay + dy * t1 / l, lineHw, off);
          t += 15;
        }
      }
      dist += l;
    }
  }

  static int _chunkKey(double x, double y, double chunkM) => City.chunkKey((x / chunkM).floor(), (y / chunkM).floor());
}
