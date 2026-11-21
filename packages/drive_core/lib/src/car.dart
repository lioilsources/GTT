import 'dart:math' as math;

import 'package:forge2d/forge2d.dart';

import 'car_spec.dart';
import 'controls.dart';

/// Collision categories.
const int catBuildings = 1;
const int catCar = 2;

/// Player car on a Box2D body with a custom tyre model (METROPOLE_PLAN 7.2):
/// each step the lateral velocity at each axle is cancelled by an impulse capped by
/// that axle's grip; past the cap the axle slides, which is the drift.
class Car {
  Car(this.world, this.spec, {required double x, required double y, required double heading, required this.scale}) {
    halfLength = spec.lengthM * scale / 2;
    halfWidth = spec.widthM * scale / 2;
    body = world.createBody(BodyDef(
      type: BodyType.dynamic,
      position: Vector2(x, y),
      rotation: Rot.fromAngle(heading),
      angularDamping: 1.2,
      linearDamping: 0.0,
      isBullet: true,
    ));
    _shape = body.createShape(
      Polygon.box(halfLength, halfWidth, radius: 0.4),
      ShapeDef(
        density: spec.mass / (4 * halfLength * halfWidth),
        material: SurfaceMaterial(friction: 0.25, restitution: 0.15),
        filter: Filter(categoryBits: catCar, maskBits: catBuildings),
        enableContactEvents: true,
      ),
    );
  }

  final World world;
  final CarSpec spec;
  final double scale;
  late final Body body;
  late Shape _shape;
  late final double halfLength;
  late final double halfWidth;

  /// Current front wheel angle (radians, + = left).
  double wheelAngle = 0;
  int layer = 0;

  /// Lateral slip of the rear axle in the last step, m/s (skid marks, smoke).
  double rearSlip = 0;
  double frontSlip = 0;
  bool braking = false;
  bool reversing = false;

  double get x => body.position.x;
  double get y => body.position.y;
  double get heading => body.angle;
  Vector2 get velocity => body.linearVelocity;
  double get speed => body.linearVelocity.length;

  /// Signed speed along the car's nose.
  double get forwardSpeed {
    final r = body.rotation;
    final v = body.linearVelocity;
    return v.x * r.cos + v.y * r.sin;
  }

  /// Sideways slip angle of the whole car (radians), 0 when rolling straight.
  double get slipAngle {
    final r = body.rotation;
    final v = body.linearVelocity;
    final f = v.x * r.cos + v.y * r.sin;
    final l = -v.x * r.sin + v.y * r.cos;
    if (v.length < 3) return 0;
    return math.atan2(l, f.abs());
  }

  void setLayer(int l) {
    if (l == layer) return;
    layer = l;
    // Buildings only exist on the ground layer; bridges and tunnels use rails instead.
    _shape.filter = Filter(categoryBits: catCar, maskBits: l == 0 ? catBuildings : 0);
  }

  /// Applies controls and tyre forces; call before `world.step(dt)`.
  void drive(ControlInput input, double dt, {required double cruise, required double top}) {
    final rot = body.rotation;
    final fx = rot.cos, fy = rot.sin; // nose
    final v = body.linearVelocity;
    final w = body.angularVelocity;
    final m = body.mass;
    final speedF = v.x * fx + v.y * fy;
    final speed = v.length;
    final topSpeed = math.min(top, spec.topSpeed);

    // Steering: wheels turn at steer_speed, less lock at speed.
    final lock = 0.62 - 0.42 * (speed / math.max(topSpeed, 1)).clamp(0.0, 1.0);
    var target = -input.steer * lock;
    // Counter-steer assist while drifting forward.
    final slip = slipAngle;
    if (speedF > 4 && slip.abs() > 0.12 && input.steer.abs() < 0.9) {
      target += (slip * 0.55).clamp(-lock, lock);
    }
    final maxStep = spec.steerSpeed * dt;
    wheelAngle += (target - wheelAngle).clamp(-maxStep, maxStep);

    // Longitudinal: auto-throttle to cruise (or top with boost), brake, reverse.
    final wantSpeed = input.boost ? topSpeed : math.min(cruise, topSpeed);
    var drive = 0.0;
    braking = false;
    reversing = false;
    if (input.brake > 0) {
      if (speedF > 1.0) {
        drive = -spec.brake * input.brake;
        braking = true;
      } else {
        // Reverse up to 9 m/s.
        reversing = true;
        drive = speedF > -9 ? -spec.power * 0.6 : 0;
      }
    } else {
      final thr = input.throttle > 0 ? input.throttle : (speedF < wantSpeed ? 1.0 : 0.0);
      final k = (1 - math.pow((speedF / topSpeed).clamp(0.0, 1.0), 2)).toDouble();
      drive = spec.power * thr * k;
      if (speedF > wantSpeed + 1) drive = -2.0; // engine braking back to cruise
    }
    if (input.handbrake) {
      drive = math.min(drive, speedF > 1 ? -3.5 : 0);
      // Kick the tail out: yaw acceleration towards the steer direction, stronger with speed.
      if (speedF > 5) {
        final k = (speedF / 20).clamp(0.0, 1.5);
        body.applyAngularImpulse(-input.steer * body.rotationalInertia * 2.6 * k * dt);
      }
    }
    final rearOff = -halfLength * 0.62;
    final rearPx = x + fx * rearOff, rearPy = y + fy * rearOff;
    body.applyForce(Vector2(fx * drive * m, fy * drive * m), point: Vector2(rearPx, rearPy));

    // Drag: rolling + air.
    body.applyForce(Vector2(-v.x * m * (0.04 + 0.0012 * speed), -v.y * m * (0.04 + 0.0012 * speed)));

    // Lateral tyre impulses.
    frontSlip = _axle(halfLength * 0.62, wheelAngle, spec.gripFront, dt, fx, fy, v, w, m);
    final rearGrip = input.handbrake ? spec.gripRear * spec.driftBias : spec.gripRear;
    rearSlip = _axle(rearOff, 0, rearGrip, dt, fx, fy, v, w, m);
    // Quiet the spin when nearly stopped.
    if (speed < 0.5 && input.brake == 0 && input.steer == 0) {
      body.angularVelocity = w * 0.8;
    }
  }

  /// Cancels lateral velocity at an axle up to its grip; returns the remaining slip (m/s).
  double _axle(double offset, double steerAngle, double grip, double dt, double fx, double fy, Vector2 v, double w,
      double m) {
    final rx = fx * offset, ry = fy * offset;
    final vpx = v.x - w * ry, vpy = v.y + w * rx;
    final c = math.cos(steerAngle), s = math.sin(steerAngle);
    final dx = fx * c - fy * s, dy = fx * s + fy * c; // wheel direction
    final nx = -dy, ny = dx; // wheel lateral
    final vlat = vpx * nx + vpy * ny;
    final mAxle = m / 2;
    var j = -vlat * mAxle;
    final maxJ = grip * mAxle * dt;
    var slip = 0.0;
    if (j.abs() > maxJ) {
      slip = (j.abs() - maxJ) / mAxle;
      j = j.sign * maxJ;
    }
    body.applyLinearImpulse(Vector2(nx * j, ny * j), point: Vector2(x + rx, y + ry));
    return slip;
  }

  void teleport(double px, double py, double heading) {
    body.setTransform(Vector2(px, py), Rot.fromAngle(heading));
    body.linearVelocity = Vector2.zero();
    body.angularVelocity = 0;
    wheelAngle = 0;
  }

  void destroy() => body.destroy();
}
