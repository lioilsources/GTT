import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drive_core/drive_core.dart';
import 'package:flame/game.dart' show Vector2;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_loop/game_loop.dart';
import 'package:mg_api/mg_api.dart' show loadArtIndex;
import 'package:metropole/game/metropole_game.dart';
import 'package:metropole/game/pause.dart';
import 'package:metropole/l10n/app_localizations.dart';
import 'package:metropole/loop/loop_controller.dart';
import 'package:metropole/loop/save_store.dart';
import 'package:metropole/phone/phone_controller.dart';
import 'package:metropole/shops/shops_controller.dart';
import 'package:metropole/shops/shops_layer.dart';
import 'package:metropole/ui/garage_sheet.dart';
import 'package:npc_dialogue/npc_dialogue.dart';
import 'package:world_engine/world_engine.dart';

// specs/shops.md P1 in client F: venues of the NYC pack, the context button, the shop and bar
// cards, cash, the snack bonus, beers and the drunk driver, the chosen bar minigame, the shelf.

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

typedef _W = ({MetropoleGame g, PhoneController phone, LoopController loop, ShopsController shops, _MemStore store});

/// PNGs of the cards for a visual check: `SHOPS_PNG=1 flutter test test/shops_test.dart` writes
/// them to ../run/ (not in git).
final _png = Platform.environment['SHOPS_PNG'] != null;

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
  // Let the art decode and the button state animations finish.
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.runAsync(() async {
    final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 2);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    final out = File('../run/$name')..createSync(recursive: true);
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  locale: locale,
  theme: ThemeData(fontFamily: 'Roboto', brightness: Brightness.dark),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(backgroundColor: const Color(Tokens.colorUiBackground), body: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tuning = Tuning.fromYaml(File('../content/tuning.yaml').readAsStringSync());

  testWidgets('the drunk banner shows shopsDrunk on shops.drunk', (tester) async {
    await tester.pumpWidget(_app(const DrunkBanner()));
    expect(find.text('Too many beers – win a minigame to sober up'), findsOneWidget);
    final box = tester.widget<Container>(find.byKey(const ValueKey('shopsDrunk')));
    expect(box.color, const Color(Tokens.colorShopsDrunk));
  });

  testWidgets('the shelf: shopShelfEmpty, then the names in purchase order with the icon', (tester) async {
    await tester.pumpWidget(_app(const SouvenirShelf(items: [])));
    expect(find.text('Shelf'), findsOneWidget);
    expect(find.text('No souvenirs yet – find a gift shop'), findsOneWidget);
    await tester.pumpWidget(
      _app(const SouvenirShelf(items: [(id: 'souvenir_canal', name: 'Canal'), (id: 'souvenir_soho', name: 'SoHo')])),
    );
    expect(find.text('No souvenirs yet – find a gift shop'), findsNothing);
    expect(tester.getTopLeft(find.text('Canal')).dx, lessThan(tester.getTopLeft(find.text('SoHo')).dx));
    expect(find.byIcon(Icons.redeem), findsNWidgets(2));
  });

  group('shops and bars in the game (NYC pack)', () {
    const root = '../build/packs/nyc/';
    final has = File('${root}manifest.pb').existsSync();
    final npcFile = File('assets/shared/content/npc.json');
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

    DialogueSession? npc() => npcFile.existsSync()
        ? DialogueSession(
            NpcPack.fromJson(jsonDecode(npcFile.readAsStringSync()) as Map<String, Object?>),
            tuning.npc,
            'nyc',
            7,
          )
        : null;

    Future<_W> start({Object? saved, _MemStore? store, bool withNpc = false}) async {
      final g = MetropoleGame(assets)..onGameResize(Vector2(400, 800));
      await g.preload();
      final phone = PhoneController(g, feedSeed: 1);
      final s = store ?? _MemStore();
      final loop = LoopController(
        g,
        phone,
        store: s,
        npc: withNpc ? npc() : null,
        saved: saved,
        settingsGet: () => (scheme: 'a', night: false),
        settingsSet: (_) {},
      );
      final shops = ShopsController(g, phone, loop);
      return (g: g, phone: phone, loop: loop, shops: shops, store: s);
    }

    void stop(_W w) {
      w.shops.dispose();
      w.loop.dispose();
      w.phone.dispose();
      w.g.onRemove();
    }

    void park(MetropoleGame g, Shop s) {
      g.drive.spawn(s.x, s.y, s.heading);
      g.camera.snap(s.x, s.y, s.heading, tuning);
    }

    Shop byId(_W w, String id) => w.shops.shops.firstWhere((s) => s.id == id);

    test('venues from the pack in spots.pb order, Map dots, the bar games of the city', () async {
      final w = await start();
      expect(w.shops.world, isNotNull);
      expect(w.shops.shops.map((s) => s.id), [
        for (final s in w.g.city.spots.items)
          if (const ['food', 'souvenir', 'bar'].contains(s.kind)) s.id,
      ]);
      expect(w.shops.shops.where((s) => s.kind == 'souvenir'), hasLength(5));
      expect(w.shops.games, ['sirky', 'oko', 'sipky']);
      final dots = w.phone.mapPoints.expand((f) => f()).where((e) => e.color == Tokens.colorShopsFood);
      expect(dots.length, w.shops.shops.where((s) => s.kind == 'food').length);
      // A bar with a minigame shows "Bar" instead of "Hrát".
      expect(w.loop.playHidden!('east_village_bar'), isTrue);
      expect(w.loop.playHidden!('washington_square'), isFalse);
      stop(w);
    }, skip: !has);

    test('city off: no module, no hooks, the shelf keeps the saved souvenirs', () async {
      tuning.shops.cities.nyc = false;
      try {
        final save = freshSave(SaveConfig.fromTuning(tuning, 'nyc', CarId.values.map((c) => c.id)))
          ..['souvenirs'] = ['souvenir_canal'];
        final w = await start(saved: save);
        expect(w.shops.world, isNull);
        expect(w.loop.playHidden, isNull);
        expect(w.shops.shelf().map((s) => s.id), ['souvenir_canal']);
        stop(w);
      } finally {
        tuning.shops.cities.nyc = true;
      }
    }, skip: !has);

    test('"Koupit" at a food stall takes over "Hrát" and the car button; the card pauses; buy pays', () async {
      final w = await start();
      final g = w.g, shops = w.shops, food = byId(w, 'food_slice_bleecker');
      park(g, food);
      shops.tick();
      expect(shops.here.value?.id, food.id);
      expect(w.loop.yieldTo!(), isTrue);
      expect(g.carActionYield!(), isTrue);
      w.phone.open();
      shops.tick();
      expect(shops.here.value, isNull);
      w.phone.close();
      g.fleet.setCash(10);
      expect(shops.tryOpen(), isTrue);
      expect(g.pauseOverlays.isOpen(GameOverlay.shop), isTrue);
      expect(shops.canBuy(food), isFalse);
      expect(shops.buy(food), 0);
      expect(g.fleet.state.cash, 10);
      g.fleet.setCash(1000);
      expect(shops.buy(food), tuning.shops.priceFood);
      expect(g.fleet.state.cash, 1000 - tuning.shops.priceFood);
      expect(shops.world!.snack, isTrue);
      expect(shops.toast.value?.kind, ShopToast.snack);
      shops.close();
      expect(g.worldPaused, isFalse);
      stop(w);
    }, skip: !has);

    test('a souvenir is saved once, shows owned, and loads back', () async {
      final w = await start();
      final s = byId(w, 'souvenir_canal');
      w.g.fleet.setCash(500);
      w.shops.open(s);
      expect(w.shops.buy(s), tuning.shops.priceSouvenir);
      expect(w.shops.owns(s), isTrue);
      expect(w.shops.canBuy(s), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(w.store.saves['nyc']!['souvenirs'], ['souvenir_canal']);
      expect(w.shops.shelf(), [(id: 'souvenir_canal', name: s.name)]);
      final saved = w.store.saves['nyc'];
      stop(w);
      final again = await start(saved: saved);
      expect(again.shops.world!.owned, ['souvenir_canal']);
      // Debug reset: a fresh save empties the shelf.
      await again.loop.resetSave();
      expect(again.shops.world!.owned, isEmpty);
      stop(again);
    }, skip: !has);

    test('drunk: input ignored, the car brakes to a stop; a won bar game sobers, the snack pays', () async {
      final w = await start();
      final g = w.g, shops = w.shops, bar = byId(w, 'bar_third_ave');
      g.fleet.setCash(1000);
      shops.open(bar);
      for (var i = 0; i < tuning.shops.beerLimit; i++) {
        shops.buy(bar);
      }
      expect(shops.drunk, isFalse);
      shops.buy(byId(w, 'food_slice_bleecker'));
      shops.close();
      // A couple of beers: the car rolls off by itself (auto throttle).
      g.drive.spawn(bar.x, bar.y, bar.heading);
      for (var i = 0; i < 30 * 3; i++) {
        g.update(1 / 30);
      }
      expect(g.drive.car.speed, greaterThan(2));
      // One more: drunk, the input is ignored, the car only brakes and never reverses.
      shops.open(bar);
      shops.buy(bar);
      shops.close();
      expect(shops.drunk, isTrue);
      expect(shops.toast.value?.kind, ShopToast.drunk);
      for (var i = 0; i < 30 * 8; i++) {
        g.update(1 / 30);
        expect(g.drive.input.steer, 0);
        expect(g.drive.input.throttle, 0);
      }
      expect(g.drive.car.speed, lessThan(tuning.drive.brakeMinMps + 0.5));
      expect(g.drive.car.forwardSpeed, greaterThan(-0.5));
      // The bar card: the chosen minigame runs on this bar.
      shops.open(bar);
      shops.play(bar, 'oko');
      final q = w.loop.request.value!;
      expect((q.spot, q.id.id), ('bar_third_ave', 'oko'));
      final cash = g.fleet.state.cash;
      w.loop.finish(MinigameResult(stars: 2, score: 100, playedMs: 1000, aborted: false));
      final o = w.loop.outcome.value!;
      expect(o.minigame, 'oko');
      expect(o.snack, o.cash.amount * tuning.shops.snackPct ~/ 100);
      expect(g.fleet.state.cash, cash + o.cash.amount + o.snack);
      expect(w.loop.book.plays['bar_third_ave'], 1);
      expect(shops.drunk, isFalse);
      expect(shops.toast.value?.kind, ShopToast.sober);
      w.loop.closeResult();
      stop(w);
    }, skip: !has);

    test('beers wear off with game time only; the clock stands while paused', () async {
      final w = await start();
      final shops = w.shops, bar = byId(w, 'bar_third_ave');
      w.g.fleet.setCash(1000);
      shops.open(bar);
      shops.buy(bar);
      shops.close();
      expect(shops.beers, 1);
      shops.update(tuning.shops.beerS - 1.0);
      expect(shops.beers, 1);
      shops.update(1);
      expect(shops.beers, 0);
      stop(w);
    }, skip: !has);

    test('the card starts the host skit of context shop / bar when one fits', () async {
      final w = await start(withNpc: true);
      final n = w.loop.npc;
      if (n == null) return stop(w);
      final s = w.shops.shops.firstWhere(
        (s) => n.canStart(w.shops.hostId(s)!, s.isBar ? 'bar' : 'shop'),
        orElse: () => w.shops.shops.first,
      );
      w.shops.open(s);
      expect(w.shops.skit, n.canStart(w.shops.hostId(s)!, s.isBar ? 'bar' : 'shop') || n.running);
      w.shops.close();
      expect(n.running, isFalse);
      stop(w);
    }, skip: !has || !npcFile.existsSync());

    Future<void> pumpCard(WidgetTester tester, _W w, Shop s, GlobalKey key) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      await tester.pumpWidget(
        _app(RepaintBoundary(key: key, child: ShopsLayer(shops: w.shops))),
      );
      w.shops.open(s);
      await tester.pump();
    }

    testWidgets('shop card: name, snack line, price; Koupit grey with shopNoCash; Zpět closes', (tester) async {
      if (_png) {
        await _loadFonts();
        await tester.runAsync(() => loadArtIndex(rootBundle));
      }
      final w = (await tester.runAsync(() => start(withNpc: _png)))!;
      final food = byId(w, 'food_slice_bleecker');
      w.g.fleet.setCash(5);
      final key = GlobalKey();
      await pumpCard(tester, w, food, key);
      expect(find.text(food.name), findsOneWidget);
      expect(find.text('Snack: +${tuning.shops.snackPct} % on your next minigame reward'), findsOneWidget);
      expect(find.text('${tuning.shops.priceFood} cash'), findsOneWidget);
      expect(find.text('Not enough cash'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(ValueKey('shopBuy:${food.id}'))).onPressed, isNull);
      w.g.fleet.setCash(500);
      w.shops.notifyListeners();
      await tester.pump();
      expect(find.text('Not enough cash'), findsNothing);
      if (_png) await _shot(tester, key, 'shops_card.png');
      await tester.tap(find.byKey(ValueKey('shopBuy:${food.id}')));
      await tester.pump();
      expect(w.g.fleet.state.cash, 500 - tuning.shops.priceFood);
      await tester.tap(find.byKey(const ValueKey('shopBack')));
      await tester.pump();
      expect(w.shops.card.value, isNull);
      expect(find.byKey(const ValueKey('shopBack')), findsNothing);
      stop(w);
      await tester.binding.setSurfaceSize(null);
    }, skip: !has);

    testWidgets('a card whose host has a skit shows its opening line under the bust; a tap opens it; leaving keeps the card', (tester) async {
      if (_png) {
        await _loadFonts();
        await tester.runAsync(() => loadArtIndex(rootBundle));
      }
      final w = (await tester.runAsync(() => start(withNpc: true)))!;
      final n = w.loop.npc!;
      final s = w.shops.shops.where((s) => n.canStart(w.shops.hostId(s)!, s.isBar ? 'bar' : 'shop')).firstOrNull;
      if (s == null) return stop(w);
      final key = GlobalKey();
      await pumpCard(tester, w, s, key);
      expect(w.shops.skit, isTrue);
      expect(find.byKey(const ValueKey('shopSkit')), findsOneWidget);
      expect(find.byType(DialogueView), findsNothing);
      expect(find.text(s.name), findsWidgets);
      if (_png) await _shot(tester, key, 'shops_skit_card.png');
      await tester.tap(find.byKey(const ValueKey('shopSkit')));
      await tester.pump();
      expect(find.byType(DialogueView), findsOneWidget);
      if (_png) await _shot(tester, key, 'shops_skit_dialogue.png');
      await tester.tap(find.text(tr('en', MessageKey.npcLeave)));
      await tester.pump();
      expect(w.shops.skit, isFalse);
      expect(find.byType(DialogueView), findsNothing);
      expect(w.shops.card.value, s);
      w.shops.close();
      stop(w);
      await tester.binding.setSurfaceSize(null);
    }, skip: !has || !npcFile.existsSync());

    testWidgets('souvenir card: owned shows shopOwned instead of the button', (tester) async {
      final w = (await tester.runAsync(start))!;
      final s = byId(w, 'souvenir_soho');
      w.g.fleet.setCash(500);
      final key = GlobalKey();
      await pumpCard(tester, w, s, key);
      await tester.tap(find.byKey(ValueKey('shopBuy:${s.id}')));
      await tester.pump();
      expect(find.byKey(ValueKey('shopBuy:${s.id}')), findsNothing);
      expect(find.text('Already on your shelf'), findsWidgets);
      w.shops.close();
      stop(w);
      await tester.binding.setSurfaceSize(null);
    }, skip: !has);

    testWidgets('bar card: beer row and one "Play <game>" per distinct bar game; Play starts it', (tester) async {
      if (_png) {
        await _loadFonts();
        await tester.runAsync(() => loadArtIndex(rootBundle));
      }
      final w = (await tester.runAsync(() => start(withNpc: _png)))!;
      final bar = byId(w, 'bar_third_ave');
      w.g.fleet.setCash(500);
      final key = GlobalKey();
      await pumpCard(tester, w, bar, key);
      expect(find.text('Beer'), findsOneWidget);
      expect(find.text('${tuning.shops.priceBeer} cash'), findsOneWidget);
      for (final g in ['sirky', 'oko', 'sipky']) {
        expect(find.byKey(ValueKey('shopPlay:$g')), findsOneWidget);
      }
      if (_png) await _shot(tester, key, 'shops_bar_card.png');
      w.shops.close();
      w.shops.open(bar);
      w.shops.play(bar, 'sipky');
      expect(w.loop.request.value?.id.id, 'sipky');
      expect(w.loop.request.value?.spot, 'bar_third_ave');
      expect(w.g.pauseOverlays.isOpen(GameOverlay.shop), isFalse);
      w.loop.finish(MinigameResult(stars: 0, score: 0, playedMs: 1, aborted: true));
      w.loop.closeResult();
      stop(w);
      await tester.binding.setSurfaceSize(null);
    }, skip: !has);

    testWidgets('drunk HUD: the banner, no beers pill; sober: the beers pill', (tester) async {
      if (_png) {
        await _loadFonts();
        await tester.runAsync(() => loadArtIndex(rootBundle));
      }
      final w = (await tester.runAsync(() => start(withNpc: _png)))!;
      final bar = byId(w, 'bar_third_ave');
      w.g.fleet.setCash(500);
      w.shops.open(bar);
      w.shops.buy(bar);
      w.shops.close();
      await tester.binding.setSurfaceSize(const Size(400, 800));
      final key = GlobalKey();
      await tester.pumpWidget(
        _app(
          RepaintBoundary(
            key: key,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Color(Tokens.colorUiBackground)),
                ShopsLayer(shops: w.shops),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Beers: 1'), findsWidgets);
      w.shops.open(bar);
      for (var i = 0; i < tuning.shops.beerLimit; i++) {
        w.shops.buy(bar);
      }
      w.shops.close();
      w.shops.toast.value = null;
      await tester.pump();
      expect(find.byType(DrunkBanner), findsOneWidget);
      expect(find.text('Beers: ${tuning.shops.beerLimit + 1}'), findsNothing);
      if (_png) await _shot(tester, key, 'shops_drunk_hud.png');
      stop(w);
      await tester.binding.setSurfaceSize(null);
    }, skip: !has);

    testWidgets('the Garage shows the shelf of the shops module', (tester) async {
      final w = (await tester.runAsync(start))!;
      final s = byId(w, 'souvenir_times_sq');
      w.g.fleet.setCash(500);
      w.shops.open(s);
      w.shops.buy(s);
      w.shops.close();
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showGarage(context, w.g.fleet, shelf: w.shops.shelf),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('shopShelf')), findsOneWidget);
      expect(find.text(s.name), findsOneWidget);
      stop(w);
    }, skip: !has);
  });
}
