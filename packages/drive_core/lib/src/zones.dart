import 'dart:math' as math;
import 'dart:typed_data';

import 'package:forge2d/forge2d.dart';
import 'package:world_engine/core.dart';

import 'car.dart';

/// Whether (x, y) lies in a triangle of the mesh [xy] / [indices] (edges count as inside).
bool pointInMesh(Float32List xy, Uint16List indices, double x, double y) {
  for (var i = 0; i + 2 < indices.length; i += 3) {
    final a = indices[i], b = indices[i + 1], c = indices[i + 2];
    final ax = xy[2 * a], ay = xy[2 * a + 1];
    final bx = xy[2 * b], by = xy[2 * b + 1];
    final cx = xy[2 * c], cy = xy[2 * c + 1];
    if (x < math.min(ax, math.min(bx, cx)) || x > math.max(ax, math.max(bx, cx))) continue;
    if (y < math.min(ay, math.min(by, cy)) || y > math.max(ay, math.max(by, cy))) continue;
    final d1 = (bx - ax) * (y - ay) - (by - ay) * (x - ax);
    final d2 = (cx - bx) * (y - by) - (cy - by) * (x - bx);
    final d3 = (ax - cx) * (y - cy) - (ay - cy) * (x - cx);
    final neg = d1 < 0 || d2 < 0 || d3 < 0, pos = d1 > 0 || d2 > 0 || d3 > 0;
    if (!(neg && pos)) return true;
  }
  return false;
}

/// Bollard centres along [line] (interleaved x, y): one every [spacing] metres from the start,
/// plus the end point when the last gap would be longer than half a spacing.
Float32List bollardsAlong(Float32List line, double spacing) {
  final out = <double>[];
  if (line.length < 4 || spacing <= 0) return Float32List(0);
  out
    ..add(line[0])
    ..add(line[1]);
  var next = spacing; // distance from the start of the line to the next bollard
  var walked = 0.0;
  for (var i = 0; i + 3 < line.length; i += 2) {
    final x0 = line[i], y0 = line[i + 1], x1 = line[i + 2], y1 = line[i + 3];
    final len = math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
    while (len > 0 && next <= walked + len) {
      final f = (next - walked) / len;
      out
        ..add(x0 + (x1 - x0) * f)
        ..add(y0 + (y1 - y0) * f);
      next += spacing;
    }
    walked += len;
  }
  if (walked - (next - spacing) > spacing / 2) {
    out
      ..add(line[line.length - 2])
      ..add(line[line.length - 1]);
  }
  return Float32List.fromList(out);
}

class _ZoneChunk {
  _ZoneChunk(this.body, this.meshes, this.bollards, this.barriers);
  final Body? body;
  final List<GroundData> meshes;
  final Float32List bollards;
  final List<Float32List> barriers;
  double minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
}

/// Pedestrian zones of the loaded chunks (specs/zones.md): bollard colliders, the
/// inside-a-zone test for the player's mask, and bollard positions for drawing.
class Zones {
  Zones(this.world, this.tuning);

  final World world;
  final Tuning tuning;
  final Map<int, _ZoneChunk> _chunks = {};

  /// Number of chunks that have bollard colliders.
  int get bodyCount => _chunks.values.where((c) => c.body != null).length;

  /// The static collider body of chunk (x, y), or null when it has no barriers or is not loaded.
  Body? bodyOf(int x, int y) => _chunks[City.chunkKey(x, y)]?.body;

  void add(ChunkData c) {
    final key = City.chunkKey(c.x, c.y);
    if (_chunks.containsKey(key)) return;
    final meshes = [
      for (final g in c.ground)
        if (g.kind == GroundKind.PEDESTRIAN && g.indices.isNotEmpty) g,
    ];
    if (meshes.isEmpty && c.barriers.isEmpty) return;
    Body? body;
    final bollards = <double>[];
    if (c.barriers.isNotEmpty) {
      final d = tuning.drive;
      body = world.createBody(BodyDef(type: BodyType.static));
      // Bollards stop the player's car only; traffic, parked cars and police ignore them.
      final def = ShapeDef(
        filter: Filter(categoryBits: catZone, maskBits: catCar),
        material: SurfaceMaterial(friction: d.buildingFriction, restitution: d.buildingRestitution),
      );
      for (final line in c.barriers) {
        // Separate segments: an open Box2D chain treats its first and last pieces as ghosts.
        for (var i = 0; i + 3 < line.length; i += 2) {
          final p1 = Vector2(line[i], line[i + 1]), p2 = Vector2(line[i + 2], line[i + 3]);
          if (p1.distanceToSquared(p2) < 1e-6) continue;
          body.createShape(Segment(point1: p1, point2: p2), def);
        }
        bollards.addAll(bollardsAlong(line, tuning.zones.bollardSpacingM));
      }
    }
    final z = _ZoneChunk(body, meshes, Float32List.fromList(bollards), c.barriers);
    for (final m in meshes) {
      for (var i = 0; i + 1 < m.xy.length; i += 2) {
        z
          ..minX = math.min(z.minX, m.xy[i])
          ..maxX = math.max(z.maxX, m.xy[i])
          ..minY = math.min(z.minY, m.xy[i + 1])
          ..maxY = math.max(z.maxY, m.xy[i + 1]);
      }
    }
    _chunks[key] = z;
  }

  void remove(ChunkData c) => _chunks.remove(City.chunkKey(c.x, c.y))?.body?.destroy();

  /// Whether (x, y) lies inside a loaded pedestrian zone (ground meshes are layer 0).
  bool contains(double x, double y) {
    for (final z in _chunks.values) {
      if (x < z.minX || x > z.maxX || y < z.minY || y > z.maxY) continue;
      for (final m in z.meshes) {
        if (pointInMesh(m.xy, m.indices, x, y)) return true;
      }
    }
    return false;
  }

  /// Whether a loaded bollard line passes within [radius] of (x, y).
  bool nearBarrier(double x, double y, double radius) {
    final r2 = radius * radius;
    for (final z in _chunks.values) {
      for (final line in z.barriers) {
        for (var i = 0; i + 3 < line.length; i += 2) {
          if (_segDist2(x, y, line[i], line[i + 1], line[i + 2], line[i + 3]) < r2) return true;
        }
      }
    }
    return false;
  }

  /// The inside-zone flag for [zoneMask] (specs/zones.md). Once the bollards are off the mask
  /// ([wasInside]), they stay off until the car of bounding [radius] has fully cleared the bollard
  /// line too: re-enabling them while the body still overlaps a barrier would trap it there.
  bool insideFor(double x, double y, double radius, {required bool wasInside}) =>
      contains(x, y) || (wasInside && nearBarrier(x, y, radius));

  static double _segDist2(double px, double py, double ax, double ay, double bx, double by) {
    final dx = bx - ax, dy = by - ay;
    final l2 = dx * dx + dy * dy;
    final t = l2 == 0 ? 0.0 : (((px - ax) * dx + (py - ay) * dy) / l2).clamp(0.0, 1.0);
    final ex = ax + dx * t - px, ey = ay + dy * t - py;
    return ex * ex + ey * ey;
  }

  /// Bollard centres (interleaved x, y) of each loaded chunk that has any.
  Iterable<Float32List> get bollards sync* {
    for (final z in _chunks.values) {
      if (z.bollards.isNotEmpty) yield z.bollards;
    }
  }

  void clear() {
    for (final z in _chunks.values) {
      z.body?.destroy();
    }
    _chunks.clear();
  }
}
