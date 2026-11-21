import 'dart:math' as math;

import 'package:world_engine/core.dart';

import '../traffic/road_rules.dart';

/// Pure geometry of the police (specs/police.md "Chodník", "Dohled"). Port of
/// web/src/police/sense.ts; both clients test the same cases.

/// True when the point of [hits] is on the sidewalk band of some kept ground edge and on the
/// carriageway of none (hits = `graph.near(x, y, r)` for the player's centre).
bool onSidewalk(List<EdgeHit> hits, Tuning tuning) {
  final margin = tuning.police.sidewalkMarginM;
  var band = false;
  for (final h in hits) {
    final e = h.edge;
    if (!e.kept || e.layerAt(h.t) != 0 || e.tunnel) continue;
    if (h.dist <= carriageHalf(e, tuning) + margin) return false;
    if (h.dist <= e.width / 2) band = true;
  }
  return band;
}

/// True when segment a–b properly crosses segment c–d (touching ends do not count).
bool segmentsCross(double ax, double ay, double bx, double by, double cx, double cy, double dx, double dy) {
  final d1 = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
  final d2 = (bx - ax) * (dy - ay) - (by - ay) * (dx - ax);
  final d3 = (dx - cx) * (ay - cy) - (dy - cy) * (ax - cx);
  final d4 = (dx - cx) * (by - cy) - (dy - cy) * (bx - cx);
  return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
}

double _pointSegDist(double px, double py, double ax, double ay, double bx, double by) {
  final dx = bx - ax, dy = by - ay;
  final l2 = dx * dx + dy * dy;
  final t = l2 == 0 ? 0.0 : (((px - ax) * dx + (py - ay) * dy) / l2).clamp(0.0, 1.0);
  final qx = ax + dx * t - px, qy = ay + dy * t - py;
  return math.sqrt(qx * qx + qy * qy);
}

/// True when segment a–b crosses an outline edge of a colliding building (bounding circle first).
bool sightBlocked(double ax, double ay, double bx, double by, Iterable<BuildingData> buildings) {
  for (final b in buildings) {
    if (!b.collide || _pointSegDist(b.cx, b.cy, ax, ay, bx, by) > b.radius) continue;
    var start = 0;
    for (final end in b.ringEnds) {
      for (var i = start; i < end; i++) {
        final j = i + 1 < end ? i + 1 : start;
        if (segmentsCross(ax, ay, bx, by, b.xy[2 * i], b.xy[2 * i + 1], b.xy[2 * j], b.xy[2 * j + 1])) return true;
      }
      start = end;
    }
  }
  return false;
}

/// Patrol sees the player (without the building test): tunnel ↔ tunnel and within [viewM].
bool inView(double px, double py, int pLayer, double qx, double qy, int qLayer, double viewM) {
  if ((pLayer < 0) != (qLayer < 0)) return false;
  final dx = qx - px, dy = qy - py;
  return dx * dx + dy * dy <= viewM * viewM;
}

/// Light-bar phase (specs/police.md "Kreslení"): −1 = off (not chasing), else 0 / 1 alternating
/// every [blinkS]. Same rule as web/src/police/view.ts.
int lightPhase(bool pursuing, double timeS, double blinkS) => pursuing ? (timeS / blinkS).floor() % 2 : -1;
