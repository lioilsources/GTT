// Soak test for acceptance M3-A3 (specs/cities.md "Testy"): switching cities NYC → Prague → NYC … 10×
// with the real city packs and the building blocks the game uses for a city, without a crash, with each
// city keeping its own save, and with the physics body count back at the same baseline after a city is
// disposed (no leak). Skipped when the packs are not synced.
import 'dart:io';
import 'dart:typed_data';

import 'package:drive_core/drive_core.dart';
import 'package:forge2d/forge2d.dart' hide initializeForge2D;
import 'package:flutter_test/flutter_test.dart';
import 'package:game_loop/game_loop.dart';
import 'package:metropole/cities/cities.dart';
import 'package:metropole/loop/save_store.dart';
import 'package:world_engine/world_engine.dart';

class _FilePack implements PackSource {
  _FilePack(this.root);
  final String root;
  @override
  Future<Uint8List> read(String path) async => File('$root$path').readAsBytes();
}

/// Packs synced by `metro sync` (app assets), else the citypack build output.
String? packRoot(CityId c) {
  for (final r in ['assets/shared/packs/${c.id}/', '../build/packs/${c.id}/']) {
    if (File('${r}manifest.pb').existsSync()) return r;
  }
  return null;
}

/// Live bodies of [world]: every body with a shape in the broad phase, whatever its filter.
int liveBodies(World world) {
  const big = 1e7;
  final shapes = world.overlapAabb(
    Aabb(Vector2(-big, -big), Vector2(big, big)),
    filter: QueryFilter(categoryBits: Filter.allCategories, maskBits: Filter.allCategories),
  );
  return {for (final s in shapes) s.body}.length;
}

/// One running city as MetropoleGame builds it (drive, fleet, police, pedestrians, streaming).
class CitySession {
  CitySession._(this.city, this.drive, this.fleet, this.police, this.peds, this.streamer);

  static Future<CitySession> open(CityId id, Tuning tuning, Map<String, CarSpec> specs) async {
    final source = _FilePack(packRoot(id)!);
    final city = await City.load(source);
    final drive = DriveWorld(city: city, spec: specs[tuning.cars.startCar]!, tuning: tuning);
    final g = city.spots.items.where((s) => s.kind == 'garage').firstOrNull;
    final fleet = CarFleet(
      drive,
      specs,
      tuning,
      g == null ? null : (id: g.id, x: g.parkX / 10, y: g.parkY / 10, heading: g.parkHeading),
    );
    final police = Police(drive, tuning, fleet);
    final streamer = ChunkStreamer(
      city,
      source,
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
    return CitySession._(city, drive, fleet, police, PedestrianWorld(city, tuning), streamer);
  }

  final City city;
  final DriveWorld drive;
  final CarFleet fleet;
  final Police police;
  final PedestrianWorld peds;
  final ChunkStreamer streamer;

  /// Drives forward for [frames] frames of [dt] seconds.
  void drive_(int frames, double dt) {
    drive.input.throttle = 1;
    for (var i = 0; i < frames; i++) {
      final car = drive.car;
      streamer.update(car.x, car.y, car.heading);
      drive.update(dt);
      fleet.update();
      police.update(dt);
      peds.update(dt, [CarPose.of(car)], 150, night: false);
    }
  }

  /// Same order as MetropoleGame.onRemove, with traffic and trams emptied before the world goes.
  void close() {
    streamer.dispose();
    police.dispose();
    drive.traffic?.dispose();
    drive.trams?.dispose();
  }
}

void main() {
  final tuning = Tuning.fromYaml(File('../content/tuning.yaml').readAsStringSync());
  final specs = {
    for (final f in Directory('../content/cars').listSync().whereType<File>())
      for (final s in [parseCarSpec(f.readAsStringSync())]) s.id: s,
  };
  SaveConfig cfg(CityId c) => SaveConfig.fromTuning(tuning, c.id, CarId.values.map((c) => c.id));
  final hasPacks = packRoot(CityId.nyc) != null && packRoot(CityId.prague) != null;

  setUpAll(() async => initializeForge2D());

  test(
    '10 city switches NYC ↔ Prague: no throw, own saves, body count back at baseline',
    () async {
      final saves = MemorySaveStore();
      final cityStore = MemoryCityStore();
      final baseline = <CityId, int>{};
      final loadedPeak = <CityId, List<int>>{};
      final rounds = <CityId, int>{};
      var current = CityId.nyc;
      var state = <String, Object?>{};

      for (var round = 0; round <= 10; round++) {
        final c = round.isEven ? CityId.nyc : CityId.prague;
        if (round > 0) {
          await switchCity(current, c, saveCurrent: () => saves.write(current.id, state));
        }
        current = c;
        state = normalizeSave(cfg(c), await saves.read(c.id));
        await cityStore.write(c.id);

        // Each city sees only its own progress: one stamp and its round count as cash per visit.
        final s = saveOf(state);
        final visits = rounds[c] ?? 0;
        expect(s.stamps.length, visits, reason: '${c.id} round $round');
        expect(s.cash, visits == 0 ? cfg(c).startCash : 1000 * (c.index + 1) + visits - 1);

        final session = await CitySession.open(c, tuning, specs);
        expect(session.city.id, c.id);
        final start = liveBodies(session.drive.world);
        await session.streamer.preload(session.drive.car.x, session.drive.car.y, session.drive.car.heading);
        session.drive_(240, 1 / 30);
        final peak = liveBodies(session.drive.world);
        expect(session.streamer.loaded, isNotEmpty);
        expect(peak, greaterThan(start));
        session.close();
        final after = liveBodies(session.drive.world);
        // Only the player's car is left once chunks, parked cars, traffic and trams are gone.
        expect(after, start, reason: '${c.id} round $round: $after bodies after dispose, $start at start');
        expect(after, baseline.putIfAbsent(c, () => after), reason: '${c.id} round $round baseline');
        session.drive.dispose();
        expect(session.drive.world.isValid, isFalse);
        (loadedPeak[c] ??= []).add(peak);

        rounds[c] = visits + 1;
        state = composeSave(
          cfg(c),
          SaveParts(
            cash: 1000 * (c.index + 1) + visits,
            cars: s.cars,
            car: s.car,
            stamps: [...s.stamps, 'landmark:${c.id}_$visits'],
            best: const {},
            plays: const {},
          ),
        );
      }
      await saves.write(current.id, state);

      expect(await cityStore.read(), 'nyc');
      expect(rounds, {CityId.nyc: 6, CityId.prague: 5});
      final nyc = saveOf(normalizeSave(cfg(CityId.nyc), await saves.read('nyc')));
      final prague = saveOf(normalizeSave(cfg(CityId.prague), await saves.read('prague')));
      expect(nyc.stamps, [for (var i = 0; i < 6; i++) 'landmark:nyc_$i']);
      expect(prague.stamps, [for (var i = 0; i < 5; i++) 'landmark:prague_$i']);
      expect(nyc.cash, 1000 * (CityId.nyc.index + 1) + 5);
      expect(prague.cash, 1000 * (CityId.prague.index + 1) + 4);
      // ignore: avoid_print
      print('cities soak: baseline $baseline, peak bodies $loadedPeak');
    },
    skip: !hasPacks,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
