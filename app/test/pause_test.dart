import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drive_core/drive_core.dart';
import 'package:flame/game.dart' show Vector2;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_loop/game_loop.dart' show BoothWorld, boothsOf;
import 'package:meta_progress/meta_progress.dart';
import 'package:metropole/game/metropole_game.dart';
import 'package:metropole/game/pause.dart';
import 'package:metropole/l10n/app_localizations.dart';
import 'package:metropole/phone/phone_controller.dart';
import 'package:metropole/ui/garage_sheet.dart';
import 'package:metropole/ui/passport.dart';
import 'package:world_engine/world_engine.dart';

class _FilePack implements PackSource {
  _FilePack(this.root);
  final String root;
  @override
  Future<Uint8List> read(String path) async => File('$root$path').readAsBytes();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tuning = Tuning.fromYaml(File('../content/tuning.yaml').readAsStringSync());

  group('pause registry (specs/pause.md)', () {
    test('paused(overlays) is true while any overlay is open', () {
      expect(paused(const []), isFalse);
      for (final o in GameOverlay.values) {
        expect(paused([o]), isTrue, reason: o.name);
      }
    });

    test('every pausing overlay of specs/pause.md has a kind, the booth offer card included', () {
      expect(GameOverlay.values.map((o) => o.name).toList()..sort(), [
        'about',
        'bench',
        'booth',
        'dialogue',
        'gallery',
        'garage',
        'minigame',
        'passport',
        'phone',
        'postcard',
        'result',
        'tuning',
      ]);
    });

    test('the booth offer card stops the booth clock (game dt 0 while paused)', () {
      final r = OverlayRegistry();
      final spot = Spot(id: 'b', kind: 'booth', name: 'b', parkX: 1000, parkY: 0);
      final w = BoothWorld(boothsOf([spot]), tuning, ['bar'], 8);
      final next0 = w.state.next;
      double step(double dt) => r.isPaused ? 0 : dt;
      r.register(GameOverlay.booth);
      expect(r.isPaused, isTrue);
      for (var i = 0; i < 300; i++) {
        w.update(step(1 / 60), () => [0]);
      }
      expect(w.state.next, next0);
      r.unregister(GameOverlay.booth);
      for (var i = 0; i < 61; i++) {
        w.update(step(1 / 60), () => [0]);
      }
      expect(w.state.next, next0 - 1);
    });

    test('register / unregister are counted; set is one-shot; hold lasts until the future completes', () async {
      final r = OverlayRegistry();
      r.register(GameOverlay.passport);
      r.register(GameOverlay.passport);
      r.unregister(GameOverlay.passport);
      expect(r.isPaused, isTrue);
      r.unregister(GameOverlay.passport);
      expect(r.isPaused, isFalse);
      r.unregister(GameOverlay.passport);
      expect(r.isPaused, isFalse);
      r
        ..set(GameOverlay.phone, true)
        ..set(GameOverlay.phone, true)
        ..set(GameOverlay.phone, false);
      expect(r.isPaused, isFalse);
      final c = Completer<void>();
      final f = r.hold(GameOverlay.garage, c.future);
      expect(r.isOpen(GameOverlay.garage), isTrue);
      c.complete();
      await f;
      expect(r.isPaused, isFalse);
    });
  });

  group('the game stands under overlays (NYC pack)', () {
    const root = '../build/packs/nyc/';
    final has = File('${root}manifest.pb').existsSync();
    late GameAssets assets;
    setUpAll(() async {
      if (!has) return;
      await initializeForge2D();
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

    Future<(MetropoleGame, PhoneController)> start() async {
      final g = MetropoleGame(assets);
      await g.preload();
      final phone = PhoneController(g, feedSeed: 1);
      // Get the car and the traffic going.
      for (var i = 0; i < 90; i++) {
        g.update(1 / 60);
      }
      return (g, phone);
    }

    /// Car pose, traffic poses and the world clocks after [frames] frames.
    List<double> snapshot(MetropoleGame g) => [
      g.drive.car.x,
      g.drive.car.y,
      g.drive.car.heading,
      g.drive.time,
      for (final c in g.drive.traffic?.cars ?? const <TrafficCar>[]) ...[c.x, c.y],
    ];

    void frames(MetropoleGame g, int n) {
      for (var i = 0; i < n; i++) {
        g.update(1 / 60);
      }
    }

    test('phone, garage and postcard freeze the car, traffic and the clock; closing resumes', () async {
      final (g, phone) = await start();
      expect(g.drive.car.speed, greaterThan(1));
      expect(g.drive.traffic!.cars, isNotEmpty);

      phone.open();
      expect(g.worldPaused, isTrue);
      final a = snapshot(g);
      frames(g, 120);
      expect(snapshot(g), a);
      phone.close();
      expect(g.worldPaused, isFalse);
      frames(g, 30);
      expect(snapshot(g), isNot(a));

      final garage = Completer<void>();
      final held = g.pauseOverlays.hold(GameOverlay.garage, garage.future);
      final b = snapshot(g);
      frames(g, 120);
      expect(snapshot(g), b);
      garage.complete();
      await held;
      frames(g, 30);
      expect(snapshot(g), isNot(b));

      g.pauseOverlays.set(GameOverlay.postcard, true);
      final c = snapshot(g);
      frames(g, 120);
      expect(snapshot(g), c);
      g.pauseOverlays.set(GameOverlay.postcard, false);
      frames(g, 30);
      expect(snapshot(g), isNot(c));

      phone.dispose();
      g.onRemove();
    }, skip: !has);

    test('a short toast does not pause', () async {
      final (g, phone) = await start();
      phone.toast.value = MessageKey.arrived;
      final a = snapshot(g);
      frames(g, 30);
      expect(g.worldPaused, isFalse);
      expect(snapshot(g), isNot(a));
      phone.dispose();
      g.onRemove();
    }, skip: !has);

    test('resume starts from zero input: a finger held when the phone opened is dropped', () async {
      final (g, phone) = await start();
      g.onGameResize(Vector2(400, 800));
      g.pointerDown(1, const Offset(200, 600));
      g.pointerMove(1, const Offset(320, 680));
      g.update(1 / 60);
      expect(g.drive.input.steer != 0 || g.drive.input.brake != 0, isTrue);
      phone.open();
      g.update(1 / 60);
      expect(g.drive.input.steer, 0);
      phone.close();
      g.update(1 / 60);
      final i = g.drive.input;
      expect([i.steer, i.throttle, i.brake], [0, 0, 0]);
      expect(i.handbrake || i.boost, isFalse);
      phone.dispose();
      g.onRemove();
    }, skip: !has);

    testWidgets('garage: free air refill for the Roadster, hidden for cars without a tank', (tester) async {
      final g = MetropoleGame(assets);
      final d = g.drive;
      d.replaceCar(assets.cars['vega_roadster']!, d.car.x, d.car.y, d.car.heading);
      d.hop.charges = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(onPressed: () => showGarage(context, g.fleet), child: const Text('open')),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Air tank empty'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hopRefill')));
      await tester.pumpAndSettle();
      expect(d.hop.charges, 3);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('hopRefill'))).onPressed, isNull);
      Navigator.of(tester.element(find.byKey(const ValueKey('hopRefill')))).pop();
      await tester.pumpAndSettle();
      d.replaceCar(assets.cars['m0_coupe']!, d.car.x, d.car.y, d.car.heading);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('hopRefill')), findsNothing);
      g.onRemove();
    }, skip: !has);

    test('phone slow motion is gone: the phone stops the world instead', () async {
      final (g, phone) = await start();
      phone.open();
      final t0 = g.drive.time;
      frames(g, 60);
      expect(g.drive.time, t0);
      phone.dispose();
      g.onRemove();
    }, skip: !has);
  });

  group('postcard overlay', () {
    Widget app(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

    testWidgets('the postcard pauses until tapped; the stamp toast does not', (tester) async {
      final events = ValueNotifier<StampEvent?>(null);
      final r = OverlayRegistry();
      await tester.pumpWidget(app(PassportOverlay(events: events, seconds: 60, overlays: r)));
      events.value = const StampEvent('district', 'midtown', name: 'Midtown');
      await tester.pump();
      expect(r.isPaused, isFalse);
      events.value = const StampEvent(
        'landmark',
        'empire_state',
        landmark: PassportLandmark('empire_state', 'Empire State Building', 0, 0, 381),
      );
      await tester.pumpAndSettle();
      expect(r.isOpen(GameOverlay.postcard), isTrue);
      await tester.tap(find.byType(PostcardCard));
      await tester.pumpAndSettle();
      expect(r.isPaused, isFalse);
      // Let the toast and card timers run out before the test ends.
      await tester.pump(const Duration(seconds: 61));
    });
  });
}
