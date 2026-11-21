import 'dart:math' as math;
import 'dart:typed_data';

import 'package:rules_core/rules_core.dart' show Prng;
import 'package:world_engine/core.dart';

import 'car.dart';

// Pedestrians (specs/pedestrians.md, version 1). Pure logic, no Flutter or dart:ui. They walk the
// sidewalks of kept ground edges and always dodge cars (R7): not physics bodies, the dodge is a
// pure function of the car pose and velocity. Port of web/src/peds/pedestrians.ts.

/// A car pedestrians dodge (player now, traffic later). Half sizes already include car_scale.
class CarPose {
  const CarPose({
    required this.x,
    required this.y,
    required this.heading,
    required this.halfLength,
    required this.halfWidth,
    required this.vx,
    required this.vy,
  });

  factory CarPose.of(Car car) {
    final v = car.body.linearVelocity;
    return CarPose(
      x: car.x,
      y: car.y,
      heading: car.heading,
      halfLength: car.halfLength,
      halfWidth: car.halfWidth,
      vx: v.x,
      vy: v.y,
    );
  }

  final double x, y, heading, halfLength, halfWidth, vx, vy;

  CarPose moved(double dx, double dy) =>
      CarPose(x: x + dx, y: y + dy, heading: heading, halfLength: halfLength, halfWidth: halfWidth, vx: vx, vy: vy);
}

/// A predicted contact: leap by (dx, dy) within [dur] seconds; contact in [tc] seconds.
class Dodge {
  const Dodge(this.tc, this.dx, this.dy, this.dur);
  final double tc, dx, dy, dur;
}

/// Threat test of specs/pedestrians.md "Uskočení": is the point (px, py) with body radius r in
/// the band the car's box sweeps over dodge_horizon_s? Returns the sideways leap out of the band.
Dodge? dodge(double px, double py, double r, CarPose car, TuningPedestrians t) {
  final v = math.sqrt(car.vx * car.vx + car.vy * car.vy);
  if (v < t.dodgeMinMps) return null;
  final ux = car.vx / v, uy = car.vy / v;
  final nx = -uy, ny = ux;
  final th = car.heading - math.atan2(car.vy, car.vx);
  final c = math.cos(th).abs(), s = math.sin(th).abs();
  final a = car.halfLength * c + car.halfWidth * s;
  final e = car.halfWidth * c + car.halfLength * s;
  final dx = px - car.x, dy = py - car.y;
  final along = dx * ux + dy * uy;
  final perp = dx * nx + dy * ny;
  final rr = r + t.dodgeMarginM;
  if (perp.abs() >= e + rr) return null;
  if (along <= -a - rr || along >= a + v * t.dodgeHorizonS + rr) return null;
  final tc = math.max(0.0, (along - a - rr) / v);
  final side = perp < 0 ? -1.0 : 1.0;
  final k = side * (e + rr + t.dodgeExtraM) - perp;
  return Dodge(tc, nx * k, ny * k, math.min(t.leapS, tc * t.leapFraction));
}

/// The soonest dodge over all cars, or null.
Dodge? dodgeAll(double px, double py, double r, List<CarPose> cars, TuningPedestrians t) {
  Dodge? best;
  for (final c in cars) {
    final d = dodge(px, py, r, c, t);
    if (d != null && (best == null || d.tc < best.tc)) best = d;
  }
  return best;
}

/// True when a circle (px, py, r) overlaps the car's oriented box.
bool overlapsBox(double px, double py, double r, CarPose car) {
  final cs = math.cos(car.heading), sn = math.sin(car.heading);
  final dx = px - car.x, dy = py - car.y;
  final lx = dx * cs + dy * sn, ly = -dx * sn + dy * cs;
  final qx = lx.clamp(-car.halfLength, car.halfLength), qy = ly.clamp(-car.halfWidth, car.halfWidth);
  final ex = lx - qx, ey = ly - qy;
  return ex * ex + ey * ey < r * r;
}

/// Moves a point straight out across the nearest side of the car's box to distance R.
({double x, double y}) pushOut(double px, double py, double rr, CarPose car) {
  final cs = math.cos(car.heading), sn = math.sin(car.heading);
  final dx = px - car.x, dy = py - car.y;
  var lx = dx * cs + dy * sn, ly = -dx * sn + dy * cs;
  final fx = car.halfLength + rr - lx.abs(), fy = car.halfWidth + rr - ly.abs();
  if (fx < fy) {
    lx = (lx < 0 ? -1 : 1) * (car.halfLength + rr);
  } else {
    ly = (ly < 0 ? -1 : 1) * (car.halfWidth + rr);
  }
  return (x: car.x + lx * cs - ly * sn, y: car.y + lx * sn + ly * cs);
}

enum PedMode { walk, cross, leap, stun, recover }

class Pedestrian {
  Pedestrian(this.id);
  final int id;

  /// Path: edge index, side (+1 = left of from → to), metres from `from`, walking direction.
  int edge = 0;
  int side = 1;
  double s = 0;
  int dir = 1;
  double speed = 1.4;
  PedMode mode = PedMode.walk;

  /// Mode to return to after a dodge (walk or cross).
  PedMode resume = PedMode.walk;

  /// Base point (on the path or the crossing line) and the offset from it.
  double bx = 0, by = 0, ox = 0, oy = 0;
  double x = 0, y = 0, heading = 0;

  /// Seconds left of the "!!" bubble.
  double bubble = 0;

  /// Leap from (lx0, ly0) to (lx1, ly1) offset over ldur; lt elapsed.
  double lx0 = 0, ly0 = 0, lx1 = 0, ly1 = 0, lt = 0, ldur = 0;

  /// Stun countdown.
  double timer = 0;

  /// Crossing line target.
  double cx1 = 0, cy1 = 0;
}

class PedStats {
  int clamps = 0;
  int dodges = 0;
}

bool _moving(PedMode m) => m == PedMode.walk || m == PedMode.cross;

/// One step of dodging for a pedestrian (steps 1–3 and 6 of "Průběh v kroku"). Returns true when
/// the base point may advance this step (walk, cross, or a blocked recover walking around).
bool stepAvoid(Pedestrian p, List<CarPose> cars, double r, double dt, TuningPedestrians t, PedStats stats) {
  p.bubble = math.max(0, p.bubble - dt);
  final leaping = p.mode == PedMode.leap;
  final tx = p.bx + (leaping ? p.lx1 : p.ox), ty = p.by + (leaping ? p.ly1 : p.oy);
  if (dodgeAll(tx, ty, r, cars, t) != null) {
    final d = dodgeAll(p.bx + p.ox, p.by + p.oy, r, cars, t);
    if (d != null) {
      if (_moving(p.mode)) p.resume = p.mode;
      stats.dodges++;
      p
        ..bubble = t.bubbleS
        ..lx0 = p.ox
        ..ly0 = p.oy
        ..lx1 = p.ox + d.dx
        ..ly1 = p.oy + d.dy
        ..lt = 0
        ..ldur = d.dur
        ..mode = PedMode.leap;
    }
  }
  switch (p.mode) {
    case PedMode.walk:
    case PedMode.cross:
      return true;
    case PedMode.leap:
      p.lt += dt;
      final k = p.ldur <= dt ? 1.0 : math.min(1.0, p.lt / p.ldur);
      p.ox = p.lx0 + (p.lx1 - p.lx0) * k;
      p.oy = p.ly0 + (p.ly1 - p.ly0) * k;
      if (k >= 1) {
        p.mode = PedMode.stun;
        p.timer = t.stunS;
      }
      return false;
    case PedMode.stun:
      p.timer -= dt;
      if (p.timer <= 0) p.mode = PedMode.recover;
      return false;
    case PedMode.recover:
      final len = math.sqrt(p.ox * p.ox + p.oy * p.oy);
      if (len == 0) {
        p.mode = p.resume;
        return true;
      }
      final step = math.min(p.speed * dt, len);
      final k = 1 - step / len;
      final nx = p.bx + p.ox * k, ny = p.by + p.oy * k;
      final rr = r + t.dodgeMarginM;
      if (dodgeAll(nx, ny, r, cars, t) != null || cars.any((c) => overlapsBox(nx, ny, rr, c))) return true;
      p.ox *= k;
      p.oy *= k;
      if (step >= len) {
        p.ox = p.oy = 0;
        p.mode = p.resume;
      }
      return false;
  }
}

/// Sets x, y from base + offset and applies the safety push-out (step 5).
void settle(Pedestrian p, List<CarPose> cars, double r, TuningPedestrians t, PedStats stats) {
  p.x = p.bx + p.ox;
  p.y = p.by + p.oy;
  for (final c in cars) {
    if (!overlapsBox(p.x, p.y, r, c)) continue;
    stats.clamps++;
    final q = pushOut(p.x, p.y, r + t.dodgeMarginM, c);
    p.x = q.x;
    p.y = q.y;
    p.ox = p.x - p.bx;
    p.oy = p.y - p.by;
    if (_moving(p.mode)) {
      p.resume = p.mode;
      p.mode = PedMode.recover;
    } else if (p.mode == PedMode.leap) {
      p.mode = PedMode.stun;
      p.timer = t.stunS;
    }
  }
}

/// All pedestrians of a city around the player (specs/pedestrians.md).
class PedestrianWorld {
  PedestrianWorld(this.city, this.tuning)
    : t = tuning.pedestrians,
      radius = tuning.pedestrians.radiusM * tuning.carScale,
      _rnd = Prng(tuning.pedestrians.seed),
      _busy = tuning.pedestrians.busyDistricts.toSet();

  final City city;
  final Tuning tuning;
  final TuningPedestrians t;

  /// Body radius in metres (radius_m · car_scale).
  final double radius;
  final List<Pedestrian> peds = [];
  final PedStats stats = PedStats();
  final Prng _rnd;
  final Set<String> _busy;
  final Map<int, Float64List> _cum = {};
  int _nextId = 1;
  double _spawnAcc = 0;
  ({double x, double y})? _focus;

  bool get enabled => t.enabled;

  /// Sidewalk offset from the edge axis (same as street furniture).
  double offset(RoadEdge e) => e.width / 2 - tuning.sidewalkWidthM / 2;

  bool walkable(RoadEdge e) => e.kept && e.isGround && !e.bridge && e.length > 0 && offset(e) > 0;

  /// Cap on the count (night lowers it).
  int cap(bool night) {
    if (!t.enabled) return 0;
    return night ? (t.maxCount * t.nightFactor).round() : t.maxCount;
  }

  /// Nearest pedestrian to (x, y) within [maxDist], or null (for dialogue and police).
  Pedestrian? nearest(double x, double y, {double maxDist = double.infinity}) {
    Pedestrian? best;
    var bd = maxDist;
    for (final p in peds) {
      final d = math.sqrt((p.x - x) * (p.x - x) + (p.y - y) * (p.y - y));
      if (d <= bd) {
        bd = d;
        best = p;
      }
    }
    return best;
  }

  Pedestrian? byId(int id) {
    for (final p in peds) {
      if (p.id == id) return p;
    }
    return null;
  }

  void clear() {
    peds.clear();
    _focus = null;
  }

  /// One frame. cars[0] is the player's car (the spawn and despawn centre).
  void update(double dt, List<CarPose> cars, double viewRadius, {required bool night}) {
    if (!t.enabled || cars.isEmpty) {
      peds.clear();
      return;
    }
    dt = math.min(dt, 0.1);
    final fx = cars.first.x, fy = cars.first.y;
    final rIn = viewRadius + t.spawnMarginM, rOut = rIn + t.spawnBandM;
    final max = cap(night);
    final f = _focus;
    if (f == null || _hyp(fx - f.x, fy - f.y) > t.spawnBandM) {
      peds.clear();
      for (var i = 0; i < t.fillAttempts && peds.length < max; i++) {
        _trySpawn(fx, fy, t.fillClearM, rOut, night);
      }
    }
    _focus = (x: fx, y: fy);

    final far = viewRadius + t.despawnMarginM;
    for (var i = peds.length - 1; i >= 0; i--) {
      final p = peds[i];
      final d = _hyp(p.x - fx, p.y - fy);
      if (d > far || (peds.length > max && d > viewRadius)) peds.removeAt(i);
    }
    _spawnAcc += t.spawnPerS * dt;
    while (_spawnAcc >= 1) {
      _spawnAcc -= 1;
      if (peds.length < max) _trySpawn(fx, fy, rIn, rOut, night);
    }

    for (final p in peds) {
      if (stepAvoid(p, cars, radius, dt, t, stats)) _advance(p, dt);
      settle(p, cars, radius, t, stats);
    }
  }

  double _unit() => _rnd.nextU32() / 4294967296;

  void _trySpawn(double fx, double fy, double rIn, double rOut, bool night) {
    final ang = _unit() * 2 * math.pi;
    final rad = math.sqrt(rIn * rIn + _unit() * (rOut * rOut - rIn * rIn));
    final px = fx + math.cos(ang) * rad, py = fy + math.sin(ang) * rad;
    final hit = city.graph.nearest(px, py, maxDist: t.snapM, where: walkable);
    if (hit == null) return;
    final district = city.districtAt(hit.x, hit.y);
    final cls = hit.edge.roadClass.value;
    final dens =
        (cls < t.classDensity.length ? t.classDensity[cls] : 0.0) *
        (district != null && _busy.contains(district) ? t.busyFactor : t.quietFactor) *
        (night ? t.nightFactor : 1.0);
    if (_unit() >= math.min(1.0, dens)) return;
    final side = hit.dirX * (py - hit.y) - hit.dirY * (px - hit.x) >= 0 ? 1 : -1;
    final dir = _unit() < 0.5 ? 1 : -1;
    final speed = t.walkMps + (_unit() * 2 - 1) * t.walkJitterMps;
    final e = hit.edge;
    final s = hit.t * e.length;
    final q = pathPoint(e, s, side);
    if (_hyp(q.x - fx, q.y - fy) < rIn) return;
    final p = Pedestrian(_nextId++)
      ..edge = e.index
      ..side = side
      ..s = s
      ..dir = dir
      ..speed = speed
      ..bx = q.x
      ..by = q.y
      ..x = q.x
      ..y = q.y
      ..heading = math.atan2(q.dy * dir, q.dx * dir);
    peds.add(p);
  }

  /// Point on the sidewalk at s metres along edge e, on [side]; (dx, dy) is the segment direction.
  ({double x, double y, double dx, double dy}) pathPoint(RoadEdge e, double s, int side) {
    final cum = _cum.putIfAbsent(e.index, () {
      final c = Float64List(e.pointCount);
      for (var i = 1; i < e.pointCount; i++) {
        c[i] = c[i - 1] + _hyp(e.pts[2 * i] - e.pts[2 * i - 2], e.pts[2 * i + 1] - e.pts[2 * i - 1]);
      }
      return c;
    });
    s = s.clamp(0.0, e.length);
    var i = 0;
    while (i < e.pointCount - 2 && (cum[i + 1] < s || cum[i + 1] == cum[i])) {
      i++;
    }
    final ax = e.pts[2 * i], ay = e.pts[2 * i + 1], bx = e.pts[2 * i + 2], by = e.pts[2 * i + 3];
    final l = _hyp(bx - ax, by - ay);
    final dx = l == 0 ? 1.0 : (bx - ax) / l, dy = l == 0 ? 0.0 : (by - ay) / l;
    final k = math.min(l, math.max(0.0, s - cum[i]));
    final o = offset(e) * side;
    return (x: ax + dx * k - dy * o, y: ay + dy * k + dx * o, dx: dx, dy: dy);
  }

  /// Walk, turn at nodes, cross (specs/pedestrians.md "Chůze").
  void _advance(Pedestrian p, double dt) {
    final step = p.speed * dt;
    if (p.mode == PedMode.cross || (p.mode == PedMode.recover && p.resume == PedMode.cross)) {
      final dx = p.cx1 - p.bx, dy = p.cy1 - p.by;
      final l = _hyp(dx, dy);
      if (l <= step) {
        p.bx = p.cx1;
        p.by = p.cy1;
        if (p.mode == PedMode.cross) {
          p.mode = PedMode.walk;
        } else {
          p.resume = PedMode.walk;
        }
      } else {
        p.bx += dx / l * step;
        p.by += dy / l * step;
        p.heading = math.atan2(dy, dx);
      }
      return;
    }
    final g = city.graph;
    final e = g.edges[p.edge];
    p.s += p.dir * step;
    if (p.dir > 0 ? p.s >= e.length : p.s <= 0) {
      final node = p.dir > 0 ? e.to : e.from;
      final opts = [
        for (final i in g.nodeEdges[node])
          if (i != p.edge && walkable(g.edges[i])) i,
      ];
      final next = opts.isNotEmpty ? opts[_rnd.nextInt(opts.length)] : p.edge;
      var ws = p.side * p.dir;
      if (_unit() < t.crossChance) ws = -ws;
      final ne = g.edges[next];
      final nd = ne.from == node ? 1 : -1;
      p
        ..edge = next
        ..dir = nd
        ..side = ws * nd
        ..s = nd > 0 ? 0 : ne.length;
      final q = pathPoint(ne, p.s, p.side);
      p.cx1 = q.x;
      p.cy1 = q.y;
      if (p.mode == PedMode.recover) {
        p.resume = PedMode.cross;
      } else {
        p.mode = PedMode.cross;
      }
      return;
    }
    final q = pathPoint(e, p.s, p.side);
    p.bx = q.x;
    p.by = q.y;
    p.heading = math.atan2(q.dy * p.dir, q.dx * p.dir);
  }
}

double _hyp(double x, double y) => math.sqrt(x * x + y * y);
