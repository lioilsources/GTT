import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:shared_gen/shared_gen.dart';

import 'camera.dart';
import 'chunk.dart';
import 'extrusion.dart';
import 'model.dart';
import 'models.dart';
import 'palette.dart';
import 'package:shared_gen/citypack_pb.dart';
import 'roads.dart';
import 'streaming.dart';
import 'style_geometry.dart';
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

  /// Screen-space filter over the static world only (specs/style.md "Risograf"), null = none.
  ///
  /// Vehicles of layer 0 are drawn between the ground and the buildings, so the world is split in
  /// two offscreen layers that each get the filter: (a) paper, ground, roads; (b) buildings and
  /// bridges. Cars, peds, props and trams (drawDynamic) go between and after them unfiltered.
  /// The layers are opened in screen space (camera transform popped) so the filter's pixel
  /// coordinates are the device's, not world metres. The tunnel layer is left unfiltered.
  ui.ImageFilter? worldFilter;
  ui.ImageFilter? _layerFilter;
  ui.Paint? _layerPaint;
  final stats = RenderStats();
  final _batcher = BuildingBatcher();
  final _sw = Stopwatch();
  final _visible = <BuildingData>[];
  final _dist = <BuildingData, double>{};
  final _paint = ui.Paint()..isAntiAlias = false;
  final _shadowLayer = ui.Paint();
  final _shadowFill = ui.Paint()..isAntiAlias = false;

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
    final filter = worldFilter;
    final screen = ui.Offset.zero & size;
    if (!identical(filter, _layerFilter)) {
      _layerFilter = filter;
      _layerPaint = filter == null ? null : (ui.Paint()..imageFilter = filter);
    }
    final layerPaint = _layerPaint;
    if (layerPaint != null) canvas.saveLayer(screen, layerPaint);
    canvas.drawRect(screen, _paint..color = pal.land);
    canvas.save();
    cam.apply(canvas, size, tuning);
    // Closes the current filtered layer and/or opens a new one, keeping the camera transform.
    void layer({required bool close, required bool open}) {
      if (layerPaint == null) return;
      canvas.restore(); // camera
      if (close) canvas.restore(); // filtered layer
      if (open) canvas.saveLayer(screen, layerPaint);
      canvas.save();
      cam.apply(canvas, size, tuning);
    }

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
    // 2. roads, markings, alleys, zebras
    _roadPasses(canvas, roadKeys, groundPasses);
    // 2b. building cast shadows (specs/style.md v2) above the road paint, below everything else
    _castShadows(canvas, vx, vy, r);
    _roadblocks(canvas, vx, vy, r);
    layer(close: true, open: false);
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
    layer(close: false, open: true);
    _sw
      ..reset()
      ..start();
    _visible.clear();
    _dist.clear();
    for (final c in chunks) {
      for (final b in c.data.buildings) {
        if (!c.shows(b)) continue;
        final dx = b.cx - vx, dy = b.cy - vy;
        final d = math.sqrt(dx * dx + dy * dy);
        if (d - b.radius > r) continue;
        _visible.add(b);
        // Stacked parts draw after what they stand on.
        _dist[b] = d - b.minHeight * 0.3;
      }
    }
    // Landmark roof plans (specs/models.md "Pohled shora") instead of the buildings they replace:
    // one unit at the plan's centre, its polygons by height_m (sorted in prepareModels).
    for (final m in _models) {
      final dx = m.cx - vx, dy = m.cy - vy;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d - m.radius > r) continue;
      for (var k = 0; k < m.plan.length; k++) {
        final b = m.plan[k];
        _visible.add(b);
        _dist[b] = d - k * 1e-4;
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
    layer(close: true, open: false);
    drawDynamic(canvas, 1);
    canvas.restore();
  }

  /// Shadows are drawn opaque into their own layer that is composited once with the shadow
  /// alpha, so overlapping shadows give one uniform shade. The meshes are built once per chunk.
  void _castShadows(ui.Canvas canvas, double vx, double vy, double r) {
    final pal = palette;
    final color = pal.castShadow;
    if (color == null || !castShadowOn(tuning.style, city.id, night: pal.night)) return;
    final (dx, dy) = shadowDirection(pal.sunX, pal.sunY);
    final st = tuning.style;
    final cm = city.chunkM;
    // A shadow is drawn with its building's chunk, so look up to one shadow length further.
    final reach = r + st.shadowMaxM;
    var open = false;
    for (final c in streamer.chunks) {
      final x0 = c.data.x * cm, y0 = c.data.y * cm;
      final ex = math.max(0.0, math.max(x0 - vx, vx - (x0 + cm)));
      final ey = math.max(0.0, math.max(y0 - vy, vy - (y0 + cm)));
      if (ex * ex + ey * ey > reach * reach) continue;
      final meshes = c.shadows(dirX: dx, dirY: dy, ratio: st.shadowRatio, maxM: st.shadowMaxM);
      if (meshes.isEmpty) continue;
      if (!open) {
        canvas.saveLayer(null, _shadowLayer..color = ui.Color.fromARGB((color.a * 255).round(), 0, 0, 0));
        _shadowFill.color = color.withValues(alpha: 1);
        open = true;
      }
      for (final v in meshes) {
        canvas.drawVertices(v, ui.BlendMode.dst, _shadowFill);
      }
    }
    // Roof plans cast the shadows of the buildings they hide (prisms up to height_m).
    final shadowKey = (dx, dy, st.shadowRatio, st.shadowMaxM);
    for (final m in _models) {
      final ex = m.cx - vx, ey = m.cy - vy;
      final far = reach + m.radius;
      if (ex * ex + ey * ey > far * far) continue;
      final meshes = _planShadows(m, shadowKey);
      if (meshes.isEmpty) continue;
      if (!open) {
        canvas.saveLayer(null, _shadowLayer..color = ui.Color.fromARGB((color.a * 255).round(), 0, 0, 0));
        _shadowFill.color = color.withValues(alpha: 1);
        open = true;
      }
      for (final v in meshes) {
        canvas.drawVertices(v, ui.BlendMode.dst, _shadowFill);
      }
    }
    if (open) canvas.restore();
  }

  /// Landmark models drawn as roof plans; none with `models.enabled` off.
  List<ModelData> get _models => tuning.models.enabled ? city.models : const [];

  final _planShadowCache = <ModelData, ((double, double, double, double), List<ui.Vertices>)>{};

  List<ui.Vertices> _planShadows(ModelData m, (double, double, double, double) key) {
    final hit = _planShadowCache[m];
    if (hit != null && hit.$1 == key) return hit.$2;
    for (final v in hit?.$2 ?? const <ui.Vertices>[]) {
      v.dispose();
    }
    final (dx, dy, ratio, maxM) = key;
    final out = [
      for (final t in buildShadowMeshes(m.plan, dirX: dx, dirY: dy, ratio: ratio, maxM: maxM))
        ui.Vertices.raw(ui.VertexMode.triangles, t.xy, indices: t.indices),
    ];
    _planShadowCache[m] = (key, out);
    return out;
  }

  void _roadPasses(ui.Canvas canvas, List<int> keys, List<RoadPass> passes) {
    for (final p in passes) {
      if (p == RoadPass.crosswalks && palette.night) continue;
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
          _paint.color = i.isEven
              ? const ui.Color(Tokens.colorWorldRoadblockA)
              : const ui.Color(Tokens.colorWorldRoadblockB);
          canvas.drawRect(ui.Rect.fromLTWH(1, -hw + i * 2 * hw / stripes, 2.5, 2 * hw / stripes), _paint);
        }
        canvas.restore();
      }
    }
  }
}
