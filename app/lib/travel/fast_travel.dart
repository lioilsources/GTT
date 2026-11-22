import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:drive_core/drive_core.dart' show DriveWorld, PedestrianWorld;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:game_loop/game_loop.dart';
import 'package:world_engine/world_engine.dart';

import '../game/metropole_game.dart';
import '../game/pause.dart';
import '../loop/loop_controller.dart';
import '../phone/phone_controller.dart';
import '../phone/phone_sheet.dart';
import 'taxi_screen.dart';

/// Hero landmarks with a kept ground road within [searchM] (landmarks.pb order): the stop point is
/// the projection on that road, heading along the edge, against it on a reverse one-way
/// (specs/travel.md "Taxi"). A landmark without a road in reach is left out.
List<TaxiTarget> taxiLandmarkTargets(RoadGraph g, Iterable<Landmark> landmarks, double searchM) => [
  for (final l in landmarks)
    if (l.hero)
      if (g.nearest(l.x / 10, l.y / 10, maxDist: searchM, where: (e) => e.kept && e.isGround) case final h?)
        for (final back in [h.edge.oneway == -1])
          TaxiTarget(
            kind: TaxiTargetKind.landmark,
            id: l.id,
            name: l.name,
            x: h.x,
            y: h.y,
            heading: math.atan2(back ? -h.dirY : h.dirY, back ? -h.dirX : h.dirX),
          ),
];

/// Taxi destinations: spots with a catalog minigame (spots.pb order), then hero landmarks.
List<TaxiTarget> taxiTargets(City city, double searchM) => [
  ...taxiSpotTargets(city.spots.items, {for (final e in minigameCatalog.entries) e.key.id: e.value}),
  ...taxiLandmarkTargets(city.graph, city.landmarks.items, searchM),
];

/// The move (spec "Přesun"): the roadblock goes first (before the traffic reset), then a new body
/// at rest on the target's parking point facing its heading (layer from the ground), traffic with
/// its patrols and pedestrians reset like after a teleport. The caller snaps the camera.
void moveTo(DriveWorld drive, PedestrianWorld? peds, void Function()? clearRoadblock, TravelPoint p) {
  clearRoadblock?.call();
  drive.spawn(p.x, p.y, p.heading);
  drive.traffic?.reset();
  peds?.clear();
}

/// The line card of a move: the target's name and whether it is a metro ride.
typedef TravelCut = ({String name, bool metro});

/// Fast travel of client F (specs/travel.md P1): station unlocking, the "Metro" button and card, the
/// Taxi phone app, the line card and the move. Port of web/src/travel/fastTravel.ts; [FastTravelLayer]
/// draws the HUD part. Off (no [world], no hooks) when `travel.enabled` is false.
class FastTravelController extends ChangeNotifier {
  FastTravelController(this.game, this.phone, this.loop) {
    stations = stationsOf(game.city.spots.items);
    if (!tuning.travel.enabled) return;
    final w = world = TravelWorld(stations, tuning, getCash: () => game.fleet.state.cash, setCash: game.fleet.setCash);
    w.load(loop.savedStations);
    loop.stations = () => [...w.unlocked];
    loop.onStationsRestored = w.load;
    targets = taxiTargets(game.city, tuning.minigames.taxi.destSearchM);
    phone.mapPoints.add(_mapPoints);
    registerPhoneApp(PhoneAppId.taxi, (context, phone) => TaxiScreen(travel: this));
    game.hud.addListener(_hud);
    _prevWorld = game.paintWorld;
    game.paintWorld = _paintWorld;
  }

  final MetropoleGame game;
  final PhoneController phone;
  final LoopController loop;
  late final List<TravelPoint> stations;
  List<TaxiTarget> targets = const [];

  /// Null when travel is off (no module).
  TravelWorld? world;

  void Function(ui.Canvas)? _prevWorld;
  Timer? _cutTimer;

  Tuning get tuning => game.tuning;

  /// The station the open metro card departs from (the game is paused while it is up).
  final metroCard = ValueNotifier<TravelPoint?>(null);

  /// The line card of a running move.
  final cut = ValueNotifier<TravelCut?>(null);

  /// The station whose "Metro" button shows now (HUD tick).
  final metroHere = ValueNotifier<TravelPoint?>(null);

  /// Name of the station in the "unlocked" toast shown now.
  final unlockedToast = ValueNotifier<String?>(null);
  double _toastS = 0;

  int get wanted => game.police.wantedLevel;

  /// Fast travel is offered: no move running, no minigame, no Taxi shift, not wanted.
  bool get offered =>
      world != null &&
      cut.value == null &&
      travelOffered(busy: loop.busy, inWorldGame: loop.inWorldGame, wanted: wanted);

  /// The unlocked station in reach of the "Metro" button (hidden with the phone or a card open).
  TravelPoint? stationHere() {
    final w = world, c = game.drive.car;
    if (w == null || !offered || metroCard.value != null || phone.isOpen) return null;
    return w.stationAt(c.x, c.y, c.speed, c.layer, tuning.loop);
  }

  /// The Taxi list from the car: sorted by distance, with fares; greyed when short of cash.
  List<TravelChoice<TaxiTarget>> taxiList() {
    final w = world, c = game.drive.car;
    if (w == null) return const [];
    return taxiChoices(targets, c.x, c.y, game.fleet.state.cash, w.config);
  }

  List<TravelChoice<TravelPoint>> metroList() {
    final from = metroCard.value;
    return from == null ? const [] : world?.metroChoices(from.id) ?? const [];
  }

  List<({double x, double y, int color})> _mapPoints() => [
    for (final id in world?.unlocked ?? const <String>[])
      for (final s in [world!.station(id)!]) (x: s.x, y: s.y, color: Tokens.colorTravelEntry),
  ];

  /// HUD tick (~10×/s): unlocking by passing (not during a minigame or the result card), the toast,
  /// the "Metro" button. Public for tests.
  void tick([double dt = 0.1]) {
    final w = world;
    if (w == null) return;
    if (_toastS > 0 && (_toastS -= dt) <= 0) unlockedToast.value = null;
    if (!loop.busy) {
      final c = game.drive.car;
      final fresh = w.pass(c.x, c.y, c.layer, tuning.travel.unlockM);
      if (fresh.isNotEmpty) {
        unlockedToast.value = fresh.last.name;
        _toastS = tuning.nav.toastS;
        loop.save();
        notifyListeners();
      }
    }
    final here = stationHere();
    if (here?.id != metroHere.value?.id) metroHere.value = here;
  }

  void _hud() => tick();

  /// Opens the metro card at the station in reach; false when not offered.
  bool openMetro() {
    final s = stationHere();
    if (s == null) return false;
    metroCard.value = s;
    metroHere.value = null;
    game.pauseOverlays.register(GameOverlay.travel);
    notifyListeners();
    return true;
  }

  void closeMetro() {
    if (metroCard.value == null) return;
    metroCard.value = null;
    game.pauseOverlays.unregister(GameOverlay.travel);
    notifyListeners();
  }

  /// A station of the metro card: pays the fare and moves; false when it is not legal (cash).
  bool metro(String to) {
    final w = world, from = metroCard.value;
    final p = w?.station(to);
    if (w == null || from == null || p == null || w.metro(from.id, to) == null) return false;
    closeMetro();
    _travel(p, metro: true);
    return true;
  }

  /// Takes a taxi to the target [id]; false when not offered or not affordable.
  bool taxi(String id) {
    final w = world;
    if (w == null || !offered) return false;
    final ch = taxiList().where((x) => x.point.id == id).firstOrNull;
    if (ch == null || !ch.affordable || w.taxi(ch.distDm) == null) return false;
    _travel(ch.point, metro: false);
    return true;
  }

  /// The line card over the world for travel.cut_s of real time, the move at its start (spec
  /// "Přesun"); the game stands under it. The accepted feed card and the navigation stay, the route
  /// is recomputed when the card goes.
  void _travel(TravelPoint p, {required bool metro}) {
    phone.close();
    cut.value = (name: p.name, metro: metro);
    metroHere.value = null;
    game.pauseOverlays.register(GameOverlay.travel);
    moveTo(game.drive, game.peds, game.police.clearRoadblock, p);
    final c = game.drive.car;
    game.camera.snap(c.x, c.y, c.heading, tuning);
    loop.save();
    notifyListeners();
    _cutTimer?.cancel();
    _cutTimer = Timer(Duration(milliseconds: (tuning.travel.cutS * 1000).round()), endCut);
  }

  /// Ends the line card (its timer; tests call it directly).
  void endCut() {
    _cutTimer?.cancel();
    _cutTimer = null;
    if (cut.value == null) return;
    cut.value = null;
    game.pauseOverlays.unregister(GameOverlay.travel);
    final t = phone.nav.active ? phone.nav.target : null;
    if (t != null) phone.navigateTo(t, silent: false);
    notifyListeners();
  }

  // ---------- drawing: station entrances seen from above at the parking point
  void _paintWorld(ui.Canvas c) {
    final w = world;
    if (w != null && stations.isNotEmpty) {
      final t = tuning.travel;
      final open = Paint()..color = const Color(Tokens.colorTravelEntry);
      final locked = Paint()..color = const Color(Tokens.colorTravelEntryLocked);
      final rect = Rect.fromCenter(center: Offset.zero, width: t.entryLM, height: t.entryWM);
      for (final s in stations) {
        c
          ..save()
          ..translate(s.x, s.y)
          ..rotate(s.heading)
          ..drawRect(rect, w.isUnlocked(s.id) ? open : locked)
          ..restore();
      }
    }
    _prevWorld?.call(c);
  }

  @override
  void dispose() {
    _cutTimer?.cancel();
    if (world != null) {
      closeMetro();
      if (cut.value != null) {
        cut.value = null;
        game.pauseOverlays.unregister(GameOverlay.travel);
      }
      if (game.paintWorld == _paintWorld) game.paintWorld = _prevWorld;
      if (loop.onStationsRestored != null) loop.onStationsRestored = null;
      loop.stations = null;
      phone.mapPoints.remove(_mapPoints);
      phoneApps.remove(PhoneAppId.taxi);
      game.hud.removeListener(_hud);
    }
    metroCard.dispose();
    cut.dispose();
    metroHere.dispose();
    unlockedToast.dispose();
    super.dispose();
  }
}
