import 'dart:math' as math;
import 'dart:typed_data';

import 'package:shared_gen/citypack_pb.dart' as pb;

import 'chunk.dart';
import 'model.dart' show City;

/// One landmark model as client F draws it (specs/models.md v4 "Pohled shora"): only the roof
/// plan. F has no chase view (Prompts/06 H7), so the parts (the full mesh) are not kept.
class ModelData {
  ModelData({
    required this.landmarkId,
    required this.plan,
    required this.replaces,
    required this.cx,
    required this.cy,
    required this.radius,
    required this.tris,
  });

  final String landmarkId;

  /// Roof-plan polygons as prisms from the ground to `height_m`, sorted by height ascending (the
  /// 2D draw order of the spec). Each has [BuildingData.planShade] 0–3 and `landmark` 1.
  final List<BuildingData> plan;

  /// Pack buildings the plan stands in for: chunk key → indices into `Chunk.buildings`.
  final Map<int, Set<int>> replaces;

  /// Centre and radius of the plan's bounding circle (m), for culling and the painter order.
  final double cx;
  final double cy;
  final double radius;
  final int tris;
}

/// A roof-plan polygon (`PlanPoly`, rings like `Building`: dm absolute, outer CCW, holes CW) as a
/// [BuildingData]. The base height (`base_z_dm`) is not used: F draws a flat world.
BuildingData? planBuilding(pb.PlanPoly p) {
  final n = p.points.length ~/ 2;
  if (n < 3 || n > 65535 || p.triangles.isEmpty) return null;
  final xy = Float32List(2 * n);
  for (var i = 0; i < 2 * n; i++) {
    xy[i] = p.points[i] / 10;
  }
  final ends = Int32List.fromList(p.ringEnds.isEmpty ? [n] : p.ringEnds);
  final outer = ends.first;
  var sx = 0.0, sy = 0.0;
  for (var i = 0; i < outer; i++) {
    sx += xy[2 * i];
    sy += xy[2 * i + 1];
  }
  final cx = sx / outer, cy = sy / outer;
  var r2 = 0.0;
  for (var i = 0; i < outer; i++) {
    final dx = xy[2 * i] - cx, dy = xy[2 * i + 1] - cy;
    r2 = math.max(r2, dx * dx + dy * dy);
  }
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
  return BuildingData(
    xy: xy,
    ringEnds: ends,
    roof: Uint16List.fromList(p.triangles),
    height: math.max(0.1, p.heightM),
    minHeight: 0,
    landmark: 1,
    collide: false,
    seed: 0,
    cx: cx,
    cy: cy,
    radius: math.sqrt(r2),
    wallU: wallU,
    planShade: p.shade.clamp(0, 3),
  );
}

/// `models.pb` → what F draws. Models without a roof plan are skipped (nothing to draw instead of
/// the footprints, so those stay).
List<ModelData> prepareModels(pb.Models m) {
  final out = <ModelData>[];
  for (final md in m.models) {
    final plan = md.roofPlan.map(planBuilding).whereType<BuildingData>().toList();
    if (plan.isEmpty) continue;
    plan.sort((a, b) => a.height.compareTo(b.height));
    var x0 = double.infinity, y0 = double.infinity, x1 = -double.infinity, y1 = -double.infinity;
    for (final b in plan) {
      for (var i = 0; i < b.xy.length; i += 2) {
        x0 = math.min(x0, b.xy[i]);
        x1 = math.max(x1, b.xy[i]);
        y0 = math.min(y0, b.xy[i + 1]);
        y1 = math.max(y1, b.xy[i + 1]);
      }
    }
    final replaces = <int, Set<int>>{};
    for (final r in md.replaces) {
      (replaces[City.chunkKey(r.chunkX, r.chunkY)] ??= <int>{}).add(r.index);
    }
    out.add(ModelData(
      landmarkId: md.landmarkId,
      plan: plan,
      replaces: replaces,
      cx: (x0 + x1) / 2,
      cy: (y0 + y1) / 2,
      radius: math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)) / 2,
      tris: md.tris,
    ));
  }
  return out;
}

/// All buildings replaced by any model: chunk key → indices into `Chunk.buildings`.
Map<int, Set<int>> replacedBuildings(List<ModelData> models) {
  final out = <int, Set<int>>{};
  for (final m in models) {
    m.replaces.forEach((k, s) => (out[k] ??= <int>{}).addAll(s));
  }
  return out;
}
