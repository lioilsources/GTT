import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:drive_core/drive_core.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:game_loop/game_loop.dart' show CarLook;
import 'package:meta_progress/meta_progress.dart';
import 'package:world_engine/world_engine.dart';

import 'paint/bollards_painter.dart';
import 'paint/car_painter.dart';
import 'paint/controls_painter.dart';
import 'paint/pedestrians_painter.dart';
import 'paint/police_painter.dart';
import 'paint/props_painter.dart';
import 'paint/traffic_painter.dart';
import 'paint/trams_painter.dart';
import '../ui/passport.dart' show passportCityOf;
import 'pause.dart';

/// Everything loaded before the first frame.
class GameAssets {
  GameAssets({
    required this.city,
    required this.source,
    required this.tuning,
    required this.car,
    required this.cars,
    required this.textures,
    this.risograph,
  }) : tuningBaseline = tuning.flatten(),
       carBaseline = car.toJson();

  final City city;
  final PackSource source;
  final Tuning tuning;
  final CarSpec car;

  /// Every car of content/cars by id (specs/cars.md); [car] is one of them.
  final Map<String, CarSpec> cars;
  final FacadeTextures textures;

  /// Risograph shader (specs/style.md), null where shader filters are unsupported (no Impeller).
  final ui.FragmentProgram? risograph;

  /// Values as loaded, so the tuning panel can export only what was changed.
  final Map<String, Object> tuningBaseline;
  final Map<String, Object?> carBaseline;

  /// Shared runtime files are copied into assets/shared/ by `metro sync`.
  static const shared = 'assets/shared/';

  static Future<GameAssets> load(CityId city, CarId car) async {
    await initializeForge2D();
    final source = AssetPackSource('${shared}packs/${city.id}/');
    final results = await Future.wait([
      City.load(source),
      rootBundle.loadString('${shared}content/tuning.yaml'),
      Future.wait([for (final c in CarId.values) rootBundle.loadString('${shared}content/cars/${c.id}.json')]),
      FacadeTextures.create(),
      _loadRisograph(),
    ]);
    final cars = {
      for (final j in results[2] as List<String>)
        for (final s in [parseCarSpec(j)]) s.id: s,
    };
    return GameAssets(
      city: results[0] as City,
      source: source,
      tuning: Tuning.fromYaml(results[1] as String),
      car: cars[car.id]!,
      cars: cars,
      textures: results[3] as FacadeTextures,
      risograph: results[4] as ui.FragmentProgram?,
    );
  }

  static Future<ui.FragmentProgram?> _loadRisograph() async {
    if (!ui.ImageFilter.isShaderFilterSupported) return null;
    try {
      return await ui.FragmentProgram.fromAsset('shaders/risograph.frag');
    } catch (e) {
      debugPrint('risograph shader unavailable: $e');
      return null;
    }
  }
}

/// Values the Flutter HUD shows; refreshed ~10× a second, not every frame.
class HudState {
  const HudState({
    this.street = '',
    this.district,
    this.speedMps = 0,
    this.layer = 0,
    this.fps = 0,
    this.frameMs = 0,
    this.prepMs = 0,
    this.buildings = 0,
    this.chunks = 0,
    this.nearBorder = false,
    this.carName = '',
    this.carAction,
    this.hopFull,
    this.hopCharges = 0,
    this.hopReady = false,
  });

  final String street;
  final String? district;
  final double speedMps;
  final int layer;
  final double fps;
  final double frameMs;
  final double prepMs;
  final int buildings;
  final int chunks;
  final bool nearBorder;

  /// Name of the car being driven and the context button (specs/cars.md).
  final String carName;
  final CarAction? carAction;

  /// Air tank of the driven car (specs/hop.md): full size (null = the car cannot hop), hops left,
  /// and whether the "Hop" button is live now.
  final int? hopFull;
  final int hopCharges;
  final bool hopReady;
}

/// Context button next to a parked car or in the garage.
enum CarAction { board, garage }

/// M0 game loop: drive, stream, render (no traffic, peds, police, feed or saving).
class MetropoleGame extends Game {
  MetropoleGame(this.data) {
    final city = data.city;
    tuning = data.tuning;
    drive = DriveWorld(city: city, spec: data.cars[tuning.cars.startCar] ?? data.car, tuning: tuning);
    // Cars, switching and the garage (specs/cars.md).
    final g = city.spots.items.where((s) => s.kind == 'garage').firstOrNull;
    fleet = CarFleet(
      drive,
      data.cars,
      tuning,
      g == null ? null : (id: g.id, x: g.parkX / 10, y: g.parkY / 10, heading: g.parkHeading),
    );
    streamer = ChunkStreamer(
      city,
      data.source,
      tuning,
      onLoaded: (c) {
        drive.addChunk(c.data);
        fleet.addChunk(c.data);
        police.addChunk(c.data);
      },
      onUnloaded: (c) {
        fleet.removeChunk(c.data);
        police.removeChunk(c.data);
        drive.removeChunk(c.data);
      },
    );
    scheme = ControlScheme.create(ControlSchemeId.a, tuning.controls);
    renderer = WorldRenderer(
      city: city,
      roads: RoadMeshes.build(
        city.graph,
        city.chunkM,
        sidewalkM: tuning.sidewalkWidthM,
        laneM: tuning.laneWidthM,
        crosswalks: crosswalksOn(tuning.style, city.id) ? CrosswalkParams.fromTuning(tuning) : null,
      ),
      streamer: streamer,
      tuning: tuning,
      textures: data.textures,
    );
    // Tracks are part of the city even with trams switched off (specs/trams.md).
    _applySkin();
    _tramsPainter = city.trams.isEmpty ? null : TramsPainter(city.trams, tuning.trams);
    camera.snap(drive.car.x, drive.car.y, drive.car.heading, tuning);
    peds = PedestrianWorld(city, tuning);
    _pedBubbles = PedBubblePainter(
      tr(ui.PlatformDispatcher.instance.locale.languageCode, MessageKey.pedestrianBubble),
      tuning.pedestrians.bubblePx,
    );
    passport = PassportTracker(passportCityOf(city), tuning.passport)..onStamp((e) => passportEvent.value = e);
    // Police and wanted level (specs/police.md); the HUD listens to its hooks.
    police = Police(drive, tuning, fleet);
    // The benchmark result card pauses the game until it is closed (specs/pause.md).
    benchResult.addListener(() => pauseOverlays.set(GameOverlay.bench, benchResult.value != null));
  }

  final GameAssets data;
  late final PedestrianWorld peds;
  late final PedBubblePainter _pedBubbles;
  late final Tuning tuning;
  late final DriveWorld drive;
  late final CarFleet fleet;
  late final Police police;
  double _policeClock = 0;
  late final ChunkStreamer streamer;
  late final WorldRenderer renderer;
  late final TramsPainter? _tramsPainter;
  final camera = CameraRig();
  late ControlScheme scheme;
  final hud = ValueNotifier<HudState>(const HudState());
  bool night = false;

  /// Tourist passport (specs/passport.md); the save feature will pass stamps in and read them out.
  late final PassportTracker passport;
  final passportEvent = ValueNotifier<StampEvent?>(null);

  /// Benchmark (specs/bench.md): progress 0..1 while running, then the result.
  Autopilot? pilot;
  final benchProgress = ValueNotifier<double?>(null);
  final benchResult = ValueNotifier<BenchResult?>(null);
  final List<double> _benchMs = [];
  double _benchClock = 0;

  /// Milliseconds from `main` to the first frame with the car's surroundings loaded.
  int firstFrameMs = 0;

  /// Feature hooks (the phone, specs/phone.md): per-frame update with the real dt (read [worldPaused]
  /// for world clocks), drawing in world metres on layer 0 and on top of the screen.
  void Function(double dt)? afterUpdate;
  void Function(ui.Canvas canvas)? paintWorld;
  void Function(ui.Canvas canvas, ui.Size size)? paintScreen;

  /// Screen-space drawing straight over the world layer (after the risograph pass), under
  /// [paintScreen], street labels and the HUD: rain and fog of specs/weather.md.
  void Function(ui.Canvas canvas, ui.Size size)? paintOverWorld;

  /// Drives the camera rig this frame with the real dt (the Camera glide, specs/photo.md); false =
  /// the rig follows the car.
  bool Function(double dt)? cameraHook;

  /// Looks of owned cars (specs/garage.md "Kreslení"), set by the garage: the driven car's look
  /// (null = the catalog drawing: a stolen car, a Taxi shift) and that of a car the player left
  /// parked (owner `player`).
  CarLook? Function()? playerLook;
  CarLook? Function(ParkedCar p)? parkedLook;

  /// Rewrites the player's control input after the scheme and the keyboard (not under the
  /// autopilot or while paused): the drunk driver of specs/shops.md brakes to a stop.
  void Function(ControlInput input)? inputHook;

  ui.Size _size = ui.Size.zero;
  double _hudTimer = 0;
  int _frames = 0;
  double _frameAcc = 0;
  double _fps = 0;
  double _frameMs = 0;
  double _prepAcc = 0;
  int _prepN = 0;

  City get city => data.city;

  /// The game view size in logical pixels (zero before the first resize).
  ui.Size get viewSize => _size;

  Future<void> preload() => streamer.preload(drive.car.x, drive.car.y, drive.car.heading);

  void setNight(bool v) {
    night = v;
    drive.traffic?.night = v;
    _applySkin();
  }

  /// City skin (specs/style.md): the city's day palette, or the shared night one, and the
  /// risograph filter over the world layer by day. The renderer rebuilds nothing per palette
  /// (colours are applied per draw), so swapping the palette is all a switch needs; a city
  /// switch builds a new game, which lands here from the constructor.
  void _applySkin() {
    final base = night ? Palette.nightPalette : Palette.forCity(city.id);
    renderer.palette = base.wet(_wet / _wetSteps);
    renderer.worldFilter = risographEnabled(tuning.style, city.id, night: night) ? _risographFilter() : null;
  }

  /// Wet roads (specs/weather.md): the darkening in [_wetSteps] steps, so a blend rebuilds the
  /// palette a few dozen times, not every frame.
  int _wet = 0;
  static const _wetSteps = 64;

  /// Road, sidewalk and alley colours × (1 − [k]) (`weather.wet_darken` × the rain amount).
  void setWet(double k) {
    final q = (k.clamp(0.0, 1.0) * _wetSteps).round();
    if (q == _wet) return;
    _wet = q;
    _applySkin();
  }

  ui.ImageFilter? _risoFilter;

  /// The filter is built once per game: its uniforms (tuning, inks, pixel ratio) are fixed.
  ui.ImageFilter? _risographFilter() {
    final program = data.risograph;
    if (program == null) return null;
    final f = _risoFilter;
    if (f != null) return f;
    final st = tuning.style;
    final ink = Palette.forCity(city.id).inks.first;
    final dpr = ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1.0;
    final sh = program.fragmentShader();
    // Index 0–1 is uSize, set by the engine for an image filter.
    var i = 2;
    for (final v in [
      dpr,
      st.misregistrationPx,
      st.fringe,
      st.grainStrength,
      st.grainSizePx,
      st.halftoneCellPx,
      st.halftoneStrength,
      st.halftoneLow,
      st.halftoneHigh,
      ink.r,
      ink.g,
      ink.b,
    ]) {
      sh.setFloat(i++, v);
    }
    return _risoFilter = ui.ImageFilter.shader(sh);
  }

  void setScheme(ControlSchemeId id) => scheme = ControlScheme.create(id, tuning.controls);

  /// Starts the D1 benchmark: the autopilot takes over and drives the route of content/bench.
  Future<void> startBench() async {
    final json = await rootBundle.loadString('${GameAssets.shared}content/bench/${city.id}.json');
    final route = resolveRoute(city.graph, BenchRoute.fromJson(jsonDecode(json) as Map<String, Object?>));
    final p = pilot = Autopilot(route, tuning)..start(drive);
    drive.beforeStep = (step) => p.step(drive, drive.input, step);
    camera.snap(drive.car.x, drive.car.y, drive.car.heading, tuning);
    await streamer.preload(drive.car.x, drive.car.y, drive.car.heading);
    _benchMs.clear();
    _benchClock = 0;
    benchResult.value = null;
    benchProgress.value = 0;
  }

  void _benchFrame(double dt) {
    final p = pilot;
    if (p == null || benchResult.value != null) return;
    _benchClock += dt;
    if (_benchClock >= tuning.bench.warmupS) _benchMs.add(dt * 1000);
    if (!p.finished) {
      benchProgress.value = p.s / p.route.length;
      return;
    }
    final s = frameStats(_benchMs);
    double r(double v, int d) => (v * math.pow(10, d)).round() / math.pow(10, d);
    benchResult.value = BenchResult(
      client: 'flutter',
      route: 'midtown-42nd',
      device: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      completed: true,
      durationS: r(_benchClock, 1),
      frames: _benchMs.length,
      fpsAvg: r(s.fpsAvg, 1),
      fps1low: r(s.fps1Low, 1),
      frameMsP50: r(s.p50, 2),
      frameMsP99: r(s.p99, 2),
      firstFrameMs: firstFrameMs.toDouble(),
      memoryMb: r(ProcessInfo.currentRss / 1e6, 0),
      respawns: p.respawns,
      date: DateTime.now().toUtc().toIso8601String(),
    );
    benchProgress.value = null;
    drive.beforeStep = null;
    pilot = null;
  }

  /// A context button with priority ("Zvednout", specs/booths.md): while true, the car button hides.
  bool Function()? carActionYield;

  /// The context button: switch to the parked car, or open the garage (the UI shows the list).
  void boardCandidate() {
    final p = fleet.boardTarget;
    if (hud.value.carAction == CarAction.board && p != null && fleet.parked.contains(p)) fleet.board(p);
  }

  /// Open overlays (specs/pause.md): while any is open the simulation and the game clock stand.
  final pauseOverlays = OverlayRegistry();

  /// True while an overlay pauses the game; paused frames give every simulation and clock dt 0.
  bool get worldPaused => pauseOverlays.isPaused;
  bool _wasPaused = false;

  /// World time step of this frame: the real dt, or 0 while [worldPaused].
  double worldDt(double dt) => worldPaused ? 0 : dt;

  /// The HUD "Hop" button (specs/hop.md).
  bool hop() => !worldPaused && drive.startHop();

  void respawn() {
    police.clearRoadblock(); // specs/roadblock.md: a respawn drops the roadblock
    drive.spawn(city.startX, city.startY, city.startHeading);
    camera.snap(drive.car.x, drive.car.y, drive.car.heading, tuning);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _size = ui.Size(size.x, size.y);
  }

  // Pointer events arrive from a Listener wrapping the GameWidget.
  void pointerDown(int id, ui.Offset p) => scheme.down(id, (x: p.dx, y: p.dy), _size.width, _size.height);
  void pointerMove(int id, ui.Offset p) => scheme.move(id, (x: p.dx, y: p.dy), _size.width, _size.height);
  void pointerUp(int id) => scheme.up(id);

  @override
  void update(double dt) {
    final pause = worldPaused;
    if (pause != _wasPaused) {
      _wasPaused = pause;
      // Resume from zero input (released throttle, no brake): a finger that went down before the
      // overlay opened never reaches the scheme's up event (specs/pause.md).
      if (!pause) scheme = ControlScheme.create(scheme.id, tuning.controls);
    }
    final input = drive.input;
    if (pause) {
      input.reset();
    } else if (pilot == null) {
      input.reset();
      scheme.update(input);
      _keyboard(input);
      inputHook?.call(input);
    }
    final stepDt = worldDt(dt);
    if (!pause) {
      drive.update(stepDt);
      police.update(stepDt);
      _policeClock += stepDt;
    }
    afterUpdate?.call(dt);
    if (!pause) _benchFrame(dt);
    final car = drive.car;
    if (!(cameraHook?.call(dt) ?? false)) {
      camera.follow(car.x, car.y, car.heading, car.speed, dt, tuning, reversing: car.forwardSpeed < -0.5);
    }
    // Streaming may finish loading chunks while paused.
    streamer.update(car.x, car.y, car.heading);
    if (!_size.isEmpty && !pause) {
      peds.update(stepDt, [CarPose.of(car)], camera.visibleRadius(_size, tuning), night: night);
    }

    _frames++;
    _frameAcc += dt;
    _prepAcc += renderer.stats.buildingPrepMicros / 1000;
    _prepN++;
    if (_frameAcc >= 0.5) {
      _fps = _frames / _frameAcc;
      _frameMs = _frameAcc * 1000 / _frames;
      _frames = 0;
      _frameAcc = 0;
    }
    _hudTimer += dt;
    if (_hudTimer >= 0.1) {
      final action = fleet.action(pause ? 0 : _hudTimer);
      _hudTimer = 0;
      if (!pause) fleet.update();
      final edge = drive.layers.edge;
      hud.value = HudState(
        street: edge?.name ?? '',
        district: city.districtAt(car.x, car.y),
        speedMps: car.speed,
        layer: car.layer,
        fps: _fps,
        frameMs: _frameMs,
        prepMs: _prepN == 0 ? 0 : _prepAcc / _prepN,
        buildings: renderer.stats.buildings,
        chunks: renderer.stats.chunks,
        nearBorder: _nearBorder(),
        carName: drive.spec.name,
        hopFull: hopCharges(drive.spec),
        hopCharges: drive.hop.charges,
        hopReady: !pause && drive.hopReady,
        carAction: (carActionYield?.call() ?? false)
            ? null
            : switch (action) {
                'board' => CarAction.board,
                'garage' => CarAction.garage,
                _ => null,
              },
      );
      _prepAcc = 0;
      _prepN = 0;
      if (pilot == null) passport.update(car.x, car.y, hud.value.district);
    }
  }

  bool _nearBorder() {
    final d = drive.borderDistance();
    return d != null && d < tuning.hud.borderNoticeM;
  }

  void _keyboard(ControlInput input) {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    bool any(List<LogicalKeyboardKey> k) => k.any(keys.contains);
    if (any([LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.keyA])) input.steer = -1;
    if (any([LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.keyD])) input.steer = 1;
    if (any([LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.keyS])) input.brake = 1;
    if (any([LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.keyW])) input.boost = true;
    if (any([LogicalKeyboardKey.space])) input.handbrake = true;
    // Hop on the J key edge, like client W (specs/hop.md "Ovládání").
    final j = keys.contains(LogicalKeyboardKey.keyJ);
    if (j && !_hopKey) hop();
    _hopKey = j;
  }

  bool _hopKey = false;

  final _bollards = BollardPainter();

  @override
  void render(ui.Canvas canvas) {
    if (_size.isEmpty) return;
    final car = drive.car;
    final lift = _hopLift();
    final shadow = renderer.palette.shadow;
    renderer.render(
      canvas,
      _size,
      camera,
      playerLayer: car.layer,
      drawDynamic: (c, layer) {
        final r = camera.visibleRadius(_size, tuning);
        _tramsPainter?.paintTracks(c, layer, camera.x, camera.y, r);
        if (layer == 0) {
          paintSkids(c, drive.skids, car.halfWidth * 0.32);
          paintProps(c, drive.propsNear(car.x, car.y, r), night: night);
          _bollards.paint(c, drive.zones.bollards, tuning, vpX: camera.x, vpY: camera.y, radius: r);
          paintParked(
            c,
            fleet.parked.where((p) => (p.x - car.x).abs() < r && (p.y - car.y).abs() < r),
            data.cars,
            tuning,
            shadow: shadow,
            lookOf: parkedLook == null
                ? null
                : (p) => switch (parkedLook!(p)) {
                    final l? => lookPaint(l, tuning.garage, night: night),
                    null => null,
                  },
          );
          paintPedestrians(c, peds);
          paintWorld?.call(c);
          final tr = drive.traffic;
          if (tr != null && car.layer >= 0) {
            paintTrafficLights(c, tr, camera.x, camera.y, r, tuning.traffic);
          }
        }
        final tr = drive.traffic;
        if (tr != null) {
          paintTraffic(c, tr, layer, night: night, shadow: shadow);
          paintPolice(
            c,
            tr,
            layer,
            timeS: _policeClock,
            blinkS: tuning.police.lightBlinkS,
            night: night,
            shadow: shadow,
          );
        }
        final tm = drive.trams;
        if (tm != null) _tramsPainter?.paintTrams(c, tm, layer, night: night, shadow: shadow);
        final pl = playerLook?.call();
        final look = pl == null ? null : lookPaint(pl, tuning.garage, night: night, layer: car.layer);
        if (lift == null) {
          if (layer == car.layer) paintCar(c, car, night: night, shadow: shadow, look: look);
        } else if (layer == 0) {
          paintHopShadow(c, car, lift, shadow: shadow);
        } else if (layer == 1) {
          // In the air above everything on the ground, buildings included (specs/hop.md).
          paintCar(c, car, night: night, lift: lift, look: look);
        }
      },
    );
    paintOverWorld?.call(canvas, _size);
    _streetLabels(canvas);
    paintScreen?.call(canvas, _size);
    _pedBubbles.paint(canvas, _size, peds, camera, tuning);
    paintControls(canvas, _size, scheme);
  }

  /// Lift and roll of the car while it hops (specs/hop.md "Kreslení"), null on the ground.
  CarLift? _hopLift() {
    final h = drive.hop, t = tuning.hop;
    if (!h.airborne) return null;
    final car = drive.car;
    final roll = 2 * math.pi * t.flips * h.t / t.airS;
    return carLift(car.x, car.y, camera.x, camera.y, hopArc(h.t, t.airS, t.heightM), roll, tuning);
  }

  final Map<String, TextPainter> _labels = {};

  /// Street names along the road axis while driving slowly (METROPOLE_PLAN 6.3 step 8).
  void _streetLabels(ui.Canvas canvas) {
    final car = drive.car;
    final h = tuning.hud;
    if (car.speed > h.streetLabelsBelowMps) return;
    final hits = city.graph.near(car.x, car.y, h.streetLabelRadiusM)
      ..removeWhere((h) => !h.edge.kept || h.edge.name.isEmpty || h.edge.drawLayer != car.layer)
      ..sort((a, b) => a.dist.compareTo(b.dist));
    final shown = <String>{};
    for (final hit in hits) {
      if (shown.length >= h.streetLabelsMax || !shown.add(hit.edge.name)) continue;
      final tp = _labels.putIfAbsent(
        hit.edge.name,
        () => TextPainter(
          text: TextSpan(
            text: hit.edge.name.toUpperCase(),
            style: const TextStyle(
              fontSize: Tokens.fontLabel,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700,
              color: Color(Tokens.colorUiStreetLabel),
              shadows: [Shadow(blurRadius: 3, color: Color(Tokens.colorUiLabelShadow))],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(),
      );
      // Label at the edge midpoint nearest to the car, rotated along the road, kept upright.
      final p = camera.toScreen(hit.x, hit.y, _size, tuning);
      var a = camera.screenAngle(math.atan2(hit.dirY, hit.dirX));
      while (a > math.pi / 2) {
        a -= math.pi;
      }
      while (a < -math.pi / 2) {
        a += math.pi;
      }
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(a);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  void onRemove() {
    streamer.dispose();
    police.dispose();
    drive.dispose();
    super.onRemove();
  }
}
