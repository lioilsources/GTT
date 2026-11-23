import 'dart:async';
import 'dart:convert';

import 'package:drive_core/drive_core.dart';
import 'package:flame/game.dart';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:npc_dialogue/npc_dialogue.dart';
import 'package:shared_gen/shared_gen.dart';

import '../booths/booths_controller.dart';
import '../booths/booths_layer.dart';
import '../cities/cities.dart';
import '../cities/passport_percent.dart';
import '../game/metropole_game.dart';
import '../game/pause.dart';
import '../game/stuck_log.dart';
import '../garage/garage_controller.dart';
import '../garage/test_drive_hud.dart';
import '../l10n/app_localizations.dart';
import '../loop/loop_controller.dart';
import '../loop/loop_layer.dart';
import '../loop/save_store.dart';
import '../main.dart' show appClock;
import '../phone/nav_hud.dart';
import '../phone/phone_controller.dart';
import '../phone/phone_sheet.dart';
import '../photo/photo_controller.dart';
import '../photo/photo_layer.dart';
import '../shops/shops_controller.dart';
import '../shops/shops_layer.dart';
import '../drift/drift_controller.dart';
import '../drift/drift_hud.dart';
import '../minigames/world_hud.dart';
import '../sprint/sprint_controller.dart';
import '../sprint/sprint_hud.dart';
import '../taxi/taxi_controller.dart';
import '../taxi/taxi_hud.dart';
import '../travel/fast_travel.dart';
import '../weather/weather_controller.dart';
import '../weather/weather_layer.dart';
import '../travel/fast_travel_layer.dart';
import 'garage_sheet.dart';
import 'hud.dart';
import 'passport.dart';
import 'police_hud.dart';
import 'tuning_panel.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.city = CityId.nyc, this.car = CarId.m0Coupe, this.from});

  final CityId city;
  final CarId car;

  /// The city the player travelled from; a failed load offers the way back (specs/cities.md).
  final CityId? from;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final Future<MetropoleGame> _game = _load();
  ControlSchemeId _scheme = ControlSchemeId.a;
  PhoneController? _phone;
  // Loop glue and the save (specs/loop.md, specs/save.md): read before the first frame.
  LoopController? _loop;
  LoopController? _finesWired;
  TaxiController? _taxi;
  DriftController? _drift;
  SprintController? _sprint;
  BoothsController? _booths;
  FastTravelController? _fastTravel;
  PhotoController? _photo;
  ShopsController? _shops;
  WeatherController? _weather;
  GarageController? _garage;
  final SaveStore _store = FileSaveStore();
  final CityStore _cities = FileCityStore();
  Object? _saved;
  DialogueSession? _npc;
  bool _hasBench = false;
  bool _leaving = false;
  bool _shown = false;

  @override
  void dispose() {
    // A game that never reached the GameWidget (still loading) is released when it arrives; a shown
    // one is released by the GameWidget (onRemove: streamer, police, physics).
    if (!_shown) _game.then((g) => g.onRemove(), onError: (_) {});
    _loop?.save();
    _weather?.dispose();
    _garage?.dispose();
    _shops?.dispose();
    _photo?.dispose();
    _fastTravel?.dispose();
    _booths?.dispose();
    _loop?.dispose();
    _taxi?.dispose();
    TaxiGame.startInCity = null;
    _drift?.dispose();
    _sprint?.dispose();
    WorldCardGame.startInCity.clear();
    _phone?.dispose();
    super.dispose();
  }

  Future<MetropoleGame> _load() async {
    final assets = await GameAssets.load(widget.city, widget.car);
    // The last city is written on every city start, after its pack loaded (specs/cities.md).
    unawaited(_cities.write(widget.city.id));
    _hasBench = await _assetExists('${GameAssets.shared}content/bench/${widget.city.id}.json');
    _saved = await _store.read(widget.city.id);
    _npc = await ensureDialogueSession(
      assets.tuning,
      city: widget.city.id,
    ).then<DialogueSession?>((s) => s, onError: (_) => null);
    final game = MetropoleGame(assets);
    await game.preload();
    return game;
  }

  static Future<bool> _assetExists(String path) async {
    try {
      return (await AssetManifest.loadFromAssetBundle(rootBundle)).listAssets().contains(path);
    } catch (_) {
      return false;
    }
  }

  /// Travel app (specs/cities.md): close the phone, save this city as on pause, then replace the
  /// screen with the chosen city; dispose releases this game. A running loop is dropped unscored.
  Future<void> _travel(CityId to) async {
    if (_leaving || to == widget.city) return;
    _leaving = true;
    _phone?.close();
    _booths?.clear(); // the booth offer does not travel (specs/booths.md "Bonus")
    await switchCity(widget.city, to, saveCurrent: () => _loop?.save() ?? Future.value());
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(city: to, car: widget.car, from: widget.city),
      ),
    );
  }

  Future<int> _passportPercent(MetropoleGame game, CityId c) => c.id == game.city.id
      ? Future.value(game.passport.result.percent)
      : cityPassportPercent(c, _store, game.tuning).then((p) => p, onError: (_) => 0);

  /// Gallery: teleport to the taxi stand and start the shift there.
  void _startTaxi(MetropoleGame game, LoopController loop) {
    final s = game.city.spots.items.where((s) => s.minigame == MinigameId.taxi.id).firstOrNull;
    if (s == null) return;
    game.drive.spawn(s.parkX / 10, s.parkY / 10, s.parkHeading.toDouble());
    game.camera.snap(game.drive.car.x, game.drive.car.y, game.drive.car.heading, game.tuning);
    loop.start(s.id);
  }

  /// Gallery: moves the car to the first spot of a world minigame and starts it there.
  void _startAtSpot(MetropoleGame game, LoopController loop, MinigameId id) {
    final s = game.city.spots.items.where((s) => s.minigame == id.id).firstOrNull;
    if (s == null) return;
    game.drive.spawn(s.parkX / 10, s.parkY / 10, s.parkHeading.toDouble());
    game.camera.snap(game.drive.car.x, game.drive.car.y, game.drive.car.heading, game.tuning);
    loop.start(s.id);
  }

  void _setSettings(MetropoleGame game, LoopSettings s) {
    _scheme = ControlSchemeId.values.firstWhere((c) => c.name == s.scheme, orElse: () => ControlSchemeId.a);
    game.setScheme(_scheme);
    game.setNight(s.night);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(Tokens.colorUiBackground),
      body: FutureBuilder<MetropoleGame>(
        future: _game,
        builder: (context, snap) {
          if (snap.hasError) {
            final back = widget.from;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l.loadFailed('${snap.error}'), style: const TextStyle(color: Color(Tokens.colorUiText))),
                    if (back != null)
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Color(Tokens.colorUiText)),
                        onPressed: () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute<void>(
                            builder: (_) => GameScreen(city: back, car: widget.car),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }
          final game = snap.data;
          if (game != null && game.firstFrameMs == 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (game.firstFrameMs == 0) game.firstFrameMs = appClock.elapsedMilliseconds;
            });
          }
          if (game == null) {
            return Center(
              child: Text(l.loading(widget.city.name), style: const TextStyle(color: Color(Tokens.colorUiTextMuted))),
            );
          }
          _shown = true;
          final phone = _phone ??= PhoneController(game)
            ..onTravel = _travel
            ..passportPercent = ((c) => _passportPercent(game, c));
          // Wall slide and rescue (specs/flow.md, F-069): the road move faces along the GPS route, the
          // phone home screen (the pause menu) has "Na silnici", the debug build logs stuck events.
          if (phone.onToRoad == null) {
            phone.onToRoad = () => game.toRoad();
            game.drive.routeAhead = () {
              final r = phone.nav.ahead();
              return r.length >= 4 ? r : null;
            };
            if (kDebugMode) game.drive.flow.onStuck = StuckLogFile(game.city.id).append;
          }
          final loop = _loop ??= LoopController(
            game,
            phone,
            store: _store,
            npc: _npc,
            saved: _saved,
            settingsGet: () => (scheme: _scheme.name, night: game.night),
            settingsSet: (s) => _setSettings(game, s),
          );
          // Police fines take cash through the economy (specs/economy.md); wired once per controller.
          if (_finesWired != loop) {
            _finesWired = loop;
            game.police.onFined.add(loop.fine);
          }
          // Taxi: a world minigame the loop starts at the taxi stand (specs/minigames/taxi.md).
          final taxi = _taxi ??= TaxiController(game, phone);
          loop.worldGames[MinigameId.taxi] = taxi;
          TaxiGame.startInCity = () => _startTaxi(game, loop);
          // Drift zone and Sprint A→B: world minigames in the player's own car (specs/minigames/drift.md,
          // sprint.md); the Gallery card moves the car to the spot and starts it.
          final drift = _drift ??= DriftController(game);
          loop.worldGames[MinigameId.drift] = drift;
          final sprint = _sprint ??= SprintController(game, phone);
          loop.worldGames[MinigameId.sprint] = sprint;
          for (final id in [MinigameId.drift, MinigameId.sprint]) {
            WorldCardGame.startInCity[id] = () => _startAtSpot(game, loop, id);
          }
          // Ringing phone booths (specs/booths.md): offer a minigame with a cash bonus.
          final booths = _booths ??= BoothsController(game, phone, loop);
          // Fast travel by metro and taxi (specs/travel.md): stations unlock by passing, the move
          // resets traffic, patrols and pedestrians like a teleport.
          final fastTravel = _fastTravel ??= FastTravelController(game, phone, loop);
          // Photo spots and the Camera (specs/photo.md): after the booths, whose "Zvednout" goes first.
          final photo = _photo ??= PhotoController(game, phone, loop);
          // Shops and bars (specs/shops.md): after the Camera, whose "Foťák" goes first.
          final shops = _shops ??= ShopsController(game, phone, loop);
          // Weather (specs/weather.md): a new module per game, so a city switch starts clear.
          final weather = _weather ??= WeatherController(game);
          // Tuning and cosmetics (specs/garage.md): the garage tabs, the tuned body, the looks.
          final garage = _garage ??= GarageController(game, loop, phone: phone)..shelf = shops.shelf;
          // The garage sheet: from the context button at the spot, or from the phone Garage app
          // anywhere (specs/testdrive.md v2: away from the spot cars appear in place).
          Future<void> openGarage() async {
            // Opening the garage ends a test drive: back in the own car (specs/testdrive.md).
            game.fleet.endTest();
            final here = !game.fleet.atGarage();
            await game.pauseOverlays.hold(
              GameOverlay.garage,
              showGarage(
                context,
                game.fleet,
                shelf: shops.shelf,
                garage: garage,
                testBlocked: loop.inWorldGame,
                here: here,
              ),
            );
            garage.leave();
          }

          garage.openSheet = () {
            phone.close();
            openGarage();
          };
          return Stack(
            fit: StackFit.expand,
            children: [
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) => game.pointerDown(e.pointer, e.localPosition),
                onPointerMove: (e) => game.pointerMove(e.pointer, e.localPosition),
                onPointerUp: (e) => game.pointerUp(e.pointer),
                onPointerCancel: (e) => game.pointerUp(e.pointer),
                child: GameWidget(game: game, autofocus: true),
              ),
              Hud(
                game: game,
                scheme: _scheme,
                onNight: () => setState(() => game.setNight(!game.night)),
                onPhone: phone.toggle,
                onCarAction: (a) async {
                  if (a == CarAction.board) return game.boardCandidate();
                  await openGarage();
                },
                onHop: game.hop,
                onToRoad: () {
                  if (!game.worldPaused) game.toRoad();
                },
                onTuning: () => showTuningPanel(
                  context,
                  game,
                  onScheme: (id) {
                    setState(() => _scheme = id);
                    game.setScheme(id);
                  },
                  onBench: _hasBench ? game.startBench : null,
                  onResetSave: loop.resetSave,
                  onDebugCash: loop.grantDebugCash,
                  weather: weather,
                ),
                onPassport: () => PassportScreen.open(
                  context,
                  game.passport,
                  game.city.manifest.name,
                  AboutInfo.of(game.city),
                  city: game.city.id,
                  overlays: game.pauseOverlays,
                ),
              ),
              PoliceHud(police: game.police),
              NavHud(phone: phone),
              TaxiHud(taxi: taxi),
              TestDriveHud(game: game),
              DriftHud(drift: drift),
              SprintHud(sprint: sprint),
              PhoneLayer(phone: phone),
              LoopLayer(loop: loop),
              BoothsLayer(booths: booths),
              FastTravelLayer(travel: fastTravel),
              PhotoLayer(photo: photo),
              ShopsLayer(shops: shops),
              WeatherLayer(weather: weather),
              PassportOverlay(
                events: game.passportEvent,
                seconds: game.tuning.passport.postcardS,
                city: game.city.id,
                overlays: game.pauseOverlays,
              ),
              _BenchOverlay(game: game),
            ],
          );
        },
      ),
    );
  }
}

/// Progress pill while the benchmark runs, then the result with a copy button (specs/bench.md).
class _BenchOverlay extends StatelessWidget {
  const _BenchOverlay({required this.game});
  final MetropoleGame game;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([game.benchProgress, game.benchResult]),
      builder: (context, _) {
        final p = game.benchProgress.value;
        final r = game.benchResult.value;
        if (p == null && r == null) return const SizedBox.shrink();
        if (r == null) {
          return SafeArea(
            child: Align(
              alignment: const Alignment(0, -0.82),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(Tokens.colorUiNotice),
                  borderRadius: BorderRadius.circular(Tokens.radiusPill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    l.benchRunning((p! * 100).floor()),
                    style: const TextStyle(color: Color(Tokens.colorUiText), fontSize: Tokens.fontNotice),
                  ),
                ),
              ),
            ),
          );
        }
        final text = const JsonEncoder.withIndent('  ').convert(r.toJson());
        return Center(
          child: Container(
            width: 380,
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(Tokens.colorUiSheet),
              borderRadius: BorderRadius.circular(Tokens.radiusButton),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.benchDone,
                  style: const TextStyle(color: Color(Tokens.colorUiText), fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      text,
                      style: const TextStyle(
                        color: Color(Tokens.colorUiTextMuted),
                        fontSize: Tokens.fontFaint,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: Text(l.copy),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.copied)));
                    }
                  },
                ),
                TextButton(onPressed: () => game.benchResult.value = null, child: Text(l.close)),
              ],
            ),
          ),
        );
      },
    );
  }
}
