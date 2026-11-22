import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:feed_hub/feed_hub.dart' show edgeArrow;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:game_loop/game_loop.dart';
import 'package:shared_gen/shared_gen.dart';

import '../game/metropole_game.dart';
import '../game/pause.dart';
import '../loop/loop_controller.dart';
import '../phone/phone_controller.dart';

/// The offer card of an answered booth.
typedef BoothCard = ({Booth booth, BoothOffer offer});

/// Ringing phone booths of client F (specs/booths.md P1): the 1 s game tick, reach, "Zvednout",
/// the offer card, the bonus and drawing. Port of web/src/booths/index.ts; [BoothsLayer] draws the
/// HUD part. Off (no [world], no hooks) when `booths.enabled` is false or the city has no booths.
class BoothsController extends ChangeNotifier {
  BoothsController(this.game, this.phone, this.loop, {int? seed}) {
    final spots = game.city.spots.items;
    booths = boothsOf(spots);
    if (!tuning.booths.enabled || booths.isEmpty) return;
    final catalog = {for (final e in minigameCatalog.entries) e.key.id: e.value};
    final w = world = BoothWorld(booths, tuning, boothGames(spots, catalog), seed ?? math.Random().nextInt(1 << 32));
    w.onRing.add(_onRing);
    loop.yieldTo = canAnswer;
    game.carActionYield = canAnswer;
    loop.book.bonus = w.finish;
    phone.onAccept.add(_onAccept);
    phone.mapPoints.add(_mapPoints);
    game.hud.addListener(_hud);
    // Chain onto the hooks the phone and Taxi already use.
    _prevUpdate = game.afterUpdate;
    _prevWorld = game.paintWorld;
    _prevScreen = game.paintScreen;
    game
      ..afterUpdate = _afterUpdate
      ..paintWorld = _paintWorld
      ..paintScreen = _paintScreen;
  }

  final MetropoleGame game;
  final PhoneController phone;
  final LoopController loop;
  late final List<Booth> booths;

  /// Null when booths are off or the city has none (no module).
  BoothWorld? world;

  void Function(double)? _prevUpdate;
  void Function(ui.Canvas)? _prevWorld;
  void Function(ui.Canvas, ui.Size)? _prevScreen;

  Tuning get tuning => game.tuning;

  /// The open offer card (the game is paused while it is up).
  final card = ValueNotifier<BoothCard?>(null);

  /// True while the "Zvednout" button shows (HUD tick).
  final answerable = ValueNotifier<bool>(false);

  /// True while the "booth is ringing" toast shows.
  final ringingToast = ValueNotifier<bool>(false);
  double _toastS = 0;

  /// Real time for the ring pulse.
  double _clock = 0;

  /// Ringing is suppressed during navigation, a minigame, Taxi and while wanted (spec "Dosah").
  bool get quiet => phone.nav.active || loop.busy || loop.inWorldGame || game.police.wantedLevel > 0;

  List<int> _near() {
    if (quiet) return const [];
    final c = game.drive.car, b = tuning.booths;
    return nearBooths(booths, c.x, c.y, b.ringMinM, b.ringMaxM);
  }

  /// "Zvednout": the same conditions as "Hrát" at a spot (specs/loop.md); priority over "Hrát" and
  /// the car button.
  bool canAnswer() {
    final b = world?.ringing, c = game.drive.car;
    if (b == null || card.value != null || loop.busy || phone.isOpen || phone.nav.active || loop.inWorldGame) {
      return false;
    }
    return boothInReach(b, c.x, c.y, c.speed, c.layer, tuning.loop);
  }

  void _onRing(Booth _) {
    ringingToast.value = true;
    _toastS = tuning.nav.toastS;
  }

  void _onAccept(String _) => world?.clear();

  List<({double x, double y, int color})> _mapPoints() {
    final b = world?.ringing;
    return b == null ? const [] : [(x: b.x, y: b.y, color: Tokens.colorBoothRing)];
  }

  void _hud() {
    final v = canAnswer();
    if (v != answerable.value) answerable.value = v;
  }

  void _afterUpdate(double dt) {
    _prevUpdate?.call(dt);
    update(game.worldDt(dt), dt);
  }

  /// One frame: [stepDt] = game dt (0 while paused), [dt] = real dt (pulse, toast). Public for tests.
  void update(double stepDt, double dt) {
    final w = world;
    if (w == null) return;
    w.update(stepDt, _near);
    _clock += dt;
    if (_toastS > 0 && (_toastS -= dt) <= 0) ringingToast.value = false;
    if (w.ringing == null && answerable.value) answerable.value = false;
  }

  /// Picks up the ringing booth and opens its offer card (the "Zvednout" button).
  BoothOffer? answer() {
    final w = world;
    final b = w?.ringing;
    if (w == null || b == null) return null;
    final offer = w.answer(w.state.ringing);
    answerable.value = false;
    if (offer != null) {
      card.value = (booth: b, offer: offer);
      game.pauseOverlays.register(GameOverlay.booth);
    }
    notifyListeners();
    return offer;
  }

  void _closeCard() {
    if (card.value == null) return;
    card.value = null;
    game.pauseOverlays.unregister(GameOverlay.booth);
  }

  /// "Jedu" = an accepted feed card: route, driveDm = road distance, feed.difficulty_base.
  void go() {
    final c = card.value;
    if (c == null) return;
    _closeCard();
    phone.acceptSpot(c.offer.spot, tuning.feed.difficultyBase);
    notifyListeners();
  }

  /// "Nechat být" = clear.
  void skip() {
    _closeCard();
    world?.clear();
    notifyListeners();
  }

  /// Drops the offer (city switch).
  void clear() => world?.clear();

  /// Host name: characters[fnv1a(boothId) mod n], the booth's name without characters.
  String hostName(Booth b) {
    final chars = loop.npc?.pack.characters ?? const [];
    final i = boothHost(b.id, chars.length);
    return i >= 0 ? chars[i].name : b.name;
  }

  /// Host character id (the same pick as [hostName]), null without characters.
  String? hostId(Booth b) {
    final chars = loop.npc?.pack.characters ?? const [];
    final i = boothHost(b.id, chars.length);
    return i >= 0 ? chars[i].id : null;
  }

  /// Minigame id of the offered spot ('' when unknown).
  String gameOf(BoothOffer o) => game.city.spots.items.where((s) => s.id == o.spot).firstOrNull?.minigame ?? '';

  // ---------- drawing
  void _paintWorld(ui.Canvas c) {
    final bt = tuning.booths;
    final body = Paint()..color = const Color(Tokens.colorBoothBody);
    final roof = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bt.boothWM / 5
      ..color = const Color(Tokens.colorBoothRoof);
    final rect = Rect.fromCenter(center: Offset.zero, width: bt.boothLM, height: bt.boothWM);
    for (final b in booths) {
      c
        ..save()
        ..translate(b.x, b.y)
        ..rotate(b.heading)
        ..drawRect(rect, body)
        ..drawRect(rect, roof)
        ..restore();
    }
    final ring = world?.ringing;
    if (ring != null) {
      // Pulse: a ring growing to the answer reach (loop.spot_radius_m) once per ring_pulse_s.
      final phase = bt.ringPulseS > 0 ? (_clock % bt.ringPulseS) / bt.ringPulseS : 0.0;
      c.drawCircle(
        Offset(ring.x, ring.y),
        math.max(0.1, tuning.loop.spotRadiusM * phase),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = bt.boothWM * 0.25
          ..color = const Color(Tokens.colorBoothRing).withValues(alpha: 1 - phase),
      );
    }
    _prevWorld?.call(c);
  }

  void _paintScreen(ui.Canvas c, ui.Size size) {
    final ring = world?.ringing;
    if (ring != null) {
      // Edge arrow towards an off-screen ringing booth (as navigation, specs/phone.md).
      final p = game.camera.toScreen(ring.x, ring.y, size, tuning);
      final a = edgeArrow(
        p.dx,
        p.dy,
        size.width,
        size.height,
        tuning.nav.arrowMarginPx,
        size.width * tuning.carAnchor.x,
        size.height * tuning.carAnchor.y,
      );
      if (a != null) {
        final s = tuning.nav.arrowPx;
        c
          ..save()
          ..translate(a.x, a.y)
          ..rotate(a.angle)
          ..drawPath(
            ui.Path()
              ..moveTo(s, 0)
              ..lineTo(-s * 0.7, s * 0.8)
              ..lineTo(-s * 0.3, 0)
              ..lineTo(-s * 0.7, -s * 0.8)
              ..close(),
            Paint()..color = const Color(Tokens.colorBoothRing),
          )
          ..restore();
      }
    }
    _prevScreen?.call(c, size);
  }

  @override
  void dispose() {
    if (world != null) {
      _closeCard();
      if (game.afterUpdate == _afterUpdate) game.afterUpdate = _prevUpdate;
      if (game.paintWorld == _paintWorld) game.paintWorld = _prevWorld;
      if (game.paintScreen == _paintScreen) game.paintScreen = _prevScreen;
      if (game.carActionYield == canAnswer) game.carActionYield = null;
      if (loop.yieldTo == canAnswer) loop.yieldTo = null;
      loop.book.bonus = null;
      phone.onAccept.remove(_onAccept);
      phone.mapPoints.remove(_mapPoints);
      game.hud.removeListener(_hud);
    }
    card.dispose();
    answerable.dispose();
    ringingToast.dispose();
    super.dispose();
  }
}
