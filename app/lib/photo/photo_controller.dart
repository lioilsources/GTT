import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:game_loop/game_loop.dart';
import 'package:shared_gen/shared_gen.dart';

import '../game/metropole_game.dart';
import '../game/pause.dart';
import '../loop/loop_controller.dart';
import '../phone/phone_controller.dart';
import '../phone/phone_sheet.dart';
import 'photo_layer.dart';

/// The open Camera: its spot, the glide into the framing view and the frame being dragged.
class PhotoMode {
  PhotoMode(this.point, this.glide);
  final PhotoPoint point;
  final PhotoGlide glide;

  /// The frame between two opposite corners (screen pixels), null without a drag.
  ({int pointer, double x0, double y0, double x1, double y1})? drag;
}

/// Toast keys of the verdicts (spec "Výsledek").
const photoToastKey = {
  'ok': MessageKey.photoTaken,
  'again': MessageKey.photoAgain,
  'cut': MessageKey.photoCut,
  'loose': MessageKey.photoLoose,
};

/// Photo spots and the Camera of client F (specs/photo.md P1): camera icons, the "Foťák" button,
/// the phone app, the framing mode (pause kind `photo`), shots and Passport stamps. Port of
/// web/src/photo/index.ts; [PhotoLayer] draws the HUD part. Off (no [world], no hooks) when
/// `photo.enabled` is false.
class PhotoController extends ChangeNotifier {
  PhotoController(this.game, this.phone, this.loop) {
    points = photoSpotsOf(game.city.spots.items);
    if (!tuning.photo.enabled) return;
    final w = world = PhotoWorld(points, tuning);
    w.loadStamps(game.passport.stamps);
    // A restored save (debug reset) brings other stamps: reload from the Passport.
    loop.addListener(_reload);
    // Priority: "Zvednout" (booth) > "Foťák" > "Hrát" > the car button (spec "U fotomísta").
    _prevLoopYield = loop.yieldTo;
    _prevCarYield = game.carActionYield;
    loop.yieldTo = _yieldLoop;
    game.carActionYield = _yieldCar;
    registerPhoneApp(PhoneAppId.camera, (context, phone) => CameraAppScreen(photo: this));
    phone.mapPoints.add(_mapPoints);
    game.hud.addListener(_hud);
    _prevScreen = game.paintScreen;
    _prevCamera = game.cameraHook;
    game
      ..paintScreen = _paintScreen
      ..cameraHook = _camera;
  }

  final MetropoleGame game;
  final PhoneController phone;
  final LoopController loop;
  late final List<PhotoPoint> points;

  /// Null when photo is off (no module).
  PhotoWorld? world;

  bool Function()? _prevLoopYield, _prevCarYield;
  void Function(ui.Canvas, ui.Size)? _prevScreen;
  bool Function(double)? _prevCamera;

  Tuning get tuning => game.tuning;

  /// The open Camera, null while driving.
  PhotoMode? mode;

  /// The glide back to the car after closing (null = the rig follows the car).
  PhotoGlide? _back;
  double flashS = 0;

  /// True while the "Foťák" button shows (HUD tick).
  final openable = ValueNotifier<bool>(false);

  /// The toast shown now: its key and the spot name.
  final toast = ValueNotifier<({MessageKey key, String name})?>(null);
  double _toastS = 0;

  bool get active => mode != null;

  PhotoBlock? blocked() =>
      photoBlocked(busy: loop.busy, inWorldGame: loop.inWorldGame, wanted: game.police.wantedLevel);

  /// The photo spot in reach of the car, or null.
  PhotoPoint? spotHere() {
    final c = game.drive.car;
    return photoSpotAt(points, c.x, c.y, c.speed, c.layer, tuning.loop);
  }

  /// The "Foťák" button: at a photo spot, not blocked, phone and cards closed, no booth to answer.
  bool canOpen() =>
      world != null &&
      mode == null &&
      !phone.isOpen &&
      !game.worldPaused &&
      blocked() == null &&
      !(_prevLoopYield?.call() ?? false) &&
      spotHere() != null;

  bool _yieldLoop() => (_prevLoopYield?.call() ?? false) || mode != null || canOpen();
  bool _yieldCar() => (_prevCarYield?.call() ?? false) || mode != null || canOpen();

  void _reload() {
    if (mode == null) world?.loadStamps(game.passport.stamps);
  }

  List<({double x, double y, int color})> _mapPoints() => [
    for (final p in points)
      (x: p.x, y: p.y, color: (world?.isTaken(p.id) ?? false) ? Tokens.colorPhotoSpotDone : Tokens.colorPhotoSpot),
  ];

  /// HUD tick (~10×/s): the toast and the "Foťák" button. Public for tests.
  void tick([double dt = 0.1]) {
    if (_toastS > 0 && (_toastS -= dt) <= 0) toast.value = null;
    final v = canOpen();
    if (v != openable.value) openable.value = v;
  }

  void _hud() => tick();

  void _showToast(MessageKey key, String name) {
    toast.value = (key: key, name: name);
    _toastS = tuning.nav.toastS;
  }

  RigPose _pose() {
    final r = game.camera;
    return (x: r.x, y: r.y, heading: r.heading, viewWidth: r.viewWidth);
  }

  /// The framing pose: the midpoint of the car and the look at the screen centre, heading kept.
  RigPose _framing(PhotoPoint p, double heading) {
    final s = game.viewSize, c = game.drive.car;
    final vw = photoViewWidth(tuning, p.subjectM);
    final at = rigForCentre((c.x + p.lookX) / 2, (c.y + p.lookY) / 2, heading, vw, s.width, s.height, tuning);
    return (x: at.x, y: at.y, heading: heading, viewWidth: vw);
  }

  /// Opens the Camera at the photo spot in reach ("Foťák"); false when not offered.
  bool tryOpen() {
    final p = canOpen() ? spotHere() : null;
    if (p == null) return false;
    open(p);
    return true;
  }

  /// The Camera at [p]: the phone closes, the game stands (pause kind `photo`), the camera glides.
  void open(PhotoPoint p) {
    if (_disposed || mode != null || world == null) return;
    if (phone.app == PhoneAppId.camera) phone.launch(null);
    phone.close();
    _back = null;
    game.pauseOverlays.register(GameOverlay.photo);
    final from = _pose();
    mode = PhotoMode(p, PhotoGlide(from, () => _framing(p, from.heading), tuning.photo.zoomS));
    openable.value = false;
    notifyListeners();
  }

  /// "Zpět" or after an `ok`: back to driving, the camera glides back to the car.
  void close() {
    if (mode == null) return;
    mode = null;
    game.pauseOverlays.unregister(GameOverlay.photo);
    final from = _pose();
    _back = PhotoGlide(
      from,
      () => (x: game.drive.car.x, y: game.drive.car.y, heading: from.heading, viewWidth: tuning.viewWidthM.slow),
      tuning.photo.zoomS,
    );
    notifyListeners();
  }

  /// The Camera phone app (specs/phone.md slot `camera`): at a photo spot the mode opens (after the
  /// phone finished building the app); otherwise the reason text.
  MessageKey? appOpen() {
    final b = blocked();
    final p = b == null ? spotHere() : null;
    if (p == null) return b == PhotoBlock.wanted ? MessageKey.photoWanted : MessageKey.photoNoSpot;
    SchedulerBinding.instance.addPostFrameCallback((_) => open(p));
    return null;
  }

  // ---------- the frame
  void dragStart(int pointer, double x, double y) {
    final m = mode;
    if (m == null || m.drag != null) return;
    m.drag = (pointer: pointer, x0: x, y0: y, x1: x, y1: y);
  }

  void dragMove(int pointer, double x, double y) {
    final m = mode, d = m?.drag;
    if (m == null || d == null || d.pointer != pointer) return;
    m.drag = (pointer: pointer, x0: d.x0, y0: d.y0, x1: x, y1: y);
  }

  /// Release = the shot.
  PhotoVerdict? dragEnd(int pointer, double x, double y) {
    final d = mode?.drag;
    if (d == null || d.pointer != pointer) return null;
    return shoot(d.x0, d.y0, x, y);
  }

  void dragCancel(int pointer) {
    final m = mode;
    if (m != null && m.drag?.pointer == pointer) m.drag = null;
  }

  /// Shoots the frame between two screen corners; the verdict, null when not framing.
  PhotoVerdict? shoot(double x0, double y0, double x1, double y1) {
    final m = mode, w = world;
    if (m == null || w == null) return null;
    final s = game.viewSize, p = m.point;
    final v = w.shoot(p.id, frameToShot(_pose(), x0, y0, x1, y1, s.width, s.height, tuning));
    m.drag = null;
    if (v == null) return v;
    if (v == 'ok' || v == 'again') flashS = tuning.photo.flashS;
    _showToast(photoToastKey[v]!, p.name);
    if (v == 'ok') {
      game.passport.photo(p.id);
      loop.save();
      close();
    }
    notifyListeners();
    return v;
  }

  // ---------- camera
  bool _camera(double dt) {
    if (flashS > 0) flashS = math.max(0, flashS - dt);
    final g = mode?.glide ?? _back;
    if (g == null) return _prevCamera?.call(dt) ?? false;
    g.step(dt);
    final p = g.pose(), r = game.camera;
    r
      ..x = p.x
      ..y = p.y
      ..heading = p.heading
      ..viewWidth = p.viewWidth;
    if (mode == null && g.done) _back = null;
    return true;
  }

  // ---------- drawing (screen pixels, above the world)
  void _paintScreen(ui.Canvas c, ui.Size size) {
    _prevScreen?.call(c, size);
    final w = world;
    if (w == null) return;
    final pt = tuning.photo, cam = game.camera;
    final ppm = cam.pixelsPerMetre(size);
    final s = math.max(8.0, pt.spotIconM * ppm);
    for (final p in points) {
      final q = cam.toScreen(p.x, p.y, size, tuning);
      if (q.dx < -s || q.dy < -s || q.dx > size.width + s || q.dy > size.height + s) continue;
      paintCameraIcon(c, q, s, w.isTaken(p.id) ? Tokens.colorPhotoSpotDone : Tokens.colorPhotoSpot);
    }
    final m = mode;
    if (m != null) {
      // Crosshair on the look (photo.cross).
      final o = cam.toScreen(m.point.lookX, m.point.lookY, size, tuning);
      final r = pt.crossPx / 2;
      final cross = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(Tokens.colorPhotoCross);
      c
        ..drawCircle(o, r * 0.6, cross)
        ..drawLine(o.translate(-r, 0), o.translate(r, 0), cross)
        ..drawLine(o.translate(0, -r), o.translate(0, r), cross);
      final d = m.drag;
      if (d != null) {
        final rect = Rect.fromPoints(Offset(d.x0, d.y0), Offset(d.x1, d.y1));
        c
          ..drawPath(
            ui.Path()
              ..fillType = ui.PathFillType.evenOdd
              ..addRect(Offset.zero & size)
              ..addRect(rect),
            Paint()..color = const Color(Tokens.colorPhotoFrameShade),
          )
          ..drawRect(
            rect,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = const Color(Tokens.colorPhotoFrame),
          );
      }
    }
    if (flashS > 0) {
      // Real-time fade; the screen is redrawn every frame even while paused.
      final a = math.min(1.0, flashS / math.max(pt.flashS, 1e-6));
      final base = const Color(Tokens.colorPhotoFlash);
      c.drawRect(Offset.zero & size, Paint()..color = base.withValues(alpha: base.a * a));
    }
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    if (world != null) {
      if (mode != null) {
        mode = null;
        game.pauseOverlays.unregister(GameOverlay.photo);
      }
      if (game.paintScreen == _paintScreen) game.paintScreen = _prevScreen;
      if (game.cameraHook == _camera) game.cameraHook = _prevCamera;
      if (loop.yieldTo == _yieldLoop) loop.yieldTo = _prevLoopYield;
      if (game.carActionYield == _yieldCar) game.carActionYield = _prevCarYield;
      loop.removeListener(_reload);
      phone.mapPoints.remove(_mapPoints);
      phoneApps.remove(PhoneAppId.camera);
      game.hud.removeListener(_hud);
    }
    openable.dispose();
    toast.dispose();
    super.dispose();
  }
}

/// A small camera, upright on screen: body, viewfinder bump, lens ring (as client W).
void paintCameraIcon(ui.Canvas c, Offset at, double s, int color) {
  final fill = Paint()..color = Color(color);
  final edge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1, s * 0.08)
    ..color = const Color(Tokens.colorPhotoFrame);
  final body = RRect.fromRectAndRadius(Rect.fromLTWH(-s / 2, -s * 0.3, s, s * 0.65), Radius.circular(s * 0.12));
  c
    ..save()
    ..translate(at.dx, at.dy)
    ..drawRRect(body, fill)
    ..drawRRect(body, edge)
    ..drawRect(Rect.fromLTWH(-s * 0.18, -s * 0.44, s * 0.36, s * 0.16), fill)
    ..drawCircle(Offset(0, s * 0.03), s * 0.2, edge)
    ..restore();
}
