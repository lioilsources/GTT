import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:drive_core/drive_core.dart' show CarSpec, RouteGraph;
import 'package:feed_hub/feed_hub.dart' show NavTarget, edgeLengthsDm;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_taxi/mg_taxi.dart';
import 'package:shared_gen/shared_gen.dart';

import '../game/metropole_game.dart';
import '../phone/phone_controller.dart';

/// The taxi car of the shift (specs/minigames/taxi.md "Start").
const taxiCar = 'taxi_metro';

/// Taxi as a world minigame of client F: car swap, passengers, navigation and the shift result.
/// Port of web/src/minigames/taxi/index.ts; [TaxiHud] draws its state.
class TaxiController extends ChangeNotifier implements WorldMinigame {
  TaxiController(this.game, this.phone) {
    final city = game.city;
    _world = TaxiWorld(
      graph: city.graph,
      route: RouteGraph.fromPb(city.graphPb, tuning.route.classCost),
      lensDm: edgeLengthsDm(city.graphPb),
      straightPct: tuning.feed.straightPct,
      searchM: tuning.nav.searchM,
      leftHand: city.leftHand,
    );
    dests = taxiDests(city.graph, [
      for (final l in city.landmarks.items) (id: l.id, name: l.name, x: l.x, y: l.y, hero: l.hero),
    ], t.destSearchM);
    // Chain onto the hooks the phone already uses.
    _prevUpdate = game.afterUpdate;
    _prevPaint = game.paintWorld;
    game
      ..afterUpdate = _afterUpdate
      ..paintWorld = _paint;
    game.fleet.onCarChanged.add(_carChanged);
    _offHit = game.drive.traffic?.onHit((_, _) => shift?.hit());
  }

  final MetropoleGame game;
  final PhoneController phone;
  late final TaxiWorld _world;
  late final List<NavTarget> dests;
  void Function(double)? _prevUpdate;
  void Function(ui.Canvas)? _prevPaint;
  void Function()? _offHit;

  Tuning get tuning => game.tuning;
  TuningMinigamesTaxi get t => tuning.minigames.taxi;

  /// The running shift (debug, tests).
  TaxiShift? shift;
  void Function(MinigameResult)? _done;
  CarSpec? _prevSpec;
  NavTarget? _navFor;
  double _renav = 0;
  bool _swapping = false;

  /// The passenger's line (or the paid fare) shown now, and its time left.
  final line = ValueNotifier<String?>(null);
  double _lineS = 0;

  /// UI language; the HUD keeps it current.
  String locale = 'en';

  @override
  bool get active => shift != null;

  String _t(MessageKey k, [Map<String, Object> a = const {}]) => tr(locale, k, a);

  void _say(String text, double s) {
    line.value = text;
    _lineS = s;
  }

  void _navigate(NavTarget? target, String name) {
    _navFor = target;
    _renav = 0;
    if (target == null) {
      phone.cancelNav();
    } else {
      phone.navigateTo(
        NavTarget(id: target.id, name: name, edge: target.edge, parkX: target.parkX, parkY: target.parkY),
        silent: true,
      );
    }
  }

  String _nameOf(NavTarget tg) => identical(tg, shift?.dest) ? tg.name : _t(MessageKey.taxiPassenger);

  @override
  void start(String spotId, MinigameContext ctx, void Function(MinigameResult) onFinish) {
    if (shift != null) return;
    final spec = game.data.cars[taxiCar];
    if (spec == null) return;
    shift = TaxiShift(_world, t, dests, ctx.seed);
    _done = onFinish;
    final d = game.drive;
    _prevSpec = d.spec;
    if (d.spec.id != taxiCar) _swap(spec);
    _say(_t(MessageKey.taxiStart), t.lineS);
    notifyListeners();
  }

  void _swap(CarSpec spec) {
    final c = game.drive.car;
    _swapping = true;
    game.drive.replaceCar(spec, c.x, c.y, c.heading);
    _swapping = false;
  }

  /// Ends the shift as given up (the HUD's end button).
  void quit() => _finish(aborted: true, giveBack: true);

  void _finish({required bool aborted, required bool giveBack}) {
    final s = shift;
    if (s == null) return;
    final r = s.end();
    shift = null;
    _navigate(null, '');
    final prev = _prevSpec;
    if (giveBack && prev != null && game.drive.spec.id != prev.id) _swap(prev);
    _prevSpec = null;
    final cb = _done;
    _done = null;
    notifyListeners();
    cb?.call(MinigameResult(stars: aborted ? 0 : r.stars, score: r.score, playedMs: s.ms, aborted: aborted));
  }

  // Boarding another car or leaving the garage during the shift ends it (no car given back).
  void _carChanged(String _) {
    if (shift != null && !_swapping) _finish(aborted: false, giveBack: false);
  }

  void _onEvent(TaxiEvent e) {
    switch (e) {
      case TaxiSpawn(:final passenger):
        _navigate(passenger.target, _t(MessageKey.taxiPassenger));
      case TaxiPickup(:final dest, line: final l):
        final key = MessageKey.values.firstWhere(
          (k) => k.key == 'taxiLine${l + 1}',
          orElse: () => MessageKey.taxiLine1,
        );
        _say(tr(locale, key, {'place': dest.name}), t.lineS);
        _navigate(dest, dest.name);
      case TaxiDropoff(:final ride):
        _say(_t(MessageKey.taxiPaid, {'fare': ride.fare}), tuning.nav.toastS);
        _navigate(null, '');
      case TaxiOver():
        _finish(aborted: false, giveBack: true);
    }
  }

  void _afterUpdate(double dt) {
    _prevUpdate?.call(dt);
    // Shift time is a world clock: it stands while the game is paused (specs/pause.md).
    update(game.worldDt(dt));
  }

  /// One frame with the world dt (0 while paused); public for tests.
  void update(double dt) {
    if (_lineS > 0 && (_lineS -= dt) <= 0) line.value = null;
    final s = shift;
    if (s == null) return;
    final c = game.drive.car;
    for (final e in s.update(dt, (
      x: c.x,
      y: c.y,
      heading: c.heading,
      speed: c.speed,
      layer: c.layer,
    ), game.drive.layers.hit)) {
      _onEvent(e);
    }
    if (shift == null) return;
    // Navigation cancelled (✕ on the pill) or ended short of the target: bring it back.
    final tg = s.target;
    if (tg != null && !phone.nav.active) {
      final far = math.sqrt(math.pow(tg.parkX / 10 - c.x, 2) + math.pow(tg.parkY / 10 - c.y, 2)) > t.dropRadiusM;
      if (far && (_renav += dt) >= t.renavS) _navigate(tg, _nameOf(tg));
    } else if (tg != null && !identical(_navFor, tg)) {
      _navigate(tg, _nameOf(tg));
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
    final p = shift?.passenger;
    if (p == null) return;
    final o = ui.Offset(p.x, p.y);
    c.drawCircle(o, t.passengerM, Paint()..color = const Color(Tokens.colorTaxiPassenger));
    c.drawCircle(
      o,
      t.passengerM,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = t.passengerM * 0.3
        ..color = const Color(Tokens.colorTaxiPassengerRing),
    );
  }

  @override
  void dispose() {
    if (game.afterUpdate == _afterUpdate) game.afterUpdate = _prevUpdate;
    if (game.paintWorld == _paint) game.paintWorld = _prevPaint;
    game.fleet.onCarChanged.remove(_carChanged);
    _offHit?.call();
    line.dispose();
    super.dispose();
  }
}
