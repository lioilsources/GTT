import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:drive_core/drive_core.dart' show ControlInput, RouteGraph, WorldHits;
import 'package:feed_hub/feed_hub.dart' show NavTarget, edgeLengthsDm;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_sprint/mg_sprint.dart';
import 'package:mg_taxi/mg_taxi.dart' show taxiDests;
import 'package:shared_gen/shared_gen.dart';

import '../game/metropole_game.dart';
import '../phone/phone_controller.dart';

/// Signed seconds with one decimal: "+1.2 s" behind par, "−0.8 s" ahead.
String splitText(int deltaMs) {
  final s = (deltaMs.abs() / 1000).toStringAsFixed(1);
  return '${deltaMs > 0
      ? '+'
      : deltaMs < 0
      ? '−'
      : '±'}$s s';
}

/// Sprint A→B as a world minigame of client F (specs/minigames/sprint.md "Svět"): start line, gates,
/// navigation, countdown brake, crashes and the result. Port of web/src/minigames/sprint/index.ts;
/// [SprintHud] draws its state.
class SprintController extends ChangeNotifier implements WorldMinigame {
  SprintController(this.game, this.phone) {
    final city = game.city;
    _world = SprintWorld(
      graph: city.graph,
      route: RouteGraph.fromPb(city.graphPb, tuning.route.classCost),
      lensDm: edgeLengthsDm(city.graphPb),
      searchM: tuning.nav.searchM,
    );
    dests = taxiDests(city.graph, [
      for (final l in city.landmarks.items) (id: l.id, name: l.name, x: l.x, y: l.y, hero: l.hero),
    ], t.destSearchM);
    _prevUpdate = game.afterUpdate;
    _prevPaint = game.paintWorld;
    _prevInput = game.inputHook;
    game
      ..afterUpdate = _afterUpdate
      ..paintWorld = _paint
      ..inputHook = _input;
    game.fleet.onCarChanged.add(_carChanged);
  }

  final MetropoleGame game;
  final PhoneController phone;
  late final SprintWorld _world;
  late final List<NavTarget> dests;
  void Function(double)? _prevUpdate;
  void Function(ui.Canvas)? _prevPaint;
  void Function(ControlInput)? _prevInput;

  Tuning get tuning => game.tuning;
  TuningMinigamesSprint get t => tuning.minigames.sprint;

  /// The running race (debug, tests).
  SprintRace? race;
  WorldHits? _hits;
  void Function(MinigameResult)? _done;
  NavTarget? _navFor;
  double _renav = 0;

  /// A short line (destination, go, split) and whether it is good news (ahead of par) or bad.
  final line = ValueNotifier<({String text, bool? good})?>(null);
  double _lineS = 0;

  /// UI language; the HUD keeps it current.
  String locale = 'en';

  @override
  bool get active => race != null;

  String _t(MessageKey k, [Map<String, Object> a = const {}]) => tr(locale, k, a);

  void _say(String text, double s, {bool? good}) {
    line.value = (text: text, good: good);
    _lineS = s;
  }

  void _navigate(NavTarget? target) {
    _navFor = target;
    _renav = 0;
    if (target == null) {
      phone.cancelNav();
      return;
    }
    final r = race;
    final name = target.name.isNotEmpty
        ? target.name
        : _t(MessageKey.sprintCp, {'n': (r?.state.passed ?? 0) + 1, 'total': r?.state.cps ?? 0});
    phone.navigateTo(
      NavTarget(id: target.id, name: name, edge: target.edge, parkX: target.parkX, parkY: target.parkY),
      silent: true,
    );
  }

  /// The car is moved (at rest) to the spot's parking point with parkHeading; the race clock starts
  /// at 0 and the pick goes at once.
  @override
  void start(String spotId, MinigameContext ctx, void Function(MinigameResult) onFinish) {
    if (race != null) return;
    final spot = game.city.spots.items.where((s) => s.id == spotId).firstOrNull;
    if (spot == null) return;
    final d = game.drive;
    d.spawn(spot.parkX / 10, spot.parkY / 10, spot.parkHeading.toDouble());
    game.camera.snap(d.car.x, d.car.y, d.car.heading, tuning);
    final r = race = SprintRace(_world, t, dests, ctx.difficulty, ctx.seed);
    _hits = WorldHits(d, t.hitMinMps);
    _done = onFinish;
    final c = d.car;
    for (final e in r.begin((hit: d.layers.hit, x: c.x, y: c.y, heading: c.heading))) {
      _onEvent(e);
    }
    update(0);
    notifyListeners();
  }

  /// Ends the race as given up (the HUD's end button): timeout, aborted, 0 stars, score 0.
  void quit() => _finish(aborted: true);

  void _finish({required bool aborted}) {
    final r0 = race;
    if (r0 == null) return;
    final r = r0.end();
    race = null;
    _hits?.dispose();
    _hits = null;
    _navigate(null);
    final cb = _done;
    _done = null;
    notifyListeners();
    cb?.call(
      MinigameResult(stars: aborted ? 0 : r.stars, score: aborted ? 0 : r.score, playedMs: r0.ms, aborted: aborted),
    );
  }

  // Boarding another car or leaving the garage ends the race (timeout, normal result).
  void _carChanged(String _) {
    if (race != null) _finish(aborted: false);
  }

  void _onEvent(SprintEvent e) {
    switch (e) {
      case SprintPicked(:final dest):
        _say(_t(MessageKey.sprintTo, {'place': dest.name}), t.countdownS.toDouble());
        _navFor = null;
      case SprintGo():
        _say(_t(MessageKey.sprintGo), tuning.nav.toastS, good: true);
        if (race?.next case final g?) _navigate(g.target);
      case SprintCp(:final splitMs, :final parAtMs):
        final d = splitMs - parAtMs;
        _say(_t(MessageKey.sprintSplit, {'delta': splitText(d)}), tuning.nav.toastS, good: d <= 0);
        if (race?.next case final g?) _navigate(g.target);
      case SprintOver():
        _finish(aborted: false);
    }
  }

  /// During the countdown the input is replaced by braking to a stop (brake above
  /// drive.brake_min_mps forward, handbrake).
  void _input(ControlInput input) {
    _prevInput?.call(input);
    if (race?.state.phase != 'ready') return;
    final fwd = game.drive.car.forwardSpeed;
    input
      ..reset()
      ..brake = fwd > tuning.drive.brakeMinMps ? 1 : 0
      ..handbrake = true;
  }

  void _afterUpdate(double dt) {
    _prevUpdate?.call(dt);
    // Race time is a world clock: it stands while the game is paused (specs/pause.md).
    update(game.worldDt(dt));
  }

  /// One frame with the world dt (0 while paused); public for tests.
  void update(double dt) {
    if (_lineS > 0 && (_lineS -= dt) <= 0) line.value = null;
    final r = race;
    if (r == null) return;
    final c = game.drive.car;
    for (final e in r.update(dt, (
      x: c.x,
      y: c.y,
      heading: c.heading,
      layer: c.layer,
    ), (atMs) => _hits?.take(atMs) ?? false)) {
      _onEvent(e);
    }
    if (race == null) return;
    final s = r.state;
    if (s.phase == 'ready' && r.plan != null) {
      _say('${_t(MessageKey.sprintTo, {'place': r.plan!.dest.name})} · ${r.countdown.ceil()}', 0.5);
    }
    // Navigation cancelled (✕ on the pill) or ended short of the gate: bring it back.
    final tg = s.phase == 'run' ? r.next?.target : null;
    if (tg != null && !phone.nav.active) {
      if ((_renav += dt) >= tuning.minigames.taxi.renavS) _navigate(tg);
    } else if (tg != null && !identical(_navFor, tg)) {
      _navigate(tg);
    }
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
    final r = race;
    final p = r?.plan;
    if (r == null || p == null) return;
    final next = r.next;
    void gate(SprintGate q, int color) {
      final a = ui.Offset(q.x - q.dirY * q.halfWidth, q.y + q.dirX * q.halfWidth);
      final b = ui.Offset(q.x + q.dirY * q.halfWidth, q.y - q.dirX * q.halfWidth);
      c.drawLine(
        a,
        b,
        Paint()
          ..color = Color(color)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
    }

    for (var i = r.state.passed; i < p.gates.length; i++) {
      gate(p.gates[i], identical(p.gates[i], next) ? Tokens.colorSprintNext : Tokens.colorSprintGate);
    }
    // Finish: a chequered square on the destination point.
    final f = p.finish;
    final side = math.max(4.0, f.halfWidth * 2), cell = side / 4;
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 4; j++) {
        c.drawRect(
          ui.Rect.fromLTWH(f.x - side / 2 + i * cell, f.y - side / 2 + j * cell, cell, cell),
          Paint()..color = Color((i + j).isOdd ? Tokens.colorSprintFinishDark : Tokens.colorSprintFinish),
        );
      }
    }
  }

  @override
  void dispose() {
    if (game.afterUpdate == _afterUpdate) game.afterUpdate = _prevUpdate;
    if (game.paintWorld == _paint) game.paintWorld = _prevPaint;
    if (game.inputHook == _input) game.inputHook = _prevInput;
    game.fleet.onCarChanged.remove(_carChanged);
    _hits?.dispose();
    line.dispose();
    super.dispose();
  }
}
