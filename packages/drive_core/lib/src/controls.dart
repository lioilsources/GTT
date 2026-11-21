import 'dart:math' as math;
import 'dart:ui';

/// What the driver asks for this frame. [steer] > 0 turns right.
class ControlInput {
  double steer = 0;

  /// 0..1; schemes add throttle automatically up to cruise speed.
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

enum ControlSchemeId { a, b, c }

/// A touch layout. Pointer events come in screen pixels; [update] writes [ControlInput].
abstract class ControlScheme {
  ControlSchemeId get id;
  void down(int pointer, Offset p, Size screen);
  void move(int pointer, Offset p, Size screen);
  void up(int pointer);
  void update(ControlInput out);

  /// Visual hints (wheel, pedal, halves) for the HUD painter.
  void paint(Canvas canvas, Size screen) {}

  static ControlScheme create(ControlSchemeId id) => switch (id) {
        ControlSchemeId.a => SchemeA(),
        ControlSchemeId.b => SchemeB(),
        ControlSchemeId.c => SchemeC(),
      };
}

/// A (default): the car accelerates by itself; dragging the thumb sideways steers,
/// dragging down brakes and reverses, dragging up boosts; a second finger anywhere is
/// the handbrake.
class SchemeA extends ControlScheme {
  int? _main;
  Offset _origin = Offset.zero;
  Offset _pos = Offset.zero;
  Size _screen = Size.zero;
  final Set<int> _extra = {};

  @override
  ControlSchemeId get id => ControlSchemeId.a;

  @override
  void down(int pointer, Offset p, Size screen) {
    _screen = screen;
    if (_main == null) {
      _main = pointer;
      _origin = p;
      _pos = p;
    } else {
      _extra.add(pointer);
    }
  }

  @override
  void move(int pointer, Offset p, Size screen) {
    if (pointer == _main) _pos = p;
  }

  @override
  void up(int pointer) {
    if (pointer == _main) {
      _main = null;
      // A remaining finger becomes the steering thumb.
      if (_extra.isNotEmpty) {
        _main = _extra.first;
        _extra.remove(_main);
        _origin = _pos;
      }
    } else {
      _extra.remove(pointer);
    }
  }

  @override
  void update(ControlInput out) {
    if (_main == null) return;
    final w = math.max(_screen.width, 1.0), h = math.max(_screen.height, 1.0);
    final d = _pos - _origin;
    out.steer = (d.dx / (0.22 * w)).clamp(-1.0, 1.0);
    final v = d.dy / h;
    if (v > 0.06) out.brake = ((v - 0.06) / 0.08).clamp(0.0, 1.0);
    if (v < -0.06) out.boost = true;
    if (_extra.isNotEmpty) out.handbrake = true;
  }

  @override
  void paint(Canvas canvas, Size screen) {
    if (_main == null) return;
    final p = Paint()
      ..color = const Color(0x55FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(_origin, 34, p);
    canvas.drawCircle(_pos, 18, p..style = PaintingStyle.fill);
  }
}

/// B: hold the left or right half to steer; both halves brake (and reverse).
class SchemeB extends ControlScheme {
  final Map<int, bool> _right = {};
  double _width = 1;

  @override
  ControlSchemeId get id => ControlSchemeId.b;

  @override
  void down(int pointer, Offset p, Size screen) {
    _width = screen.width;
    _right[pointer] = p.dx > screen.width / 2;
  }

  @override
  void move(int pointer, Offset p, Size screen) {
    if (_right.containsKey(pointer)) _right[pointer] = p.dx > screen.width / 2;
  }

  @override
  void up(int pointer) => _right.remove(pointer);

  @override
  void update(ControlInput out) {
    final r = _right.values.any((v) => v), l = _right.values.any((v) => !v);
    if (r && l) {
      out.brake = 1;
    } else if (r) {
      out.steer = 1;
    } else if (l) {
      out.steer = -1;
    }
  }

  @override
  void paint(Canvas canvas, Size screen) {
    final p = Paint()..color = const Color(0x22FFFFFF);
    final r = _right.values.any((v) => v), l = _right.values.any((v) => !v);
    if (l) canvas.drawRect(Rect.fromLTWH(0, screen.height * 0.6, _width / 2, screen.height * 0.4), p);
    if (r) canvas.drawRect(Rect.fromLTWH(_width / 2, screen.height * 0.6, _width / 2, screen.height * 0.4), p);
  }
}

/// C: a virtual steering wheel at the bottom centre, brake pedal bottom right,
/// handbrake button bottom left.
class SchemeC extends ControlScheme {
  int? _wheel;
  double _grabAngle = 0;
  double _wheelAngle = 0;
  final Set<int> _brake = {};
  final Set<int> _hand = {};
  Size _screen = Size.zero;

  static const maxWheel = math.pi * 0.6;

  @override
  ControlSchemeId get id => ControlSchemeId.c;

  Offset _centre(Size s) => Offset(s.width / 2, s.height - s.width * 0.26);
  double _radius(Size s) => s.width * 0.2;
  Rect _pedal(Size s) => Rect.fromLTWH(s.width * 0.8, s.height - s.width * 0.42, s.width * 0.17, s.width * 0.3);
  Rect _handRect(Size s) => Rect.fromLTWH(s.width * 0.03, s.height - s.width * 0.3, s.width * 0.17, s.width * 0.17);

  @override
  void down(int pointer, Offset p, Size screen) {
    _screen = screen;
    if (_pedal(screen).inflate(8).contains(p)) {
      _brake.add(pointer);
    } else if (_handRect(screen).inflate(8).contains(p)) {
      _hand.add(pointer);
    } else if (_wheel == null && (p - _centre(screen)).distance < _radius(screen) * 1.6) {
      _wheel = pointer;
      _grabAngle = _angle(p, screen) - _wheelAngle;
    }
  }

  double _angle(Offset p, Size s) {
    final d = p - _centre(s);
    return math.atan2(d.dx, -d.dy);
  }

  @override
  void move(int pointer, Offset p, Size screen) {
    if (pointer != _wheel) return;
    var a = _angle(p, screen) - _grabAngle;
    while (a > math.pi) {
      a -= 2 * math.pi;
    }
    while (a < -math.pi) {
      a += 2 * math.pi;
    }
    _wheelAngle = a.clamp(-maxWheel, maxWheel);
  }

  @override
  void up(int pointer) {
    if (pointer == _wheel) {
      _wheel = null;
      _wheelAngle = 0;
    }
    _brake.remove(pointer);
    _hand.remove(pointer);
  }

  @override
  void update(ControlInput out) {
    out.steer = _wheelAngle / maxWheel;
    if (_brake.isNotEmpty) out.brake = 1;
    if (_hand.isNotEmpty) out.handbrake = true;
  }

  @override
  void paint(Canvas canvas, Size screen) {
    final s = _screen == Size.zero ? screen : _screen;
    final c = _centre(s), r = _radius(s);
    final ring = Paint()
      ..color = const Color(0x88FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.16;
    canvas.drawCircle(c, r, ring);
    final spoke = Paint()
      ..color = const Color(0x88FFFFFF)
      ..strokeWidth = r * 0.1
      ..strokeCap = StrokeCap.round;
    for (final a in [-math.pi / 2, math.pi / 2, math.pi]) {
      final ang = a + _wheelAngle - math.pi / 2;
      canvas.drawLine(c, c + Offset(math.cos(ang), math.sin(ang)) * r, spoke);
    }
    final fill = Paint()..color = Color(_brake.isEmpty ? 0x55FFFFFF : 0xAAFF5050);
    canvas.drawRRect(RRect.fromRectAndRadius(_pedal(s), const Radius.circular(10)), fill);
    fill.color = Color(_hand.isEmpty ? 0x55FFFFFF : 0xAAFFC040);
    canvas.drawRRect(RRect.fromRectAndRadius(_handRect(s), const Radius.circular(10)), fill);
  }
}
