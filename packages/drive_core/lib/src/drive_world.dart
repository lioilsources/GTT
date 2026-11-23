import 'dart:math' as math;

import 'package:forge2d/forge2d.dart';
import 'package:world_engine/core.dart';

import 'car.dart';
import 'controls.dart';
import 'flow.dart';
import 'hop.dart';
import 'props.dart';
import 'traffic/traffic.dart';
import 'trams/trams.dart';
import 'zones.dart';

/// Tracks which road edge the car is on, and with it the layer (−1 tunnel, 0, +1 bridge).
///
/// The car only changes to an edge that shares a node with its current edge, so driving
/// under a bridge never lifts it onto the deck. On layers ≠ 0 the edge corridor acts as
/// rails (there are no buildings up there to stop the car).
class LayerTracker {
  LayerTracker(this.graph, this.t);
  final RoadGraph graph;
  final TuningLayers t;
  RoadEdge? edge;
  EdgeHit? hit;

  int get layer => hit == null ? 0 : hit!.edge.layerAt(hit!.t);

  void reset(double x, double y) {
    hit = graph.nearest(x, y, maxDist: t.spawnSearchM, where: (e) => e.isGround);
    edge = hit?.edge;
  }

  void update(double x, double y) {
    final cur = edge;
    final cands = graph.near(x, y, t.searchM);
    bool onIt(EdgeHit h) => h.dist <= h.edge.width / 2 + t.switchMarginM;
    EdgeHit? best;
    if (cur != null) {
      final adj = graph.neighbours(cur.index).toSet();
      for (final h in cands) {
        if (!adj.contains(h.edge.index) || !onIt(h)) continue;
        if (best == null || h.dist < best.dist) best = h;
      }
    }
    if (best == null) {
      // Off our edge's neighbourhood: re-acquire, staying on the current layer.
      final l = layer;
      for (final h in cands) {
        if (h.edge.layerAt(h.t) != l || !onIt(h)) continue;
        if (best == null || h.dist < best.dist) best = h;
      }
    }
    if (best != null) {
      edge = best.edge;
      hit = best;
    } else if (cur != null) {
      // Off-road (plaza, sidewalk): keep the edge, refresh the projection.
      EdgeHit? h;
      for (var s = 0; s + 1 < cur.pointCount; s++) {
        final p = graph.project(cur, s, x, y);
        if (h == null || p.dist < h.dist) h = p;
      }
      hit = h;
    }
  }
}

/// Physics for M0: one car, building colliders, layers, knockable street furniture.
/// Pure logic (no UI); the app draws from the public state.
class DriveWorld {
  DriveWorld({required this.city, required this.spec, required this.tuning}) : flow = FlowState(tuning.flow.rescue) {
    world = World(gravity: Vector2.zero());
    // Static contacts of the player's car (buildings, bollards) with their normal, every step
    // (specs/flow.md "Náraz do pevné překážky"); only the car shape has pre-solve events on.
    world.preSolveCallback = _preSolve;
    zones = Zones(world, tuning);
    layers = LayerTracker(city.graph, tuning.layers);
    spawn(city.startX, city.startY, city.startHeading);
    hop.fill(spec);
    traffic = tuning.traffic.enabled ? Traffic(world, city, tuning) : null;
    trams = tuning.trams.enabled && !city.trams.isEmpty ? Trams(world, city.trams, tuning) : null;
    final tr = traffic, tm = trams;
    if (tr != null && tm != null) {
      tr.tramCars = tm.items;
      tm.traffic = tr.cars;
    }
  }

  final City city;

  /// The car being driven; [replaceCar] switches it (specs/cars.md).
  CarSpec spec;
  final Tuning tuning;
  late final World world;
  late Car car;
  late final LayerTracker layers;

  /// Pedestrian zones and their bollards (specs/zones.md).
  late final Zones zones;

  /// AI traffic and lights (specs/traffic.md); null when `traffic.enabled` is off.
  late final Traffic? traffic;

  /// Trams on the track graph (specs/trams.md); null when `trams.enabled` is off or the city has
  /// no tracks.
  late final Trams? trams;
  final input = ControlInput();

  /// Air-tank hop of the driven car (specs/hop.md); full on load and after switching cars.
  final hop = HopState();
  final Map<int, Body> _colliders = {};
  final Map<int, PropSet> props = {};
  double time = 0;
  double _acc = 0;
  int knockedCount = 0;
  bool _spawned = false;

  /// Skid marks: x0, y0, x1, y1 per segment, newest last.
  final List<double> skids = [];
  (double, double, double, double)? _lastSkid;

  /// Grip multiplier of the player's car set by the client (rain, specs/weather.md); kept across
  /// respawns and car switches. The drive rules themselves stay those of specs/drive.md.
  double get gripScale => _gripScale;
  set gripScale(double v) {
    _gripScale = v;
    if (_spawned) car.gripScale = v;
  }

  double _gripScale = 1;

  /// The parameters the body of the player's car is built from (specs/garage.md "Účinek na jízdu"):
  /// the client maps the catalog [spec] to the tuned one of an owned car; null or the same spec =
  /// the catalog. Applied at every spawn, car switch and rebuild; [spec] stays the catalog car.
  CarSpec Function(CarSpec spec)? bodySpec;

  CarSpec get _bodySpec => bodySpec?.call(spec) ?? spec;

  /// Wall response, trail and rescue (specs/flow.md, F-069).
  final FlowState flow;

  /// An open context menu that does not pause (specs/flow.md: no automatic rescue then); none in F:
  /// every menu over the world pauses it, and a shown context button does not block.
  bool Function() flowBlocked = () => false;

  /// The GPS route still ahead (interleaved metres) or null; the road move faces along it.
  List<double>? Function() routeAhead = () => null;

  /// Called after every rescue move (automatic or manual) with its kind.
  void Function(StuckKind kind)? onRescue;

  /// Static contact in the previous step; a head-on bounce needs a new contact.
  bool wallContact = false;

  /// The head-on bounce (with the 1 m unstick) is armed; see [_wallStep].
  bool _bounceArmed = true;
  double _freeT = 0;

  // Velocity before the step (the "v before contact" of specs/flow.md).
  double _preVx = 0, _preVy = 0;

  /// Normals (from the wall to the car) of this step's static contacts, filled by [_preSolve].
  final List<double> _contactN = [];

  bool _preSolve(Shape a, Shape b, Vector2 normal) {
    final s = car.shape;
    final mine = a == s;
    if (!mine && b != s) return true;
    final other = mine ? b : a;
    if (other.filter.categoryBits & (catBuildings | catZone) == 0) return true;
    // Box2D's normal points from A to B; n must point from the wall to the car.
    _contactN.addAll(mine ? [-normal.x, -normal.y] : [normal.x, normal.y]);
    return true;
  }

  /// Called before every fixed step (the benchmark autopilot sets the input here).
  void Function(double step)? beforeStep;

  TuningDrive get _d => tuning.drive;

  void spawn(double x, double y, double heading) {
    if (_spawned) car.destroy();
    hop
      ..air = 0
      ..t = 0;
    car = Car(world, _bodySpec, _d, x: x, y: y, heading: heading, scale: tuning.carScale)..gripScale = _gripScale;
    _spawned = true;
    layers.reset(x, y);
    car.setLayer(layers.layer);
    _zoneMask();
    flow.reset();
    wallContact = false;
    _bounceArmed = true;
    _freeT = 0;
  }

  /// Switches to another car: a new body with that car's parameters, at rest (specs/cars.md).
  void replaceCar(CarSpec next, double x, double y, double heading) {
    spec = next;
    _lastSkid = null;
    spawn(x, y, heading);
    hop.fill(next);
  }

  /// The HUD "Hop" button (specs/hop.md): takes off when [canHop] allows; true when it did.
  bool startHop() {
    if (!hop.start(spec, car.layer, car.speed, tuning.hop)) return false;
    car.setAirborne(true);
    _lastSkid = null;
    return true;
  }

  /// Whether the hop button is live now.
  bool get hopReady => canHop(spec, hop.charges, hop.air, car.layer, car.speed, tuning.hop);

  /// Free garage refill (specs/hop.md "Doplnění"); false when there is nothing to refill.
  bool refillHop() {
    if (!hop.canRefill(spec)) return false;
    hop.charges = hopCharges(spec)!;
    return true;
  }

  /// Rebuilds the car after `car_scale` changed in the debug panel.
  void rescaleCar() => _rebuild(keepVelocity: true);

  /// Builds the body again from [bodySpec] in the same place at speed 0 (leaving the garage with
  /// new upgrades, specs/garage.md).
  void rebuildCar() => _rebuild(keepVelocity: false);

  void _rebuild({required bool keepVelocity}) {
    final x = car.x, y = car.y, h = car.heading, v = car.velocity.clone();
    final l = car.layer;
    car.destroy();
    car = Car(world, _bodySpec, _d, x: x, y: y, heading: h, scale: tuning.carScale)..gripScale = _gripScale;
    if (keepVelocity) car.body.linearVelocity = v;
    car.setLayer(l);
    car.setAirborne(hop.airborne);
    _zoneMask();
  }

  void addChunk(ChunkData c) {
    final key = City.chunkKey(c.x, c.y);
    if (_colliders.containsKey(key)) return;
    final body = world.createBody(BodyDef(type: BodyType.static));
    // Pushed parked cars and loose traffic cars stop at walls.
    final filter = Filter(categoryBits: catBuildings, maskBits: catCar | catParked | catTraffic);
    // Static contacts use flow.wall friction and restitution (specs/flow.md), not drive.building_*.
    final w = tuning.flow.wall;
    final material = SurfaceMaterial(friction: w.friction, restitution: w.restitution);
    for (final b in c.buildings) {
      if (!b.collide) continue;
      var start = 0;
      for (final end in b.ringEnds) {
        final n = end - start;
        final pts = <Vector2>[for (var i = start; i < end; i++) Vector2(b.xy[2 * i], b.xy[2 * i + 1])];
        start = end;
        try {
          if (n >= 4) {
            body.createChain(ChainDef(points: pts, isLoop: true, filter: filter, materials: [material]));
          } else if (n == 3) {
            body.createShape(Polygon(pts), ShapeDef(filter: filter, material: material));
          }
        } on ArgumentError {
          // Degenerate ring (collinear points); skip it.
        }
      }
    }
    _colliders[key] = body;
    props[key] = generateProps(city.graph, c.x, c.y, tuning);
    zones.add(c);
  }

  void removeChunk(ChunkData c) {
    final key = City.chunkKey(c.x, c.y);
    _colliders.remove(key)?.destroy();
    props.remove(key);
    zones.remove(c);
  }

  /// Advances with a fixed step (`drive.step_hz`).
  void update(double dt) {
    final step = 1 / _d.stepHz;
    _acc = math.min(_acc + dt, step * 6);
    while (_acc >= step) {
      _acc -= step;
      _fixedStep(step);
    }
  }

  void _fixedStep(double step) {
    time += step;
    beforeStep?.call(step);
    final flying = hop.airborne;
    final frozen = flow.animT > 0;
    if (frozen) {
      // Rescue animation (specs/flow.md): the car stands where it was put.
      _hold();
    } else if (flying) {
      car.fly();
    } else {
      car.drive(input, step, cruise: tuning.speedMps.cruise, top: tuning.speedMps.topDefault);
    }
    traffic?.preStep(step, car);
    trams?.preStep(step, car);
    final pv = car.velocity;
    _preVx = pv.x;
    _preVy = pv.y;
    _contactN.clear();
    world.step(step, subStepCount: _d.substeps);
    (double, double)? rail;
    if (flying) {
      // In the air the layer, the zone bit and the hit events stay out (specs/hop.md).
      car.body.angularVelocity = 0;
      traffic?.postStep(car, airborne: true);
      trams?.postStep(car, airborne: true);
      _props(step);
      if (hop.step(step)) _land();
    } else {
      layers.update(car.x, car.y);
      car.setLayer(layers.layer);
      _zoneMask();
      traffic?.postStep(car);
      trams?.postStep(car);
      if (car.layer != 0) rail = _rails();
      _props(step);
      _skidMarks();
    }
    if (frozen) {
      _hold();
    } else {
      _wallStep(step, rail);
    }
    _rescueStep(step);
  }

  void _hold() {
    car.body
      ..linearVelocity = Vector2.zero()
      ..angularVelocity = 0;
  }

  /// Static contact response (specs/flow.md "Náraz do pevné překážky") after the physics step. The
  /// contact normal is the one the pre-step velocity drives into most (smallest v·n). A slide
  /// applies in every step of contact; the head-on bounce only on a new contact while armed: it
  /// disarms itself until the car has been free of static contact for flow.rescue.stuck_time_s or
  /// was rescued, so a car pushing into a wall comes to rest there (and is rescued) instead of
  /// bouncing forever.
  void _wallStep(double step, (double, double)? rail) {
    final body = car.body;
    final vx = _preVx, vy = _preVy;
    var nx = 0.0, ny = 0.0, best = double.infinity;
    for (var i = 0; i + 1 < _contactN.length; i += 2) {
      final sx = _contactN[i], sy = _contactN[i + 1];
      final vn = vx * sx + vy * sy;
      if (vn < best) {
        best = vn;
        nx = sx;
        ny = sy;
      }
    }
    if (rail != null) {
      final vn = vx * rail.$1 + vy * rail.$2;
      if (vn < best) {
        best = vn;
        nx = rail.$1;
        ny = rail.$2;
      }
    }
    final contact = best != double.infinity;
    final isNew = contact && !wallContact;
    wallContact = contact;
    if (!contact) {
      _freeT += step;
      if (_freeT >= tuning.flow.rescue.stuckTimeS) _bounceArmed = true;
      return;
    }
    _freeT = 0;
    final r = wallResponse(vx, vy, nx, ny, tuning.flow.wall);
    if (r == null) return;
    if (r.slide) {
      body.linearVelocity = Vector2(r.vx, r.vy);
      body.setTransform(body.position.clone(), Rot.fromAngle(easeHeading(body.angle, r.tx, r.ty, step)));
      body.angularVelocity = body.angularVelocity * slideSpinKeep;
    } else if (isNew && _bounceArmed) {
      _bounceArmed = false;
      final p = body.position;
      body.setTransform(Vector2(p.x + nx * unstickM, p.y + ny * unstickM), body.rotation);
      body
        ..linearVelocity = Vector2(r.vx, r.vy)
        ..angularVelocity = 0;
    }
  }

  /// Trail and automatic rescue (specs/flow.md "Vyproštění"); the move itself is [_place].
  void _rescueStep(double step) {
    final plan = flow.step(
      step,
      time,
      FlowCar(
        x: car.x,
        y: car.y,
        heading: car.heading,
        speed: car.speed,
        braking: input.brake > 0 || input.handbrake,
        airborne: car.airborne,
      ),
      flowBlocked(),
    );
    if (plan == null) return;
    final p = plan.point;
    if (p == null) {
      _toRoadSpot();
    } else {
      _place(p.x, p.y, p.heading);
    }
    onRescue?.call(plan.kind);
  }

  /// "Na silnici" (button or pause menu, specs/flow.md): the road move, free, counted as stuck.
  /// Returns false when the city has no kept ground road.
  bool toRoad() {
    flow.manual(time, car.x, car.y);
    final ok = _toRoadSpot();
    onRescue?.call(StuckKind.button);
    return ok;
  }

  bool _toRoadSpot() {
    final s = roadSpot(city.graph, car.x, car.y, routeAhead(), tuning.layers.searchM);
    if (s == null) return false;
    _place(s.x, s.y, s.heading);
    return true;
  }

  /// The rescue move: the same body, at rest, on the ground at (x, y).
  void _place(double x, double y, double heading) {
    car.body.setTransform(Vector2(x, y), Rot.fromAngle(heading));
    _hold();
    car.wheelAngle = 0;
    layers.reset(x, y);
    car.setLayer(layers.layer);
    _zoneMask();
    _lastSkid = null;
    wallContact = false;
    _bounceArmed = true;
    _freeT = 0;
  }

  /// Landing: the mask goes back by layer and zones; a car that lands inside a zone or right on its
  /// bollards keeps the zone bit off until it is clear (the same hold-off as driving out).
  void _land() {
    car.setAirborne(false);
    layers.update(car.x, car.y);
    car.setLayer(layers.layer);
    car.setInsideZone(car.layer == 0 && zones.insideFor(car.x, car.y, car.boundingRadius, wasInside: true));
  }

  /// Drops the bollards from the player's mask while its centre is inside a zone (specs/zones.md).
  /// The zone bit only matters on layer 0 (Car.maskBits), so other layers skip the test.
  void _zoneMask() => car.setInsideZone(
      car.layer == 0 && zones.insideFor(car.x, car.y, car.boundingRadius, wasInside: car.zoneBits == 0));

  /// Keeps the car on bridge decks and in tunnels; returns the rail's normal (towards the road) when
  /// the car moved into it, a static contact for [_wallStep] (specs/flow.md: bridge rails).
  (double, double)? _rails() {
    final h = layers.hit;
    if (h == null || h.dist == 0) return null;
    final limit = math.max(0.0, h.edge.width / 2 - car.halfWidth * tuning.layers.railMargin);
    if (h.dist <= limit) return null;
    final nx = (car.x - h.x) / h.dist, ny = (car.y - h.y) / h.dist;
    final v = car.velocity;
    final out = v.x * nx + v.y * ny;
    car.body.setTransform(Vector2(h.x + nx * limit, h.y + ny * limit), car.body.rotation);
    if (out > 0) {
      final k = out * tuning.layers.railBounce;
      car.body.linearVelocity = Vector2(v.x - nx * k, v.y - ny * k);
      return (-nx, -ny);
    }
    return null;
  }

  void _props(double step) {
    final t = tuning.props;
    final rot = car.body.rotation;
    final cx = car.x, cy = car.y;
    final v = car.velocity;
    final speed = v.length;
    final damp = math.pow(t.flyDamping, step).toDouble();
    for (final set in props.values) {
      for (final p in set.props) {
        if (p.knocked) {
          final age = time - p.knockedAt;
          if (age < t.flyS) {
            p
              ..ox += p.vx * step
              ..oy += p.vy * step
              ..rot += p.spin * step
              ..vx *= damp
              ..vy *= damp
              ..spin *= damp;
          } else if (age > t.respawnS) {
            p
              ..knocked = false
              ..ox = 0
              ..oy = 0
              ..rot = 0;
          }
          continue;
        }
        if (car.layer != 0 || car.airborne || speed < t.knockMinMps) continue;
        final dx = p.x - cx, dy = p.y - cy;
        final reachX = car.halfLength + p.radius, reachY = car.halfWidth + p.radius;
        if (dx.abs() > reachX + reachY || dy.abs() > reachX + reachY) continue;
        final lx = dx * rot.cos + dy * rot.sin, ly = -dx * rot.sin + dy * rot.cos;
        if (lx.abs() > reachX || ly.abs() > reachY) continue;
        final side = ly >= 0 ? 1.0 : -1.0;
        p
          ..knocked = true
          ..knockedAt = time
          ..vx = v.x * t.knockCarry - side * rot.sin * speed * t.knockSide
          ..vy = v.y * t.knockCarry + side * rot.cos * speed * t.knockSide
          ..spin = side * (t.knockSpin + speed * t.knockSpinPerMps);
        knockedCount++;
        car.body.linearVelocity = v * t.knockSlowdown;
      }
    }
  }

  void _skidMarks() {
    final s = tuning.skids;
    if (car.rearSlip < s.minSlipMps && !(car.braking && car.speed > s.brakeMinMps)) {
      _lastSkid = null;
      return;
    }
    final rot = car.body.rotation;
    final off = -car.axleOffset;
    final side = car.halfWidth;
    final rx = car.x + rot.cos * off, ry = car.y + rot.sin * off;
    final l = (rx - rot.sin * side, ry + rot.cos * side), r = (rx + rot.sin * side, ry - rot.cos * side);
    final last = _lastSkid;
    if (last != null) {
      skids.addAll([last.$1, last.$2, l.$1, l.$2, last.$3, last.$4, r.$1, r.$2]);
      final max = s.maxSegments * 4;
      if (skids.length > max) skids.removeRange(0, skids.length - max);
    }
    _lastSkid = (l.$1, l.$2, r.$1, r.$2);
  }

  /// Props within [radius] of (x, y).
  Iterable<Prop> propsNear(double x, double y, double radius) sync* {
    for (final set in props.values) {
      for (final p in set.props) {
        if ((p.x - x).abs() < radius && (p.y - y).abs() < radius) yield p;
      }
    }
  }

  /// Distance from the car to the nearest roadblock on its edge's neighbourhood, or null.
  double? borderDistance() {
    final g = city.graph;
    final e = layers.edge;
    if (e == null) return null;
    double? best;
    for (final ei in g.neighbours(e.index)) {
      final n = g.edges[ei];
      for (final node in [n.from, n.to]) {
        if (!g.border[node]) continue;
        final dx = g.nodeXY[2 * node] - car.x, dy = g.nodeXY[2 * node + 1] - car.y;
        final d = math.sqrt(dx * dx + dy * dy);
        if (best == null || d < best) best = d;
      }
    }
    return best;
  }

  void dispose() {
    traffic?.dispose();
    trams?.dispose();
    world.destroy();
  }
}
