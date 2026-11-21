import 'dart:math' as math;
import 'dart:ui';

import 'tuning.dart';

/// Rotating follow camera: the car always points up and sits at `car_anchor` (METROPOLE_PLAN 6.1).
class CameraRig {
  double x = 0;
  double y = 0;

  /// World heading that points up on screen (radians, 0 = east, CCW).
  double heading = math.pi / 2;
  double viewWidth = 1; // set by snap() from tuning

  void snap(double px, double py, double h, Tuning t) {
    x = px;
    y = py;
    heading = h;
    viewWidth = t.viewWidthSlow;
  }

  /// Follows the car; heading and zoom are smoothed so drifts do not whip the map around.
  void follow(double px, double py, double carHeading, double speed, double dt, Tuning t, {bool reversing = false}) {
    x = px;
    y = py;
    if (!reversing) {
      final d = _wrap(carHeading - heading);
      final rate = 1 - math.exp(-dt * t.camera.headingFollowRate);
      heading = _wrap(heading + d * rate);
    }
    final k = (speed / math.max(t.topMps, 1)).clamp(0.0, 1.0);
    final target = t.viewWidthSlow + (t.viewWidthFast - t.viewWidthSlow) * k;
    viewWidth += (target - viewWidth) * (1 - math.exp(-dt * t.camera.zoomFollowRate));
  }

  double pixelsPerMetre(Size size) => size.width / viewWidth;

  /// Applies world → screen to [canvas]. World y points north, screen y down.
  void apply(Canvas canvas, Size size, Tuning t) {
    final ppm = pixelsPerMetre(size);
    canvas.translate(size.width * t.anchorX, size.height * t.anchorY);
    canvas.scale(ppm, -ppm);
    canvas.rotate(math.pi / 2 - heading);
    canvas.translate(-x, -y);
  }

  Offset toScreen(double wx, double wy, Size size, Tuning t) {
    final ppm = pixelsPerMetre(size);
    final a = math.pi / 2 - heading;
    final dx = wx - x, dy = wy - y;
    final rx = dx * math.cos(a) - dy * math.sin(a);
    final ry = dx * math.sin(a) + dy * math.cos(a);
    return Offset(size.width * t.anchorX + rx * ppm, size.height * t.anchorY - ry * ppm);
  }

  /// Screen angle (radians, clockwise from screen-right) of a world direction.
  double screenAngle(double worldAngle) => -(worldAngle - heading + math.pi / 2);

  /// Radius around the car (metres) that covers the whole screen.
  double visibleRadius(Size size, Tuning t) {
    final w = viewWidth, h = viewWidth * size.height / size.width;
    final dx = math.max(t.anchorX, 1 - t.anchorX) * w;
    final dy = math.max(t.anchorY, 1 - t.anchorY) * h;
    return math.sqrt(dx * dx + dy * dy);
  }

  static double _wrap(double a) {
    while (a > math.pi) {
      a -= 2 * math.pi;
    }
    while (a < -math.pi) {
      a += 2 * math.pi;
    }
    return a;
  }
}
