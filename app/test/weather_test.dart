import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drive_core/drive_core.dart';
import 'package:flame/game.dart' show Vector2;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_loop/game_loop.dart';
import 'package:metropole/game/metropole_game.dart';
import 'package:metropole/game/paint/weather_painter.dart';
import 'package:metropole/game/pause.dart';
import 'package:metropole/l10n/app_localizations.dart';
import 'package:metropole/weather/weather_controller.dart';
import 'package:metropole/weather/weather_layer.dart';
import 'package:world_engine/world_engine.dart';

// specs/weather.md P1 in client F: the module per game, the rain grip, pause, wet roads, the
// overlays, the HUD icon and toast. The pack tests also write PNGs of NYC (and Prague with the
// risograph where shader filters run) in rain and fog to ../run/ (not in git).

class _FilePack implements PackSource {
  _FilePack(this.root);
  final String root;
  @override
  Future<Uint8List> read(String path) async => File('$root$path').readAsBytes();
}

Tuning _tuning() => Tuning.fromYaml(File('../content/tuning.yaml').readAsStringSync());

Future<ui.Image> _frame(MetropoleGame g, ui.Size size) {
  final rec = ui.PictureRecorder();
  g.render(ui.Canvas(rec));
  return rec.endRecording().toImage(size.width.toInt(), size.height.toInt());
}

Future<Uint8List> _rgba(ui.Image img) async =>
    (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();

Future<void> _png(ui.Image img, String name) async {
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  final out = File('../run/$name')..createSync(recursive: true);
  out.writeAsBytesSync(png!.buffer.asUint8List());
}

/// Fraction of pixels that differ between two RGBA buffers.
double _diff(Uint8List a, Uint8List b) {
  var n = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) n++;
  }
  return n / (a.length / 4);
}

/// Mean |a − b| of the RGB channels inside a box (x0..x1, y0..y1) of a [w] wide image.
double _delta(Uint8List a, Uint8List b, int w, int x0, int y0, int x1, int y1) {
  var s = 0, n = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final i = 4 * (y * w + x);
      s += (a[i] - b[i]).abs() + (a[i + 1] - b[i + 1]).abs() + (a[i + 2] - b[i + 2]).abs();
      n += 3;
    }
  }
  return s / n;
}

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('painter: rain streaks and the fog ramp change the picture, amount 0 draws nothing', () async {
    final t = _tuning().weather;
    const size = ui.Size(200, 300);
    Future<Uint8List> draw(void Function(WeatherPainter p, ui.Canvas c) f) async {
      final p = WeatherPainter(t, seed: 3);
      final rec = ui.PictureRecorder();
      final c = ui.Canvas(rec)..drawRect(Offset.zero & size, Paint()..color = const Color(0xFF000000));
      f(p, c);
      return _rgba(await rec.endRecording().toImage(200, 300));
    }

    final black = await draw((_, _) {});
    expect(_diff(black, await draw((p, c) => p.paintRain(c, size, 0, 1))), 0);
    expect(_diff(black, await draw((p, c) => p.paintFog(c, size, 0))), 0);
    final rain = await draw((p, c) => p.paintRain(c, size, 1, 0.5));
    expect(_diff(black, rain), greaterThan(0.01));
    // Streaks move with game time.
    expect(_diff(rain, await draw((p, c) => p.paintRain(c, size, 1, 0.6))), greaterThan(0.01));
    // Fog: thin in the middle, thick at the corners.
    final fog = await draw((p, c) => p.paintFog(c, size, 1));
    expect(_delta(black, fog, 200, 0, 0, 10, 10), greaterThan(2 * _delta(black, fog, 200, 95, 145, 105, 155)));
    expect(_delta(black, fog, 200, 95, 145, 105, 155), greaterThan(0));
  });

  test('three distinct HUD icons', () {
    expect({for (final k in WeatherKind.values) weatherIcon(k)}, hasLength(3));
  });

  group('weather in the game (NYC pack)', () {
    const root = '../build/packs/nyc/';
    final has = File('${root}manifest.pb').existsSync();
    late GameAssets assets;
    late Tuning tuning;
    setUpAll(() async {
      if (!has) return;
      await initializeForge2D();
      tuning = _tuning();
      final src = _FilePack(root);
      final cars = {
        for (final f in Directory('../content/cars').listSync().whereType<File>())
          for (final s in [parseCarSpec(f.readAsStringSync())]) s.id: s,
      };
      assets = GameAssets(
        city: await City.load(src),
        source: src,
        tuning: tuning,
        car: cars[tuning.cars.startCar]!,
        cars: cars,
        textures: await FacadeTextures.create(),
      );
    });

    Future<MetropoleGame> game() async {
      final g = MetropoleGame(assets)..onGameResize(Vector2(400, 800));
      await g.preload();
      return g;
    }

    test('starts clear; rain scales the player grip at once, fog and clear do not', () async {
      final g = await game();
      final w = WeatherController(g, seed: 5);
      expect(w.world, isNotNull);
      expect(w.kind.value, WeatherKind.clear);
      expect(g.drive.gripScale, 1);
      w.set(WeatherKind.rain);
      expect(g.drive.gripScale, tuning.weather.rainGrip);
      expect(g.drive.car.gripScale, tuning.weather.rainGrip);
      expect(w.toast.value, WeatherKind.rain);
      expect(w.kind.value, WeatherKind.rain);
      // A car switch keeps the multiplier.
      g.drive.replaceCar(g.drive.spec, g.drive.car.x, g.drive.car.y, g.drive.car.heading);
      expect(g.drive.car.gripScale, tuning.weather.rainGrip);
      w.set(WeatherKind.fog);
      expect(g.drive.gripScale, 1);
      w.cycle();
      expect(w.kind.value, WeatherKind.clear);
      expect(g.drive.gripScale, 1);
      w.dispose();
      g.onRemove();
    }, skip: !has);

    test('ticks once per game second and stand while paused', () async {
      final g = await game();
      final w = WeatherController(g, seed: 9);
      final left = w.world!.state.left;
      g.update(0.5);
      g.update(0.6);
      expect(w.world!.state.left, left - 1);
      g.pauseOverlays.register(GameOverlay.tuning);
      for (var i = 0; i < 20; i++) {
        g.update(0.5);
      }
      expect(w.world!.state.left, left - 1, reason: 'paused');
      g.pauseOverlays.unregister(GameOverlay.tuning);
      g.update(0.5);
      g.update(0.5);
      expect(w.world!.state.left, left - 2);
      w.dispose();
      g.onRemove();
    }, skip: !has);

    test('wet roads blend over blend_s; dispose restores grip, palette and hooks', () async {
      final g = await game();
      final dry = g.renderer.palette;
      final w = WeatherController(g, seed: 1);
      w.set(WeatherKind.rain);
      final b = tuning.weather.blendS;
      w.update(b / 2, b / 2);
      final half = g.renderer.palette.asphalt;
      w.update(b, b);
      final wet = g.renderer.palette.asphalt;
      final k = 1 - tuning.weather.wetDarken;
      expect(wet.r, closeTo(dry.asphalt.r * k, 0.01));
      expect(half.r, closeTo(dry.asphalt.r * (1 - tuning.weather.wetDarken / 2), 0.01));
      expect(g.renderer.palette.land, dry.land);
      // Night keeps the wet look.
      g.setNight(true);
      expect(g.renderer.palette.asphalt.r, closeTo(Palette.nightPalette.asphalt.r * k, 0.01));
      g.setNight(false);
      w.dispose();
      expect(g.drive.gripScale, 1);
      expect(g.renderer.palette.asphalt, dry.asphalt);
      expect(g.paintOverWorld, isNull);
      g.onRemove();
    }, skip: !has);

    test('weather off in the city: no module, no icon, grip unchanged', () async {
      tuning.weather.cities.nyc = false;
      try {
        final g = await game();
        final w = WeatherController(g);
        expect(w.world, isNull);
        expect(w.kind.value, isNull);
        expect(g.paintOverWorld, isNull);
        w.set(WeatherKind.rain);
        expect(g.drive.gripScale, 1);
        w.dispose();
        g.onRemove();
      } finally {
        tuning.weather.cities.nyc = true;
      }
    }, skip: !has);

    testWidgets('HUD layer: icon of the kind, toast text on a change', (tester) async {
      late MetropoleGame g;
      late WeatherController w;
      await tester.runAsync(() async {
        g = await game();
        w = WeatherController(g, seed: 2);
      });
      await tester.pumpWidget(_app(WeatherLayer(weather: w)));
      expect(find.byKey(const ValueKey('weatherIcon.clear')), findsOneWidget);
      expect(find.byKey(const ValueKey('weatherToast')), findsNothing);
      w.set(WeatherKind.fog);
      await tester.pump();
      expect(find.byKey(const ValueKey('weatherIcon.fog')), findsOneWidget);
      expect(find.text('Fog rolls in'), findsOneWidget);
      final icon = tester.widget<Icon>(find.byKey(const ValueKey('weatherIcon.fog')));
      expect(icon.color, const Color(Tokens.colorWeatherIcon));
      w.update(0, tuning.nav.toastS + 0.1);
      await tester.pump();
      expect(find.byKey(const ValueKey('weatherToast')), findsNothing);
      w.dispose();
      g.onRemove();
    }, skip: !has);

    test(
      'render: NYC clear, rain and fog (PNGs in run/)',
      () async {
        const size = ui.Size(400, 800);
        final g = await game();
        g.update(1 / 60);
        final clear = await _frame(g, size);
        final w = WeatherController(g, seed: 4);
        w.set(WeatherKind.rain);
        w.update(tuning.weather.blendS + 1, 1 / 60);
        final rain = await _frame(g, size);
        w.set(WeatherKind.fog);
        w.update(tuning.weather.blendS + 1, 1 / 60);
        final fog = await _frame(g, size);
        w.set(WeatherKind.rain);
        w.update(tuning.weather.blendS / 2, 1 / 60);
        final blend = await _frame(g, size);
        g.setNight(true);
        w.update(tuning.weather.blendS, 1 / 60);
        final night = await _frame(g, size);
        await _png(clear, 'weather_nyc_clear.png');
        await _png(rain, 'weather_nyc_rain.png');
        await _png(fog, 'weather_nyc_fog.png');
        await _png(blend, 'weather_nyc_fog_to_rain.png');
        await _png(night, 'weather_nyc_rain_night.png');
        final c = await _rgba(clear), r = await _rgba(rain), f = await _rgba(fog);
        expect(_diff(c, r), greaterThan(0.05), reason: 'wet roads and streaks');
        final wd = size.width.toInt(), ht = size.height.toInt();
        // Fog is thicker at the corners than in the middle.
        expect(
          _delta(c, f, wd, 0, 0, 20, 20),
          greaterThan(_delta(c, f, wd, wd ~/ 2 - 10, ht ~/ 2 - 10, wd ~/ 2 + 10, ht ~/ 2 + 10)),
        );
        w.dispose();
        g.onRemove();
      },
      skip: !has,
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  test('render: Prague rain and fog over the risograph pass (PNGs in run/)', () async {
    const root = '../build/packs/prague/';
    if (!File('${root}manifest.pb').existsSync()) return; // pack not built
    await initializeForge2D();
    final tuning = _tuning();
    final src = _FilePack(root);
    final cars = {
      for (final f in Directory('../content/cars').listSync().whereType<File>())
        for (final s in [parseCarSpec(f.readAsStringSync())]) s.id: s,
    };
    // The risograph needs shader image filters (Impeller); without them Prague renders plain.
    final riso = ui.ImageFilter.isShaderFilterSupported
        ? await ui.FragmentProgram.fromAsset('shaders/risograph.frag')
        : null;
    final g = MetropoleGame(
      GameAssets(
        city: await City.load(src),
        source: src,
        tuning: tuning,
        car: cars[tuning.cars.startCar]!,
        cars: cars,
        textures: await FacadeTextures.create(),
        risograph: riso,
      ),
    )..onGameResize(Vector2(400, 800));
    await g.preload();
    g.update(1 / 60);
    expect(g.renderer.worldFilter != null, riso != null && risographEnabled(tuning.style, 'prague', night: false));
    const size = ui.Size(400, 800);
    final w = WeatherController(g, seed: 6);
    w.set(WeatherKind.rain);
    w.update(tuning.weather.blendS + 1, 1 / 60);
    await _png(await _frame(g, size), 'weather_prague_rain.png');
    w.set(WeatherKind.fog);
    w.update(tuning.weather.blendS + 1, 1 / 60);
    await _png(await _frame(g, size), 'weather_prague_fog.png');
    w.dispose();
    g.onRemove();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
