import 'dart:math' as math;

import 'model.dart';
import 'tuning.dart';

/// Which chunks to keep loaded around the player (METROPOLE_PLAN 6.4). Pure logic.
///
/// The window is `side` chunks to each side, `behind` back and `ahead` forward along the
/// driving direction, plus the 3×3 ring around the player's own chunk.
class ChunkWindow {
  ChunkWindow(this.city, this.tuning);
  final City city;
  final Tuning tuning;

  /// Chunks wanted for a player at (x, y) heading [heading] (radians, 0 = east); own chunk first.
  List<(int, int)> wanted(double x, double y, double heading) {
    final cm = city.chunkM;
    final s = tuning.streaming;
    final fx = math.cos(heading), fy = math.sin(heading);
    final out = <(int, int)>[];
    final seen = <int>{};
    void add(double px, double py) {
      final cx = (px / cm).floor(), cy = (py / cm).floor();
      if (city.hasChunk(cx, cy) && seen.add(City.chunkKey(cx, cy))) out.add((cx, cy));
    }

    add(x, y);
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        add(x + dx * cm, y + dy * cm);
      }
    }
    for (var j = -s.behind; j <= s.ahead; j++) {
      for (var i = -s.side; i <= s.side; i++) {
        add(x + (fx * j - fy * i) * cm, y + (fy * j + fx * i) * cm);
      }
    }
    return out;
  }

  /// True when chunk (cx, cy) is outside the keep ring around (x, y) and can be dropped.
  bool drop(int cx, int cy, double x, double y) {
    final cm = city.chunkM;
    final k = tuning.streaming.keep;
    return (cx - (x / cm).floor()).abs() > k || (cy - (y / cm).floor()).abs() > k;
  }
}
