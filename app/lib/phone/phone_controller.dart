import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:drive_core/drive_core.dart' show RouteGraph;
import 'package:feed_hub/feed_hub.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:world_engine/world_engine.dart';

import '../game/metropole_game.dart';
import '../game/pause.dart';

/// Phone apps in home-screen order (specs/phone.md "Telefon").
enum PhoneAppId { feed, map, garage, passport, camera, contacts, wallet, travel, settings }

/// What the navigation pill shows; refreshed ~10× a second.
class NavHudState {
  const NavHudState(this.place, this.remainingM);
  final String place;
  final double remainingM;
}

/// State of the in-game phone, the feed session and the GPS navigation (specs/phone.md).
/// Wires itself into [MetropoleGame] through its feature hooks.
class PhoneController extends ChangeNotifier {
  PhoneController(this.game, {int? feedSeed}) : _firstSeed = feedSeed {
    final city = game.city;
    rg = RouteGraph.fromPb(city.graphPb, tuning.route.classCost);
    _lens = edgeLengthsDm(city.graphPb);
    nav = Navigator(city.graph, rg, tuning.route, tuning.nav);
    _spots = {for (final s in city.spots.items) s.id: s};
    _lastX = game.drive.car.x;
    _lastY = game.drive.car.y;
    // The open phone pauses the game (phone.md v3, specs/pause.md); no slow motion any more.
    game
      ..afterUpdate = _update
      ..paintWorld = _paintRoute
      ..paintScreen = _paintArrow;
  }

  final MetropoleGame game;
  late final RouteGraph rg;
  late final Int32List _lens;
  late final Navigator nav;
  late final Map<String, Spot> _spots;

  Tuning get tuning => game.tuning;

  bool isOpen = false;
  PhoneAppId? app;

  /// arrived(spotId): the minigame launch hook (the loop, specs/loop.md).
  final List<void Function(String spotId)> onArrived = [];

  /// Travel app hooks (specs/cities.md), wired by the game screen: switch to a city, and the
  /// passport completion of a city from its save.
  void Function(CityId city)? onTravel;
  Future<int> Function(CityId city)? passportPercent;

  /// The last accepted feed card; the loop reads its distance and difficulty on arrival and clears it.
  ({String spot, int distDm, int difficulty})? accepted;

  /// Landmarks the player has discovered (passport stamps), for the feed's landmark bonus.
  Set<String> Function() discovered = () => const {};

  /// The feed state the save keeps (specs/save.md `feed`).
  ({Map<String, int> prefs, Map<String, int> visits, List<String> districts}) feedSave() =>
      (prefs: {..._prefs}, visits: {..._visits}, districts: _visitedDistricts.toList());

  void feedRestore(({Map<String, int> prefs, Map<String, int> visits, List<String> districts}) f) {
    _prefs = {...f.prefs};
    _visits
      ..clear()
      ..addAll(f.visits);
    _visitedDistricts
      ..clear()
      ..addAll(f.districts);
    _deck = null;
  }
  final navHud = ValueNotifier<NavHudState?>(null);

  /// i18n key of the toast shown now, or null.
  final toast = ValueNotifier<MessageKey?>(null);
  double _toastS = 0;
  double _hudS = 0;

  void open([PhoneAppId? a]) {
    isOpen = true;
    game.pauseOverlays.set(GameOverlay.phone, true);
    if (a != null) app = a;
    notifyListeners();
  }

  void close() {
    isOpen = false;
    game.pauseOverlays.set(GameOverlay.phone, false);
    notifyListeners();
  }

  void toggle() => isOpen ? close() : open();

  void launch(PhoneAppId? a) {
    app = a;
    notifyListeners();
  }

  String spotName(String id) => _spots[id]?.name ?? id;

  // ---------- feed session (specs/feed.md "Po balíčku")
  final _rules = FeedRules();
  FeedState? _deck;
  Map<String, int> _prefs = {};
  final Map<String, int> _visits = {};
  final Set<String> _visitedDistricts = {};
  double _driven = 0;
  bool _arrivedSinceDeal = false;
  double _lastX = 0, _lastY = 0;
  int? _firstSeed;
  final _random = math.Random();

  FeedRules get rules => _rules;

  FeedState get deck {
    final d = _deck;
    if (d == null || (d.over && (_driven >= tuning.feed.redealM || _arrivedSinceDeal))) _deal();
    return _deck!;
  }

  void _deal() {
    final city = game.city, car = game.drive.car, g = city.graph;
    final start = navStart(g, game.drive.layers.hit, car.x, car.y, car.heading, tuning.nav.searchM);
    final candidates = buildCandidates(
      cityId: city.id,
      spots: [for (final s in city.spots.items) CandidateSpot(s.id, s.minigame, s.x, s.y)],
      catalog: {for (final e in minigameCatalog.entries) e.key.id: e.value},
      districtAt: (x, y) => city.districtAt(x / 10, y / 10) ?? '',
      landmarks: [for (final l in city.landmarks.items) (id: l.id, x: l.x, y: l.y)],
      discovered: discovered(),
      visits: _visits,
      landmarkRadiusDm: tuning.feed.landmarkRadiusDm,
      distDm: (id) {
        final t = NavTarget.fromSpot(_spots[id]!);
        return feedDistDm(rg, _lens, start, navGoal(g, t), car.x, car.y, t, tuning.feed.straightPct);
      },
    );
    final seed = _firstSeed ?? _random.nextInt(1 << 32);
    _firstSeed = null;
    _deck = _rules.deal(FeedConfig.fromTuning(tuning.feed, candidates, _prefs, _visitedDistricts.toList()), seed);
    _driven = 0;
    _arrivedSinceDeal = false;
  }

  /// Applies a feed gesture through the rules; accept closes the phone and navigates.
  void act(FeedOp op) {
    final s = deck;
    if (!_rules.legalActions(s).contains(op)) return;
    final next = _rules.apply(s, op);
    _deck = next;
    _prefs = next.prefs;
    if (op == FeedOp.accept) {
      final card = next.deck.where((c) => c.spot == next.accepted).firstOrNull;
      accepted = card == null ? null : (spot: card.spot, distDm: card.distDm, difficulty: card.difficulty);
      close();
      navigate(next.accepted);
    }
    notifyListeners();
  }

  // ---------- navigation
  bool _silent = false;

  bool navigate(String spotId) {
    final s = _spots[spotId];
    if (s == null) return false;
    return navigateTo(NavTarget.fromSpot(s), silent: false);
  }

  /// Navigation to any target (a world minigame's passenger or destination). Silent: on arrival the
  /// route just ends (no toast, no visit, no onArrived).
  bool navigateTo(NavTarget target, {required bool silent}) {
    final car = game.drive.car;
    final ok = nav.start(target, car.x, car.y, car.heading, game.drive.layers.hit);
    _silent = silent;
    if (!ok && !silent) _showToast(MessageKey.noRoute);
    _hudS = 1e9;
    notifyListeners();
    return ok;
  }

  void cancelNav() {
    nav.cancel();
    navHud.value = null;
    _silent = false;
    notifyListeners();
  }

  void _showToast(MessageKey k) {
    toast.value = k;
    _toastS = tuning.nav.toastS;
  }

  void _update(double dt) {
    final car = game.drive.car;
    _driven += math.sqrt(math.pow(car.x - _lastX, 2) + math.pow(car.y - _lastY, 2));
    _lastX = car.x;
    _lastY = car.y;
    if (_toastS > 0 && (_toastS -= dt) <= 0) toast.value = null;
    // Navigation timers are world clocks: they stand while the game is paused.
    if (!nav.active || game.worldPaused) return;
    final ev = nav.update(car.x, car.y, car.heading, game.drive.layers.hit, dt);
    if (ev == NavEvent.arrived && _silent) {
      cancelNav();
      return;
    }
    if (ev == NavEvent.arrived) {
      final id = nav.target!.id;
      cancelNav();
      _visits[id] = (_visits[id] ?? 0) + 1;
      final s = _spots[id]!;
      final d = game.city.districtAt(s.x / 10, s.y / 10);
      if (d != null) _visitedDistricts.add(d);
      _arrivedSinceDeal = true;
      _showToast(MessageKey.arrived);
      for (final f in onArrived) {
        f(id);
      }
      return;
    }
    _hudS += dt;
    if (_hudS >= 0.1) {
      _hudS = 0;
      navHud.value = NavHudState(nav.target!.name, nav.remaining);
    }
  }

  void _paintRoute(ui.Canvas c) {
    if (!nav.active) return;
    final pts = nav.ahead();
    if (pts.length < 4) return;
    final path = ui.Path()..moveTo(pts[0], pts[1]);
    for (var i = 2; i + 1 < pts.length; i += 2) {
      path.lineTo(pts[i], pts[i + 1]);
    }
    c.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = tuning.route.lineWidthM
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(Tokens.colorUiRoute),
    );
  }

  void _paintArrow(ui.Canvas c, ui.Size size) {
    if (!nav.active) return;
    final p = game.camera.toScreen(nav.parkX, nav.parkY, size, tuning);
    final a = edgeArrow(
      p.dx,
      p.dy,
      size.width,
      size.height,
      tuning.nav.arrowMarginPx,
      size.width * tuning.carAnchor.x,
      size.height * tuning.carAnchor.y,
    );
    if (a == null) return;
    final s = tuning.nav.arrowPx;
    c.save();
    c.translate(a.x, a.y);
    c.rotate(a.angle);
    c.drawPath(
      ui.Path()
        ..moveTo(s, 0)
        ..lineTo(-s * 0.7, s * 0.8)
        ..lineTo(-s * 0.3, 0)
        ..lineTo(-s * 0.7, -s * 0.8)
        ..close(),
      Paint()..color = const Color(Tokens.colorUiRouteArrow),
    );
    c.restore();
  }

  @override
  void dispose() {
    game.pauseOverlays.set(GameOverlay.phone, false);
    game
      ..afterUpdate = null
      ..paintWorld = null
      ..paintScreen = null;
    navHud.dispose();
    toast.dispose();
    super.dispose();
  }
}
