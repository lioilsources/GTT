import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'chunk.dart';
import 'citypack.dart';
import 'model.dart';
import 'pb/citypack.pbenum.dart';

class LoadedChunk {
  LoadedChunk(this.data)
      : ground = {
          for (final g in data.ground)
            g.kind: ui.Vertices.raw(ui.VertexMode.triangles, g.xy, indices: g.indices),
        };

  final ChunkData data;
  final Map<GroundKind, ui.Vertices> ground;

  int get key => City.chunkKey(data.x, data.y);

  void dispose() {
    for (final v in ground.values) {
      v.dispose();
    }
  }
}

/// Keeps a 3×5 window of chunks loaded around the player, stretched in the driving
/// direction (METROPOLE_PLAN 6.4). Decoding runs in an isolate on native platforms.
class ChunkStreamer {
  ChunkStreamer(this.city, this.source, {this.onLoaded, this.onUnloaded, this.maxInFlight = 2});

  final City city;
  final PackSource source;
  final void Function(LoadedChunk)? onLoaded;
  final void Function(LoadedChunk)? onUnloaded;
  final int maxInFlight;

  final Map<int, LoadedChunk> loaded = {};
  final Set<int> _inFlight = {};
  final Map<int, DateTime> _failedAt = {};
  bool _disposed = false;

  /// Chunks whose last load failed are retried after this pause.
  static const retryAfter = Duration(seconds: 2);

  Iterable<LoadedChunk> get chunks => loaded.values;

  /// Chunk keys wanted for a player at (x, y) heading [heading] (radians, 0 = east), nearest first.
  List<(int, int)> wanted(double x, double y, double heading) {
    final cm = city.chunkM;
    final fx = math.cos(heading), fy = math.sin(heading);
    final out = <(int, int)>[];
    final seen = <int>{};
    void add(double px, double py) {
      final cx = (px / cm).floor(), cy = (py / cm).floor();
      if (city.hasChunk(cx, cy) && seen.add(City.chunkKey(cx, cy))) out.add((cx, cy));
    }

    // Own chunk and its ring first, so a sharp turn never shows an empty street.
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        add(x + dx * cm, y + dy * cm);
      }
    }
    for (var j = -1; j <= 3; j++) {
      for (var i = -1; i <= 1; i++) {
        add(x + (fx * j - fy * i) * cm, y + (fy * j + fx * i) * cm);
      }
    }
    return out;
  }

  /// Call every frame; schedules loads and drops chunks outside a 5×5 keep-ring.
  void update(double x, double y, double heading) {
    if (_disposed) return;
    final want = wanted(x, y, heading);
    for (final (cx, cy) in want) {
      final key = City.chunkKey(cx, cy);
      if (loaded.containsKey(key) || _inFlight.contains(key)) continue;
      final failed = _failedAt[key];
      if (failed != null && DateTime.now().difference(failed) < retryAfter) continue;
      if (_inFlight.length >= maxInFlight) break;
      _load(cx, cy, key);
    }
    final cm = city.chunkM;
    final px = (x / cm).floor(), py = (y / cm).floor();
    final drop = <int>[];
    loaded.forEach((key, c) {
      if ((c.data.x - px).abs() > 3 || (c.data.y - py).abs() > 3) drop.add(key);
    });
    for (final key in drop) {
      final c = loaded.remove(key)!;
      onUnloaded?.call(c);
      c.dispose();
    }
  }

  /// Loads everything [wanted] needs and waits for it (start-up, teleports).
  Future<void> preload(double x, double y, double heading) async {
    await Future.wait([
      for (final (cx, cy) in wanted(x, y, heading))
        if (!loaded.containsKey(City.chunkKey(cx, cy))) _load(cx, cy, City.chunkKey(cx, cy)),
    ]);
  }

  Future<void> _load(int cx, int cy, int key) async {
    _inFlight.add(key);
    try {
      final bytes = await source.read(chunkPath(cx, cy));
      final data = await compute(prepareChunk, bytes, debugLabel: 'chunk $cx,$cy');
      if (_disposed || loaded.containsKey(key)) return;
      final c = LoadedChunk(data);
      loaded[key] = c;
      _failedAt.remove(key);
      onLoaded?.call(c);
    } catch (e) {
      // A missing or broken chunk must not stop the drive; update() retries it later.
      _failedAt[key] = DateTime.now();
      debugPrint('chunk $cx,$cy failed to load: $e');
    } finally {
      _inFlight.remove(key);
    }
  }

  void dispose() {
    _disposed = true;
    for (final c in loaded.values) {
      onUnloaded?.call(c);
      c.dispose();
    }
    loaded.clear();
  }
}
