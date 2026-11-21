import 'dart:math' as math;

import 'package:world_engine/core.dart';

/// Kinds of street furniture; [name] is the key in `props.mix` and `props.radius_m`.
enum PropKind { lamp, hydrant, bin, newsbox, planter }

/// Street furniture: generated per chunk from its seed, never stored (METROPOLE_PLAN 6.4).
/// Props are not physics bodies; the car knocks them over by an overlap test, and they
/// come back after `props.respawn_s`.
class Prop {
  Prop(this.kind, this.x, this.y, this.radius, this.angle);
  final PropKind kind;
  final double x;
  final double y;
  final double radius;
  final double angle;

  bool knocked = false;
  double knockedAt = 0;
  double ox = 0, oy = 0; // offset while sliding
  double vx = 0, vy = 0;
  double spin = 0;
  double rot = 0;
}

class PropSet {
  PropSet(this.chunkKey, this.props);
  final int chunkKey;
  final List<Prop> props;
}

/// Places props along the sidewalks of kept ground roads whose segments lie in the chunk.
PropSet generateProps(RoadGraph graph, int cx, int cy, Tuning tuning) {
  final t = tuning.props;
  final chunkM = tuning.chunkM.toDouble();
  final rnd = math.Random(cx * 73856093 ^ cy * 19349663);
  final kinds = PropKind.values;
  final mixTotal = kinds.fold(0.0, (s, k) => s + (t.mix[k.name] ?? 0));
  PropKind pick() {
    var r = rnd.nextDouble() * mixTotal;
    for (final k in kinds) {
      r -= t.mix[k.name] ?? 0;
      if (r < 0) return k;
    }
    return kinds.last;
  }

  final props = <Prop>[];
  final x0 = cx * chunkM, y0 = cy * chunkM;
  for (final e in graph.edges) {
    if (!e.kept || !e.isGround || e.bridge) continue;
    final offset = e.width / 2 - tuning.sidewalkWidthM / 2;
    if (offset <= 0) continue;
    var along = 0.0;
    for (var s = 0; s + 1 < e.pointCount; s++) {
      final ax = e.pts[2 * s], ay = e.pts[2 * s + 1], bx = e.pts[2 * s + 2], by = e.pts[2 * s + 3];
      final mx = (ax + bx) / 2, my = (ay + by) / 2;
      final dx = bx - ax, dy = by - ay;
      final l = math.sqrt(dx * dx + dy * dy);
      if (mx < x0 || mx >= x0 + chunkM || my < y0 || my >= y0 + chunkM || l == 0) {
        along += l;
        continue;
      }
      final nx = -dy / l, ny = dx / l;
      for (var d = t.firstM; d < l - t.firstM; d += t.spacingM + rnd.nextDouble() * t.spacingJitterM) {
        if (along + d < t.clearIntersectionM || e.length - (along + d) < t.clearIntersectionM) continue;
        for (final side in const [-1.0, 1.0]) {
          if (rnd.nextDouble() < t.skipChance) continue;
          final kind = pick();
          final r = t.radiusM[kind.name];
          if (r == null) throw FormatException('tuning.yaml: props.radius_m.${kind.name} missing');
          props.add(Prop(kind, ax + dx * d / l + nx * offset * side, ay + dy * d / l + ny * offset * side,
              r * tuning.carScale, math.atan2(dy, dx)));
        }
      }
      along += l;
    }
  }
  return PropSet(City.chunkKey(cx, cy), props);
}
