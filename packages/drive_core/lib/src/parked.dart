import 'dart:math' as math;

import 'package:rules_core/rules_core.dart' show Prng;
import 'package:world_engine/core.dart';

import 'traffic/traffic.dart' show ParkedPose;

/// A parked car at a curb (specs/cars.md "Zaparkovaná auta"). The fleet keeps the pose in sync with
/// its dynamic body (it can be pushed) and fills the half extents.
class ParkedCar implements ParkedPose {
  ParkedCar({
    required this.carId,
    required this.owner,
    required this.x,
    required this.y,
    required this.heading,
    this.chunk,
  });

  final String carId;

  /// "player" or "npc".
  final String owner;
  @override
  double x, y, heading;

  /// Half length and width in metres (after car_scale); set by the fleet.
  @override
  double? hl, hw;

  /// Chunk key it was generated for; null for a car the player left behind (kept until forget_m).
  final int? chunk;

  @override
  String toString() => 'ParkedCar($carId, $owner, ${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

/// Models that park in [cityId]: `cars.parked.models` in list order, only cars whose `tags` contain
/// the city id (specs/cars.md "Zaparkovaná auta"). Unknown models are skipped.
List<String> parkedModels(Tuning tuning, Map<String, CarSpec> specs, String cityId) => [
  for (final id in tuning.cars.parked.models)
    if (specs[id]?.tags.contains(cityId) ?? false) id,
];

/// Places parked cars for chunk (cx, cy) of city [cityId] with the shared PRNG; every attempt draws
/// four numbers (segment, position, side, model) so both clients consume the stream identically.
/// [leftHand] (manifest `driveSide == 'left'`, specs/cities.md v2) mirrors the heading: a car left of
/// the segment direction faces along it, one on the right +π. Port of web/src/cars/parked.ts.
List<ParkedCar> generateParked(
  RoadGraph graph,
  int cx,
  int cy,
  int chunk,
  Tuning tuning,
  Map<String, CarSpec> specs,
  List<({double x, double y})> avoid,
  ({double x, double y}) player, {
  required String cityId,
  bool leftHand = false,
}) {
  final t = tuning.cars.parked;
  final models = parkedModels(tuning, specs, cityId);
  final chunkM = tuning.chunkM.toDouble();
  final x0 = cx * chunkM, y0 = cy * chunkM;
  final segs = <(double, double, double, double, double, double)>[]; // ax, ay, dx, dy, l, width
  for (final e in graph.edges) {
    if (!e.kept || !e.isGround || e.bridge || !t.classes.contains(e.roadClass.value)) continue;
    for (var s = 0; s + 1 < e.pointCount; s++) {
      final ax = e.pts[2 * s].toDouble(), ay = e.pts[2 * s + 1].toDouble();
      final bx = e.pts[2 * s + 2].toDouble(), by = e.pts[2 * s + 3].toDouble();
      final mx = (ax + bx) / 2, my = (ay + by) / 2;
      if (mx < x0 || mx >= x0 + chunkM || my < y0 || my >= y0 + chunkM) continue;
      final dx = bx - ax, dy = by - ay;
      final l = math.sqrt(dx * dx + dy * dy);
      if (l <= 2 * t.segmentMarginM) continue;
      segs.add((ax, ay, dx / l, dy / l, l, e.width));
    }
  }
  final out = <ParkedCar>[];
  if (segs.isEmpty || models.isEmpty) return out;
  const mask = 0xFFFFFFFF;
  final rnd = Prng(((cx * 73856093) & mask) ^ ((cy * 19349663) & mask) ^ (t.salt & mask));
  bool far(double x, double y, double px, double py, double d) => (x - px) * (x - px) + (y - py) * (y - py) >= d * d;
  for (var i = 0; i < t.attempts && out.length < t.perChunk; i++) {
    final seg = segs[rnd.nextInt(segs.length)];
    final along = rnd.nextInt(1000);
    final side = rnd.nextInt(2);
    final model = models[rnd.nextInt(models.length)];
    final spec = specs[model]!;
    final (ax, ay, dx, dy, l, width) = seg;
    final hw = spec.widthM * tuning.carScale / 2;
    final offset = width / 2 - tuning.sidewalkWidthM - hw - t.curbGapM;
    if (offset - hw < t.minInnerM) continue;
    final d = t.segmentMarginM + (l - 2 * t.segmentMarginM) * along / 1000;
    // Right of the segment direction is the normal (dy, -dx).
    final sgn = side == 0 ? 1.0 : -1.0;
    final x = ax + dx * d + dy * offset * sgn;
    final y = ay + dy * d - dx * offset * sgn;
    if (!out.every((p) => far(x, y, p.x, p.y, t.minSpacingM)) ||
        !avoid.every((p) => far(x, y, p.x, p.y, t.minSpacingM))) {
      continue;
    }
    if (!far(x, y, player.x, player.y, t.clearPlayerM)) continue;
    // Cars face along their lane: right side along the segment, left +π; mirrored for left-hand.
    final withSeg = (side == 0) != leftHand;
    final heading = math.atan2(dy, dx) + (withSeg ? 0 : math.pi);
    out.add(ParkedCar(carId: model, owner: 'npc', x: x, y: y, heading: heading, chunk: chunk));
  }
  return out;
}

/// Nearest parked car whose centre is within [maxDist] of (x, y), or null.
ParkedCar? boardCandidate(Iterable<ParkedCar> cars, double x, double y, double maxDist) {
  ParkedCar? best;
  var bd = maxDist * maxDist;
  for (final p in cars) {
    final d = (p.x - x) * (p.x - x) + (p.y - y) * (p.y - y);
    if (d <= bd) {
      bd = d;
      best = p;
    }
  }
  return best;
}
