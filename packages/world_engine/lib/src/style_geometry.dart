import 'dart:math' as math;
import 'dart:typed_data';

import 'package:shared_gen/shared_gen.dart';

import 'chunk.dart';
import 'model.dart';

// Flat vector look, style A (specs/style.md v2 "Plochý vektor"): the pure geometry of cast
// shadows, roof parapet bands and zebra crossings. No dart:ui here; the renderer turns the
// buffers into vertices once per chunk (shadows), per building (bands) or per city (zebras).

/// Whether buildings cast ground shadows in [cityId] (`style.cast_shadow.<city>`), by day only.
bool castShadowOn(TuningStyle style, String cityId, {required bool night}) {
  if (night) return false;
  return switch (cityId) {
    'nyc' => style.castShadow.nyc,
    'prague' => style.castShadow.prague,
    _ => false,
  };
}

/// Whether junctions of [cityId] get zebra crossings (`style.crosswalks.<city>`). The meshes are
/// built per city; the renderer leaves them out at night.
bool crosswalksOn(TuningStyle style, String cityId) => switch (cityId) {
  'nyc' => style.crosswalks.nyc,
  'prague' => style.crosswalks.prague,
  _ => false,
};

/// Shadow direction `s = −(sunX, sunY) / |(sunX, sunY)|`; zero when the sun has no horizontal part.
(double, double) shadowDirection(double sunX, double sunY) {
  final l = math.sqrt(sunX * sunX + sunY * sunY);
  if (l < 1e-9) return (0, 0);
  return (-sunX / l, -sunY / l);
}

/// Shadow length `L = min(height × ratio, maxM)`.
double shadowLength(double height, double ratio, double maxM) => math.min(height * ratio, maxM);

/// One triangle mesh in world metres, at most 65535 vertices (16-bit indices).
class TriMesh {
  TriMesh(this.xy, this.indices);
  final Float32List xy;
  final Uint16List indices;

  int get vertexCount => xy.length ~/ 2;
}

/// Cast shadows of [buildings] on flat ground: per building the footprint shifted by `L·s`
/// (its roof triangulation) plus the quad (a, b, b + L·s, a + L·s) of every footprint edge. The
/// union is not computed; overlaps are the renderer's job (drawn opaque, composited once).
/// Building parts with `minHeight > 0` cast nothing. Split into meshes of ≤ 65535 vertices.
List<TriMesh> buildShadowMeshes(
  Iterable<BuildingData> buildings, {
  required double dirX,
  required double dirY,
  required double ratio,
  required double maxM,
}) {
  final out = <TriMesh>[];
  if (dirX == 0 && dirY == 0) return out;
  var xy = <double>[];
  var idx = <int>[];
  void flush() {
    if (idx.isNotEmpty) out.add(TriMesh(Float32List.fromList(xy), Uint16List.fromList(idx)));
    xy = <double>[];
    idx = <int>[];
  }

  for (final b in buildings) {
    if (b.minHeight > 0) continue;
    final l = shadowLength(b.height, ratio, maxM);
    if (l <= 0) continue;
    final n = b.vertexCount;
    if (2 * n > 65535) continue;
    if (xy.length ~/ 2 + 2 * n > 65535) flush();
    final base = xy.length ~/ 2;
    final ox = dirX * l, oy = dirY * l;
    final p = b.xy;
    // Vertices base..base+n-1: footprint; base+n..base+2n-1: footprint shifted by L·s.
    for (var i = 0; i < n; i++) {
      xy
        ..add(p[2 * i])
        ..add(p[2 * i + 1]);
    }
    for (var i = 0; i < n; i++) {
      xy
        ..add(p[2 * i] + ox)
        ..add(p[2 * i + 1] + oy);
    }
    for (final r in b.roof) {
      idx.add(base + n + r);
    }
    var start = 0;
    for (final end in b.ringEnds) {
      for (var i = start; i < end; i++) {
        final j = i + 1 < end ? i + 1 : start;
        final a = base + i, bb = base + j, b2 = base + n + j, a2 = base + n + i;
        idx.addAll([a, bb, b2, a, b2, a2]);
      }
      start = end;
    }
  }
  flush();
  return out;
}

double _signedArea(Float32List xy, int start, int end) {
  var a = 0.0;
  for (var i = start; i < end; i++) {
    final j = i + 1 < end ? i + 1 : start;
    a += xy[2 * i] * xy[2 * j + 1] - xy[2 * j] * xy[2 * i + 1];
  }
  return a / 2;
}

/// The parapet band along the roof outline, [w] metres wide inwards (into the building, for the
/// outer ring and for courtyards alike). For every footprint vertex i (edge i → next in its ring)
/// four floats: the inner ends `a'`, `b'` of the edge's band quad (a, b, b', a'). Corners are not
/// mitred; each quad stays within [w] of its own edge, so nothing sticks out of the outline by
/// more than [w]. Degenerate edges get a zero-width quad (a' = a, b' = b).
Float32List roofBand(BuildingData b, double w) {
  final xy = b.xy;
  final out = Float32List(b.vertexCount * 4);
  var start = 0;
  var ring = 0;
  for (final end in b.ringEnds) {
    final area = _signedArea(xy, start, end);
    // Left normal (−ey, ex) points into a CCW ring. The building is inside the outer ring and
    // outside every courtyard, so the band goes left on a CCW outer ring and on a CW hole.
    final left = ring == 0 ? area >= 0 : area <= 0;
    final sign = left ? 1.0 : -1.0;
    for (var i = start; i < end; i++) {
      final j = i + 1 < end ? i + 1 : start;
      final ax = xy[2 * i], ay = xy[2 * i + 1], bx = xy[2 * j], by = xy[2 * j + 1];
      final ex = bx - ax, ey = by - ay;
      final len = math.sqrt(ex * ex + ey * ey);
      final k = len < 0.05 ? 0.0 : sign * w / len;
      final nx = -ey * k, ny = ex * k;
      out[4 * i] = ax + nx;
      out[4 * i + 1] = ay + ny;
      out[4 * i + 2] = bx + nx;
      out[4 * i + 3] = by + ny;
    }
    start = end;
    ring++;
  }
  return out;
}

/// [roofBand] of [b], computed once per building and width.
Float32List roofBandOf(BuildingData b, double w) {
  final c = b.roofBandXY;
  if (c != null && b.roofBandW == w) return c;
  b.roofBandW = w;
  return b.roofBandXY = roofBand(b, w);
}

/// Zebra crossing parameters (`style.crosswalk_*`) and the road cross-section of [RoadMeshes].
class CrosswalkParams {
  const CrosswalkParams({
    required this.gapM,
    required this.lenM,
    required this.stripeM,
    required this.sidewalkM,
    required this.laneM,
  });

  factory CrosswalkParams.fromTuning(Tuning t) => CrosswalkParams(
    gapM: t.style.crosswalkGapM,
    lenM: t.style.crosswalkLenM,
    stripeM: t.style.crosswalkStripeM,
    sidewalkM: t.sidewalkWidthM,
    laneM: t.laneWidthM,
  );

  final double gapM, lenM, stripeM, sidewalkM, laneM;
}

/// Half width of the carriageway of a kept edge (same as the asphalt pass of the road meshes).
double carriageHalfWidth(RoadEdge e, double sidewalkM, double laneM) => math.max(e.width - 2 * sidewalkM, laneM) / 2;

/// Zebra stripes of the whole graph as quads: 8 floats each (4 corners, x y interleaved, in
/// order around the quad), stripes parallel to the road axis.
///
/// Every junction (a node with at least three kept layer-0 edge ends) gets a crossing on each of
/// those edges, from `c = max(half width of the other edges at the node) + gap` to `c + len`
/// along the street. A street shorter than `2 × (c + len)` gets none. Stripes `stripe` wide with
/// equal gaps span the carriageway, the first one at its edge; the last is clipped to it.
///
/// "Street" is the edge continued through nodes with exactly two kept layer-0 ends: the packs
/// split roads at every Overture connector, so a plain graph edge is often a few metres long
/// even between junctions far apart (NYC: 11 % of junction approaches would get a crossing per
/// single edge, 84 % per street).
List<double> crosswalkQuads(RoadGraph g, CrosswalkParams p) {
  final out = <double>[];
  final line = <double>[];
  for (var n = 0; n < g.nodeEdges.length; n++) {
    final ends = _groundEnds(g, n);
    if (ends.length < 3) continue;
    for (var k = 0; k < ends.length; k++) {
      var c = 0.0;
      for (var o = 0; o < ends.length; o++) {
        if (o != k) c = math.max(c, ends[o].$1.width / 2);
      }
      c += p.gapM;
      final (e, atFrom) = ends[k];
      if (_street(g, n, e, atFrom, 2 * (c + p.lenM), line) < 2 * (c + p.lenM)) continue;
      _crossing(line, c, c + p.lenM, carriageHalfWidth(e, p.sidewalkM, p.laneM), p.stripeM, out);
    }
  }
  return out;
}

/// Kept layer-0 edge ends at node [n]: the edge and whether it starts there.
List<(RoadEdge, bool)> _groundEnds(RoadGraph g, int n) {
  final ends = <(RoadEdge, bool)>[];
  for (final ei in g.nodeEdges[n]) {
    final e = g.edges[ei];
    if (!e.kept || !e.isGround) continue;
    // A loop edge is listed twice: once per end.
    final atFrom = e.from == n && !ends.any((x) => identical(x.$1, e) && x.$2);
    ends.add((e, atFrom));
  }
  return ends;
}

/// Fills [line] with the polyline of the street leaving node [n] along [e] (from its [atFrom]
/// end), continued through two-ended nodes until it is [need] metres long, reaches another
/// junction or a dead end, or comes back to [n]. Returns its length.
double _street(RoadGraph g, int n, RoadEdge e, bool atFrom, double need, List<double> line) {
  line.clear();
  var len = 0.0;
  var cur = e;
  var fwd = atFrom;
  final seen = <RoadEdge>{};
  while (seen.add(cur)) {
    final m = cur.pointCount;
    for (var i = line.isEmpty ? 0 : 1; i < m; i++) {
      final j = fwd ? i : m - 1 - i;
      line
        ..add(cur.pts[2 * j])
        ..add(cur.pts[2 * j + 1]);
    }
    len += cur.length;
    final at = fwd ? cur.to : cur.from;
    if (len >= need || at == n) break;
    final next = _groundEnds(g, at);
    if (next.length != 2) break;
    final came = cur;
    final (ne, nFrom) = identical(next[0].$1, came) && next[0].$2 != fwd ? next[1] : next[0];
    cur = ne;
    fwd = nFrom;
  }
  return len;
}

/// Stripes of one crossing between distances [d0] and [d1] along the polyline [line].
void _crossing(List<double> line, double d0, double d1, double half, double stripe, List<double> out) {
  if (stripe <= 0) return;
  final n = line.length ~/ 2;
  var dist = 0.0;
  for (var s = 0; s + 1 < n && dist < d1; s++) {
    final ax = line[2 * s], ay = line[2 * s + 1], bx = line[2 * s + 2], by = line[2 * s + 3];
    final dx = bx - ax, dy = by - ay;
    final l = math.sqrt(dx * dx + dy * dy);
    if (l < 1e-6) continue;
    final t0 = math.max(d0 - dist, 0.0), t1 = math.min(d1 - dist, l);
    dist += l;
    if (t1 <= t0) continue;
    final ux = dx / l, uy = dy / l, nx = -uy, ny = ux;
    final sx = ax + ux * t0, sy = ay + uy * t0, ex = ax + ux * t1, ey = ay + uy * t1;
    for (var o = -half; o < half - 1e-6; o += 2 * stripe) {
      final o1 = math.min(o + stripe, half);
      out.addAll([
        sx + nx * o, sy + ny * o, //
        ex + nx * o, ey + ny * o,
        ex + nx * o1, ey + ny * o1,
        sx + nx * o1, sy + ny * o1,
      ]);
    }
  }
}
