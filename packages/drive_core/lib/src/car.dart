import 'dart:math' as math;

import 'package:forge2d/forge2d.dart';
import 'package:world_engine/core.dart';

import 'controls.dart';

/// Collision categories.
const int catBuildings = 1;
const int catCar = 2;

/// AI traffic (specs/traffic.md): collides with the player's car and, on the ground, parked cars.
const int catTraffic = 4;

/// Parked cars (specs/cars.md): dynamic bodies the player and traffic can push.
const int catParked = 8;

/// Tram cars (specs/trams.md): kinematic, never pushed; collide with the player, traffic and parked
/// cars in the same layer.
const int catTram = 64;

/// Pedestrian-zone bollards (specs/zones.md): static, layer 0, collide only with the player's car.
const int catZone = 32;

/// Car class that rides through pedestrian zones and gets no handbrake yaw (specs/zones.md).
const String microClass = 'micro';

/// Whether [s] is a micro vehicle (scooter, bike).
bool isMicro(CarSpec s) => s.class_ == microClass;

/// The `catZone` bit of the player's mask (specs/zones.md): micro vehicles never have it, and
/// nobody has it while the car centre is inside a zone, so a car that got in always gets out.
int zoneMask(String carClass, bool insideZone) => carClass == microClass || insideZone ? 0 : catZone;

/// Player car on a Box2D body with a custom tyre model (METROPOLE_PLAN 7.2):
/// each step the lateral velocity at each axle is cancelled by an impulse capped by
/// that axle's grip; past the cap the axle slides, which is the drift.
/// All handling numbers come from `drive` in tuning.yaml and from the car spec.
class Car {
  Car(this.world, this.spec, this.t, {required double x, required double y, required double heading, required this.scale}) {
    halfLength = spec.lengthM * scale / 2;
    halfWidth = spec.widthM * scale / 2;
    body = world.createBody(BodyDef(
      type: BodyType.dynamic,
      position: Vector2(x, y),
      rotation: Rot.fromAngle(heading),
      angularDamping: t.angularDamping,
      isBullet: true,
    ));
    _shape = body.createShape(
      Polygon.box(halfLength, halfWidth, radius: t.bodyRoundM),
      ShapeDef(
        density: spec.mass / (4 * halfLength * halfWidth),
        material: SurfaceMaterial(friction: t.carFriction, restitution: t.carRestitution),
        filter: Filter(categoryBits: catCar, maskBits: _mask(0, zoneMask(spec.class_, false))),
        enableContactEvents: true,
        // Static contacts are read in the pre-solve callback (specs/flow.md, DriveWorld).
        enablePreSolveEvents: true,
      ),
    );
  }

  final World world;
  final CarSpec spec;
  final TuningDrive t;
  final double scale;
  late final Body body;
  late Shape _shape;

  /// The body's one shape (contact tests, specs/flow.md).
  Shape get shape => _shape;
  late final double halfLength;
  late final double halfWidth;

  /// Grip multiplier on both axles, an input from the client (rain, specs/weather.md); 1 = the
  /// rules of specs/drive.md as they are.
  double gripScale = 1;

  /// Current front wheel angle (radians, + = left).
  double wheelAngle = 0;
  int layer = 0;

  /// Current `catZone` bit (0 or [catZone]), see [zoneMask].
  late int zoneBits = zoneMask(spec.class_, false);

  /// Lateral slip left over at each axle in the last step, m/s (skid marks).
  double rearSlip = 0;
  double frontSlip = 0;
  bool braking = false;
  bool reversing = false;

  double get x => body.position.x;
  double get y => body.position.y;
  double get heading => body.angle;
  Vector2 get velocity => body.linearVelocity;
  double get speed => body.linearVelocity.length;
  double get axleOffset => halfLength * t.axleOffset;

  /// Signed speed along the car's nose.
  double get forwardSpeed {
    final r = body.rotation;
    final v = body.linearVelocity;
    return v.x * r.cos + v.y * r.sin;
  }

  /// Sideways slip angle of the whole car (radians), 0 when rolling straight or slow.
  double get slipAngle {
    final r = body.rotation;
    final v = body.linearVelocity;
    if (v.length < t.countersteerMinMps) return 0;
    final f = v.x * r.cos + v.y * r.sin;
    final l = -v.x * r.sin + v.y * r.cos;
    return math.atan2(l, f.abs());
  }

  // Buildings, parked cars and zone bollards only exist on the ground layer; bridges and tunnels
  // use rails instead. Traffic cars switch their own mask by layer (traffic.dart).
  static int _mask(int layer, int zone) =>
      (layer == 0 ? catBuildings | catParked | zone : 0) | catTraffic | catTram;

  /// Airborne in a hop (specs/hop.md v2): only buildings collide, and only on the ground layer.
  bool airborne = false;

  int get maskBits => airborne ? (layer == 0 ? catBuildings : 0) : _mask(layer, zoneBits);

  /// Switches the hop mask on take-off and landing.
  void setAirborne(bool v) {
    if (v == airborne) return;
    airborne = v;
    _shape.filter = Filter(categoryBits: catCar, maskBits: maskBits);
  }

  /// One step in the air (specs/hop.md): no input, no tyre forces, no spin, air drag only.
  void fly() {
    final v = body.linearVelocity;
    final drag = body.mass * (t.dragLinear + t.dragQuadratic * v.length);
    body.applyForce(Vector2(-v.x * drag, -v.y * drag));
    body.angularVelocity = 0;
    rearSlip = 0;
    frontSlip = 0;
    braking = false;
    reversing = false;
  }

  /// Radius of the circle around the centre that covers the whole body.
  double get boundingRadius => math.sqrt(halfLength * halfLength + halfWidth * halfWidth) + t.bodyRoundM;

  void setLayer(int l) {
    if (l == layer) return;
    layer = l;
    _shape.filter = Filter(categoryBits: catCar, maskBits: maskBits);
  }

  /// Sets the zone bit from [zoneMask]; touches the shape only when it changes.
  void setInsideZone(bool inside) {
    final z = zoneMask(spec.class_, inside);
    if (z == zoneBits) return;
    zoneBits = z;
    _shape.filter = Filter(categoryBits: catCar, maskBits: maskBits);
  }

  /// Applies controls and tyre forces; call before `world.step`.
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
    final lock = t.steerLockRad - t.steerLockDropRad * (speed / math.max(topSpeed, 1)).clamp(0.0, 1.0);
    var target = -input.steer * lock;
    final slip = slipAngle;
    if (speedF > t.countersteerMinMps &&
        slip.abs() > t.countersteerMinSlipRad &&
        input.steer.abs() < t.countersteerMaxInput) {
      target += (slip * t.countersteerGain).clamp(-lock, lock);
    }
    final maxStep = spec.steerSpeed * dt;
    wheelAngle += (target - wheelAngle).clamp(-maxStep, maxStep);

    // Longitudinal: auto-throttle to cruise (or top with boost), brake, reverse.
    final wantSpeed = input.boost ? topSpeed : math.min(cruise, topSpeed);
    var accel = 0.0;
    braking = false;
    reversing = false;
    if (input.brake > 0) {
      if (speedF > t.brakeMinMps) {
        accel = -spec.brake * input.brake;
        braking = true;
      } else {
        reversing = true;
        accel = speedF > -t.reverseMaxMps ? -spec.power * t.reversePower : 0;
      }
    } else {
      final thr = input.throttle > 0 ? input.throttle : (speedF < wantSpeed ? 1.0 : 0.0);
      final k = 1 - math.pow((speedF / topSpeed).clamp(0.0, 1.0), 2).toDouble();
      accel = spec.power * thr * k;
      if (speedF > wantSpeed + t.overspeedMps) accel = -t.engineBrakeMps2;
    }
    if (input.handbrake) {
      accel = math.min(accel, speedF > t.brakeMinMps ? -t.handbrakeDecelMps2 : 0);
      // Kick the tail out: yaw acceleration towards the steer direction, stronger with speed.
      // Micro vehicles only slow down (specs/zones.md: handbrake_yaw x 0).
      if (speedF > t.handbrakeMinMps && !isMicro(spec)) {
        final k = (speedF / t.handbrakeYawRefMps).clamp(0.0, t.handbrakeYawMax);
        body.applyAngularImpulse(-input.steer * body.rotationalInertia * t.handbrakeYaw * k * dt);
      }
    }
    final rearOff = -axleOffset;
    body.applyForce(Vector2(fx * accel * m, fy * accel * m), point: Vector2(x + fx * rearOff, y + fy * rearOff));

    // Drag: rolling + air.
    final drag = m * (t.dragLinear + t.dragQuadratic * speed);
    body.applyForce(Vector2(-v.x * drag, -v.y * drag));

    // Lateral tyre impulses.
    frontSlip = _axle(axleOffset, wheelAngle, spec.gripFront * gripScale, dt, fx, fy, v, w, m);
    final rearGrip = (input.handbrake ? spec.gripRear * spec.driftBias : spec.gripRear) * gripScale;
    rearSlip = _axle(rearOff, 0, rearGrip, dt, fx, fy, v, w, m);
    if (speed < t.stopSpeedMps && input.brake == 0 && input.steer == 0) {
      body.angularVelocity = w * t.stopSpinDamping;
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

  void destroy() => body.destroy();
}
