import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:shared_gen/shared_gen.dart';

import 'camera.dart';
import 'chunk.dart';
import 'extrusion.dart';
import 'model.dart';
import 'palette.dart';
import 'package:shared_gen/citypack_pb.dart';
import 'roads.dart';
import 'streaming.dart';
import 'textures.dart';

/// Per-frame numbers for the FPS overlay.
class RenderStats {
  int buildings = 0;
  int drawCalls = 0;
  int chunks = 0;

  /// Time spent filling the building buffer, microseconds (budget ≤ 4 ms, plan 6.5).
  int buildingPrepMicros = 0;
}

/// Draws the world in the order of METROPOLE_PLAN 6.3.
///
/// [drawDynamic] is called with the world transform applied, once per layer (−1, 0, +1),
/// at the point where vehicles and props of that layer belong.
class WorldRenderer {
  WorldRenderer({
    required this.city,
    required this.roads,
    required this.streamer,
    required this.tuning,
    required this.textures,
  });

  final City city;
  RoadMeshes roads;
  final ChunkStreamer streamer;
  final Tuning tuning;
  final FacadeTextures textures;
  Palette palette = Palette.day;
  final stats = RenderStats();
  final _batcher = BuildingBatcher();
  final _sw = Stopwatch();
  final _visible = <BuildingData>[];
  final _dist = <BuildingData, double>{};
  final _paint = ui.Paint()..isAntiAlias = false;

  // Pedestrian paving last: above parks and plazas (and water, for bridges), below roads.
  static const _groundOrder = [
    GroundKind.PARK,
    GroundKind.PLAZA,
    GroundKind.RAIL,
    GroundKind.WATER,
    GroundKind.PEDESTRIAN,
  ];

  void render(
    ui.Canvas canvas,
    ui.Size size,
    CameraRig cam, {
    required int playerLayer,
    required void Function(ui.Canvas canvas, int layer) drawDynamic,
  }) {
    final pal = palette;
    canvas.drawRect(ui.Offset.zero & size, _paint..color = pal.land);
    canvas.save();
    cam.apply(canvas, size, tuning);
    final r = cam.visibleRadius(size, tuning);
    final vx = cam.x, vy = cam.y;
    final cm = city.chunkM;

    final chunks = <LoadedChunk>[];
    for (final c in streamer.chunks) {
      final x0 = c.data.x * cm, y0 = c.data.y * cm;
      final dx = math.max(0.0, math.max(x0 - vx, vx - (x0 + cm)));
      final dy = math.max(0.0, math.max(y0 - vy, vy - (y0 + cm)));
      if (dx * dx + dy * dy <= r * r) chunks.add(c);
    }
    stats.chunks = chunks.length;
    final roadKeys = <int>[];
    for (var cx = ((vx - r) / cm).floor(); cx <= ((vx + r) / cm).floor(); cx++) {
      for (var cy = ((vy - r) / cm).floor(); cy <= ((vy + r) / cm).floor(); cy++) {
        roadKeys.add(City.chunkKey(cx, cy));
      }
    }

    // 1. ground, water, parks
    for (final kind in _groundOrder) {
      _paint.color = pal.ground(kind);
      for (final c in chunks) {
        final v = c.ground[kind];
        if (v != null) canvas.drawVertices(v, ui.BlendMode.dst, _paint);
      }
    }
    // 2. roads, markings, alleys
    _roadPasses(canvas, roadKeys, groundPasses);
    _roadblocks(canvas, vx, vy, r);
    // 4. props and vehicles on the ground
    drawDynamic(canvas, 0);
    // 3. tunnel layer, only while the player is inside (the ceiling is hidden)
    final inTunnel = playerLayer < 0;
    if (inTunnel) {
      canvas.drawPaint(_paint..color = const ui.Color(Tokens.colorWorldTunnelShade));
      _roadPasses(canvas, roadKeys, tunnelPasses);
      drawDynamic(canvas, -1);
    }
    // 5. buildings, far to near from the vanishing point
    _sw
      ..reset()
      ..start();
    _visible.clear();
    _dist.clear();
    for (final c in chunks) {
      for (final b in c.data.buildings) {
        final dx = b.cx - vx, dy = b.cy - vy;
        final d = math.sqrt(dx * dx + dy * dy);
        if (d - b.radius > r) continue;
        _visible.add(b);
        // Stacked parts draw after what they stand on.
        _dist[b] = d - b.minHeight * 0.3;
      }
    }
    _visible.sort((a, b) => _dist[b]!.compareTo(_dist[a]!));
    final texPaint = pal.night ? textures.nightPaint : textures.dayPaint;
    _batcher.begin();
    final alpha = inTunnel ? 90 : 255;
    for (final b in _visible) {
      _batcher.add(canvas, texPaint, b, vx, vy, pal, tuning, alpha: alpha);
    }
    _batcher.flush(canvas, texPaint);
    _sw.stop();
    stats
      ..buildings = _batcher.buildingsDrawn
      ..drawCalls = _batcher.drawCalls
      ..buildingPrepMicros = _sw.elapsedMicroseconds;
    // 6. bridges and overpasses, then whatever drives on them
    _roadPasses(canvas, roadKeys, bridgePasses);
    drawDynamic(canvas, 1);
    canvas.restore();
  }

  void _roadPasses(ui.Canvas canvas, List<int> keys, List<RoadPass> passes) {
    for (final p in passes) {
      _paint.color = passColor(p, palette);
      for (final k in keys) {
        final v = roads.chunk(k)?[p];
        if (v != null) canvas.drawVertices(v, ui.BlendMode.dst, _paint);
      }
    }
  }

  /// Striped barriers where a road leaves the playable area.
  void _roadblocks(ui.Canvas canvas, double vx, double vy, double r) {
    final g = city.graph;
    for (var n = 0; n < g.border.length; n++) {
      if (!g.border[n]) continue;
      final x = g.nodeXY[2 * n], y = g.nodeXY[2 * n + 1];
      if ((x - vx).abs() > r || (y - vy).abs() > r) continue;
      for (final ei in g.nodeEdges[n]) {
        final e = g.edges[ei];
        final atEnd = e.to == n;
        final k = atEnd ? e.pointCount - 2 : 1;
        final dx = e.pts[2 * k] - x, dy = e.pts[2 * k + 1] - y;
        final ang = math.atan2(dy, dx);
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(ang);
        final hw = e.width / 2;
        const stripes = 8;
        for (var i = 0; i < stripes; i++) {
          _paint.color = i.isEven ? const ui.Color(Tokens.colorWorldRoadblockA) : const ui.Color(Tokens.colorWorldRoadblockB);
          canvas.drawRect(ui.Rect.fromLTWH(1, -hw + i * 2 * hw / stripes, 2.5, 2 * hw / stripes), _paint);
        }
        canvas.restore();
      }
    }
  }
}
