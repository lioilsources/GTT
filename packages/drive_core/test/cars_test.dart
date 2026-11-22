import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drive_core/drive_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge2d/forge2d.dart' show Vector2;
import 'package:rules_core/rules_core.dart' show IllegalAction;
import 'package:rules_core/vector_test_support.dart';
import 'package:world_engine/core.dart';

final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
final specs = {
  for (final f in Directory('../../content/cars').listSync().whereType<File>())
    for (final s in [parseCarSpec(f.readAsStringSync())]) s.id: s,
};
Map<String, int> get prices => {for (final e in specs.entries) e.key: e.value.price};

class _FilePack implements PackSource {
  _FilePack(this.root);
  final String root;
  @override
  Future<Uint8List> read(String path) async => File('$root$path').readAsBytes();
}

void main() {
  setUpAll(() async => initializeForge2D());

  test('M1 cars of different classes, every car tagged with known cities, paints from the tokens (specs/cars.md)', () {
    expect(specs.keys.toSet(), CarId.values.map((c) => c.id).toSet());
    const m1 = ['m0_coupe', 'hatch_pip', 'muscle_brute', 'taxi_metro', 'pickup_hauler'];
    expect(m1.map((id) => specs[id]!.class_).toSet().length, 5);
    final cities = CityId.values.map((c) => c.id).toSet();
    for (final s in specs.values) {
      expect(Tokens.colorCarPaint.containsKey(s.paint), isTrue, reason: s.id);
      expect(paintArgb(s), Tokens.colorCarPaint[s.paint]);
      expect(s.tags, isNotEmpty, reason: s.id);
      for (final tag in s.tags) {
        expect(cities, contains(tag), reason: '${s.id} $tag');
      }
    }
    for (final id in [tuning.cars.startCar, ...tuning.cars.startOwned, ...tuning.cars.parked.models]) {
      expect(specs.containsKey(id), isTrue, reason: id);
    }
  });

  group('cars rules (P0)', () {
    CarsState start(CarsRules r, {int cash = 0}) =>
        r.start(CarsConfig(prices: prices, cash: cash, owned: tuning.cars.startOwned, driving: tuning.cars.startCar));

    test('starts with the M0 coupe; stealing and the garage', () {
      final r = CarsRules();
      final s = start(r);
      expect(s.toJson(), {
        'cash': 0,
        'owned': ['m0_coupe'],
        'driving': 'm0_coupe',
        'stolen': false,
        'thefts': 0,
      });
      expect(r.legalActions(s), isEmpty);
      final a = r.apply(s, const CarsAction.board('taxi_metro', 'npc'));
      expect(a.stolen, isTrue);
      expect(r.legalActions(a), [const CarsAction.select('m0_coupe')]);
      final b = r.apply(a, const CarsAction.select('m0_coupe'));
      expect(b.toJson(), containsPair('thefts', 1));
      expect(b.stolen, isFalse);
    });

    test('rejects illegal actions and buys with cash', () {
      final r = CarsRules();
      final s = start(r);
      expect(() => r.apply(s, const CarsAction.board('taxi_metro', 'player')), throwsA(isA<IllegalAction>()));
      expect(() => r.apply(s, const CarsAction.select('m0_coupe')), throwsA(isA<IllegalAction>()));
      expect(() => r.apply(s, const CarsAction.buy('hatch_pip')), throwsA(isA<IllegalAction>()));
      final rich = start(r, cash: 16000);
      // Every affordable car not owned; M3 adds the cheap Prague cars.
      expect(r.buyable(rich), containsAll(['hatch_pip', 'taxi_metro']));
      for (final id in r.buyable(rich)) {
        expect(prices[id], lessThanOrEqualTo(16000), reason: id);
      }
      final b = r.apply(rich, const CarsAction.buy('taxi_metro'));
      expect(b.cash, 1000);
      expect(b.owned, ['m0_coupe', 'taxi_metro']);
    });

    test(
      'vectors/cars.json',
      () => expect(checkVectors(CarsRules()), isEmpty),
      skip: !flutterDone('vectors/cars.json') ? 'pending in parity.yaml' : false,
    );
  });

  group('parked model pool per city (specs/cars.md)', () {
    test('NYC keeps the original M1 pool in order, so its parked cars do not change', () {
      // The draw is nextInt(pool.length) over this list; same list = same output as before M3.
      expect(parkedModels(tuning, specs, 'nyc'), [
        'hatch_pip',
        'muscle_brute',
        'taxi_metro',
        'pickup_hauler',
        'm0_coupe',
      ]);
    });

    test('Prague parks only prague-tagged cars, in list order', () {
      final pool = parkedModels(tuning, specs, 'prague');
      expect(pool, isNotEmpty);
      expect(pool, containsAll(['hatch_pip', 'lidovka', 'kolobezka', 'kolo']));
      for (final id in pool) {
        expect(specs[id]!.tags, contains('prague'), reason: id);
      }
      final order = tuning.cars.parked.models;
      for (var i = 0; i + 1 < pool.length; i++) {
        expect(order.indexOf(pool[i]), lessThan(order.indexOf(pool[i + 1])));
      }
    });

    test('a city with no tagged cars has an empty pool', () {
      expect(parkedModels(tuning, specs, 'atlantis'), isEmpty);
    });
  });

  const root = '../../build/packs/nyc/';
  final hasPack = File('${root}manifest.pb').existsSync();

  group('parked cars and boarding in NYC', () {
    late City city;
    final chunks = <ChunkData>[];
    setUpAll(() async {
      if (!hasPack) return;
      final src = _FilePack(root);
      city = await City.load(src);
      final cx = (city.startX / city.chunkM).floor(), cy = (city.startY / city.chunkM).floor();
      for (final c in city.manifest.chunks) {
        if ((c.x - cx).abs() <= 2 && (c.y - cy).abs() <= 2) {
          chunks.add(prepareChunk(await src.read(chunkPath(c.x, c.y))));
        }
      }
    });

    test('places parked cars deterministically at curbs, spaced apart', () {
      var total = 0;
      for (final c in chunks) {
        final a = generateParked(city.graph, c.x, c.y, 1, tuning, specs, const [], (x: 1e9, y: 1e9), cityId: 'nyc');
        expect(a.length, lessThanOrEqualTo(tuning.cars.parked.perChunk));
        for (var i = 0; i < a.length; i++) {
          for (var j = i + 1; j < a.length; j++) {
            final d = math.sqrt(math.pow(a[i].x - a[j].x, 2) + math.pow(a[i].y - a[j].y, 2));
            expect(d, greaterThanOrEqualTo(tuning.cars.parked.minSpacingM));
          }
          final hit = city.graph.nearest(a[i].x, a[i].y, maxDist: 60, where: (e) => e.isGround);
          expect(hit, isNotNull);
          expect(hit!.dist, lessThan(hit.edge.width / 2));
        }
        total += a.length;
      }
      expect(total, greaterThan(10));
    }, skip: !hasPack);

    test('parked cars come only from the city pool; an empty pool parks nothing', () {
      final nyc = parkedModels(tuning, specs, 'nyc').toSet();
      final prague = parkedModels(tuning, specs, 'prague').toSet();
      for (final c in chunks) {
        for (final p in generateParked(city.graph, c.x, c.y, 1, tuning, specs, const [], (
          x: 1e9,
          y: 1e9,
        ), cityId: 'nyc')) {
          expect(nyc, contains(p.carId));
        }
        for (final p in generateParked(city.graph, c.x, c.y, 1, tuning, specs, const [], (
          x: 1e9,
          y: 1e9,
        ), cityId: 'prague')) {
          expect(prague, contains(p.carId));
        }
        expect(
          generateParked(city.graph, c.x, c.y, 1, tuning, specs, const [], (x: 1e9, y: 1e9), cityId: 'atlantis'),
          isEmpty,
        );
      }
    }, skip: !hasPack);

    test('boards a parked car: new body with its parameters, old car stays parked, events fire', () {
      final d = DriveWorld(city: city, spec: specs[tuning.cars.startCar]!, tuning: tuning);
      final fleet = CarFleet(d, specs, tuning, (id: 'g', x: d.car.x, y: d.car.y, heading: d.car.heading));
      for (final c in chunks) {
        d.addChunk(c);
        fleet.addChunk(c);
      }
      expect(fleet.parked, isNotEmpty);
      final target = fleet.parked.first;
      final side = target.heading + math.pi / 2;
      d.spawn(target.x + 6 * math.cos(side), target.y + 6 * math.sin(side), target.heading);
      expect(fleet.candidate(), same(target));
      expect(fleet.action(0), 'board');
      d.car.body.linearVelocity = Vector2(3, 0);
      expect(fleet.candidate(), isNull);
      expect(fleet.action(tuning.cars.actionHoldS / 2), 'board');
      expect(fleet.action(tuning.cars.actionHoldS), isNot('board'));
      d.car.body.linearVelocity = Vector2.zero();
      final events = <String>[];
      fleet.onStolen.add((e) => events.add('stolen ${e.car}'));
      fleet.onOwnerQuip.add((e) => events.add('quip ${e.car}'));
      fleet.onCarChanged.add((c) => events.add('changed $c'));
      final before = fleet.parked.length;
      fleet.board(target);
      expect(events, ['stolen ${target.carId}', 'quip ${target.carId}', 'changed ${target.carId}']);
      expect(fleet.state.stolen, isTrue);
      final spec = specs[target.carId]!;
      expect(d.car.spec.id, target.carId);
      expect(d.car.halfLength, closeTo(spec.lengthM * tuning.carScale / 2, 1e-9));
      expect(fleet.parked.length, before);
      final left = fleet.parked.firstWhere((p) => p.chunk == null);
      expect((left.carId, left.owner), ('m0_coupe', 'player'));
      fleet.board(left);
      expect(fleet.state.toJson(), containsPair('stolen', false));
      expect(fleet.state.thefts, 1);

      // Garage: the player stands at the garage point (set to the start above).
      d.spawn(fleet.garage!.x, fleet.garage!.y, fleet.garage!.heading);
      expect(fleet.atGarage(), isTrue);
      expect(fleet.action(0), 'garage');
      fleet.state = fleet.state.copyWith(owned: ['m0_coupe', 'pickup_hauler']);
      expect(fleet.canSelect('m0_coupe'), isFalse);
      fleet.select('pickup_hauler');
      expect(d.car.spec.id, 'pickup_hauler');
      d.spawn(city.startX, city.startY, city.startHeading);
      expect(d.car.spec.id, 'pickup_hauler');

      // The client grip multiplier (rain, specs/weather.md) survives respawns and car switches.
      d.gripScale = 0.8;
      expect(d.car.gripScale, 0.8);
      d.spawn(city.startX, city.startY, city.startHeading);
      expect(d.car.gripScale, 0.8);
      fleet.select('m0_coupe');
      expect(d.car.gripScale, 0.8);
      d.rescaleCar();
      expect(d.car.gripScale, 0.8);
      d.gripScale = 1;
      expect(d.car.gripScale, 1);
      d.dispose();
    }, skip: !hasPack);
  });
}
