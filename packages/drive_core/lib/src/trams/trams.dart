import 'dart:math' as math;
import 'dart:typed_data';

import 'package:forge2d/forge2d.dart';
import 'package:rules_core/rules_core.dart';
import 'package:world_engine/core.dart';

import '../car.dart';
import '../traffic/traffic.dart';
import 'tram_rules.dart';

/// One articulated car of a tram: a kinematic body (specs/trams.md step 4). Read-only for others.
class TramCar extends TramCarPose {
  TramCar(this.tram, this.k, this.halfLength, this.halfWidth, this.body, this.shape);

  final Tram tram;

  /// 0 = front car (changes when the tram changes ends at a terminus).
  int k;
  final double halfLength;
  final double halfWidth;
  final Body body;
  final Shape shape;

  /// Current filter mask (switched by layer and solidity).
  int mask = -1;
}

/// One tram (specs/trams.md "Stav").
class Tram {
  Tram(this.id, this.edge, this.dir, this.s, this.rng, this.trail)
    : _histE = Int32List(math.max(1, trail.capacity)),
      _histD = Int8List(math.max(1, trail.capacity));

  final int id;
  TrackEdge edge;

  /// +1 from → to, −1 to → from.
  int dir;

  /// Distance of the nose along the travel direction of [edge] (m).
  double s;

  /// Speed along the track, m/s (never negative).
  double speed = 0;
  int layer = 0;
  bool braking = false;

  /// Seconds left standing at a stop.
  double dwell = 0;

  /// Seconds left standing after the player hit it.
  double hitTimer = 0;

  /// Stop the tram is heading for (−1 none) and the stop it last stood at on this edge.
  int stop = -1;
  int served = -1;

  /// Fixed step at which the nose entered [edge] (single-track right of way, step 1).
  int entered = 0;

  /// Next polyline point of [edge] (in travel order) the nose has not passed yet.
  int nextPoint = 1;
  bool touching = false;
  final Prng rng;
  final TramTrail trail;
  final List<TramCar> cars = [];

  /// Ends changed at termini so far.
  int reversals = 0;

  /// Edges fully behind the nose (specs/trams.md v2 "Stav"), newest first; a ring.
  final Int32List _histE;
  final Int8List _histD;
  int _histStart = 0;

  /// Number of edges in the history.
  int histCount = 0;

  /// History edge [i] (0 = newest) and its travel direction.
  int histEdge(int i) => _histE[(_histStart + i) % _histE.length];
  int histDir(int i) => _histD[(_histStart + i) % _histD.length];

  /// Adds the edge just left as the newest; the oldest drops out of a full ring.
  void histPush(int edge, int dir) {
    final c = _histE.length;
    _histStart = (_histStart + c - 1) % c;
    _histE[_histStart] = edge;
    _histD[_histStart] = dir;
    if (histCount < c) histCount++;
  }

  /// Adds an edge behind the oldest (seeding); false when the ring is full.
  bool histPushOldest(int edge, int dir) {
    final c = _histE.length;
    if (histCount >= c) return false;
    _histE[(_histStart + histCount) % c] = edge;
    _histD[(_histStart + histCount) % c] = dir;
    histCount++;
    return true;
  }

  void histClear() {
    _histStart = 0;
    histCount = 0;
  }

  double get x => trail.noseX;
  double get y => trail.noseY;
}

typedef TramHitListener = void Function(Tram tram, double impactMps);

double _wrap(double a) {
  while (a > math.pi) {
    a -= 2 * math.pi;
  }
  while (a < -math.pi) {
    a += 2 * math.pi;
  }
  return a;
}

/// Trams on the track graph (specs/trams.md): spawn ring, stops, right of way. Every car is a
/// kinematic Box2D body the player bounces off; nothing ever pushes a tram.
class Trams {
  Trams(this.world, this.graph, this.tuning)
    : _rng = Prng(tuning.trams.seed),
      _halfLength = tuning.trams.carLengthM / 2,
      _halfWidth = tuning.trams.carWidthM / 2,
      _cosMin = math.cos(tuning.trams.maxSwitchDeg * math.pi / 180),
      tramLength =
          tuning.trams.carsPerTram * tuning.trams.carLengthM +
          (tuning.trams.carsPerTram - 1) * tuning.trams.jointGapM,
      _deadEnd = Uint8List(graph.edges.length * 2) {
    for (final e in graph.edges) {
      if (e.from == e.to) continue;
      for (final node in [e.from, e.to]) {
        if (graph.border[node]) continue;
        if (feasibleNext(graph, node, e.index, _cosMin, tuning.trams.turnProbeM, _scratch).isEmpty) {
          _deadEnd[2 * e.index + (node == e.to ? 1 : 0)] = 1;
        }
      }
    }
  }

  final World world;
  final TrackGraph graph;
  final Tuning tuning;
  final List<Tram> trams = [];

  /// All cars of all trams (`trams.items`): pose, heading, layer.
  final List<TramCar> items = [];

  /// Traffic cars that block the track (set by DriveWorld to `traffic.cars`).
  List<TrafficCar> traffic = const [];

  /// False = the player is a ghost to trams (benchmark autopilot, like `traffic.solid`).
  bool solid = true;

  /// Player hits so far.
  int hits = 0;

  /// Fixed steps since start.
  int stepCount = 0;

  final Prng _rng;
  final double _halfLength;
  final double _halfWidth;

  /// cos of `trams.max_switch_deg`: the sharpest turn that is still a track connection.
  final double _cosMin;

  /// Length of a whole tram, nose to tail (cars and the gaps between them).
  final double tramLength;

  /// Per edge and travel direction (2·edge + (dir > 0 ? 1 : 0)): the end node is a terminus.
  final Uint8List _deadEnd;
  final List<TramHitListener> _listeners = [];
  final List<int> _scratch = [];
  final Float64List _pt = Float64List(4);
  final Vector2 _v = Vector2.zero();
  final Vector2 _p = Vector2.zero();
  double _spawnTimer = 0;
  bool _fresh = true;
  bool _tracked = false;
  double _lastPX = 0;
  double _lastPY = 0;
  int _nextId = 1;

  TuningTrams get _t => tuning.trams;

  /// The generated stops (`trams.stops`).
  List<TrackStop> get stops => graph.stops;

  /// Registers a "tram hit by player" listener; returns the unsubscribe function.
  void Function() onHit(TramHitListener fn) {
    _listeners.add(fn);
    return () => _listeners.remove(fn);
  }

  /// Removes all trams and refills around the player on the next step.
  void reset() {
    for (final tr in trams) {
      for (final c in tr.cars) {
        c.body.destroy();
      }
    }
    trams.clear();
    items.clear();
    _fresh = true;
  }

  void dispose() {
    reset();
    _listeners.clear();
  }

  /// Before `world.step`: spawn/despawn, drive every tram, set the kinematic velocities.
  void preStep(double dt, Car player) {
    final t = _t;
    stepCount++;
    final px = player.x, py = player.y;
    final jx = px - _lastPX, jy = py - _lastPY;
    // A jump past the despawn radius (respawn, travel) leaves nothing to keep.
    if (_tracked && jx * jx + jy * jy > t.despawnM * t.despawnM) reset();
    _tracked = true;
    _lastPX = px;
    _lastPY = py;

    final d2 = t.despawnM * t.despawnM;
    for (var i = trams.length - 1; i >= 0; i--) {
      final tr = trams[i];
      final dx = tr.x - px, dy = tr.y - py;
      if (dx * dx + dy * dy > d2) _remove(i);
    }
    _spawn(dt, px, py);
    for (var i = trams.length - 1; i >= 0; i--) {
      if (!_drive(trams[i], dt, player)) _remove(i);
    }
  }

  /// After `world.step`: hit detection against the player (SAT on the boxes), body masks.
  /// [airborne]: the player is in a hop (specs/hop.md), so nothing touches it and no hit fires.
  void postStep(Car player, {bool airborne = false}) {
    final t = _t;
    final pv = player.velocity;
    final ph = player.heading, pc = math.cos(ph), ps = math.sin(ph);
    final round = tuning.drive.bodyRoundM;
    final phl = player.halfLength + round, phw = player.halfWidth + round;
    final margin = tuning.traffic.hitMarginM;
    for (final tr in trams) {
      var touch = false;
      var impact = 0.0;
      for (final c in tr.cars) {
        final same = solid && !airborne && c.layer == player.layer;
        _setMask(c, same);
        if (!same) continue;
        final ch = math.cos(c.heading), sh = math.sin(c.heading);
        if (!obbOverlap(player.x, player.y, pc, ps, phl, phw, c.x, c.y, ch, sh, c.halfLength, c.halfWidth, margin)) {
          continue;
        }
        touch = true;
        final rvx = pv.x - ch * tr.speed, rvy = pv.y - sh * tr.speed;
        impact = math.max(impact, math.sqrt(rvx * rvx + rvy * rvy));
      }
      if (touch && !tr.touching && impact >= t.hitMinMps) {
        tr
          ..hitTimer = t.hitStopS
          ..speed = 0;
        hits++;
        for (final fn in _listeners) {
          fn(tr, impact);
        }
      }
      tr.touching = touch;
    }
  }

  void _setMask(TramCar c, bool same) {
    final ground = c.layer == 0;
    final mask = (same ? catCar : 0) | (ground ? catTraffic | catParked : 0);
    if (mask == c.mask) return;
    c.mask = mask;
    c.shape.filter = Filter(categoryBits: catTram, maskBits: mask);
  }

  // ---------- spawning

  double _unit() => _rng.nextU32() / 4294967296;

  void _spawn(double dt, double px, double py) {
    final t = _t;
    if (_fresh) {
      _fresh = false;
      _spawnTimer = 0;
      for (var i = 0; i < t.maxTrams * t.spawnTries && trams.length < t.maxTrams; i++) {
        _trySpawn(px, py, t.initialMinM);
      }
      return;
    }
    _spawnTimer += dt;
    if (_spawnTimer < t.spawnIntervalS) return;
    _spawnTimer = 0;
    for (var i = 0; i < t.spawnTries && trams.length < t.maxTrams; i++) {
      _trySpawn(px, py, t.spawnMinM);
    }
  }

  bool _trySpawn(double px, double py, double rMin) {
    final t = _t;
    final a = _unit() * 2 * math.pi, r = rMin + _unit() * (t.spawnMaxM - rMin);
    final hit = graph.nearest(
      px + math.cos(a) * r,
      py + math.sin(a) * r,
      where: (e, d) => e.length > 0 && !e.tunnel && e.layerAt(d / e.length) == 0,
    );
    if (hit == null) return false;
    final hx = hit.x - px, hy = hit.y - py;
    final hd = math.sqrt(hx * hx + hy * hy);
    if (hd < rMin || hd > t.spawnMaxM) return false;
    for (final c in items) {
      final dx = c.x - hit.x, dy = c.y - hit.y;
      if (math.sqrt(dx * dx + dy * dy) < t.spawnClearM) return false;
    }
    final e = hit.edge;
    final dir = _rng.nextInt(2) == 0 ? 1 : -1;
    return addTram(e.index, dir, dir > 0 ? hit.d : e.length - hit.d) != null;
  }

  /// Puts a tram with its nose on track [edge] going [dir] (+1 from → to, −1 to → from), [s]
  /// metres along the travel direction. Null at the `max_trams` cap or for a bad edge.
  Tram? addTram(int edge, int dir, double s) {
    if (edge < 0 || edge >= graph.edges.length || trams.length >= _t.maxTrams) return null;
    final t = _t;
    final e = graph.edges[edge];
    final tr = Tram(
      _nextId++,
      e,
      dir > 0 ? 1 : -1,
      s.clamp(0.0, e.length),
      Prng(_rng.nextU32()),
      TramTrail(math.max(1, t.trailPoints), carM: t.carLengthM, gapM: t.jointGapM),
    );
    tr.entered = stepCount;
    // The path behind (v2): straightest predecessors, then this edge's points behind the nose.
    _seedBehind(tr);
    tr.nextPoint = 0;
    _passPoints(tr);
    _placeNose(tr);
    for (var k = 0; k < math.max(1, t.carsPerTram); k++) {
      final body = world.createBody(BodyDef(type: BodyType.kinematic, position: Vector2.zero()));
      final shape = body.createShape(
        Polygon.box(_halfLength, _halfWidth),
        ShapeDef(
          material: SurfaceMaterial(
            friction: tuning.drive.buildingFriction,
            restitution: tuning.drive.buildingRestitution,
          ),
          filter: Filter(categoryBits: catTram, maskBits: catCar | catTraffic | catParked),
        ),
      );
      final c = TramCar(tr, k, _halfLength, _halfWidth, body, shape);
      articulate(tr.trail, k, c);
      _p.setValues(c.x, c.y);
      body.setTransform(_p, Rot.fromAngle(c.heading));
      tr.cars.add(c);
      items.add(c);
    }
    trams.add(tr);
    return tr;
  }

  /// Pushes the points of edge [e] driven in direction [dir] whose distance along the travel
  /// direction is above [after] onto [out] as x, y, layer (travel order).
  void _edgePoints(TrackEdge e, int dir, double after, List<double> out) {
    final n = e.pointCount, len = e.length;
    for (var j = 0; j < n; j++) {
      final vi = dir > 0 ? j : n - 1 - j;
      final along = dir > 0 ? e.cum[vi] : len - e.cum[vi];
      if (along <= after) continue;
      out
        ..add(e.pts[2 * vi])
        ..add(e.pts[2 * vi + 1])
        ..add(e.layerAt(len > 0 ? e.cum[vi] / len : 0).toDouble());
    }
  }

  final List<double> _pts = [];
  final List<int> _seed = [];

  /// The path behind a new tram (specs/trams.md v2 "Hustota a vznik"): from the start of its edge
  /// back along the straightest connected edges until it covers the tram's length, a border
  /// node, a dead end or a full history.
  void _seedBehind(Tram tr) {
    final probeM = _t.turnProbeM;
    var to = tr.edge.index;
    var node = tr.dir > 0 ? tr.edge.from : tr.edge.to;
    var covered = tr.s;
    _seed.clear();
    while (covered < tramLength) {
      final p = straightestPrev(graph, node, to, _cosMin, probeM);
      if (p < 0) break;
      final pe = graph.edges[p];
      final pdir = pe.to == node ? 1 : -1;
      if (!tr.histPushOldest(p, pdir)) break;
      _seed
        ..add(p)
        ..add(pdir);
      covered += pe.length;
      node = pdir > 0 ? pe.from : pe.to;
      to = p;
    }
    // Oldest first onto the trail (push adds the newest; repeated node points are ignored).
    for (var i = _seed.length - 2; i >= 0; i -= 2) {
      _pts.clear();
      _edgePoints(graph.edges[_seed[i]], _seed[i + 1], -1, _pts);
      for (var j = 0; j < _pts.length; j += 3) {
        tr.trail.push(_pts[j], _pts[j + 1], _pts[j + 2].round());
      }
    }
  }

  /// Terminus (specs/trams.md v2, step 3): the tram stands with its nose on the end node and
  /// changes ends. The cars stay; the rear joint of the last car becomes the nose, the car order
  /// reverses and each car's heading turns by π (its axis does not move). False when the tail is
  /// not on the known path (the tram disappears).
  bool _reverse(Tram tr) {
    var rem = tramLength;
    var k = -1; // −1 = the current edge, else a history index
    var te = tr.edge;
    var td = tr.dir;
    while (rem > te.length) {
      rem -= te.length;
      k++;
      if (k >= tr.histCount) return false;
      te = graph.edges[tr.histEdge(k)];
      td = tr.histDir(k);
    }
    // Points from the tail to the old nose in old travel order, and the new history.
    _pts.clear();
    _edgePoints(te, td, te.length - rem, _pts);
    _seed.clear();
    for (var h = k - 1; h >= -1; h--) {
      final e = h >= 0 ? graph.edges[tr.histEdge(h)] : tr.edge;
      final dir = h >= 0 ? tr.histDir(h) : tr.dir;
      _edgePoints(e, dir, 0, _pts);
      _seed
        ..add(e.index)
        ..add(-dir);
    }
    tr.histClear();
    for (var i = 0; i < _seed.length; i += 2) {
      tr.histPushOldest(_seed[i], _seed[i + 1]);
    }
    // The tail edge driven back: s = rem along the new direction; its points up to s are behind.
    tr
      ..edge = te
      ..dir = -td
      ..s = rem;
    final n = te.pointCount, len = te.length;
    var np = 0;
    while (np < n) {
      final vi = tr.dir > 0 ? np : n - 1 - np;
      final along = tr.dir > 0 ? te.cum[vi] : len - te.cum[vi];
      if (along > tr.s) break;
      np++;
    }
    tr.nextPoint = np;
    // The new trail: the old nose is the oldest point, the point next to the tail the newest.
    tr.trail.clear();
    for (var j = _pts.length - 3; j >= 0; j -= 3) {
      tr.trail.push(_pts[j], _pts[j + 1], _pts[j + 2].round());
    }
    _placeNose(tr);
    // The cars: reversed order, headings turned by π, bodies placed directly (no spin).
    final cars = tr.cars.reversed.toList();
    tr.cars
      ..clear()
      ..addAll(cars);
    for (var i = 0; i < cars.length; i++) {
      final c = cars[i]
        ..k = i
        ..heading = _wrap(cars[i].heading + math.pi);
      _p.setValues(c.x, c.y);
      c.body.setTransform(_p, Rot.fromAngle(c.heading));
      c.body.linearVelocity = Vector2.zero();
      c.body.angularVelocity = 0;
    }
    tr
      ..speed = 0
      ..braking = false
      ..dwell = _t.dwellS
      ..stop = -1
      ..served = -1
      ..entered = stepCount
      ..reversals += 1;
    return true;
  }

  void _remove(int i) {
    final tr = trams[i];
    for (final c in tr.cars) {
      c.body.destroy();
      items.remove(c);
    }
    final last = trams.removeLast();
    if (!identical(last, tr)) trams[i] = last;
  }

  // ---------- driving

  /// One step of one tram; false = it has to disappear (border node).
  bool _drive(Tram tr, double dt, Car player) {
    final t = _t;
    if (tr.hitTimer > 0) {
      tr
        ..hitTimer = math.max(0, tr.hitTimer - dt)
        ..speed = 0
        ..braking = false;
    } else if (tr.dwell > 0) {
      tr
        ..dwell = math.max(0, tr.dwell - dt)
        ..speed = 0
        ..braking = false;
      if (tr.dwell == 0) {
        tr
          ..served = tr.stop
          ..stop = -1;
      }
    } else {
      if (tr.stop < 0) tr.stop = nextStopAhead(graph, tr.edge.index, tr.dir, tr.s, t.stopCommitM, skip: tr.served);
      var gap = _gapAhead(tr, player);
      // A terminus at the end of this edge: the nose halts on the end node (v2).
      if (_deadEnd[2 * tr.edge.index + (tr.dir > 0 ? 1 : 0)] == 1) {
        gap = math.min(gap, math.max(0.0, tr.edge.length - tr.s + t.minGapM));
      }
      var toStop = double.infinity;
      if (tr.stop >= 0) {
        toStop = stopTravelS(graph, tr.stop, tr.dir) - tr.s;
        if (toStop < -t.stopCommitM) {
          // Ran past it (an obstacle held the tram too close to brake): count it as served.
          tr
            ..served = tr.stop
            ..stop = -1;
        } else {
          // Stops with the nose on the stop.
          gap = math.min(gap, math.max(0.0, toStop + t.minGapM));
        }
      }
      final free = math.max(0.0, gap - t.minGapM);
      final want = math.min(t.speedMps, math.sqrt(2 * t.brakeMps2 * free));
      final dv = want - tr.speed;
      tr.braking = dv < -t.accelMps2 * dt;
      tr.speed = math.max(0, tr.speed + math.min(t.accelMps2 * dt, math.max(-t.brakeMps2 * dt, dv)));
      if (tr.stop >= 0 && toStop <= t.stopCommitM && tr.speed <= t.accelMps2 * dt) {
        tr
          ..speed = 0
          ..dwell = t.dwellS;
      }
    }
    tr.s += tr.speed * dt;
    _passPoints(tr);
    while (tr.s >= tr.edge.length) {
      final node = tr.dir > 0 ? tr.edge.to : tr.edge.from;
      final next = chooseNextTrack(graph, node, tr.edge.index, tr.rng, _cosMin, t.turnProbeM, _scratch);
      if (next < 0) return false;
      if (next == tr.edge.index) {
        // Terminus: the nose stands on the end node, the tram changes ends.
        tr.s = tr.edge.length;
        if (!_reverse(tr)) return false;
        break;
      }
      tr.histPush(tr.edge.index, tr.dir);
      tr.s -= tr.edge.length;
      final e = graph.edges[next];
      tr
        ..dir = e.from == node ? 1 : -1
        ..edge = e
        ..entered = stepCount
        ..stop = -1
        ..served = -1
        ..nextPoint = 1;
      _passPoints(tr);
    }
    _placeNose(tr);
    for (final c in tr.cars) {
      final ox = c.x, oy = c.y, oh = c.heading;
      articulate(tr.trail, c.k, c);
      _v.setValues((c.x - ox) / dt, (c.y - oy) / dt);
      c.body.linearVelocity = _v;
      c.body.angularVelocity = _wrap(c.heading - oh) / dt;
    }
    return true;
  }

  /// Pushes the polyline points of the current edge the nose has passed onto the trail.
  void _passPoints(Tram tr) {
    final e = tr.edge;
    final n = e.pointCount;
    final len = e.length;
    while (tr.nextPoint < n) {
      final vi = tr.dir > 0 ? tr.nextPoint : n - 1 - tr.nextPoint;
      final along = tr.dir > 0 ? e.cum[vi] : len - e.cum[vi];
      if (along > tr.s) break;
      tr.trail.push(e.pts[2 * vi], e.pts[2 * vi + 1], e.layerAt(len > 0 ? e.cum[vi] / len : 0));
      tr.nextPoint++;
    }
  }

  void _placeNose(Tram tr) {
    final e = tr.edge;
    final d = tr.dir > 0 ? tr.s : e.length - tr.s;
    e.sample(d.clamp(0.0, e.length), _pt);
    tr.layer = e.layerAt(e.length > 0 ? d / e.length : 0);
    tr.trail.setNose(_pt[0], _pt[1], _pt[2] * tr.dir, _pt[3] * tr.dir, tr.layer);
  }

  /// Free distance from the nose to the nearest obstacle on the track ahead (step 1): the player,
  /// a traffic car, another tram's car. Stops are handled by the caller.
  double _gapAhead(Tram tr, Car player) {
    final t = _t;
    final hc = tr.trail.dirX, hs = tr.trail.dirY;
    var gap = t.lookAheadM;
    if (solid && player.layer == tr.layer) {
      gap = math.min(gap, _gapTo(tr, hc, hs, player.x, player.y, player.heading, player.halfLength, player.halfWidth));
    }
    for (final c in traffic) {
      if (c.layer != tr.layer) continue;
      gap = math.min(gap, _gapTo(tr, hc, hs, c.x, c.y, c.heading, c.halfLength, c.halfWidth));
    }
    for (final o in trams) {
      if (identical(o, tr)) continue;
      // Oncoming on the same single track: only the tram that entered later waits.
      final oncomingHere =
          identical(o.edge, tr.edge) &&
          o.dir != tr.dir &&
          (tr.entered > o.entered || (tr.entered == o.entered && tr.id > o.id));
      for (final c in o.cars) {
        if (c.layer != tr.layer) continue;
        // Other trams count when going our way (±60°); a parallel track's oncoming tram does not.
        if (!oncomingHere && math.cos(c.heading) * hc + math.sin(c.heading) * hs < 0.5) continue;
        gap = math.min(gap, _gapTo(tr, hc, hs, c.x, c.y, c.heading, c.halfLength, c.halfWidth));
      }
    }
    return gap;
  }

  /// Gap from the nose to a box (centre, heading, half extents) whose centre lies within
  /// `corridor_m` of the track axis and reaches ahead of the nose within `look_ahead_m`.
  double _gapTo(Tram tr, double hc, double hs, double ox, double oy, double oh, double ohl, double ohw) {
    final t = _t;
    final dx = ox - tr.x, dy = oy - tr.y;
    final reach = t.lookAheadM + ohl + ohw;
    if (dx * dx + dy * dy > reach * reach) return double.infinity;
    final ly = -dx * hs + dy * hc;
    if (ly.abs() > t.corridorM) return double.infinity;
    final lx = dx * hc + dy * hs;
    final oc = math.cos(oh), os = math.sin(oh);
    final ext = ohl * (oc * hc + os * hs).abs() + ohw * (-oc * hs + os * hc).abs();
    if (lx + ext <= 0 || lx - ext > t.lookAheadM) return double.infinity;
    return math.max(0, lx - ext);
  }
}
