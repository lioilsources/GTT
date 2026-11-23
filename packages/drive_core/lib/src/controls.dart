import 'dart:math' as math;

import 'package:world_engine/core.dart';

/// What the driver asks for this frame. [steer] > 0 turns right.
class ControlInput {
  double steer = 0;

  /// 0..1; without it the car accelerates by itself up to cruise speed.
  double throttle = 0;

  /// 0..1; held while slow or stopped it reverses.
  double brake = 0;
  bool handbrake = false;

  /// Asks for top speed instead of cruise.
  bool boost = false;

  void reset() {
    steer = 0;
    throttle = 0;
    brake = 0;
    handbrake = false;
    boost = false;
  }
}

/// A screen point in logical pixels.
typedef ScreenPt = ({double x, double y});

/// A screen rectangle in logical pixels.
typedef ScreenRect = ({double left, double top, double width, double height});

bool _inRect(ScreenRect r, ScreenPt p, double pad) =>
    p.x >= r.left - pad && p.x <= r.left + r.width + pad && p.y >= r.top - pad && p.y <= r.top + r.height + pad;

enum ControlSchemeId { a, b, c }

/// A touch layout: pointer events in, [ControlInput] out. Pure logic; the app draws the hints
/// from the read-only state each scheme exposes.
abstract class ControlScheme {
  ControlScheme(this.tuning);
  final TuningControls tuning;

  ControlSchemeId get id;
  void down(int pointer, ScreenPt p, double screenW, double screenH);
  void move(int pointer, ScreenPt p, double screenW, double screenH);
  void up(int pointer);
  void update(ControlInput out);

  static ControlScheme create(ControlSchemeId id, TuningControls t) => switch (id) {
        ControlSchemeId.a => SchemeA(t),
        ControlSchemeId.b => SchemeB(t),
        ControlSchemeId.c => SchemeC(t),
      };
}

/// A (default): the car accelerates by itself; dragging the thumb sideways steers,
/// dragging down brakes and reverses, dragging up boosts; a second finger anywhere is
/// the handbrake.
class SchemeA extends ControlScheme {
  SchemeA(super.tuning);

  int? _main;
  ScreenPt origin = (x: 0, y: 0);
  ScreenPt pos = (x: 0, y: 0);
  double _w = 1, _h = 1;
  final Set<int> _extra = {};

  bool get active => _main != null;

  @override
  ControlSchemeId get id => ControlSchemeId.a;

  @override
  void down(int pointer, ScreenPt p, double screenW, double screenH) {
    _w = math.max(screenW, 1);
    _h = math.max(screenH, 1);
    if (_main == null) {
      _main = pointer;
      origin = p;
      pos = p;
    } else {
      _extra.add(pointer);
    }
  }

  @override
  void move(int pointer, ScreenPt p, double screenW, double screenH) {
    if (pointer == _main) pos = p;
  }

  @override
  void up(int pointer) {
    if (pointer == _main) {
      _main = null;
      // A remaining finger becomes the steering thumb.
      if (_extra.isNotEmpty) {
        _main = _extra.first;
        _extra.remove(_main);
        origin = pos;
      }
    } else {
      _extra.remove(pointer);
    }
  }

  @override
  void update(ControlInput out) {
    if (_main == null) return;
    final t = tuning;
    out.steer = ((pos.x - origin.x) / (t.aFullSteerWidth * _w)).clamp(-1.0, 1.0);
    final v = (pos.y - origin.y) / _h;
    if (v > t.aDeadZoneHeight) out.brake = ((v - t.aDeadZoneHeight) / t.aFullBrakeHeight).clamp(0.0, 1.0);
    if (v < -t.aDeadZoneHeight) out.boost = true;
    if (_extra.isNotEmpty) out.handbrake = true;
  }
}

/// B: hold the left or right half to steer; both halves brake (and reverse). v2: a finger that
/// starts on the Boost button bottom centre boosts until lifted and steers nothing.
class SchemeB extends ControlScheme {
  SchemeB(super.tuning);

  final Map<int, bool> _right = {};
  final Set<int> _boost = {};

  bool get leftHeld => _right.values.any((v) => !v);
  bool get rightHeld => _right.values.any((v) => v);
  bool get boostHeld => _boost.isNotEmpty;

  @override
  ControlSchemeId get id => ControlSchemeId.b;

  /// Layout in screen-width units (presentation, specs/controls.md v2).
  static ScreenRect boostButton(double w, double h) =>
      (left: w * 0.38, top: h - w * 0.28, width: w * 0.24, height: w * 0.2);

  @override
  void down(int pointer, ScreenPt p, double screenW, double screenH) {
    if (_inRect(boostButton(screenW, screenH), p, 8)) {
      _boost.add(pointer);
    } else {
      _right[pointer] = p.x > screenW / 2;
    }
  }

  @override
  void move(int pointer, ScreenPt p, double screenW, double screenH) {
    if (_right.containsKey(pointer)) _right[pointer] = p.x > screenW / 2;
  }

  @override
  void up(int pointer) {
    _right.remove(pointer);
    _boost.remove(pointer);
  }

  @override
  void update(ControlInput out) {
    if (rightHeld && leftHeld) {
      out.brake = 1;
    } else if (rightHeld) {
      out.steer = 1;
    } else if (leftHeld) {
      out.steer = -1;
    }
    if (_boost.isNotEmpty) out.boost = true;
  }
}

/// C: a virtual steering wheel at the bottom centre, brake pedal bottom right,
/// handbrake button bottom left; v2: a Boost button above the brake pedal. The layout is
/// expressed in screen-width units.
class SchemeC extends ControlScheme {
  SchemeC(super.tuning);

  int? _wheel;
  double _grabAngle = 0;

  /// Current wheel rotation, radians, + = clockwise (right).
  double wheelAngle = 0;
  final Set<int> _brake = {};
  final Set<int> _hand = {};
  final Set<int> _boost = {};

  bool get brakeHeld => _brake.isNotEmpty;
  bool get handHeld => _hand.isNotEmpty;
  bool get boostHeld => _boost.isNotEmpty;

  @override
  ControlSchemeId get id => ControlSchemeId.c;

  static ScreenPt wheelCentre(double w, double h) => (x: w / 2, y: h - w * 0.26);
  static double wheelRadius(double w) => w * 0.2;
  static ScreenRect pedal(double w, double h) => (left: w * 0.8, top: h - w * 0.42, width: w * 0.17, height: w * 0.3);
  static ScreenRect handButton(double w, double h) =>
      (left: w * 0.03, top: h - w * 0.3, width: w * 0.17, height: w * 0.17);
  static ScreenRect boostButton(double w, double h) =>
      (left: w * 0.8, top: h - w * 0.64, width: w * 0.17, height: w * 0.17);

  double _angle(ScreenPt p, double w, double h) {
    final c = wheelCentre(w, h);
    return math.atan2(p.x - c.x, -(p.y - c.y));
  }

  @override
  void down(int pointer, ScreenPt p, double screenW, double screenH) {
    final c = wheelCentre(screenW, screenH);
    if (_inRect(pedal(screenW, screenH), p, 8)) {
      _brake.add(pointer);
    } else if (_inRect(boostButton(screenW, screenH), p, 8)) {
      _boost.add(pointer);
    } else if (_inRect(handButton(screenW, screenH), p, 8)) {
      _hand.add(pointer);
    } else if (_wheel == null && math.sqrt(math.pow(p.x - c.x, 2) + math.pow(p.y - c.y, 2)) < wheelRadius(screenW) * 1.6) {
      _wheel = pointer;
      _grabAngle = _angle(p, screenW, screenH) - wheelAngle;
    }
  }

  @override
  void move(int pointer, ScreenPt p, double screenW, double screenH) {
    if (pointer != _wheel) return;
    var a = _angle(p, screenW, screenH) - _grabAngle;
    while (a > math.pi) {
      a -= 2 * math.pi;
    }
    while (a < -math.pi) {
      a += 2 * math.pi;
    }
    wheelAngle = a.clamp(-tuning.cMaxWheelRad, tuning.cMaxWheelRad);
  }

  @override
  void up(int pointer) {
    if (pointer == _wheel) {
      _wheel = null;
      wheelAngle = 0;
    }
    _brake.remove(pointer);
    _hand.remove(pointer);
    _boost.remove(pointer);
  }

  @override
  void update(ControlInput out) {
    out.steer = wheelAngle / tuning.cMaxWheelRad;
    if (_brake.isNotEmpty) out.brake = 1;
    if (_hand.isNotEmpty) out.handbrake = true;
    if (_boost.isNotEmpty) out.boost = true;
  }
}
