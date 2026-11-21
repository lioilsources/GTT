import 'dart:math' as math;

import 'package:forge2d/forge2d.dart';
import 'package:rules_core/rules_core.dart';
import 'package:world_engine/core.dart';

import '../car.dart';
import 'road_rules.dart';

/// One AI car (specs/traffic.md "Stav"). Read-only for other features.
class TrafficCar {
  TrafficCar(
    this.id,
    this.edge,
    this.dir,
    this.s,
    this.lane,
    this.rng,
    this.colour,
    this.halfLength,
    this.halfWidth,
    this.body,
    this.shape,
  );

  final int id;
  double x = 0;
  double y = 0;
  double heading = 0;

  /// Speed along the lane, m/s (never negative).
  double speed = 0;
  int layer = 0;
  bool braking = false;

  /// Seconds left standing still after the player hit it.
  double hitTimer = 0;

  // Path state.
  RoadEdge edge;
  int dir;
  double s;
  int lane;
  int seg = 0;
  double segStart = 0;
  bool touching = false;
  bool collides = true;

  final Prng rng;

  /// Index into `Tokens.colorTrafficBodies`.
  final int colour;
  final double halfLength;
  final double halfWidth;
  final Body body;
  final Shape shape;
}

typedef TrafficHitListener = void Function(TrafficCar car, double impactMps);

double _wrap(double a) {
  while (a > math.pi) {
    a -= 2 * math.pi;
  }
  while (a < -math.pi) {
    a += 2 * math.pi;
  }
  return a;
}

double _segLen(RoadEdge e, int seg) {
  final i = 2 * seg;
  final dx = e.pts[i + 2] - e.pts[i], dy = e.pts[i + 3] - e.pts[i + 1];
  return math.sqrt(dx * dx + dy * dy);
}

/// AI traffic and traffic lights (specs/traffic.md). Cars are kinematic Box2D bodies that only
/// collide with the player's car; their motion is computed here, the solver only pushes the player.
/// Port of web/src/traffic/traffic.ts.
class Traffic {
  Traffic(this.world, this.city, this.tuning)
    : graph = city.graph,
      leftHand = city.leftHand,
      _rng = Prng(tuning.traffic.seed),
      _halfLength = tuning.traffic.carLengthM * tuning.carScale / 2,
      _halfWidth = tuning.traffic.carWidthM * tuning.carScale / 2 {
    signals = buildSignals(graph, tuning, leftHand: leftHand);
  }

  final World world;
  final City city;
  final Tuning tuning;
  final RoadGraph graph;
  final bool leftHand;
  late final Signals signals;
  final List<TrafficCar> cars = [];

  /// Night lowers the density (`traffic.night_factor`); the client sets it with its day/night toggle.
  bool night = false;

  /// Player hits so far.
  int hits = 0;

  /// False = the player is a ghost to traffic: no collisions, no hits, cars do not wait for it.
  /// The D1 benchmark autopilot sets this, it does not avoid cars (specs/traffic.md).
  bool solid = true;

  /// Fixed steps since start: the signal clock.
  int stepCount = 0;

  final Prng _rng;
  final double _halfLength;
  final double _halfWidth;
  final List<TrafficHitListener> _listeners = [];
  final List<int> _scratch = [];
  final Vector2 _v = Vector2.zero();
  final Vector2 _p = Vector2.zero();
  double _spawnTimer = 0;
  bool _fresh = true;
  bool _tracked = false;
  double _lastPX = 0;
  double _lastPY = 0;
  int _nextId = 1;

  TuningTraffic get _t => tuning.traffic;

  /// Registers a "car hit by player" listener; returns the unsubscribe function.
  void Function() onHit(TrafficHitListener fn) {
    _listeners.add(fn);
    return () => _listeners.remove(fn);
  }

  /// Signal clock in ms (specs/traffic.md "Hodiny").
  int get clockMs => signalClockMs(stepCount, tuning.drive.stepHz);

  /// Light shown on approach index [a] (lightGreen / lightAmber / lightRed).
  int light(int a) {
    final ap = signals.approaches[a];
    return lightState(signals.offsets[ap.signal], ap.group, clockMs, _t);
  }

  /// Removes all cars and refills around the player on the next step.
  void reset() {
    for (final c in cars) {
      c.body.destroy();
    }
    cars.clear();
    _fresh = true;
  }

  void dispose() {
    reset();
    _listeners.clear();
  }

  /// Before `world.step`: spawn/despawn, drive every car, set the kinematic velocities.
  void preStep(double dt, Car player) {
    final t = _t;
    stepCount++;
    final px = player.x, py = player.y;
    final jx = px - _lastPX, jy = py - _lastPY;
    if (_tracked && jx * jx + jy * jy > t.teleportM * t.teleportM) reset();
    _tracked = true;
    _lastPX = px;
    _lastPY = py;

    final d2 = t.despawnM * t.despawnM;
    for (var i = cars.length - 1; i >= 0; i--) {
      final c = cars[i];
      final dx = c.x - px, dy = c.y - py;
      if (dx * dx + dy * dy > d2) _remove(i);
    }
    _spawn(dt, px, py);

    final k = 1 - math.exp(-t.followRate * dt);
    for (var i = cars.length - 1; i >= 0; i--) {
      if (!_drive(cars[i], dt, k, player)) _remove(i);
    }
  }

  /// After `world.step`: hit detection against the player (SAT on the two boxes).
  void postStep(Car player) {
    final t = _t;
    final pv = player.velocity;
    final ph = player.heading, pc = math.cos(ph), ps = math.sin(ph);
    final round = tuning.drive.bodyRoundM;
    final phl = player.halfLength + round, phw = player.halfWidth + round;
    for (final c in cars) {
      final same = solid && c.layer == player.layer;
      if (same != c.collides) {
        c.collides = same;
        c.shape.filter = Filter(categoryBits: catTraffic, maskBits: same ? catCar : 0);
      }
      final ch = math.cos(c.heading), sh = math.sin(c.heading);
      final touch =
          same &&
          obbOverlap(player.x, player.y, pc, ps, phl, phw, c.x, c.y, ch, sh, c.halfLength, c.halfWidth, t.hitMarginM);
      if (touch && !c.touching) {
        final rvx = pv.x - ch * c.speed, rvy = pv.y - sh * c.speed;
        final impact = math.sqrt(rvx * rvx + rvy * rvy);
        if (impact >= t.hitMinMps) {
          c.hitTimer = t.hitStopS;
          c.speed = 0;
          hits++;
          for (final fn in _listeners) {
            fn(c, impact);
          }
        }
      }
      c.touching = touch;
    }
  }

  // ---------- spawning

  double _unit() => _rng.nextU32() / 4294967296;

  int get _target => math.min(_t.maxCars, (_t.maxCars * (night ? _t.nightFactor : 1.0)).round());

  void _spawn(double dt, double px, double py) {
    final t = _t;
    if (_fresh) {
      _fresh = false;
      _spawnTimer = 0;
      for (var i = 0; i < t.initialTries && cars.length < _target; i++) {
        _trySpawn(px, py, t.initialMinM);
      }
      return;
    }
    _spawnTimer += dt;
    if (_spawnTimer < t.spawnIntervalS) return;
    _spawnTimer = 0;
    for (var i = 0; i < t.spawnTries && cars.length < _target; i++) {
      _trySpawn(px, py, t.spawnMinM);
    }
  }

  bool _trySpawn(double px, double py, double rMin) {
    final t = _t;
    final a = _unit() * 2 * math.pi, r = rMin + _unit() * (t.spawnMaxM - rMin);
    final hit = graph.nearest(
      px + math.cos(a) * r,
      py + math.sin(a) * r,
      maxDist: t.searchM,
      where: (e) => e.kept && e.length > 1,
    );
    if (hit == null) return false;
    final e = hit.edge;
    final cls = e.roadClass.value;
    if (_unit() >= (cls < t.classWeight.length ? t.classWeight[cls] : 0)) return false;
    final hx = hit.x - px, hy = hit.y - py;
    if (math.sqrt(hx * hx + hy * hy) < rMin) return false;
    for (final c in cars) {
      final dx = c.x - hit.x, dy = c.y - hit.y;
      if (math.sqrt(dx * dx + dy * dy) < t.spawnClearM) return false;
    }
    final fwd = canLeave(e, e.from), back = canLeave(e, e.to);
    if (!fwd && !back) return false;
    final dir = fwd && back ? (_rng.nextInt(2) == 0 ? 1 : -1) : (fwd ? 1 : -1);
    final lane = _rng.nextInt(lanesPerDir(e, tuning));
    return addCar(e.index, dir, dir > 0 ? hit.t * e.length : (1 - hit.t) * e.length, lane) != null;
  }

  /// Puts a car on [edge] going [dir] (+1 from → to, −1 to → from), [s] metres along the travel
  /// direction, in [lane]. Null for an alley, a forbidden direction or at the `max_cars` cap.
  TrafficCar? addCar(int edge, int dir, double s, int lane) {
    if (edge < 0 || edge >= graph.edges.length) return null;
    final e = graph.edges[edge];
    if (!e.kept || cars.length >= _t.maxCars) return null;
    if (!canLeave(e, dir > 0 ? e.from : e.to)) return null;
    final colour = _rng.nextInt(Tokens.colorTrafficBodies.length);
    final carRng = Prng(_rng.nextU32());
    final body = world.createBody(BodyDef(type: BodyType.kinematic, position: Vector2.zero()));
    final shape = body.createShape(
      Polygon.box(_halfLength, _halfWidth),
      ShapeDef(
        material: SurfaceMaterial(friction: tuning.drive.carFriction, restitution: tuning.drive.carRestitution),
        filter: Filter(categoryBits: catTraffic, maskBits: catCar),
      ),
    );
    final ln = lane.clamp(0, lanesPerDir(e, tuning) - 1);
    final c = TrafficCar(
      _nextId++,
      e,
      dir,
      s.clamp(0.0, e.length),
      ln,
      carRng,
      colour,
      _halfLength,
      _halfWidth,
      body,
      shape,
    );
    c.seg = dir > 0 ? 0 : e.pointCount - 2;
    c.segStart = dir > 0 ? 0 : e.length - _segLen(e, c.seg);
    _place(c, 1);
    _p.setValues(c.x, c.y);
    body.setTransform(_p, Rot.fromAngle(c.heading));
    cars.add(c);
    return c;
  }

  void _remove(int i) {
    final c = cars[i];
    c.body.destroy();
    final last = cars.removeLast();
    if (!identical(last, c)) cars[i] = last;
  }

  // ---------- driving

  /// One step of one car; false = it has to disappear.
  bool _drive(TrafficCar c, double dt, double k, Car player) {
    final t = _t;
    if (c.hitTimer > 0) {
      c.hitTimer = math.max(0, c.hitTimer - dt);
      c.speed = 0;
    } else {
      final gap = _gapAhead(c, player);
      final cls = c.edge.roadClass.value;
      final vmax = cls < t.classSpeedMps.length ? t.classSpeedMps[cls] : t.classSpeedMps[0];
      final free = math.max(0.0, gap - t.minGapM);
      final want = math.min(vmax, math.min(free / t.headwayS, math.sqrt(2 * t.brakeMps2 * free)));
      final dv = want - c.speed;
      c.braking = dv < -t.accelMps2 * dt;
      c.speed = math.max(0, c.speed + math.min(t.accelMps2 * dt, math.max(-t.brakeMps2 * dt, dv)));
    }
    c.s += c.speed * dt;
    while (c.s >= c.edge.length) {
      final node = c.dir > 0 ? c.edge.to : c.edge.from;
      final next = chooseNext(graph, node, c.edge.index, c.rng, _scratch);
      if (next < 0) return false;
      c.s -= c.edge.length;
      final e = graph.edges[next];
      c.edge = e;
      c.dir = e.from == node ? 1 : -1;
      c.lane = math.min(c.lane, lanesPerDir(e, tuning) - 1);
      c.seg = c.dir > 0 ? 0 : e.pointCount - 2;
      c.segStart = c.dir > 0 ? 0 : e.length - _segLen(e, c.seg);
    }
    final ox = c.x, oy = c.y, oh = c.heading;
    _place(c, k);
    _v.setValues((c.x - ox) / dt, (c.y - oy) / dt);
    c.body.linearVelocity = _v;
    c.body.angularVelocity = _wrap(c.heading - oh) / dt;
    return true;
  }

  /// Moves the car's pose towards its lane point at s; k = 1 snaps.
  void _place(TrafficCar c, double k) {
    final e = c.edge;
    final d = c.dir > 0 ? c.s : e.length - c.s;
    final last = e.pointCount - 2;
    var len = _segLen(e, c.seg);
    while (c.seg < last && d > c.segStart + len) {
      c.segStart += len;
      c.seg++;
      len = _segLen(e, c.seg);
    }
    while (c.seg > 0 && d < c.segStart) {
      c.seg--;
      len = _segLen(e, c.seg);
      c.segStart -= len;
    }
    final i = 2 * c.seg;
    final ax = e.pts[i], ay = e.pts[i + 1], bx = e.pts[i + 2], by = e.pts[i + 3];
    final f = len > 0 ? ((d - c.segStart) / len).clamp(0.0, 1.0) : 0.0;
    var ux = len > 0 ? (bx - ax) / len : 1.0, uy = len > 0 ? (by - ay) / len : 0.0;
    if (c.dir < 0) {
      ux = -ux;
      uy = -uy;
    }
    final off = laneOffset(e, c.lane, tuning, leftHand: leftHand);
    // Right of the travel direction (ux, uy) is (uy, −ux).
    final tx = ax + (bx - ax) * f + uy * off, ty = ay + (by - ay) * f - ux * off;
    final th = math.atan2(uy, ux);
    if (k >= 1) {
      c
        ..x = tx
        ..y = ty
        ..heading = th;
    } else {
      c
        ..x += (tx - c.x) * k
        ..y += (ty - c.y) * k
        ..heading = _wrap(c.heading + _wrap(th - c.heading) * k);
    }
    c.layer = e.layerAt(e.length > 0 ? d / e.length : 0);
  }

  /// Free distance to the nearest obstacle ahead: the player, a car going our way, a stop line.
  double _gapAhead(TrafficCar c, Car player) {
    final t = _t;
    final look = t.lookAheadM;
    final hc = math.cos(c.heading), hs = math.sin(c.heading);
    var gap = look;
    if (solid && player.layer == c.layer) {
      gap = math.min(gap, _gapTo(c, hc, hs, player.x, player.y, player.halfLength, player.halfWidth, look));
    }
    for (final o in cars) {
      if (identical(o, c) || o.layer != c.layer) continue;
      // Only cars going roughly our way (±60°); crossing traffic is ignored.
      if (math.cos(o.heading) * hc + math.sin(o.heading) * hs < 0.5) continue;
      gap = math.min(gap, _gapTo(c, hc, hs, o.x, o.y, o.halfLength, o.halfWidth, look));
    }
    final a = c.dir > 0 ? signals.approachTo[c.edge.index] : signals.approachFrom[c.edge.index];
    if (a >= 0) {
      final state = light(a);
      if (state != lightGreen) {
        final extra = c.dir > 0 ? signals.extraTo[c.edge.index] : signals.extraFrom[c.edge.index];
        final toLine = c.edge.length - c.s + extra - signals.approaches[a].stopM - c.halfLength;
        final committed = toLine < -c.halfLength || (state == lightAmber && toLine < t.amberCommitM);
        if (!committed && toLine + t.minGapM < gap) gap = math.max(0, toLine + t.minGapM);
      }
    }
    return gap;
  }

  double _gapTo(TrafficCar c, double hc, double hs, double ox, double oy, double ohl, double ohw, double look) {
    final dx = ox - c.x, dy = oy - c.y;
    final lx = dx * hc + dy * hs;
    if (lx <= 0 || lx > look + c.halfLength + ohl) return double.infinity;
    final ly = -dx * hs + dy * hc;
    if (ly.abs() > (c.halfWidth + ohw) * _t.corridor) return double.infinity;
    return math.max(0, lx - c.halfLength - ohl);
  }
}

/// Separating-axis test of two oriented boxes (centre, unit heading c/s, half extents), with margin.
bool obbOverlap(
  double ax,
  double ay,
  double ac,
  double asn,
  double ahl,
  double ahw,
  double bx,
  double by,
  double bc,
  double bsn,
  double bhl,
  double bhw,
  double margin,
) {
  final dx = bx - ax, dy = by - ay;
  return _sepAxis(ac, asn, dx, dy, ac, asn, ahl, ahw, bc, bsn, bhl, bhw, margin) &&
      _sepAxis(-asn, ac, dx, dy, ac, asn, ahl, ahw, bc, bsn, bhl, bhw, margin) &&
      _sepAxis(bc, bsn, dx, dy, ac, asn, ahl, ahw, bc, bsn, bhl, bhw, margin) &&
      _sepAxis(-bsn, bc, dx, dy, ac, asn, ahl, ahw, bc, bsn, bhl, bhw, margin);
}

/// True when the projections on axis (nx, ny) overlap.
bool _sepAxis(
  double nx,
  double ny,
  double dx,
  double dy,
  double ac,
  double asn,
  double ahl,
  double ahw,
  double bc,
  double bsn,
  double bhl,
  double bhw,
  double margin,
) {
  final ra = ahl * (ac * nx + asn * ny).abs() + ahw * (-asn * nx + ac * ny).abs();
  final rb = bhl * (bc * nx + bsn * ny).abs() + bhw * (-bsn * nx + bc * ny).abs();
  return (dx * nx + dy * ny).abs() <= ra + rb + margin;
}
