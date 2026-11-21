import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:drive_core/drive_core.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:world_engine/world_engine.dart';

import 'paint/car_painter.dart';
import 'paint/controls_painter.dart';
import 'paint/props_painter.dart';

/// Everything loaded before the first frame.
class GameAssets {
  GameAssets({
    required this.city,
    required this.source,
    required this.tuning,
    required this.car,
    required this.textures,
  }) : tuningBaseline = tuning.flatten(),
       carBaseline = car.toJson();

  final City city;
  final PackSource source;
  final Tuning tuning;
  final CarSpec car;
  final FacadeTextures textures;

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
      rootBundle.loadString('${shared}content/cars/${car.id}.json'),
      FacadeTextures.create(),
    ]);
    return GameAssets(
      city: results[0] as City,
      source: source,
      tuning: Tuning.fromYaml(results[1] as String),
      car: parseCarSpec(results[2] as String),
      textures: results[3] as FacadeTextures,
    );
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
}

/// M0 game loop: drive, stream, render (no traffic, peds, police, feed or saving).
class MetropoleGame extends Game {
  MetropoleGame(this.data) {
    final city = data.city;
    tuning = data.tuning;
    drive = DriveWorld(city: city, spec: data.car, tuning: tuning);
    streamer = ChunkStreamer(
      city,
      data.source,
      tuning,
      onLoaded: (c) => drive.addChunk(c.data),
      onUnloaded: (c) => drive.removeChunk(c.data),
    );
    scheme = ControlScheme.create(ControlSchemeId.a, tuning.controls);
    renderer = WorldRenderer(
      city: city,
      roads: RoadMeshes.build(city.graph, city.chunkM, sidewalkM: tuning.sidewalkWidthM, laneM: tuning.laneWidthM),
      streamer: streamer,
      tuning: tuning,
      textures: data.textures,
    );
    camera.snap(drive.car.x, drive.car.y, drive.car.heading, tuning);
  }

  final GameAssets data;
  late final Tuning tuning;
  late final DriveWorld drive;
  late final ChunkStreamer streamer;
  late final WorldRenderer renderer;
  final camera = CameraRig();
  late ControlScheme scheme;
  final hud = ValueNotifier<HudState>(const HudState());
  bool night = false;

  ui.Size _size = ui.Size.zero;
  double _hudTimer = 0;
  int _frames = 0;
  double _frameAcc = 0;
  double _fps = 0;
  double _frameMs = 0;
  double _prepAcc = 0;
  int _prepN = 0;

  City get city => data.city;

  Future<void> preload() => streamer.preload(drive.car.x, drive.car.y, drive.car.heading);

  void setNight(bool v) {
    night = v;
    renderer.palette = v ? Palette.nightPalette : Palette.day;
  }

  void setScheme(ControlSchemeId id) => scheme = ControlScheme.create(id, tuning.controls);

  void respawn() {
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
    final input = drive.input..reset();
    scheme.update(input);
    _keyboard(input);
    drive.update(dt);
    final car = drive.car;
    camera.follow(car.x, car.y, car.heading, car.speed, dt, tuning, reversing: car.forwardSpeed < -0.5);
    streamer.update(car.x, car.y, car.heading);

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
      _hudTimer = 0;
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
      );
      _prepAcc = 0;
      _prepN = 0;
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
  }

  @override
  void render(ui.Canvas canvas) {
    if (_size.isEmpty) return;
    final car = drive.car;
    renderer.render(
      canvas,
      _size,
      camera,
      playerLayer: car.layer,
      drawDynamic: (c, layer) {
        if (layer == 0) {
          paintSkids(c, drive.skids, car.halfWidth * 0.32);
          paintProps(c, drive.propsNear(car.x, car.y, camera.visibleRadius(_size, tuning)), night: night);
        }
        if (layer == car.layer) paintCar(c, car, night: night);
      },
    );
    _streetLabels(canvas);
    paintControls(canvas, _size, scheme);
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
    drive.dispose();
    super.onRemove();
  }
}
