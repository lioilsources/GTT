import 'dart:io';
import 'dart:ui' as ui;

import 'package:drive_core/drive_core.dart';
import 'package:flame/game.dart' show Vector2;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_loop/game_loop.dart';
import 'package:metropole/game/metropole_game.dart';
import 'package:metropole/garage/garage_app.dart';
import 'package:metropole/garage/garage_controller.dart';
import 'package:metropole/garage/garage_tabs.dart';
import 'package:metropole/l10n/app_localizations.dart';
import 'package:metropole/loop/loop_controller.dart';
import 'package:metropole/loop/save_store.dart';
import 'package:metropole/phone/phone_controller.dart';
import 'package:metropole/ui/garage_sheet.dart';
import 'package:world_engine/world_engine.dart';

// specs/garage.md P1 in client F: the tuned body of owned cars, cash and the save, the garage tabs
// (Auta / Tuning / Vzhled / Polička), the live preview and the read-only phone app.

class _FilePack implements PackSource {
  _FilePack(this.root);
  final String root;
  @override
  Future<Uint8List> read(String path) async => File('$root$path').readAsBytes();
}

class _MemStore implements SaveStore {
  final Map<String, Map<String, Object?>> saves = {};
  int writes = 0;
  @override
  Future<Object?> read(String cityId) async => saves[cityId];
  @override
  Future<void> write(String cityId, Map<String, Object?> save) async {
    writes++;
    saves[cityId] = save;
  }
}

typedef _W = ({MetropoleGame g, PhoneController phone, LoopController loop, GarageController garage, _MemStore store});

/// PNGs of the tabs for a visual check: `GARAGE_PNG=1 flutter test test/garage_test.dart` writes
/// them to ../run/ (not in git).
final _png = Platform.environment['GARAGE_PNG'] != null;

Future<void> _loadFonts() async {
  const dir = '/bin/cache/artifacts/material_fonts/';
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  Future<void> font(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      final file = File('$root$dir$f');
      if (file.existsSync()) l.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
    await l.load();
  }

  await font('Roboto', ['Roboto-Regular.ttf', 'Roboto-Bold.ttf']);
  await font('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.runAsync(() async {
    final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 2);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('../run/$name')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// Scrolls the tab to the widget with [key], then taps it.
Future<void> tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
}

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  theme: ThemeData(fontFamily: 'Roboto', brightness: Brightness.dark),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(backgroundColor: const Color(Tokens.colorUiSheet), body: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tuning = Tuning.fromYaml(File('../content/tuning.yaml').readAsStringSync());
  final g = tuning.garage;
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

  Future<_W> start({Object? saved, _MemStore? store}) async {
    final game = MetropoleGame(assets)..onGameResize(Vector2(400, 800));
    await game.preload();
    final phone = PhoneController(game, feedSeed: 1);
    final s = store ?? _MemStore();
    final loop = LoopController(
      game,
      phone,
      store: s,
      npc: null,
      saved: saved,
      settingsGet: () => (scheme: 'a', night: false),
      settingsSet: (_) {},
    );
    final garage = GarageController(game, loop, phone: phone)
      ..shelf = () => const [(id: 'souvenir_canal', name: 'Canal Street')];
    return (g: game, phone: phone, loop: loop, garage: garage, store: s);
  }

  void stop(_W w) {
    w.garage.dispose();
    w.loop.dispose();
    w.phone.dispose();
    w.g.onRemove();
  }

  final sc = SaveConfig.fromTuning(tuning, 'nyc', CarId.values.map((c) => c.id));
  Map<String, Object?> saveWith({
    CarLevels upgrades = const {},
    CarLevels looks = const {},
    int cash = 0,
    List<String> cars = const ['m0_coupe'],
  }) => {...freshSave(sc), 'cash': cash, 'cars': cars, 'upgrades': upgrades, 'looks': looks};

  group('the tuned body (specs/garage.md "Účinek na jízdu")', () {
    test('start: the loaded own car with its upgrades; stolen and the Taxi car by the catalog', () async {
      final w = await start(
        saved: saveWith(
          upgrades: const {
            'm0_coupe': {'engine': 3, 'tyres': 2},
          },
        ),
      );
      final cat = assets.cars['m0_coupe']!;
      final car = w.g.drive.car;
      expect(car.spec.power, closeTo(tunedSpec(cat, const {'engine': 3}, g).power, 1e-9));
      expect(car.spec.gripRear, closeTo(cat.gripRear * (1 + g.tyresStep * 2), 1e-9));
      expect(w.g.drive.spec.power, cat.power, reason: 'drive.spec stays the catalog car');
      // Respawn keeps the upgrades; the rain multiplies on top.
      w.g.drive.gripScale = tuning.weather.rainGrip;
      w.g.respawn();
      expect(w.g.drive.car.spec.power, closeTo(tunedSpec(cat, const {'engine': 3}, g).power, 1e-9));
      expect(w.g.drive.car.gripScale, tuning.weather.rainGrip);
      // A stolen car of the same model drives by the catalog.
      final c = w.g.drive.car;
      w.g.fleet.board(ParkedCar(carId: 'm0_coupe', owner: 'npc', x: c.x + 5, y: c.y, heading: 0));
      expect(w.g.fleet.state.stolen, isTrue);
      expect(w.g.drive.car.spec.power, cat.power);
      expect(w.g.playerLook!(), isNull);
      // The Taxi shift car (another model, not the driven one) too.
      w.g.fleet.restore(cash: 0, owned: const ['m0_coupe'], driving: 'm0_coupe');
      w.g.drive.replaceCar(assets.cars['taxi_metro']!, c.x, c.y, 0);
      expect(w.g.drive.car.spec.power, assets.cars['taxi_metro']!.power);
      stop(w);
    }, skip: !has);

    test('leaving the garage rebuilds the body in place at speed 0 with the new level', () async {
      final w = await start(saved: saveWith(cash: 100000));
      final before = w.g.drive.car;
      final x = before.x, y = before.y;
      expect(w.garage.upgrade('m0_coupe', 'engine'), isTrue);
      expect(w.g.drive.car.spec.power, assets.cars['m0_coupe']!.power, reason: 'the world stands in the garage');
      w.garage.leave();
      final after = w.g.drive.car;
      expect(identical(after, before), isFalse);
      expect(after.x, closeTo(x, 1e-6));
      expect(after.y, closeTo(y, 1e-6));
      expect(after.speed, 0);
      expect(after.spec.power, closeTo(tunedSpec(assets.cars['m0_coupe']!, const {'engine': 1}, g).power, 1e-9));
      stop(w);
    }, skip: !has);

    test('garage.enabled off only hides the tabs: what was bought still applies and stays saved', () async {
      g.enabled = false;
      try {
        final w = await start(
          saved: saveWith(
            upgrades: const {
              'm0_coupe': {'engine': 3},
            },
          ),
        );
        expect(
          w.g.drive.car.spec.power,
          closeTo(tunedSpec(assets.cars['m0_coupe']!, const {'engine': 3}, g).power, 1e-9),
        );
        expect(w.g.playerLook!(), isNotNull);
        expect(w.loop.snapshot()['upgrades'], {
          'm0_coupe': {'engine': 3},
        });
        stop(w);
      } finally {
        g.enabled = true;
      }
    }, skip: !has);
  });

  group('cash and the save (specs/garage.md "Hotovost", specs/save.md v4)', () {
    test('a purchase takes last.amount off the cars cash, toasts and saves; restore reloads', () async {
      final w = await start(saved: saveWith(cash: 3000 + g.lookPriceGlow));
      expect(w.garage.upgrade('m0_coupe', 'engine'), isTrue);
      expect(w.g.fleet.state.cash, 3000 + g.lookPriceGlow - g.priceEngine[0]);
      expect(w.garage.toast.value, isTrue);
      expect(w.store.writes, 1);
      expect(w.garage.upgrade('m0_coupe', 'engine'), isFalse, reason: 'cash below ${g.priceEngine[1]}');
      expect(w.garage.buyLook('m0_coupe', 'paint', 3), isTrue);
      expect(w.g.fleet.state.cash, 3000 + g.lookPriceGlow - g.priceEngine[0] - g.lookPricePaint);
      expect(w.garage.buyLook('m0_coupe', 'paint', 0), isTrue, reason: 'back to stock is free');
      expect(w.g.fleet.state.cash, 3000 + g.lookPriceGlow - g.priceEngine[0] - g.lookPricePaint);
      w.garage.buyLook('m0_coupe', 'glow', 2);
      final snap = w.loop.snapshot();
      expect(snap['upgrades'], {
        'm0_coupe': {'engine': 1},
      });
      expect(snap['looks'], {
        'm0_coupe': {'glow': 2},
      });
      w.garage.tick(tuning.nav.toastS + 0.1);
      expect(w.garage.toast.value, isFalse);
      // The debug reset: a fresh save drops both.
      await w.loop.resetSave();
      expect(w.garage.world.state.upgrades, isEmpty);
      expect(w.g.drive.car.spec.power, assets.cars['m0_coupe']!.power);
      stop(w);
    }, skip: !has);

    test('looks are drawn on own cars only: driven and left parked', () async {
      final w = await start(
        saved: saveWith(
          looks: const {
            'm0_coupe': {'paint': 2, 'decal': 1, 'wheels': 2, 'glow': 1},
          },
        ),
      );
      final l = w.g.playerLook!()!;
      expect(
        (l.paint, l.decal, l.rim, l.glow),
        (Tokens.colorGaragePaints[1], 1, Tokens.colorGarageWheels[2], Tokens.colorGarageGlow[0]),
      );
      expect(w.g.parkedLook!(ParkedCar(carId: 'm0_coupe', owner: 'player', x: 0, y: 0, heading: 0))?.paint, l.paint);
      expect(w.g.parkedLook!(ParkedCar(carId: 'm0_coupe', owner: 'npc', x: 0, y: 0, heading: 0)), isNull);
      // The world draws with the look (no throw at night, in a tunnel or in the air).
      final rec = ui.PictureRecorder();
      w.g.setNight(true);
      w.g.render(ui.Canvas(rec));
      rec.endRecording().dispose();
      stop(w);
    }, skip: !has);
  });

  group('the garage sheet', () {
    Future<void> pumpSheet(
      WidgetTester tester,
      _W w, {
      GarageTab tab = GarageTab.cars,
      GlobalKey? key,
      Size size = const Size(420, 900),
    }) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      await tester.pumpWidget(
        _app(
          RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: const Color(Tokens.colorUiSheet),
              child: GarageSheet(fleet: w.g.fleet, garage: w.garage, shelf: w.garage.shelf, initialTab: tab),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('tabs Cars / Tuning / Looks / Shelf; Tuning and Looks hidden with garage.enabled off', (tester) async {
      final w = (await tester.runAsync(start))!;
      await pumpSheet(tester, w);
      for (final t in ['Cars', 'Tuning', 'Looks', 'Shelf']) {
        expect(find.descendant(of: find.byKey(const ValueKey('garageTabs')), matching: find.text(t)), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('garageCars')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('garageTab:shelf')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('shopShelf')), findsOneWidget);
      expect(find.text('Canal Street'), findsOneWidget);
      g.enabled = false;
      try {
        await tester.pumpWidget(const SizedBox());
        await pumpSheet(tester, w);
        expect(find.byKey(const ValueKey('garageTab:tuning')), findsNothing);
        expect(find.byKey(const ValueKey('garageTab:looks')), findsNothing);
        expect(find.byKey(const ValueKey('garageTab:shelf')), findsOneWidget);
      } finally {
        g.enabled = true;
      }
      stop(w);
      tester.view.reset();
    }, skip: !has);

    testWidgets('Cars: the sale list sorted (city, class, price, id) with class names and previews', (tester) async {
      if (_png) await _loadFonts();
      final w = (await tester.runAsync(
        () => start(
          saved: saveWith(
            cash: 20000,
            cars: const ['m0_coupe', 'hatch_pip'],
            looks: const {
              'm0_coupe': {'paint': 3, 'decal': 2, 'wheels': 1, 'glow': 1},
            },
          ),
        ),
      ))!;
      final key = GlobalKey();
      // Tall enough that the whole list is built (and on the PNG).
      await pumpSheet(tester, w, key: key, size: const Size(420, 5600));
      final sale = saleOrder(assets.cars.values, w.g.fleet.owned, 'nyc');
      expect(sale.first.tags, contains('nyc'));
      expect(sale.last.tags, isNot(contains('nyc')), reason: 'Prague-only cars at the end');
      final tiles = find.byWidgetPredicate(
        (wd) => wd.key is ValueKey<String> && (wd.key! as ValueKey<String>).value.startsWith('garageSale:'),
      );
      // The built tiles (all of them with the real font) in saleOrder order.
      final built = [
        for (final e in tiles.evaluate()) (e.widget.key! as ValueKey<String>).value.substring('garageSale:'.length),
      ];
      expect(built.length, greaterThan(10));
      expect(built, [for (final s in sale.take(built.length)) s.id]);
      if (_png) await _shot(tester, key, 'garage_sale.png');
      for (final id in ['m0_coupe', 'hatch_pip']) {
        expect(find.byKey(ValueKey('garageCarPreview:$id')), findsOneWidget, reason: id);
      }
      final list = find.descendant(of: find.byKey(const ValueKey('garageCars')), matching: find.byType(Scrollable));
      for (final (id, cls) in [
        ('kombi_fjord', 'Estate'),
        ('vet_tourer', 'Classic'),
        ('bus_city', 'Bus'),
        ('spec_trike', 'Special'),
      ]) {
        final tile = find.byKey(ValueKey('garageSale:$id'));
        await tester.scrollUntilVisible(tile, 200, scrollable: list);
        expect(find.descendant(of: tile, matching: find.byKey(ValueKey('garageCarPreview:$id'))), findsOneWidget);
        expect(
          find.descendant(of: tile, matching: find.text(cls)),
          findsOneWidget,
          reason: id,
        );
      }
      stop(w);
      tester.view.reset();
    }, skip: !has);

    testWidgets('Tuning: a row per slot, level bar, effect, price; grey with garageNoCash; upgrade; maxed', (
      tester,
    ) async {
      if (_png) await _loadFonts();
      final w = (await tester.runAsync(
        () => start(
          saved: saveWith(
            cash: 5000,
            upgrades: const {
              'm0_coupe': {'engine': 3, 'tyres': 1},
            },
          ),
        ),
      ))!;
      final key = GlobalKey();
      await pumpSheet(tester, w, tab: GarageTab.tuning, key: key);
      final slots = assets.cars['m0_coupe']!.tuningSlots;
      for (final s in slots) {
        expect(find.byKey(ValueKey('garageSlot:$s')), findsOneWidget);
      }
      expect(find.text('Engine'), findsOneWidget);
      expect(find.text('Maxed out'), findsOneWidget);
      expect(find.byKey(const ValueKey('garageUpgrade:engine')), findsNothing);
      expect(find.text('+${(g.tyresStep * 100).round()} % grip'), findsOneWidget);
      expect(find.text('Upgrade · ${g.priceTyres[1]}'), findsOneWidget);
      expect(tester.widget<LevelBar>(find.byKey(const ValueKey('garageLevel:tyres'))).level, 1);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('garageUpgrade:tyres'))).onPressed, isNotNull);
      if (_png) await _shot(tester, key, 'garage_tuning.png');
      await tester.tap(find.byKey(const ValueKey('garageUpgrade:tyres')));
      await tester.pump();
      expect(w.g.fleet.state.cash, 5000 - g.priceTyres[1]);
      expect(tester.widget<LevelBar>(find.byKey(const ValueKey('garageLevel:tyres'))).level, 2);
      expect(find.byKey(const ValueKey('garageBought')), findsOneWidget);
      expect(find.text('Done – looking good'), findsOneWidget);
      // 1500 left: tyres 3 (6500) is grey with "Not enough cash", brakes 1 (1000) is live.
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('garageUpgrade:tyres'))).onPressed, isNull);
      expect(find.text('Not enough cash'), findsWidgets);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('garageUpgrade:brakes'))).onPressed, isNotNull);
      stop(w);
      tester.view.reset();
    }, skip: !has);

    testWidgets('Tuning of a car without slots shows garageNoSlots; the picker switches cars', (tester) async {
      final w = (await tester.runAsync(() => start(saved: saveWith(cars: const ['m0_coupe', 'kolobezka']))))!;
      await pumpSheet(tester, w, tab: GarageTab.tuning);
      expect(find.byKey(const ValueKey('garageSlot:engine')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('garageCar:kolobezka')));
      await tester.pump();
      expect(find.byKey(const ValueKey('garageNoSlots')), findsOneWidget);
      expect(find.text("This one can't be tuned"), findsOneWidget);
      stop(w);
      tester.view.reset();
    }, skip: !has);

    testWidgets('Looks: live preview of the picked choice, price and Buy, current marked, stock free', (tester) async {
      if (_png) await _loadFonts();
      final w = (await tester.runAsync(
        () => start(
          saved: saveWith(
            cash: 2000,
            looks: const {
              'm0_coupe': {'paint': 3, 'decal': 2, 'wheels': 1},
            },
          ),
        ),
      ))!;
      final key = GlobalKey();
      await pumpSheet(tester, w, tab: GarageTab.looks, key: key, size: const Size(420, 1400));
      expect(find.byKey(const ValueKey('garagePreview')), findsOneWidget);
      for (final p in garageParts) {
        expect(find.byKey(ValueKey('garagePart:$p')), findsOneWidget);
      }
      expect(find.text('Flames'), findsOneWidget);
      expect(find.text('White rims'), findsOneWidget);
      expect(find.text('Current'), findsNWidgets(garageParts.length));
      // Pick an underglow: the preview shows it before buying.
      await tapKey(tester, 'garageOption:glow:2');
      await tester.pump();
      CarPreview preview() => tester.widget<CarPreview>(find.byKey(const ValueKey('garagePreview')));
      expect(preview().look.glow, Tokens.colorGarageGlow[1]);
      expect(w.garage.world.look('m0_coupe', 'glow'), 0);
      expect(find.text('Buy · ${g.lookPriceGlow}'), findsOneWidget);
      if (_png) await _shot(tester, key, 'garage_looks.png');
      await tapKey(tester, 'garageLookBuy:glow');
      await tester.pump();
      expect(w.garage.world.look('m0_coupe', 'glow'), 2);
      expect(w.g.fleet.state.cash, 2000 - g.lookPriceGlow);
      expect(find.byKey(const ValueKey('garageLookBuy:glow')), findsNothing);
      // Back to stock paint is free even without cash.
      w.g.fleet.setCash(0);
      await tapKey(tester, 'garageOption:paint:0');
      await tester.pump();
      expect(preview().look.paint, isNull);
      await tapKey(tester, 'garageLookBuy:paint');
      await tester.pump();
      expect(w.garage.world.look('m0_coupe', 'paint'), 0);
      // A paid choice without cash is grey.
      await tapKey(tester, 'garageOption:decal:3');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('garageLookBuy:decal'))).onPressed, isNull);
      expect(find.text('Not enough cash'), findsOneWidget);
      stop(w);
      tester.view.reset();
    }, skip: !has);

    testWidgets('the phone app shows levels and looks read only, and the shelf', (tester) async {
      final w = (await tester.runAsync(
        () => start(
          saved: saveWith(
            cars: const ['m0_coupe', 'kolobezka'],
            upgrades: const {
              'm0_coupe': {'brakes': 2},
            },
            looks: const {
              'm0_coupe': {'decal': 3},
            },
          ),
        ),
      ))!;
      tester.view
        ..physicalSize = const Size(420, 900)
        ..devicePixelRatio = 1;
      await tester.pumpWidget(_app(GarageAppScreen(garage: w.garage)));
      expect(find.byKey(const ValueKey('garageAppCar:m0_coupe')), findsOneWidget);
      expect(find.byKey(const ValueKey('garageAppCar:kolobezka')), findsOneWidget);
      expect(find.text('Decal: Checker'), findsOneWidget);
      expect(find.text("This one can't be tuned"), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing, reason: 'read only');
      expect(find.text('Canal Street'), findsOneWidget);
      final bars = tester.widgetList<LevelBar>(find.byType(LevelBar)).map((b) => b.level).toList();
      expect(bars, [0, 0, 2, 0, 0]);
      stop(w);
      tester.view.reset();
    }, skip: !has);
  });

  group('test drive and debug cash (specs/testdrive.md)', () {
    test('the catalog car with the default look; at 0 the tuned own car comes back in place', () async {
      final w = await start(
        saved: saveWith(
          upgrades: const {
            'm0_coupe': {'engine': 3},
          },
          looks: const {
            'm0_coupe': {'paint': 2},
          },
        ),
      );
      final fleet = w.g.fleet;
      expect(fleet.startTest('vega_roadster'), isTrue);
      w.garage.leave(); // the sheet closes: the same test body again
      final vega = assets.cars['vega_roadster']!;
      expect(w.g.drive.car.spec.power, vega.power);
      expect(w.g.playerLook!(), isNull);
      // The save keeps the own car.
      expect(w.loop.snapshot()['car'], 'm0_coupe');
      // The timer runs out in game time: the own car with its upgrades and look, the toast.
      fleet.testing!.left = 0.05;
      final x = w.g.drive.car.x, y = w.g.drive.car.y;
      w.g.update(0.1);
      expect(fleet.testing, isNull);
      expect(w.g.testDriveOverS, greaterThan(0));
      expect(w.g.drive.spec.id, 'm0_coupe');
      expect(
        w.g.drive.car.spec.power,
        closeTo(tunedSpec(assets.cars['m0_coupe']!, const {'engine': 3}, g).power, 1e-9),
      );
      expect(w.g.playerLook!()?.paint, w.garage.lookOf('m0_coupe').paint);
      expect(w.g.playerLook!()?.paint, isNotNull);
      expect(w.g.drive.car.x, closeTo(x, 1));
      expect(w.g.drive.car.y, closeTo(y, 1));
      stop(w);
    }, skip: !has);

    test('debug cash adds economy.debug_grant and saves', () async {
      final w = await start(saved: saveWith(cash: 5));
      final writes = w.store.writes;
      w.loop.grantDebugCash();
      expect(w.g.fleet.state.cash, 5 + tuning.economy.debugGrant);
      await Future<void>.delayed(Duration.zero);
      expect(w.store.writes, writes + 1);
      expect(w.store.saves['nyc']!['cash'], 5 + tuning.economy.debugGrant);
      stop(w);
    }, skip: !has);

    testWidgets('every car for sale has "Test drive"; it starts the drive and closes the sheet', (tester) async {
      final w = (await tester.runAsync(start))!;
      tester.view
        ..physicalSize = const Size(420, 900)
        ..devicePixelRatio = 1;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showGarage(context, w.g.fleet, garage: w.garage),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final sale = saleOrder(assets.cars.values, w.g.fleet.owned, 'nyc');
      expect(find.byKey(ValueKey('garageTestDrive:${sale.first.id}')), findsOneWidget);
      expect(find.text('Test drive'), findsWidgets);
      await tapKey(tester, 'garageTestDrive:${sale.first.id}');
      await tester.pumpAndSettle();
      expect(w.g.fleet.testing?.car, sale.first.id);
      expect(find.byKey(const ValueKey('garageCars')), findsNothing);
      stop(w);
      tester.view.reset();
    }, skip: !has);
  });
}
