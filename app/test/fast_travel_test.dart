import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drive_core/drive_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_loop/game_loop.dart';
import 'package:metropole/game/metropole_game.dart';
import 'package:metropole/game/pause.dart';
import 'package:metropole/loop/loop_controller.dart';
import 'package:metropole/loop/save_store.dart';
import 'package:metropole/phone/phone_controller.dart';
import 'package:metropole/travel/fast_travel.dart';
import 'package:shared_gen/citypack_pb.dart' as pb;
import 'package:world_engine/world_engine.dart';

// Port of web/test/fastTravel.test.ts, the world part (specs/travel.md P1): taxi landmark targets on
// the road, the move, the pause of the cards and the whole feature in the NYC pack.

Uint8List _gz(List<int> b) => Uint8List.fromList(gzip.encode(b));

class _MemPack implements PackSource {
  _MemPack(this.files);
  final Map<String, Uint8List> files;
  @override
  Future<Uint8List> read(String path) async => files[path] ?? (throw StateError('no $path in the pack'));
}

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

pb.Spot _spot(String id, String kind, int x, [String minigame = '']) => pb.Spot(
  id: id,
  kind: kind,
  name: '$id name',
  x: x * 10,
  y: 0,
  edge: 0,
  parkX: x * 10,
  parkY: 0,
  parkHeading: 0,
  minigame: minigame,
);

pb.Landmark _landmark(String id, int x, int y, bool hero) =>
    pb.Landmark(id: id, name: '$id name', x: x * 10, y: y * 10, hero: hero);

/// One straight road west–east (−800 … 800 m, [oneway]), two minigame spots, three stations, landmarks.
Map<String, Uint8List> _pack({int oneway = 0}) => {
  'manifest.pb': _gz(
    pb.Manifest(
      formatVersion: 1,
      cityId: 'test',
      chunkM: 256,
      driveSide: 'right',
      units: 'metric',
      start: pb.Spawn(x: 0, y: 0, headingRad: 0),
    ).writeToBuffer(),
  ),
  'graph.pb': _gz(
    pb.Graph(
      names: [''],
      nodes: [pb.Node(x: -8000, y: 0), pb.Node(x: 8000, y: 0)],
      edges: [
        pb.Edge(
          from: 0,
          to: 1,
          points: [-8000, 0, 8000, 0],
          class_4: pb.RoadClass.PRIMARY,
          lanes: 4,
          oneway: oneway,
          kept: true,
          widthM: 42,
        ),
      ],
    ).writeToBuffer(),
  ),
  'landmarks.pb': _gz(
    pb.Landmarks(
      items: [
        _landmark('tower', 30, 20, true),
        _landmark('statue', 40, 10, false),
        _landmark('far_hero', 0, 5000, true),
      ],
    ).writeToBuffer(),
  ),
  'spots.pb': _gz(
    pb.Spots(
      items: [
        _spot('st_w', 'subway', -300),
        _spot('bar', 'bar', -100, 'oko'),
        _spot('st_c', 'subway', 100),
        _spot('pier', 'pier', 200, 'sipky'),
        _spot('garage', 'garage', 250),
        _spot('st_e', 'subway', 500),
      ],
    ).writeToBuffer(),
  ),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tuning = Tuning.fromYaml(File('../content/tuning.yaml').readAsStringSync());
  CarSpec spec() => parseCarSpec(File('../content/cars/m0_coupe.json').readAsStringSync());

  group('fast travel in the world (synthetic city)', () {
    late City city;
    setUpAll(() async {
      await initializeForge2D();
      city = await City.load(_MemPack(_pack()));
    });

    test('taxi targets: minigame spots, then hero landmarks on the nearest kept road', () {
      final tg = taxiTargets(city, tuning.minigames.taxi.destSearchM);
      expect(tg.map((x) => '${x.kind.name}:${x.id}'), ['spot:bar', 'spot:pier', 'landmark:tower']);
      final tower = tg[2];
      expect(tower.x, closeTo(30, 1e-6));
      expect(tower.y, closeTo(0, 1e-6));
      expect(tower.heading, closeTo(0, 1e-9));
    });

    test('a landmark on a reverse one-way faces against the edge', () async {
      final back = await City.load(_MemPack(_pack(oneway: -1)));
      final tg = taxiLandmarkTargets(back.graph, back.landmarks.items, tuning.minigames.taxi.destSearchM);
      expect(tg.map((x) => x.id), ['tower']);
      expect(math.cos(tg.single.heading), closeTo(-1, 1e-9));
    });

    test(
      'the move: car at rest on the parking point facing parkHeading, layer 0; traffic, roadblock and pedestrians reset',
      () {
        final drive = DriveWorld(city: city, spec: spec(), tuning: tuning);
        drive.spawn(-500, 0, 0);
        for (var i = 0; i < 240; i++) {
          drive.input
            ..reset()
            ..throttle = 1;
          drive.update(1 / 60);
        }
        expect(drive.car.speed, greaterThan(1));
        expect(drive.traffic!.cars, isNotEmpty);
        final peds = PedestrianWorld(city, tuning);
        peds.update(1 / 60, [CarPose.of(drive.car)], 200, night: false);
        expect(peds.peds, isNotEmpty);
        final order = <String>[];
        moveTo(
          drive,
          peds,
          () => order.add('roadblock ${drive.traffic!.cars.length}'),
          const TravelPoint(id: 'st_e', name: 'E', x: 500, y: 0, heading: math.pi),
        );
        expect(drive.car.x, closeTo(500, 1e-3));
        expect(drive.car.y, closeTo(0, 1e-3));
        expect(math.cos(drive.car.heading), closeTo(-1, 1e-6));
        expect(drive.car.speed, 0);
        expect(drive.car.layer, 0);
        expect(drive.traffic?.cars ?? const [], isEmpty);
        expect(peds.peds, isEmpty);
        // The roadblock goes before the traffic reset (it removes its patrols from the traffic).
        expect(order, hasLength(1));
        expect(order.single, isNot('roadblock 0'));
        drive.dispose();
      },
    );
  });

  group('cards and the phone', () {
    test('the metro card and the line card pause the world (specs/pause.md)', () {
      expect(GameOverlay.values, contains(GameOverlay.travel));
      final r = OverlayRegistry();
      r.register(GameOverlay.travel);
      r.register(GameOverlay.travel);
      expect(r.isPaused, isTrue);
      r.unregister(GameOverlay.travel);
      expect(r.isPaused, isTrue);
      r.unregister(GameOverlay.travel);
      expect(r.isPaused, isFalse);
    });

    test('Taxi in the phone grid between Map and Garage', () {
      expect(PhoneAppId.values.take(4).map((a) => a.name), ['feed', 'map', 'taxi', 'garage']);
    });
  });

  group('fast travel in the game (NYC pack)', () {
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

    Future<({MetropoleGame g, PhoneController phone, LoopController loop, FastTravelController ft, _MemStore store})>
    start({Object? saved}) async {
      final g = MetropoleGame(assets);
      await g.preload();
      final phone = PhoneController(g, feedSeed: 1);
      final store = _MemStore();
      final loop = LoopController(
        g,
        phone,
        store: store,
        npc: null,
        saved: saved,
        settingsGet: () => (scheme: 'a', night: false),
        settingsSet: (_) {},
      );
      final ft = FastTravelController(g, phone, loop);
      return (g: g, phone: phone, loop: loop, ft: ft, store: store);
    }

    void stop(
      ({MetropoleGame g, PhoneController phone, LoopController loop, FastTravelController ft, _MemStore store}) w,
    ) {
      w.ft.dispose();
      w.loop.dispose();
      w.phone.dispose();
      w.g.onRemove();
    }

    void park(MetropoleGame g, TravelPoint p) {
      g.drive.spawn(p.x, p.y, p.heading);
      g.camera.snap(p.x, p.y, p.heading, tuning);
    }

    test('passing a station unlocks it once (toast, save); stations come back from the save', () async {
      final w = await start();
      final ft = w.ft, world = ft.world!;
      expect(world.stations.length, greaterThan(3));
      final st = world.stations[1];
      park(w.g, st);
      final writes = w.store.writes;
      ft.tick();
      expect(world.unlocked, [st.id]);
      expect(ft.unlockedToast.value, st.name);
      await Future<void>.delayed(Duration.zero);
      expect(w.store.writes, writes + 1);
      expect(w.store.saves['nyc']!['stations'], [st.id]);
      ft.tick();
      expect(w.store.writes, writes + 1);
      final saved = w.store.saves['nyc'];
      stop(w);
      final again = await start(saved: saved);
      expect(again.ft.world!.unlocked, [st.id]);
      stop(again);
    }, skip: !has);

    test(
      '"Metro" at an unlocked station; the card pauses, lists the others with fares; a ride pays and moves',
      () async {
        final w = await start();
        final ft = w.ft, world = ft.world!, g = w.g;
        final a = world.stations[0], b = world.stations[2];
        world.load([a.id, b.id]);
        park(g, a);
        ft.tick();
        expect(ft.metroHere.value?.id, a.id);
        // Hidden with the phone open and while wanted.
        w.phone.open();
        ft.tick();
        expect(ft.metroHere.value, isNull);
        w.phone.close();
        g.police.state.level = 1;
        ft.tick();
        expect(ft.metroHere.value, isNull);
        g.police.state.level = 0;
        ft.tick();
        expect(ft.metroHere.value?.id, a.id);

        expect(ft.openMetro(), isTrue);
        expect(g.worldPaused, isTrue);
        expect(ft.metroHere.value, isNull);
        final list = ft.metroList();
        final fare = metroFare(world.config, travelDistDm(a.x, a.y, b.x, b.y));
        expect([for (final c in list) (c.point.id, c.fare)], [(b.id, fare)]);
        // Short of cash: greyed and the ride is refused.
        g.fleet.setCash(fare - 1);
        expect(ft.metroList().single.affordable, isFalse);
        expect(ft.metro(b.id), isFalse);
        expect(g.fleet.state.cash, fare - 1);
        g.fleet.setCash(fare + 50);
        expect(ft.metro(b.id), isTrue);
        expect(g.fleet.state.cash, 50);
        expect(ft.metroCard.value, isNull);
        // The line card: the move happened at its start, the game stands under it.
        expect(ft.cut.value, (name: b.name, metro: true));
        expect(g.worldPaused, isTrue);
        expect(g.drive.car.x, closeTo(b.x, 1e-3));
        expect(g.drive.car.y, closeTo(b.y, 1e-3));
        expect(g.drive.car.speed, 0);
        expect(g.drive.car.layer, 0);
        expect(ft.offered, isFalse);
        ft.endCut();
        expect(ft.cut.value, isNull);
        expect(g.worldPaused, isFalse);
        stop(w);
      },
      skip: !has,
    );

    test('Taxi: sorted list from the car; locked while wanted; a ride pays, moves and keeps the navigation', () async {
      final w = await start();
      final ft = w.ft, g = w.g;
      final list = ft.taxiList();
      expect(list, isNotEmpty);
      for (var i = 1; i < list.length; i++) {
        expect(list[i].distDm, greaterThanOrEqualTo(list[i - 1].distDm));
      }
      expect(list.any((c) => c.point.kind == TaxiTargetKind.landmark), isTrue);
      // Navigation to a spot survives the ride and is recomputed after the line card.
      final spot = g.city.spots.items.firstWhere((s) => s.minigame.isNotEmpty);
      expect(w.phone.navigate(spot.id), isTrue);
      final target = list.last;
      g.fleet.setCash(target.fare - 1);
      expect(ft.taxi(target.point.id), isFalse);
      g.fleet.setCash(target.fare);
      g.police.state.level = 1;
      expect(ft.taxi(target.point.id), isFalse);
      g.police.state.level = 0;
      expect(ft.taxi(target.point.id), isTrue);
      expect(g.fleet.state.cash, 0);
      expect(ft.cut.value, (name: target.point.name, metro: false));
      expect(g.drive.car.x, closeTo(target.point.x, 1e-3));
      expect(g.drive.car.y, closeTo(target.point.y, 1e-3));
      expect(g.drive.traffic?.cars ?? const [], isEmpty);
      expect(g.peds.peds, isEmpty);
      ft.endCut();
      expect(w.phone.nav.active, isTrue);
      expect(w.phone.nav.target?.id, spot.id);
      stop(w);
    }, skip: !has);
  });
}
