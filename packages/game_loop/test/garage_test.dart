import 'dart:convert';
import 'dart:io';

import 'package:game_loop/game_loop.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';
import 'package:shared_gen/shared_gen.dart';
import 'package:test/test.dart';

// specs/garage.md v1 (module garage) and specs/save.md v4 (save format 5, upgrades and looks).
void main() {
  final tuning = Tuning.fromYaml(File('$repoRoot/content/tuning.yaml').readAsStringSync());
  final cfg = GarageConfig.fromTuning(tuning.garage, const {
    'coupe': ['engine', 'tyres', 'brakes', 'weight', 'drift'],
    'scooter': [],
    'truck': ['engine', 'tyres'],
  });

  group('garage vectors', () {
    test(
      'vectors/garage.json',
      () => expect(checkVectors(GarageRules()), isEmpty),
      skip: !flutterDone('vectors/garage.json') ? 'pending in parity.yaml' : false,
    );
    test(
      'vectors/save.json',
      () => expect(checkVectors(SaveRules()), isEmpty),
      skip: !flutterDone('vectors/save.json') ? 'pending in parity.yaml' : false,
    );
  });

  group('garage rules (specs/garage.md)', () {
    test('id, spec version; init is empty and ignores the seed', () {
      final r = GarageRules();
      expect((r.id, r.specVersion), ('garage', 1));
      final j = _json(cfg);
      expect(r.stateToJson(r.init(j, 1)), r.stateToJson(r.init(j, 99)));
      expect(r.stateToJson(r.init(j, 1)), {
        'upgrades': <String, Object?>{},
        'looks': <String, Object?>{},
        'last': {'op': '', 'amount': 0},
      });
      expect(r.result(r.init(j, 1)), isNull);
      expect(() => r.aiAction(r.init(j, 1), 1, Prng(1)), throwsUnsupportedError);
    });

    test('config from tuning and tokens: parts = 1 + colours, decal 4, wheels 3', () {
      expect(cfg.parts, {
        'paint': 1 + Tokens.colorGaragePaints.length,
        'decal': 4,
        'wheels': 3,
        'glow': 1 + Tokens.colorGarageGlow.length,
        'smoke': 1 + Tokens.colorGarageSmoke.length,
      });
      expect(cfg.prices['engine'], tuning.garage.priceEngine);
      expect(cfg.maxLevel, tuning.garage.maxLevel);
      expect(cfg.lookPrices['glow'], tuning.garage.lookPriceGlow);
    });

    test('legalActions: load, upgrades by car id and slot order, then looks by car id and part order', () {
      final r = GarageRules();
      final s = r.start(cfg);
      final acts = r.legalActions(s);
      expect(acts.first, const GarageAction.load({}, {}));
      final ups = acts.where((a) => a.op == 'upgrade').map((a) => '${a.car}.${a.slot}:${a.cash}').toList();
      expect(ups, [
        'coupe.engine:${cfg.prices['engine']![0]}',
        'coupe.tyres:${cfg.prices['tyres']![0]}',
        'coupe.brakes:${cfg.prices['brakes']![0]}',
        'coupe.weight:${cfg.prices['weight']![0]}',
        'coupe.drift:${cfg.prices['drift']![0]}',
        'truck.engine:${cfg.prices['engine']![0]}',
        'truck.tyres:${cfg.prices['tyres']![0]}',
      ]);
      final looks = acts.where((a) => a.op == 'look').toList();
      final perCar = cfg.parts.values.fold(0, (a, b) => a + b) - garageParts.length;
      expect(looks.length, 3 * perCar);
      expect((looks.first.car, looks.first.part, looks.first.value), ('coupe', 'paint', 1));
      expect(looks.last.car, 'truck');
      // A maxed slot and the current look are not offered.
      var t = s;
      for (var i = 0; i < cfg.maxLevel; i++) {
        t = r.apply(t, GarageAction.upgrade('truck', 'engine', 1 << 20));
      }
      t = r.apply(t, GarageAction.look('truck', 'decal', 2, 1 << 20));
      final next = r.legalActions(t);
      expect(next.any((a) => a.op == 'upgrade' && a.car == 'truck' && a.slot == 'engine'), isFalse);
      expect(next.where((a) => a.car == 'truck' && a.part == 'decal').map((a) => (a.value, a.cash)), [
        (0, 0),
        (1, cfg.lookPrices['decal']),
        (3, cfg.lookPrices['decal']),
      ]);
    });

    test('illegal actions and strict JSON', () {
      final r = GarageRules();
      var s = r.start(cfg);
      s = r.apply(s, const GarageAction.look('coupe', 'paint', 2, 400));
      for (final a in [
        const GarageAction.upgrade('gone', 'engine', 99999),
        const GarageAction.upgrade('scooter', 'engine', 99999),
        const GarageAction.upgrade('truck', 'brakes', 99999),
        const GarageAction.upgrade('coupe', 'engine', -1),
        GarageAction.upgrade('coupe', 'engine', cfg.prices['engine']![0] - 1),
        const GarageAction.look('gone', 'paint', 1, 9999),
        const GarageAction.look('coupe', 'neon', 1, 9999),
        GarageAction.look('coupe', 'decal', cfg.parts['decal']!, 9999),
        const GarageAction.look('coupe', 'decal', -1, 9999),
        const GarageAction.look('coupe', 'paint', 2, 9999),
        const GarageAction.look('coupe', 'decal', 0, 9999),
        const GarageAction.look('coupe', 'paint', 0, -1),
        GarageAction.look('coupe', 'glow', 1, cfg.lookPrices['glow']! - 1),
      ]) {
        expect(() => r.apply(s, a), throwsA(isA<IllegalAction>()), reason: '$a');
      }
      for (final j in [
        {'by': 'ai', 'op': 'load', 'upgrades': <String, Object?>{}, 'looks': <String, Object?>{}},
        {'by': 'player', 'op': 'sell'},
        {'by': 'player', 'op': 'upgrade', 'car': 'coupe', 'slot': 'engine', 'cash': 1.5},
        {'by': 'player', 'op': 'look', 'car': 'coupe', 'part': 'paint', 'value': '1', 'cash': 400},
        {
          'by': 'player',
          'op': 'load',
          'upgrades': {
            'coupe': {'engine': 1.5},
          },
          'looks': <String, Object?>{},
        },
        {
          'by': 'player',
          'op': 'load',
          'upgrades': {'coupe': 1},
          'looks': <String, Object?>{},
        },
        {'by': 'player', 'op': 'load', 'upgrades': <String, Object?>{}, 'looks': <Object?>[]},
        {'by': 'player', 'op': 'load', 'upgrades': <String, Object?>{}},
      ]) {
        expect(() => r.actionFromJson(j), throwsA(isA<IllegalAction>()), reason: jsonEncode(j));
      }
    });

    test('upgrade pays prices[slot][level]; back to stock look is free; zeros leave the state', () {
      final r = GarageRules();
      var s = r.start(cfg);
      for (var i = 0; i < cfg.maxLevel; i++) {
        s = r.apply(s, GarageAction.upgrade('coupe', 'tyres', cfg.prices['tyres']![i]));
        expect((s.level('coupe', 'tyres'), s.last), (i + 1, (op: 'upgrade', amount: cfg.prices['tyres']![i])));
      }
      s = r.apply(s, GarageAction.look('scooter', 'glow', 2, 5000));
      expect(s.last, (op: 'look', amount: cfg.lookPrices['glow']));
      s = r.apply(s, const GarageAction.look('scooter', 'glow', 0, 0));
      expect(s.last, (op: 'look', amount: 0));
      expect(s.toJson()['looks'], <String, Object?>{});
    });
  });

  group('GarageWorld and looks', () {
    test('load drops cars, slots and values out of range; buys only when possible', () {
      final w = GarageWorld(
        cfg,
        upgrades: const {
          'coupe': {'engine': 9, 'turbo': 1},
          'gone': {'engine': 1},
        },
        looks: const {
          'truck': {'paint': 99, 'wheels': 2},
        },
      );
      expect(w.levels('coupe'), {'engine': cfg.maxLevel});
      expect(w.looks('truck'), {'wheels': 2});
      expect(w.upgradePrice('coupe', 'engine'), isNull);
      expect(w.upgrade('coupe', 'engine', 1 << 20), isNull);
      expect(w.upgradePrice('scooter', 'engine'), isNull);
      expect(w.upgrade('truck', 'tyres', 0), isNull);
      expect(w.upgrade('truck', 'tyres', 1 << 20), cfg.prices['tyres']![0]);
      expect(w.setLook('truck', 'wheels', 2, 1 << 20), isNull, reason: 'already the current one');
      expect(w.setLook('truck', 'wheels', 0, 0), 0);
      expect(w.canLook('scooter', 'paint', 1, cfg.lookPrices['paint']! - 1), isFalse);
    });

    test('CarLook resolves colours from the tokens; 0 = catalog', () {
      expect(CarLook.of(null).paint, isNull);
      final l = CarLook.of(const {'paint': 3, 'decal': 2, 'wheels': 1, 'glow': 1, 'smoke': 2});
      expect(l.paint, Tokens.colorGaragePaints[2]);
      expect(l.decal, 2);
      expect(l.rim, Tokens.colorGarageWheels[1]);
      expect(l.glow, Tokens.colorGarageGlow[0]);
      expect(l.smoke, Tokens.colorGarageSmoke[1]);
      expect(CarLook.of(const {'paint': 99, 'decal': 7}).paint, isNull);
      expect(CarLook.of(const {'decal': 7}).decal, 0);
      expect(lookSwatch('paint', 0, 0xFF123456), 0xFF123456);
      expect(lookSwatch('wheels', 0, 0), Tokens.colorGarageWheels[0]);
      expect(lookSwatch('glow', 0, 0), isNull);
      expect(lookSwatch('decal', 1, 0), isNull);
    });

    test('effect percent of the next level = the slot step', () {
      final g = tuning.garage;
      expect(garageEffectPct(g, 'engine'), (g.enginePowerStep * 100).round());
      expect(garageEffectPct(g, 'weight'), (g.weightMassStep * 100).round());
      expect(garageEffectPct(g, 'drift'), (g.driftStep * 100).round());
    });
  });

  group('save v5 (specs/save.md v4)', () {
    final sc = SaveConfig.fromTuning(tuning, 'nyc', CarId.values.map((c) => c.id));
    final v4 = <String, Object?>{
      ...freshSave(sc),
      'version': 4,
      'cash': 300,
      'souvenirs': ['souvenir_soho'],
    }..remove('upgrades')..remove('looks');

    test('fresh save is version 5 with empty upgrades and looks; spec version 4', () {
      final s = freshSave(sc);
      expect(s['version'], 5);
      expect([s['upgrades'], s['looks']], [isEmpty, isEmpty]);
      expect(SaveRules().specVersion, 4);
    });

    test('migration 4 → 5 keeps everything and sets {} (even when a v4 save carries some)', () {
      final s = normalizeSave(sc, {
        ...v4,
        'upgrades': {
          'm0_coupe': {'engine': 1},
        },
      });
      expect([s['version'], s['cash'], s['souvenirs']], [5, 300, ['souvenir_soho']]);
      expect([s['upgrades'], s['looks']], [isEmpty, isEmpty]);
    });

    test('v5: negative → 0, sorted keys, unknown cars kept for garage load; bad shapes give a fresh save', () {
      final s = normalizeSave(sc, {
        ...v4,
        'version': 5,
        'upgrades': {
          'zz': {'engine': 1},
          'm0_coupe': {'tyres': -2, 'engine': 2},
        },
        'looks': {
          'm0_coupe': {'paint': 3.0},
        },
      });
      expect(jsonEncode(s['upgrades']), '{"m0_coupe":{"engine":2,"tyres":0},"zz":{"engine":1}}');
      expect(s['looks'], {
        'm0_coupe': {'paint': 3},
      });
      final fresh = canonical(freshSave(sc));
      for (final bad in [
        {'m0_coupe': 1},
        {
          'm0_coupe': {'paint': 1.5},
        },
        [1],
      ]) {
        expect(canonical(normalizeSave(sc, {...v4, 'version': 5, 'looks': bad})), fresh, reason: '$bad');
      }
    });

    test('round trip of upgrades and looks through JSON is exact', () {
      final s = composeSave(
        sc,
        const SaveParts(
          cash: 5,
          cars: ['m0_coupe'],
          car: 'm0_coupe',
          stamps: [],
          best: {},
          plays: {},
          upgrades: {
            'm0_coupe': {'tyres': 2, 'engine': 1},
          },
          looks: {
            'm0_coupe': {'glow': 1},
          },
        ),
      );
      final back = normalizeSave(sc, jsonDecode(jsonEncode(s)));
      expect(canonical(back), canonical(s));
      expect(saveOf(back).upgrades, {
        'm0_coupe': {'engine': 1, 'tyres': 2},
      });
    });
  });
}

Map<String, Object?> _json(GarageConfig c) => {
  'cars': c.cars,
  'maxLevel': c.maxLevel,
  'prices': c.prices,
  'parts': c.parts,
  'lookPrices': c.lookPrices,
};
