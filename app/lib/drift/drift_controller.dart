import 'dart:ui' as ui;

import 'package:drive_core/drive_core.dart' show WorldHits;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_drift/mg_drift.dart';
import 'package:shared_gen/shared_gen.dart';

import '../game/metropole_game.dart';

/// Drift zone as a world minigame of client F (specs/minigames/drift.md "Svět"): the player's own car
/// (with its garage upgrades), the zone around the spot's parking point, samples, crashes and the
/// result. Port of web/src/minigames/drift/index.ts; [DriftHud] draws its state.
class DriftController extends ChangeNotifier implements WorldMinigame {
  DriftController(this.game) {
    _prevUpdate = game.afterUpdate;
    _prevPaint = game.paintWorld;
    game
      ..afterUpdate = _afterUpdate
      ..paintWorld = _paint;
    game.fleet.onCarChanged.add(_carChanged);
  }

  final MetropoleGame game;
  void Function(double)? _prevUpdate;
  void Function(ui.Canvas)? _prevPaint;

  Tuning get tuning => game.tuning;
  TuningMinigamesDrift get t => tuning.minigames.drift;

  /// The running session (debug, tests).
  DriftSession? session;
  WorldHits? _hits;
  void Function(MinigameResult)? _done;

  /// The banked chain flash ("+points") and its time left.
  final flash = ValueNotifier<int?>(null);
  double _flashS = 0;

  @override
  bool get active => session != null;

  /// The session runs in the player's own car where he pressed "Play"; the zone is the ring around
  /// the spot's parking point.
  @override
  void start(String spotId, MinigameContext ctx, void Function(MinigameResult) onFinish) {
    if (session != null) return;
    final spot = game.city.spots.items.where((s) => s.id == spotId).firstOrNull;
    if (spot == null) return;
    session = DriftSession(t, ctx.difficulty, spot.parkX / 10, spot.parkY / 10);
    _hits = WorldHits(game.drive, t.hitMinMps);
    _done = onFinish;
    update(0);
    notifyListeners();
  }

  /// Ends the session as given up (the HUD's end button): aborted, 0 stars, score 0.
  void quit() => _finish(aborted: true);

  void _finish({required bool aborted}) {
    final s = session;
    if (s == null) return;
    final r = s.end();
    session = null;
    _hits?.dispose();
    _hits = null;
    final cb = _done;
    _done = null;
    notifyListeners();
    cb?.call(
      MinigameResult(stars: aborted ? 0 : r.stars, score: aborted ? 0 : r.score, playedMs: s.ms, aborted: aborted),
    );
  }

  // Boarding another car or leaving the garage ends the session (timeout, normal result).
  void _carChanged(String _) {
    if (session != null) _finish(aborted: false);
  }

  void _afterUpdate(double dt) {
    _prevUpdate?.call(dt);
    // Session time is a world clock: it stands while the game is paused (specs/pause.md).
    update(game.worldDt(dt));
  }

  /// One frame with the world dt (0 while paused); public for tests.
  void update(double dt) {
    if (_flashS > 0 && (_flashS -= dt) <= 0) flash.value = null;
    final s = session;
    if (s == null) return;
    final c = game.drive.car, v = c.velocity;
    final pose = (x: c.x, y: c.y, heading: c.heading, vx: v.x, vy: v.y, layer: c.layer);
    for (final e in s.update(dt, pose, (atMs) => _hits?.take(atMs) ?? false)) {
      switch (e) {
        case DriftBank(:final points):
          flash.value = points;
          _flashS = tuning.nav.toastS;
        case DriftOver():
          _finish(aborted: false);
      }
    }
    if (session == null) return;
    if ((_hudS += dt) >= hudTickS) {
      _hudS = 0;
      notifyListeners();
    }
  }

  /// HUD refresh period (s), like the game HUD.
  static const hudTickS = 0.1;
  double _hudS = 0;

  void _paint(ui.Canvas c) {
    _prevPaint?.call(c);
    final s = session;
    if (s == null) return;
    final o = ui.Offset(s.cx, s.cy);
    c.drawCircle(o, t.zoneM, Paint()..color = const Color(Tokens.colorDriftZoneFill));
    c.drawCircle(
      o,
      t.zoneM,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color = const Color(Tokens.colorDriftZone),
    );
  }

  @override
  void dispose() {
    if (game.afterUpdate == _afterUpdate) game.afterUpdate = _prevUpdate;
    if (game.paintWorld == _paint) game.paintWorld = _prevPaint;
    game.fleet.onCarChanged.remove(_carChanged);
    _hits?.dispose();
    flash.dispose();
    super.dispose();
  }
}
