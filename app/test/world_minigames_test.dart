import 'dart:io';

import 'package:drive_core/drive_core.dart';
import 'package:flame/game.dart' show Vector2;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metropole/drift/drift_controller.dart';
import 'package:metropole/game/metropole_game.dart';
import 'package:metropole/loop/loop_controller.dart';
import 'package:metropole/loop/save_store.dart';
import 'package:metropole/minigames/registry.dart';
import 'package:metropole/minigames/world_hud.dart';
import 'package:metropole/phone/phone_controller.dart';
import 'package:metropole/sprint/sprint_controller.dart';
import 'package:world_engine/world_engine.dart';

// M2-S9 batch D in client F: Drift zone and Sprint A→B as world minigames in the player's own car
// (specs/minigames/drift.md, sprint.md "Svět"), Stickball and Double Dutch in the Gallery.

class _FilePack implements PackSource {
  _FilePack(this.root);
  final String root;
  @override
  Future<Uint8List> read(String path) async => File('$root$path').readAsBytes();
}

class _MemStore implements SaveStore {
  @override
  Future<Object?> read(String cityId) async => null;
  @override
  Future<void> write(String cityId, Map<String, Object?> save) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tuning = Tuning.fromYaml(File('../content/tuning.yaml').readAsStringSync());
  const root = '../build/packs/nyc/';
  final has = File('${root}manifest.pb').existsSync();
  late GameAssets assets;

  test('batch D and the NYC local games are in the Gallery', () {
    for (final id in [MinigameId.drift, MinigameId.sprint]) {
      expect(minigames[id], isA<WorldCardGame>());
      expect(minigames[id]!.meta.engine, 'drive');
    }
    expect(minigames[MinigameId.stickball]!.meta.id, 'stickball');
    expect(minigames[MinigameId.doubledutch]!.meta.id, 'doubledutch');
    expect([240.0, 59.2, 0.0, 61.0].map(worldClock), ['4:00', '1:00', '0:00', '1:01']);
    expect([1234, -800, 0].map(splitText), ['+1.2 s', '−0.8 s', '±0.0 s']);
  });

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

  Future<(MetropoleGame, PhoneController, LoopController)> start() async {
    final game = MetropoleGame(assets)..onGameResize(Vector2(400, 800));
    await game.preload();
    final phone = PhoneController(game, feedSeed: 1);
    final loop = LoopController(
      game,
      phone,
      store: _MemStore(),
      npc: null,
      saved: null,
      settingsGet: () => (scheme: 'a', night: false),
      settingsSet: (_) {},
    );
    return (game, phone, loop);
  }

  test('drift: own car, the zone at the spot, samples, give up = aborted 0 stars', () async {
    final (game, phone, loop) = await start();
    final drift = DriftController(game);
    loop.worldGames[MinigameId.drift] = drift;
    final spot = game.city.spots.items.firstWhere((s) => s.minigame == 'drift');
    final own = game.drive.spec.id;
    final x0 = game.drive.car.x;
    MinigameResult? got;
    drift.start(spot.id, MinigameContext(cityId: 'nyc', difficulty: 3, seed: 1, locale: 'en'), (r) => got = r);
    expect(drift.active, true);
    expect([game.drive.spec.id, game.drive.car.x], [own, x0], reason: 'no swap, no move');
    final s = drift.session!;
    expect([s.cx, s.cy], [spot.parkX / 10, spot.parkY / 10]);
    for (var i = 0; i < 12; i++) {
      drift.update(0.05);
    }
    expect(s.log.where((a) => a.op == 'sample').length, 6);
    // Far from the spot: out of the ring.
    expect(s.inZone, false);
    drift.quit();
    expect([got!.aborted, got!.stars, got!.score], [true, 0, 0]);
    expect(drift.active, false);
    expect(game.drive.onWall, isNull, reason: 'crash hooks released');
    drift.dispose();
    loop.dispose();
    phone.dispose();
    game.onRemove();
  }, skip: has ? false : 'no pack');

  test('drift: the session ends by timeout with the rules result', () async {
    final (game, phone, loop) = await start();
    final drift = DriftController(game);
    final spot = game.city.spots.items.firstWhere((s) => s.minigame == 'drift');
    game.drive.spawn(spot.parkX / 10, spot.parkY / 10, spot.parkHeading.toDouble());
    MinigameResult? got;
    drift.start(spot.id, MinigameContext(cityId: 'nyc', difficulty: 1, seed: 1, locale: 'en'), (r) => got = r);
    expect(drift.session!.inZone, true);
    for (var i = 0; i < tuning.minigames.drift.sessionS * 10 + 1 && got == null; i++) {
      drift.update(0.1);
    }
    expect(got!.aborted, false);
    expect(got!.playedMs, greaterThanOrEqualTo(tuning.minigames.drift.sessionS * 1000));
    drift.dispose();
    loop.dispose();
    phone.dispose();
    game.onRemove();
  }, skip: has ? false : 'no pack');

  test('sprint: start line, pick, countdown brake, go, navigation to the first gate, give up', () async {
    final (game, phone, loop) = await start();
    final sprint = SprintController(game, phone);
    loop.worldGames[MinigameId.sprint] = sprint;
    final spot = game.city.spots.items.firstWhere((s) => s.minigame == 'sprint');
    MinigameResult? got;
    sprint.start(spot.id, MinigameContext(cityId: 'nyc', difficulty: 3, seed: 7, locale: 'en'), (r) => got = r);
    final c = game.drive.car;
    expect([c.x, c.y], [closeTo(spot.parkX / 10, 1e-3), closeTo(spot.parkY / 10, 1e-3)]);
    final r = sprint.race!;
    expect(r.log.first.op, 'pick');
    expect(r.state.phase, 'ready');
    expect(sprint.line.value!.text, startsWith('Sprint to '));
    // Countdown: the input becomes braking with the handbrake.
    final input = ControlInput()..boost = true;
    game.inputHook!(input);
    expect([input.boost, input.handbrake], [false, true]);
    for (var t = 0.0; t < tuning.minigames.sprint.countdownS + 0.1; t += 0.1) {
      sprint.update(0.1);
    }
    expect(r.state.phase, 'run');
    expect(r.state.cps, r.plan!.gates.length);
    expect(phone.nav.active, true);
    final boost = ControlInput()..boost = true;
    game.inputHook!(boost);
    expect(boost.boost, true, reason: 'no brake after go');
    sprint.quit();
    expect([got!.aborted, got!.stars, got!.score], [true, 0, 0]);
    expect(phone.nav.active, false);
    sprint.dispose();
    loop.dispose();
    phone.dispose();
    game.onRemove();
  }, skip: has ? false : 'no pack');
}
