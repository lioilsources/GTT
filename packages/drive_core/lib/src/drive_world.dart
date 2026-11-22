import 'dart:math' as math;

import 'package:forge2d/forge2d.dart';
import 'package:world_engine/core.dart';

import 'car.dart';
import 'controls.dart';
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
  DriveWorld({required this.city, required this.spec, required this.tuning}) {
    world = World(gravity: Vector2.zero());
    zones = Zones(world, tuning);
    layers = LayerTracker(city.graph, tuning.layers);
    spawn(city.startX, city.startY, city.startHeading);
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
  final Map<int, Body> _colliders = {};
  final Map<int, PropSet> props = {};
  double time = 0;
  double _acc = 0;
  int knockedCount = 0;
  bool _spawned = false;

  /// Skid marks: x0, y0, x1, y1 per segment, newest last.
  final List<double> skids = [];
  (double, double, double, double)? _lastSkid;

  /// Called before every fixed step (the benchmark autopilot sets the input here).
  void Function(double step)? beforeStep;

  TuningDrive get _d => tuning.drive;

  void spawn(double x, double y, double heading) {
    if (_spawned) car.destroy();
    car = Car(world, spec, _d, x: x, y: y, heading: heading, scale: tuning.carScale);
    _spawned = true;
    layers.reset(x, y);
    car.setLayer(layers.layer);
    _zoneMask();
  }

  /// Switches to another car: a new body with that car's parameters, at rest (specs/cars.md).
  void replaceCar(CarSpec next, double x, double y, double heading) {
    spec = next;
    _lastSkid = null;
    spawn(x, y, heading);
  }

  /// Rebuilds the car after `car_scale` changed in the debug panel.
  void rescaleCar() {
    final x = car.x, y = car.y, h = car.heading, v = car.velocity;
    final l = car.layer;
    car.destroy();
    car = Car(world, spec, _d, x: x, y: y, heading: h, scale: tuning.carScale);
    car.body.linearVelocity = v;
    car.setLayer(l);
    _zoneMask();
  }

  void addChunk(ChunkData c) {
    final key = City.chunkKey(c.x, c.y);
    if (_colliders.containsKey(key)) return;
    final body = world.createBody(BodyDef(type: BodyType.static));
    // Pushed parked cars and loose traffic cars stop at walls.
    final filter = Filter(categoryBits: catBuildings, maskBits: catCar | catParked | catTraffic);
    final material = SurfaceMaterial(friction: _d.buildingFriction, restitution: _d.buildingRestitution);
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
    car.drive(input, step, cruise: tuning.speedMps.cruise, top: tuning.speedMps.topDefault);
    traffic?.preStep(step, car);
    trams?.preStep(step, car);
    world.step(step, subStepCount: _d.substeps);
    layers.update(car.x, car.y);
    car.setLayer(layers.layer);
    _zoneMask();
    traffic?.postStep(car);
    trams?.postStep(car);
    if (car.layer != 0) _rails();
    _props(step);
    _skidMarks();
  }

  /// Drops the bollards from the player's mask while its centre is inside a zone (specs/zones.md).
  /// The zone bit only matters on layer 0 (Car.maskBits), so other layers skip the test.
  void _zoneMask() => car.setInsideZone(
      car.layer == 0 && zones.insideFor(car.x, car.y, car.boundingRadius, wasInside: car.zoneBits == 0));

  /// Keeps the car on bridge decks and in tunnels.
  void _rails() {
    final h = layers.hit;
    if (h == null || h.dist == 0) return;
    final limit = math.max(0.0, h.edge.width / 2 - car.halfWidth * tuning.layers.railMargin);
    if (h.dist <= limit) return;
    final nx = (car.x - h.x) / h.dist, ny = (car.y - h.y) / h.dist;
    final v = car.velocity;
    final out = v.x * nx + v.y * ny;
    car.body.setTransform(Vector2(h.x + nx * limit, h.y + ny * limit), car.body.rotation);
    if (out > 0) {
      final k = out * tuning.layers.railBounce;
      car.body.linearVelocity = Vector2(v.x - nx * k, v.y - ny * k);
    }
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
        if (car.layer != 0 || speed < t.knockMinMps) continue;
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
