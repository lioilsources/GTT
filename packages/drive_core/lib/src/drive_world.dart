import 'dart:math' as math;

import 'package:forge2d/forge2d.dart';
import 'package:world_engine/world_engine.dart';

import 'car.dart';
import 'car_spec.dart';
import 'controls.dart';
import 'props.dart';

/// Ground-layer building colliders of one loaded chunk.
class _ChunkColliders {
  _ChunkColliders(this.body);
  final Body body;
}

/// Tracks which road edge the car is on, and with it the layer (−1 tunnel, 0, +1 bridge).
///
/// The car only changes to an edge that shares a node with its current edge, so driving
/// under a bridge never lifts it onto the deck. On layers ≠ 0 the edge corridor acts as
/// rails (there are no buildings up there to stop the car).
class LayerTracker {
  LayerTracker(this.graph);
  final RoadGraph graph;
  RoadEdge? edge;
  EdgeHit? hit;

  int get layer => hit == null ? 0 : hit!.edge.layerAt(hit!.t);

  void reset(double x, double y) {
    hit = graph.nearest(x, y, maxDist: 200, where: (e) => e.isGround);
    edge = hit?.edge;
  }

  void update(double x, double y) {
    final cur = edge;
    final cands = graph.near(x, y, 30);
    EdgeHit? best;
    if (cur != null) {
      final adj = graph.neighbours(cur.index).toSet();
      for (final h in cands) {
        if (!adj.contains(h.edge.index)) continue;
        if (h.dist > h.edge.width / 2 + 2) continue;
        if (best == null || h.dist < best.dist) best = h;
      }
    }
    if (best == null) {
      // Off our edge's neighbourhood: re-acquire, staying on the current layer.
      final l = layer;
      for (final h in cands) {
        if (h.edge.layerAt(h.t) != l || h.dist > h.edge.width / 2 + 2) continue;
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
class DriveWorld {
  DriveWorld({required this.city, required this.spec, required this.tuning}) {
    world = World(gravity: Vector2.zero());
    layers = LayerTracker(city.graph);
    spawn(city.startX, city.startY, city.startHeading);
  }

  final City city;
  final CarSpec spec;
  final Tuning tuning;
  late final World world;
  late Car car;
  late final LayerTracker layers;
  final input = ControlInput();
  final Map<int, _ChunkColliders> _colliders = {};
  final Map<int, PropSet> props = {};
  double time = 0;
  double _acc = 0;
  int knockedCount = 0;

  /// Skid marks: x0, y0, x1, y1 per segment, newest last.
  final List<double> skids = [];
  static const _maxSkids = 600;

  static const double step = 1 / 60;

  void spawn(double x, double y, double heading) {
    if (_spawned) car.destroy();
    car = Car(world, spec, x: x, y: y, heading: heading, scale: tuning.carScale);
    _spawned = true;
    layers.reset(x, y);
    car.setLayer(layers.layer);
  }

  bool _spawned = false;

  /// Rebuilds the car after `car_scale` changed in the debug panel.
  void rescaleCar() {
    final x = car.x, y = car.y, h = car.heading, v = car.velocity;
    final l = car.layer;
    car.destroy();
    car = Car(world, spec, x: x, y: y, heading: h, scale: tuning.carScale);
    car.body.linearVelocity = v;
    car.setLayer(l);
  }

  void addChunk(LoadedChunk c) {
    final key = c.key;
    if (_colliders.containsKey(key)) return;
    final body = world.createBody(BodyDef(type: BodyType.static));
    for (final b in c.data.buildings) {
      if (!b.collide) continue;
      var start = 0;
      for (final end in b.ringEnds) {
        final n = end - start;
        final pts = <Vector2>[for (var i = start; i < end; i++) Vector2(b.xy[2 * i], b.xy[2 * i + 1])];
        start = end;
        try {
          if (n >= 4) {
            body.createChain(ChainDef(
              points: pts,
              isLoop: true,
              filter: Filter(categoryBits: catBuildings, maskBits: catCar),
              materials: [SurfaceMaterial(friction: 0.2, restitution: 0.12)],
            ));
          } else if (n == 3) {
            body.createShape(Polygon(pts), ShapeDef(filter: Filter(categoryBits: catBuildings, maskBits: catCar)));
          }
        } on ArgumentError {
          // Degenerate ring (collinear points); skip it.
        }
      }
    }
    _colliders[key] = _ChunkColliders(body);
    props[key] = generateProps(city.graph, c.data.x, c.data.y, city.chunkM, tuning.sidewalkWidthM, tuning.carScale);
  }

  void removeChunk(LoadedChunk c) {
    _colliders.remove(c.key)?.body.destroy();
    props.remove(c.key);
  }

  /// Advances with a fixed 60 Hz step.
  void update(double dt) {
    _acc = math.min(_acc + dt, 0.1);
    while (_acc >= step) {
      _acc -= step;
      _fixedStep();
    }
  }

  void _fixedStep() {
    time += step;
    car.drive(input, step, cruise: tuning.cruiseMps, top: tuning.topMps);
    world.step(step);
    layers.update(car.x, car.y);
    car.setLayer(layers.layer);
    if (car.layer != 0) _rails();
    _props();
    _skidMarks();
  }

  /// Keeps the car on bridge decks and in tunnels.
  void _rails() {
    final h = layers.hit;
    if (h == null) return;
    final limit = math.max(1.0, h.edge.width / 2 - car.halfWidth * 0.6);
    if (h.dist <= limit) return;
    final nx = (car.x - h.x) / h.dist, ny = (car.y - h.y) / h.dist;
    final px = h.x + nx * limit, py = h.y + ny * limit;
    final v = car.velocity;
    final out = v.x * nx + v.y * ny;
    car.body.setTransform(Vector2(px, py), car.body.rotation);
    if (out > 0) {
      car.body.linearVelocity = Vector2(v.x - nx * out * 1.25, v.y - ny * out * 1.25);
    }
  }

  void _props() {
    final rot = car.body.rotation;
    final cx = car.x, cy = car.y;
    final v = car.velocity;
    final speed = v.length;
    final reach = car.halfLength + 3;
    for (final set in props.values) {
      for (final p in set.props) {
        if (p.knocked) {
          final age = time - p.knockedAt;
          if (age < 2.5) {
            p.ox += p.vx * step;
            p.oy += p.vy * step;
            p.rot += p.spin * step;
            final f = math.pow(0.08, step).toDouble();
            p.vx *= f;
            p.vy *= f;
            p.spin *= f;
          } else if (age > respawnSeconds) {
            p
              ..knocked = false
              ..ox = 0
              ..oy = 0
              ..rot = 0;
          }
          continue;
        }
        if (car.layer != 0) continue;
        final dx = p.x - cx, dy = p.y - cy;
        if (dx.abs() > reach || dy.abs() > reach) continue;
        final lx = dx * rot.cos + dy * rot.sin, ly = -dx * rot.sin + dy * rot.cos;
        if (lx.abs() > car.halfLength + p.radius || ly.abs() > car.halfWidth + p.radius) continue;
        if (speed < 1.5) continue;
        p
          ..knocked = true
          ..knockedAt = time
          ..vx = v.x * 0.9 + (ly.sign) * -rot.sin * speed * 0.3
          ..vy = v.y * 0.9 + (ly.sign) * rot.cos * speed * 0.3
          ..spin = (ly >= 0 ? 1 : -1) * (4 + speed * 0.2);
        knockedCount++;
        car.body.linearVelocity = v * 0.94;
      }
    }
  }

  void _skidMarks() {
    if (car.rearSlip < 2.5 && !(car.braking && car.speed > 12)) {
      _lastSkid = null;
      return;
    }
    final rot = car.body.rotation;
    final off = -car.halfLength * 0.62;
    final side = car.halfWidth * 0.8;
    final rx = car.x + rot.cos * off, ry = car.y + rot.sin * off;
    final l = (rx - rot.sin * side, ry + rot.cos * side), r = (rx + rot.sin * side, ry - rot.cos * side);
    final last = _lastSkid;
    if (last != null) {
      skids.addAll([last.$1, last.$2, l.$1, l.$2, last.$3, last.$4, r.$1, r.$2]);
      if (skids.length > _maxSkids * 4) skids.removeRange(0, skids.length - _maxSkids * 4);
    }
    _lastSkid = (l.$1, l.$2, r.$1, r.$2);
  }

  (double, double, double, double)? _lastSkid;

  /// Props within [radius] of (x, y).
  Iterable<Prop> propsNear(double x, double y, double radius) sync* {
    for (final set in props.values) {
      for (final p in set.props) {
        if ((p.x - x).abs() < radius && (p.y - y).abs() < radius) yield p;
      }
    }
  }

  void dispose() => world.destroy();
}
