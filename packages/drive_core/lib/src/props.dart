import 'dart:math' as math;
import 'dart:ui';

import 'package:world_engine/world_engine.dart';

enum PropKind { lamp, hydrant, bin, newsbox, planter }

/// Street furniture: generated per chunk from its seed, never stored (METROPOLE_PLAN 6.4).
/// Props are not physics bodies; the car knocks them over by an overlap test, and they
/// come back after [respawnSeconds].
class Prop {
  Prop(this.kind, this.x, this.y, this.radius, this.angle);
  final PropKind kind;
  final double x;
  final double y;
  final double radius;
  final double angle;

  bool knocked = false;
  double knockedAt = 0;
  double ox = 0, oy = 0; // offset while flying
  double vx = 0, vy = 0;
  double spin = 0;
  double rot = 0;
}

class PropSet {
  PropSet(this.chunkKey, this.props);
  final int chunkKey;
  final List<Prop> props;
}

const double respawnSeconds = 25;

/// Places props along the sidewalks of kept ground roads whose segments lie in the chunk.
PropSet generateProps(RoadGraph graph, int cx, int cy, double chunkM, double sidewalkM, double scale) {
  final rnd = math.Random(cx * 73856093 ^ cy * 19349663);
  final props = <Prop>[];
  final x0 = cx * chunkM, y0 = cy * chunkM;
  for (final e in graph.edges) {
    if (!e.kept || !e.isGround || e.bridge) continue;
    final offset = e.width / 2 - sidewalkM / 2;
    if (offset <= 1) continue;
    var along = 0.0;
    for (var s = 0; s + 1 < e.pointCount; s++) {
      final ax = e.pts[2 * s], ay = e.pts[2 * s + 1], bx = e.pts[2 * s + 2], by = e.pts[2 * s + 3];
      final mx = (ax + bx) / 2, my = (ay + by) / 2;
      final dx = bx - ax, dy = by - ay;
      final l = math.sqrt(dx * dx + dy * dy);
      if (mx < x0 || mx >= x0 + chunkM || my < y0 || my >= y0 + chunkM || l < 1) {
        along += l;
        continue;
      }
      final nx = -dy / l, ny = dx / l;
      for (var t = 14.0; t < l - 14; t += 20 + rnd.nextDouble() * 10) {
        // Keep intersections clear.
        if (along + t < 16 || e.length - (along + t) < 16) continue;
        for (final side in const [-1.0, 1.0]) {
          if (rnd.nextDouble() < 0.35) continue;
          final r = rnd.nextDouble();
          final kind = r < 0.38
              ? PropKind.lamp
              : r < 0.55
                  ? PropKind.hydrant
                  : r < 0.8
                      ? PropKind.bin
                      : r < 0.9
                          ? PropKind.newsbox
                          : PropKind.planter;
          final base = switch (kind) {
            PropKind.lamp => 0.25,
            PropKind.hydrant => 0.25,
            PropKind.bin => 0.35,
            PropKind.newsbox => 0.4,
            PropKind.planter => 0.6,
          };
          props.add(Prop(kind, ax + dx * t / l + nx * offset * side, ay + dy * t / l + ny * offset * side,
              base * scale, math.atan2(dy, dx)));
        }
      }
      along += l;
    }
  }
  return PropSet(City.chunkKey(cx, cy), props);
}

/// Draws props in world space (canvas already transformed to metres).
void paintProps(Canvas canvas, Iterable<Prop> props, {required bool night, required double scale}) {
  final p = Paint();
  for (final o in props) {
    canvas.save();
    canvas.translate(o.x + o.ox, o.y + o.oy);
    canvas.rotate(o.angle + o.rot);
    final r = o.radius;
    final a = o.knocked ? 0.75 : 1.0;
    switch (o.kind) {
      case PropKind.lamp:
        if (night && !o.knocked) {
          p.color = const Color(0x40FFE9A8);
          canvas.drawCircle(Offset.zero, 2.6 * scale, p);
        }
        p.color = Color.fromRGBO(60, 64, 72, a);
        if (o.knocked) {
          canvas.drawRect(Rect.fromLTWH(0, -r * 0.5, 1.8 * scale, r), p);
        } else {
          canvas.drawCircle(Offset.zero, r, p);
          p.color = const Color(0xFFFFF3C4);
          canvas.drawCircle(Offset.zero, r * 0.5, p);
        }
      case PropKind.hydrant:
        p.color = Color.fromRGBO(200, 40, 40, a);
        canvas.drawCircle(Offset.zero, r, p);
      case PropKind.bin:
        p.color = Color.fromRGBO(46, 110, 64, a);
        canvas.drawCircle(Offset.zero, r, p);
        p.color = Color.fromRGBO(30, 70, 40, a);
        canvas.drawCircle(Offset.zero, r * 0.6, p);
      case PropKind.newsbox:
        p.color = Color.fromRGBO(40, 90, 170, a);
        canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: r * 1.6, height: r * 1.2), p);
      case PropKind.planter:
        p.color = Color.fromRGBO(120, 96, 80, a);
        canvas.drawCircle(Offset.zero, r, p);
        p.color = Color.fromRGBO(70, 140, 70, a);
        canvas.drawCircle(Offset.zero, r * 0.75, p);
    }
    canvas.restore();
  }
}
