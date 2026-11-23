import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_gen/citypack_pb.dart' as pb;
import 'package:world_engine/core.dart';

// specs/style.md v2 "Plochý vektor": cast shadows, roof parapet band, zebra crossings.

final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());

BuildingData building(List<double> pts, {List<int>? ends, List<int>? roof, double h = 20, double minH = 0}) {
  final xy = Float32List.fromList(pts);
  final n = xy.length ~/ 2;
  return BuildingData(
    xy: xy,
    ringEnds: Int32List.fromList(ends ?? [n]),
    roof: Uint16List.fromList(roof ?? [0, 1, 2, 0, 2, 3]),
    height: h,
    minHeight: minH,
    landmark: 0,
    collide: true,
    seed: 1,
    cx: 0,
    cy: 0,
    radius: 1,
    wallU: Float32List(n),
  );
}

/// CCW 10 × 10 square at the origin.
const square = <double>[0, 0, 10, 0, 10, 10, 0, 10];

bool _inTri(double px, double py, List<double> t) {
  double cross(int a, int b) =>
      (t[2 * b] - t[2 * a]) * (py - t[2 * a + 1]) - (t[2 * b + 1] - t[2 * a + 1]) * (px - t[2 * a]);
  final d1 = cross(0, 1), d2 = cross(1, 2), d3 = cross(2, 0);
  final neg = d1 < 0 || d2 < 0 || d3 < 0, pos = d1 > 0 || d2 > 0 || d3 > 0;
  return !(neg && pos);
}

bool covered(List<TriMesh> meshes, double x, double y) {
  for (final m in meshes) {
    for (var i = 0; i < m.indices.length; i += 3) {
      final t = <double>[];
      for (var k = 0; k < 3; k++) {
        t
          ..add(m.xy[2 * m.indices[i + k]])
          ..add(m.xy[2 * m.indices[i + k] + 1]);
      }
      if (_inTri(x, y, t)) return true;
    }
  }
  return false;
}

pb.Graph graph(List<(int, int)> nodes, List<({int a, int b, double w, bool kept, int layer})> edges) {
  return pb.Graph(
    names: [''],
    nodes: [for (final (x, y) in nodes) pb.Node(x: x * 10, y: y * 10)],
    edges: [
      for (final e in edges)
        pb.Edge(
          from: e.a,
          to: e.b,
          points: [nodes[e.a].$1 * 10, nodes[e.a].$2 * 10, nodes[e.b].$1 * 10, nodes[e.b].$2 * 10],
          class_4: pb.RoadClass.PRIMARY,
          lanes: 2,
          layerFrom: e.layer,
          layerTo: e.layer,
          kept: e.kept,
          widthM: e.w,
        ),
    ],
  );
}

({int a, int b, double w, bool kept, int layer}) edge(int a, int b, {double w = 20, bool kept = true, int layer = 0}) =>
    (a: a, b: b, w: w, kept: kept, layer: layer);

/// Quads of [q] whose centre passes [where].
List<List<double>> quadsWhere(List<double> q, bool Function(double x, double y) where) => [
  for (var i = 0; i + 8 <= q.length; i += 8)
    if (where((q[i] + q[i + 4]) / 2, (q[i + 1] + q[i + 5]) / 2)) q.sublist(i, i + 8),
];

/// Quads of [q] whose centre is within [r] of (x, y).
List<List<double>> quadsNear(List<double> q, double x, double y, double r) =>
    quadsWhere(q, (cx, cy) => math.sqrt(math.pow(cx - x, 2) + math.pow(cy - y, 2)) < r);

void main() {
  final st = tuning.style;

  group('cast shadows', () {
    test('direction is away from the sun, length is capped', () {
      final (dx, dy) = shadowDirection(-0.6, 0.8);
      expect(dx, closeTo(0.6, 1e-9));
      expect(dy, closeTo(-0.8, 1e-9));
      expect(shadowDirection(0, 0), (0.0, 0.0));
      expect(shadowLength(20, st.shadowRatio, st.shadowMaxM), closeTo(20 * st.shadowRatio, 1e-9));
      expect(shadowLength(1000, st.shadowRatio, st.shadowMaxM), st.shadowMaxM);
    });

    test('a box casts its prism shadow: shifted footprint plus one quad per edge', () {
      final b = building(square, h: 20);
      final meshes = buildShadowMeshes([b], dirX: 0.6, dirY: -0.8, ratio: 0.5, maxM: 22);
      expect(meshes, hasLength(1));
      final m = meshes.single;
      expect(m.vertexCount, 8); // footprint + shifted footprint, shared by the quads
      expect(m.indices.length, b.roof.length + 4 * 6);
      // L = 10: the shifted footprint is the square moved by (6, −8).
      expect(m.xy.sublist(8), [6, -8, 16, -8, 16, 2, 6, 2]);
      expect(covered(meshes, 12, -3), isTrue); // inside the shifted footprint
      expect(covered(meshes, 8, -2), isTrue); // swept between footprint and shift
      expect(covered(meshes, 13, 4), isTrue);
      expect(covered(meshes, -1, -1), isFalse);
      expect(covered(meshes, 17, -3), isFalse);
      expect(covered(meshes, 2, -6), isFalse); // behind the sweep's diagonal
    });

    test('towers are capped at shadow_max_m, parts above ground cast nothing', () {
      final tall = building(square, h: 500);
      final m = buildShadowMeshes([tall], dirX: 1, dirY: 0, ratio: st.shadowRatio, maxM: st.shadowMaxM).single;
      expect(m.xy[8], closeTo(st.shadowMaxM, 1e-4));
      expect(buildShadowMeshes([building(square, minH: 5)], dirX: 1, dirY: 0, ratio: 0.5, maxM: 22), isEmpty);
      expect(buildShadowMeshes([building(square)], dirX: 0, dirY: 0, ratio: 0.5, maxM: 22), isEmpty);
    });

    test('meshes split before the 16-bit index limit', () {
      final many = List.generate(9000, (_) => building(square));
      final meshes = buildShadowMeshes(many, dirX: 1, dirY: 0, ratio: 0.5, maxM: 22);
      expect(meshes.length, greaterThan(1));
      for (final m in meshes) {
        expect(m.vertexCount, lessThanOrEqualTo(65535));
        expect(m.indices.every((i) => i < m.vertexCount), isTrue);
      }
      expect(meshes.fold<int>(0, (s, m) => s + m.vertexCount), 9000 * 8);
    });

    test('toggle is per city and day only', () {
      expect(castShadowOn(st, 'nyc', night: false), st.castShadow.nyc);
      expect(castShadowOn(st, 'nyc', night: true), isFalse);
      expect(castShadowOn(st, 'prague', night: false), st.castShadow.prague);
      expect(castShadowOn(st, 'tokyo', night: false), st.castShadow.tokyo);
      expect(castShadowOn(st, 'atlantis', night: false), isFalse);
    });
  });

  group('roof edge band', () {
    void inwardSquare(List<double> pts) {
      final b = building(pts);
      final band = roofBand(b, 1);
      for (var i = 0; i < 4; i++) {
        // The band's inner side is the edge moved 1 m into the square.
        final ax = pts[2 * i], ay = pts[2 * i + 1], bx = pts[(2 * i + 2) % 8], by = pts[(2 * i + 3) % 8];
        final mx = (band[4 * i] + band[4 * i + 2]) / 2, my = (band[4 * i + 1] + band[4 * i + 3]) / 2;
        expect(mx, inExclusiveRange(0, 10));
        expect(my, inExclusiveRange(0, 10));
        expect(math.sqrt(math.pow(mx - (ax + bx) / 2, 2) + math.pow(my - (ay + by) / 2, 2)), closeTo(1, 1e-5));
        expect(band[4 * i + 2] - band[4 * i], closeTo(bx - ax, 1e-5));
        expect(band[4 * i + 3] - band[4 * i + 1], closeTo(by - ay, 1e-5));
      }
    }

    test('goes inwards on a CCW outer ring', () {
      inwardSquare(square);
      final band = roofBand(building(square), st.roofEdgeM);
      // Edge (0,0)→(10,0): inner ends (0, w), (10, w).
      expect(band.sublist(0, 4), [0, closeTo(st.roofEdgeM, 1e-6), 10, closeTo(st.roofEdgeM, 1e-6)]);
    });

    test('goes inwards on a CW outer ring too', () => inwardSquare([0, 0, 0, 10, 10, 10, 10, 0]));

    test('goes into the building around a courtyard', () {
      // Outer 0..10 CCW, hole 4..6 CW.
      final b = building([0, 0, 10, 0, 10, 10, 0, 10, 4, 4, 4, 6, 6, 6, 6, 4], ends: [4, 8], roof: [0, 1, 2]);
      final band = roofBand(b, 1);
      for (var i = 4; i < 8; i++) {
        for (var k = 0; k < 2; k++) {
          final x = band[4 * i + 2 * k], y = band[4 * i + 2 * k + 1];
          final outsideHole = x <= 3 + 1e-5 || x >= 7 - 1e-5 || y <= 3 + 1e-5 || y >= 7 - 1e-5;
          expect(outsideHole, isTrue, reason: 'hole edge $i end $k at ($x, $y)');
        }
      }
    });

    test('is cached per building and width', () {
      final b = building(square);
      final a = roofBandOf(b, 1);
      expect(identical(roofBandOf(b, 1), a), isTrue);
      expect(identical(roofBandOf(b, 2), a), isFalse);
    });
  });

  group('crosswalks', () {
    final p = CrosswalkParams.fromTuning(tuning);

    test('every edge of a 4-way junction gets a crossing at c = max half width + gap', () {
      // Centre 0, arms 100 m; the east arm is wider (30 m).
      final g = RoadGraph.fromPb(
        graph(
          [(0, 0), (100, 0), (-100, 0), (0, 100), (0, -100)],
          [edge(0, 1, w: 30), edge(2, 0), edge(0, 3), edge(4, 0)],
        ),
      );
      final q = crosswalkQuads(g, p);
      // East arm: others are 20 m wide → c = 10 + gap.
      final east = quadsWhere(q, (x, y) => x > y.abs());
      expect(east, isNotEmpty);
      for (final s in east) {
        final xs = [s[0], s[2], s[4], s[6]];
        expect(xs.reduce(math.min), closeTo(10 + p.gapM, 1e-4));
        expect(xs.reduce(math.max), closeTo(10 + p.gapM + p.lenM, 1e-4));
      }
      // Stripes across the carriageway, first at its edge, width = gap = stripe.
      final half = carriageHalfWidth(g.edges[0], p.sidewalkM, p.laneM);
      final ys = [
        for (final s in east) [s[1], s[5]].reduce(math.min),
      ]..sort();
      expect(ys.first, closeTo(-half, 1e-4));
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i] - ys[i - 1], closeTo(2 * p.stripeM, 1e-4));
      }
      expect(east.length, (2 * half / (2 * p.stripeM)).ceil());
      for (final s in east) {
        expect([s[1], s[3], s[5], s[7]].reduce(math.max), lessThanOrEqualTo(half + 1e-4));
      }
      // North arm: the east arm is the widest other edge → c = 15 + gap.
      final north = quadsWhere(q, (x, y) => y > x.abs());
      expect(north, isNotEmpty);
      expect(
        [
          for (final s in north) ...[s[1], s[3], s[5], s[7]],
        ].reduce(math.min),
        closeTo(15 + p.gapM, 1e-4),
      );
      // West arm runs to the centre (edge 2 → 0): measured from the junction end all the same.
      final west = quadsWhere(q, (x, y) => -x > y.abs());
      expect(west, isNotEmpty);
      expect(
        [
          for (final s in west) ...[s[0], s[2], s[4], s[6]],
        ].reduce(math.max),
        closeTo(-(15 + p.gapM), 1e-4),
      );
    });

    test('short edges, plain bends and alleys get no crossing', () {
      final c = 10 + p.gapM;
      final short = (2 * (c + p.lenM) - 1).floor();
      final g = RoadGraph.fromPb(
        graph(
          [(0, 0), (short, 0), (-100, 0), (0, 100), (0, -100), (-100, 100)],
          [edge(0, 1), edge(0, 2), edge(0, 3), edge(4, 0), edge(2, 5), edge(5, 3, kept: false)],
        ),
      );
      final q = crosswalkQuads(g, p);
      expect(quadsNear(q, c + p.lenM / 2, 0, 5), isEmpty); // too short
      expect(quadsNear(q, -(c + p.lenM / 2), 0, 5), isNotEmpty);
      // Node 2 has two kept edges and node 5 one kept + one alley: no crossings there.
      expect(quadsNear(q, -100, 0, 30), isEmpty);
      expect(quadsNear(q, -100, 100, 30), isEmpty);
    });

    test('a street split at two-ended nodes counts as one edge', () {
      // East arm in three pieces: 0 → 5 → 6 → 1 (5 m, 10 m, 85 m); the crossing spans the split.
      final g = RoadGraph.fromPb(
        graph(
          [(0, 0), (100, 0), (-100, 0), (0, 100), (0, -100), (5, 0), (15, 0)],
          [edge(0, 5), edge(5, 6), edge(6, 1), edge(2, 0), edge(0, 3), edge(4, 0)],
        ),
      );
      final east = quadsWhere(crosswalkQuads(g, p), (x, y) => x > y.abs());
      expect(east, isNotEmpty);
      final xs = [
        for (final s in east) ...[s[0], s[2], s[4], s[6]],
      ];
      expect(xs.reduce(math.min), closeTo(10 + p.gapM, 1e-4));
      expect(xs.reduce(math.max), closeTo(10 + p.gapM + p.lenM, 1e-4));
      // Nodes 5 and 6 are not junctions, so nothing else on the east arm.
      expect(xs.reduce(math.max), lessThan(20));
    });

    test('bridges and tunnels do not count towards a junction', () {
      final g = RoadGraph.fromPb(
        graph([(0, 0), (100, 0), (-100, 0), (0, 100)], [edge(0, 1), edge(0, 2), edge(0, 3, layer: 1)]),
      );
      expect(crosswalkQuads(g, p), isEmpty);
    });

    test('toggle is per city', () {
      expect(crosswalksOn(st, 'nyc'), st.crosswalks.nyc);
      expect(crosswalksOn(st, 'prague'), st.crosswalks.prague);
      expect(crosswalksOn(st, 'tokyo'), st.crosswalks.tokyo);
      expect(crosswalksOn(st, 'atlantis'), isFalse);
    });
  });
}
