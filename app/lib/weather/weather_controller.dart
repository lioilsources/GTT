import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:game_loop/game_loop.dart';
import 'package:shared_gen/shared_gen.dart';

import '../game/metropole_game.dart';
import '../game/paint/weather_painter.dart';

/// Weather of client F (specs/weather.md P1): the 1 s game tick (stands while paused), the rain
/// grip of the player's car, wet roads, rain and fog over the world with the blend, the HUD kind
/// and the change toast; [WeatherLayer] draws the HUD part. Off (no [world], no hooks, grip
/// unchanged) when `weather.enabled` or `weather.cities.<city>` is false. Every game, and so every
/// city switch, starts a new module with a random seed: the game starts clear.
class WeatherController {
  WeatherController(this.game, {int? seed}) {
    final t = tuning;
    if (!weatherOn(t, game.city.id)) return;
    final s = seed ?? math.Random().nextInt(1 << 32);
    final w = world = WeatherWorld(t, s);
    painter = WeatherPainter(t, seed: s);
    w.onChange.add(_onChange);
    _prevUpdate = game.afterUpdate;
    _prevOver = game.paintOverWorld;
    game
      ..afterUpdate = _afterUpdate
      ..paintOverWorld = _paintOverWorld;
  }

  final MetropoleGame game;

  /// Null when weather is off in this city.
  WeatherWorld? world;
  WeatherPainter? painter;

  void Function(double)? _prevUpdate;
  void Function(ui.Canvas, ui.Size)? _prevOver;

  TuningWeather get tuning => game.tuning.weather;

  /// The current kind for the HUD icon (null = weather off: no icon).
  late final kind = ValueNotifier<WeatherKind?>(world?.kind);

  /// The change toast (`weatherClear` / `weatherRain` / `weatherFog`), null when hidden.
  final toast = ValueNotifier<WeatherKind?>(null);
  double _toastS = 0;

  /// Game seconds for the falling streaks (they stand with the world while paused).
  double _clock = 0;

  void _onChange(WeatherKind k) {
    kind.value = k;
    toast.value = k;
    _toastS = game.tuning.nav.toastS;
    // The grip switches at once on a change (the look blends).
    game.drive.gripScale = world!.grip;
  }

  void _afterUpdate(double dt) {
    _prevUpdate?.call(dt);
    update(game.worldDt(dt), dt);
  }

  /// One frame: [stepDt] = game dt (0 while paused), [dt] = real dt (toast). Public for tests.
  void update(double stepDt, double dt) {
    final w = world;
    if (w == null) return;
    w.update(stepDt);
    _clock += stepDt;
    game.setWet(tuning.wetDarken * w.mix.rain);
    if (_toastS > 0 && (_toastS -= dt) <= 0) toast.value = null;
  }

  /// Debug panel: the next kind (`set`).
  void cycle() => world?.cycle();

  /// Debug and tests: the `set` action.
  void set(WeatherKind k) => world?.set(k);

  void _paintOverWorld(ui.Canvas c, ui.Size size) {
    final w = world, p = painter;
    if (w != null && p != null) {
      p.paintRain(c, size, w.mix.rain, _clock);
      p.paintFog(c, size, w.mix.fog);
    }
    _prevOver?.call(c, size);
  }

  void dispose() {
    if (world != null) {
      if (game.afterUpdate == _afterUpdate) game.afterUpdate = _prevUpdate;
      if (game.paintOverWorld == _paintOverWorld) game.paintOverWorld = _prevOver;
      game.drive.gripScale = 1;
      game.setWet(0);
    }
    kind.dispose();
    toast.dispose();
  }
}
