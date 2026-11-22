import 'dart:math' as math;

import 'package:forge2d/forge2d.dart';
import 'package:rules_core/rules_core.dart';
import 'package:world_engine/core.dart';

import '../car.dart';
import '../trams/trams.dart';
import 'road_rules.dart';

/// What traffic needs of a parked car (specs/traffic.md step 8); hl/hw null = a traffic car.
abstract interface class ParkedPose {
  double get x;
  double get y;
  double get heading;
  double? get hl;
  double? get hw;
}

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

  /// Seconds left loose after the last touch (specs/traffic.md step 7).
  double pushTimer = 0;

  /// Dynamic body: pushed or hit; the pose comes from physics.
  bool loose = false;

  /// Police hooks (specs/police.md), set by the police module: a patrol car, chasing a goal.
  bool police = false;
  bool pursuing = false;
  double goalX = 0;
  double goalY = 0;
  double pursuitMps = 0;

  /// A chasing patrol brakes to stop this far from its goal.
  double goalStopM = 0;

  // Path state.
  RoadEdge edge;
  int dir;
  double s;
  int lane;
  int seg = 0;
  double segStart = 0;
  bool touching = false;

  /// Current filter mask (switched by layer, solidity and looseness).
  int mask = -1;

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

  /// Parked cars to drive round (set by the car fleet, specs/traffic.md step 8).
  List<ParkedPose> parked = const [];

  /// Tram cars that block the road ahead in any direction (set by DriveWorld, specs/traffic.md v3).
  List<TramCar> tramCars = const [];

  final Prng _rng;
  final double _halfLength;
  final double _halfWidth;
  final List<TrafficHitListener> _listeners = [];
  final List<int> _scratch = [];
  final Vector2 _v = Vector2.zero();
  final Vector2 _p = Vector2.zero();
  final List<double> _obs = [];
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
  /// [airborne]: the player is in a hop (specs/hop.md), so nothing touches it and no hit fires.
  void postStep(Car player, {bool airborne = false}) {
    final t = _t;
    final pv = player.velocity;
    final ph = player.heading, pc = math.cos(ph), ps = math.sin(ph);
    final round = tuning.drive.bodyRoundM;
    final phl = player.halfLength + round, phw = player.halfWidth + round;
    for (final c in cars) {
      final same = solid && !airborne && c.layer == player.layer;
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
      if (touch) c.pushTimer = t.pushHoldS;
      c.touching = touch;
      _setLoose(c, c.hitTimer > 0 || c.pushTimer > 0);
      _setMask(c, same);
    }
  }

  /// Dynamic while loose, kinematic otherwise (specs/traffic.md step 7).
  void _setLoose(TrafficCar c, bool loose) {
    if (loose == c.loose) return;
    c.loose = loose;
    if (loose) {
      c.body
        ..type = BodyType.dynamic
        ..linearDamping = _t.pushLinearDamping
        ..angularDamping = _t.pushAngularDamping
        ..isAwake = true;
      c.speed = 0;
    } else {
      c.body.type = BodyType.kinematic;
      c.s = _projectS(c);
    }
  }

  void _setMask(TrafficCar c, bool same) {
    final ground = c.layer == 0;
    final mask = (same ? catCar : 0) | (ground ? catParked | catTram : 0) | (ground && c.loose ? catBuildings : 0);
    if (mask == c.mask) return;
    c.mask = mask;
    c.shape.filter = Filter(categoryBits: catTraffic, maskBits: mask);
  }

  /// Distance along the travel direction of the car's own edge nearest to its position.
  double _projectS(TrafficCar c) {
    final e = c.edge;
    var best = double.infinity, d = 0.0;
    for (var seg = 0; seg + 1 < e.pointCount; seg++) {
      final h = graph.project(e, seg, c.x, c.y);
      if (h.dist < best) {
        best = h.dist;
        d = h.t * e.length;
      }
    }
    return c.dir > 0 ? d : e.length - d;
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
        density: _t.massKg / (4 * _halfLength * _halfWidth),
        material: SurfaceMaterial(friction: tuning.drive.carFriction, restitution: tuning.drive.carRestitution),
        filter: Filter(categoryBits: catTraffic, maskBits: catCar | catParked | catTram),
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
    c.pushTimer = math.max(0, c.pushTimer - dt);
    if (c.loose) {
      // Pushed or knocked: physics owns the pose until it settles (specs/traffic.md step 7).
      c
        ..hitTimer = math.max(0, c.hitTimer - dt)
        ..speed = 0
        ..braking = false
        ..x = c.body.position.x
        ..y = c.body.position.y
        ..heading = c.body.angle;
      return true;
    }
    if (c.hitTimer > 0) {
      c.hitTimer = math.max(0, c.hitTimer - dt);
      c.speed = 0;
    } else {
      final gap = _gapAhead(c, player);
      final cls = c.edge.roadClass.value;
      final vmax = c.pursuing
          ? _pursuitSpeed(c)
          : cls < t.classSpeedMps.length
          ? t.classSpeedMps[cls]
          : t.classSpeedMps[0];
      final free = math.max(0.0, gap - t.minGapM);
      final want = math.min(vmax, math.min(free / t.headwayS, math.sqrt(2 * t.brakeMps2 * free)));
      final dv = want - c.speed;
      c.braking = dv < -t.accelMps2 * dt;
      c.speed = math.max(0, c.speed + math.min(t.accelMps2 * dt, math.max(-t.brakeMps2 * dt, dv)));
    }
    c.s += c.speed * dt;
    while (c.s >= c.edge.length) {
      final node = c.dir > 0 ? c.edge.to : c.edge.from;
      final next = c.pursuing
          ? chooseToward(graph, node, c.edge.index, c.goalX, c.goalY)
          : chooseNext(graph, node, c.edge.index, c.rng, _scratch);
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

  /// Chase speed: pursuitMps, braking to a stop goalStopM from the goal (specs/police.md).
  double _pursuitSpeed(TrafficCar c) {
    final dx = c.goalX - c.x, dy = c.goalY - c.y;
    final left = math.max(0.0, math.sqrt(dx * dx + dy * dy) - c.goalStopM);
    return math.min(c.pursuitMps, math.sqrt(2 * _t.brakeMps2 * left));
  }

  /// Turns a car around on its edge (police U-turn): same point, opposite direction.
  void turnAround(TrafficCar c) {
    c.dir = -c.dir;
    c.s = math.max(0, c.edge.length - c.s);
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
    var tx = ax + (bx - ax) * f + uy * off, ty = ay + (by - ay) * f - ux * off;
    c.layer = e.layerAt(e.length > 0 ? d / e.length : 0);
    if (c.layer == 0 && parked.isNotEmpty) {
      final sh = _swerve(c, tx, ty, ux, uy);
      tx += uy * sh;
      ty -= ux * sh;
    }
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
  }

  /// Sideways shift round parked cars near the lane point (tx, ty) heading (ux, uy).
  double _swerve(TrafficCar c, double tx, double ty, double ux, double uy) {
    final t = _t;
    final o = _obs;
    final reach = t.swerveAheadM + 4 * c.halfLength;
    final lane = math.atan2(uy, ux);
    var n = 0;
    for (final p in parked) {
      final dx = p.x - tx, dy = p.y - ty;
      if (dx * dx + dy * dy > reach * reach) continue;
      final phl = p.hl ?? c.halfLength, phw = p.hw ?? c.halfWidth;
      final da = p.heading - lane;
      if (o.length < 4 * n + 4) o.addAll(const [0.0, 0.0, 0.0, 0.0]);
      // Ahead of the car itself (its pose lags the lane point), sideways from the lane point.
      o[4 * n] = (p.x - c.x) * ux + (p.y - c.y) * uy;
      o[4 * n + 1] = dx * uy - dy * ux;
      o[4 * n + 2] = phl * math.sin(da).abs() + phw * math.cos(da).abs();
      o[4 * n + 3] = phl;
      n++;
    }
    return n == 0 ? 0 : swerveShift(o, n, c.halfLength, c.halfWidth, t);
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
    // Tram cars in the same layer block in any direction (v3, step 1 b); even a chasing patrol stops.
    for (final o in tramCars) {
      if (o.layer != c.layer) continue;
      gap = math.min(gap, _gapToBox(c, hc, hs, o.x, o.y, o.heading, o.halfLength, o.halfWidth, look));
    }
    // A chasing patrol ignores other cars and the lights (sirens, specs/police.md).
    if (c.pursuing) return gap;
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

  /// Like [_gapTo] for a box at any heading [oh]: its extents are projected on the car's axes.
  double _gapToBox(
    TrafficCar c,
    double hc,
    double hs,
    double ox,
    double oy,
    double oh,
    double ohl,
    double ohw,
    double look,
  ) {
    final dx = ox - c.x, dy = oy - c.y;
    final oc = math.cos(oh), os = math.sin(oh);
    final along = ohl * (oc * hc + os * hs).abs() + ohw * (-oc * hs + os * hc).abs();
    final side = ohl * (-oc * hs + os * hc).abs() + ohw * (oc * hc + os * hs).abs();
    final lx = dx * hc + dy * hs;
    if (lx <= 0 || lx > look + c.halfLength + along) return double.infinity;
    final ly = -dx * hs + dy * hc;
    if (ly.abs() > (c.halfWidth + side) * _t.corridor) return double.infinity;
    return math.max(0, lx - c.halfLength - along);
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
