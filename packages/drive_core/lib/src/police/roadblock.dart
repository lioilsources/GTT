import 'dart:math' as math;

import 'package:world_engine/core.dart';

import '../traffic/road_rules.dart';

/// Where a roadblock stands (specs/roadblock.md "Kde"): [edge], [d] metres from its `from` node,
/// the point ([x], [y]) on the centre line and the unit direction ([ux], [uy]) of the edge (from → to)
/// there.
typedef RoadblockSpot = ({int edge, double d, double x, double y, double ux, double uy});

/// Point and from → to unit direction of [e] at [d] metres from its `from` node.
({double x, double y, double ux, double uy}) edgePointAt(RoadEdge e, double d) {
  var acc = 0.0;
  final last = e.pointCount - 2;
  for (var seg = 0; seg <= last; seg++) {
    final ax = e.pts[2 * seg], ay = e.pts[2 * seg + 1], bx = e.pts[2 * seg + 2], by = e.pts[2 * seg + 3];
    final len = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
    if (seg < last && d > acc + len) {
      acc += len;
      continue;
    }
    final f = len > 0 ? ((d - acc) / len).clamp(0.0, 1.0) : 0.0;
    return (
      x: ax + (bx - ax) * f,
      y: ay + (by - ay) * f,
      ux: len > 0 ? (bx - ax) / len : 1.0,
      uy: len > 0 ? (by - ay) / len : 0.0,
    );
  }
  return (x: e.pts[0], y: e.pts[1], ux: 1.0, uy: 0.0);
}

/// The roadblock spot [aheadM] along the road in front of the player at ([x], [y]) facing [heading]
/// in [layer] (specs/roadblock.md "Kde"), or null when the attempt gives up: no kept edge of the
/// player's layer within [searchM], a border node (−1), a U-turn at a dead end (`chooseToward`
/// returns the arrival edge) or a spot edge off the ground. Same rules as web/src/police/roadblock.ts.
RoadblockSpot? roadblockSpot(
  RoadGraph g,
  double x,
  double y,
  double heading,
  int layer,
  double searchM,
  double aheadM,
  double probeM,
) {
  EdgeHit? hit;
  for (final h in g.near(x, y, searchM)) {
    if (!h.edge.kept || h.edge.layerAt(h.t) != layer) continue;
    if (hit == null || h.dist < hit.dist) hit = h;
  }
  if (hit == null) return null;
  final hc = math.cos(heading), hs = math.sin(heading);
  final gx = x + probeM * hc, gy = y + probeM * hs;
  var e = hit.edge;
  var dir = hit.dirX * hc + hit.dirY * hs >= 0 ? 1 : -1;
  var d = hit.t * e.length;
  var left = aheadM;
  // Every step moves to another node; the bound only guards against a malformed graph.
  for (var guard = 0; guard < 4096; guard++) {
    final rest = dir > 0 ? e.length - d : d;
    if (rest >= left) {
      if (!e.isGround) return null;
      final at = d + dir * left;
      final p = edgePointAt(e, at);
      return (edge: e.index, d: at, x: p.x, y: p.y, ux: p.ux, uy: p.uy);
    }
    left -= rest;
    final node = dir > 0 ? e.to : e.from;
    final next = chooseToward(g, node, e.index, gx, gy);
    if (next < 0 || next == e.index) return null;
    e = g.edges[next];
    dir = e.from == node ? 1 : -1;
    d = dir > 0 ? 0 : e.length;
  }
  return null;
}
