import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:shared_gen/citypack_pb.dart';
import 'package:shared_gen/shared_gen.dart';

import 'chunk.dart';
import 'chunk_window.dart';
import 'citypack.dart';
import 'model.dart';
import 'style_geometry.dart';

class LoadedChunk {
  LoadedChunk(this.data)
    : ground = {
        for (final g in data.ground) g.kind: ui.Vertices.raw(ui.VertexMode.triangles, g.xy, indices: g.indices),
      };

  final ChunkData data;
  final Map<GroundKind, ui.Vertices> ground;

  int get key => City.chunkKey(data.x, data.y);

  List<ui.Vertices>? _shadows;
  (double, double, double, double)? _shadowKey;

  /// Cast shadows of this chunk's buildings (specs/style.md v2), built on first use and kept
  /// until the parameters change; may reach into neighbouring chunks.
  List<ui.Vertices> shadows({required double dirX, required double dirY, required double ratio, required double maxM}) {
    final k = (dirX, dirY, ratio, maxM);
    final cached = _shadows;
    if (cached != null && _shadowKey == k) return cached;
    _disposeShadows();
    _shadowKey = k;
    return _shadows = [
      for (final m in buildShadowMeshes(data.buildings, dirX: dirX, dirY: dirY, ratio: ratio, maxM: maxM))
        ui.Vertices.raw(ui.VertexMode.triangles, m.xy, indices: m.indices),
    ];
  }

  void _disposeShadows() {
    for (final v in _shadows ?? const <ui.Vertices>[]) {
      v.dispose();
    }
    _shadows = null;
  }

  void dispose() {
    for (final v in ground.values) {
      v.dispose();
    }
    _disposeShadows();
  }
}

/// Loads the [ChunkWindow] around the player; decoding runs in an isolate on native platforms.
class ChunkStreamer {
  ChunkStreamer(this.city, this.source, this.tuning, {this.onLoaded, this.onUnloaded})
    : window = ChunkWindow(city, tuning);

  final City city;
  final PackSource source;
  final Tuning tuning;
  final ChunkWindow window;
  final void Function(LoadedChunk)? onLoaded;
  final void Function(LoadedChunk)? onUnloaded;

  final Map<int, LoadedChunk> loaded = {};
  final Set<int> _inFlight = {};
  final Map<int, DateTime> _failedAt = {};
  bool _disposed = false;

  Iterable<LoadedChunk> get chunks => loaded.values;

  List<(int, int)> wanted(double x, double y, double heading) => window.wanted(x, y, heading);

  /// Call every frame; schedules loads and drops chunks outside the keep ring.
  void update(double x, double y, double heading) {
    if (_disposed) return;
    final want = wanted(x, y, heading);
    for (final (cx, cy) in want) {
      final key = City.chunkKey(cx, cy);
      if (loaded.containsKey(key) || _inFlight.contains(key)) continue;
      final failed = _failedAt[key];
      if (failed != null && DateTime.now().difference(failed).inMilliseconds < tuning.streaming.retryS * 1000) {
        continue;
      }
      if (_inFlight.length >= tuning.streaming.maxInFlight) break;
      _load(cx, cy, key);
    }
    final drop = <int>[];
    loaded.forEach((key, c) {
      if (window.drop(c.data.x, c.data.y, x, y)) drop.add(key);
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
