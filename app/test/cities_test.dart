// City start and switching (specs/cities.md "Testy"); mirrors the web cities test.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_loop/game_loop.dart';
import 'package:metropole/cities/cities.dart';
import 'package:metropole/loop/save_store.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  final tuning = Tuning.fromYaml(File('../content/tuning.yaml').readAsStringSync());
  SaveConfig cfg(CityId c) => SaveConfig.fromTuning(tuning, c.id, CarId.values.map((c) => c.id));

  group('pickStartCity', () {
    const bundled = [CityId.nyc, CityId.prague];

    test('parameter wins when it is a known city', () {
      expect(pickStartCity('prague', 'nyc', bundled), CityId.prague);
    });

    test('then the last city', () {
      expect(pickStartCity(null, 'prague', bundled), CityId.prague);
      expect(pickStartCity('atlantis', 'prague', bundled), CityId.prague);
    });

    test('then the first bundled city', () {
      expect(pickStartCity(null, null, bundled), CityId.nyc);
      expect(pickStartCity('', 'atlantis', bundled), CityId.nyc);
      expect(pickStartCity(null, 'prague', const [CityId.nyc]), CityId.nyc);
    });
  });

  test('city.json parsing ignores unreadable files', () {
    expect(parseLastCity('{"city": "prague"}'), 'prague');
    expect(parseLastCity('{"city": 3}'), isNull);
    expect(parseLastCity('[]'), isNull);
    expect(parseLastCity('not json'), isNull);
  });

  test('FileCityStore writes and reads city.json', () async {
    final dir = await Directory.systemTemp.createTemp('metropole_city');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileCityStore(() async => dir);
    expect(await store.read(), isNull);
    await store.write('prague');
    expect(await store.read(), 'prague');
    expect(File('${dir.path}/city.json').readAsStringSync(), '{"city":"prague"}');
    File('${dir.path}/city.json').writeAsStringSync('{broken');
    expect(await store.read(), isNull);
  });

  test('switching NYC → Prague → NYC keeps both saves', () async {
    final saves = MemorySaveStore();
    final cities = MemoryCityStore();

    // A running city: its save loaded on start, the last city written, state saved on the switch.
    var state = <String, Object?>{};
    var current = CityId.nyc;
    Future<void> start(CityId c) async {
      current = c;
      state = normalizeSave(cfg(c), await saves.read(c.id));
      await cities.write(c.id);
    }

    Map<String, Object?> play(CityId c, int cash, String stamp) {
      final s = saveOf(state);
      return composeSave(
        cfg(c),
        SaveParts(cash: cash, cars: s.cars, car: s.car, stamps: [...s.stamps, stamp], best: const {}, plays: const {}),
      );
    }

    Future<void> travel(CityId to) async {
      await switchCity(current, to, saveCurrent: () => saves.write(current.id, state));
      await start(to);
    }

    await start(CityId.nyc);
    state = play(CityId.nyc, 1234, 'landmark:empire_state');
    await travel(CityId.prague);
    expect(saveOf(state).cash, cfg(CityId.prague).startCash);
    expect(saveOf(state).stamps, isEmpty);
    state = play(CityId.prague, 77, 'district:zizkov');
    await travel(CityId.nyc);

    expect(await cities.read(), 'nyc');
    expect(saveOf(state).cash, 1234);
    expect(saveOf(state).stamps, ['landmark:empire_state']);
    final prague = saveOf(normalizeSave(cfg(CityId.prague), await saves.read('prague')));
    expect(prague.cash, 77);
    expect(prague.stamps, ['district:zizkov']);
    expect(pickStartCity(null, await cities.read(), CityId.values), CityId.nyc);
  });

  test('switching to the same city does not save', () async {
    var saved = 0;
    await switchCity(CityId.nyc, CityId.nyc, saveCurrent: () async => saved++);
    expect(saved, 0);
  });
}
