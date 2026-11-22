import 'dart:convert';
import 'dart:io';

import 'package:game_loop/game_loop.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';
import 'package:shared_gen/citypack_pb.dart' show Spot;
import 'package:shared_gen/shared_gen.dart';
import 'package:test/test.dart';

// Port of web/test/fastTravel.test.ts (specs/travel.md, specs/save.md v2): rules, the pure world
// part and save v3. The road projection of landmarks and the move are tested in the app.
void main() {
  final tuning = Tuning.fromYaml(File('$repoRoot/content/tuning.yaml').readAsStringSync());
  const cfg = TravelConfig(stations: ['a', 'b', 'c'], fareBase: 30, farePerKm: 4, taxiBase: 60, taxiPerKm: 25);

  group('travel vectors', () {
    test(
      'vectors/travel.json',
      () => expect(checkVectors(TravelRules()), isEmpty),
      skip: !flutterDone('vectors/travel.json') ? 'pending in parity.yaml' : false,
    );
  });

  group('travel rules (specs/travel.md)', () {
    test('fares: base + distDm × perKm ÷ 10000, integer division', () {
      expect(metroFare(cfg, 0), 30);
      expect(metroFare(cfg, 24999), 39);
      expect(metroFare(cfg, 25000), 40);
      expect(taxiFare(cfg, 0), 60);
      expect(taxiFare(cfg, 42345), 165);
      expect(
        metroFare(const TravelConfig(stations: [], fareBase: 0, farePerKm: 4, taxiBase: 0, taxiPerKm: 0), 2499),
        0,
      );
    });

    test('distDm: floor(sqrt) of rounded whole dm', () {
      expect(travelDistDm(0, 0, 3, 4), 50);
      expect(travelDistDm(0.04, 0, 0.16, 0), 2); // 0 dm → 2 dm
      expect(travelDistDm(0, 0, 1, 1), 14);
    });

    test('config from tuning', () {
      final t = tuning.travel;
      expect(TravelConfig.fromTuning(t, ['x']).toJson(), {
        'stations': ['x'],
        'fareBase': t.fareBase,
        'farePerKm': t.farePerKm,
        'taxiBase': t.taxiBase,
        'taxiPerKm': t.taxiPerKm,
      });
    });

    test('init, load (unknown and duplicates drop), unlock, legalActions', () {
      final r = TravelRules();
      var s = r.init(cfg.toJson(), 5);
      expect(s.toJson(), {
        'unlocked': <String>[],
        'paid': 0,
        'last': {'op': '', 'amount': 0},
      });
      s = r.apply(s, const TravelAction.load(['c', 'zz', 'a', 'c']));
      expect(s.unlocked, ['c', 'a']);
      expect(r.legalActions(s), [const TravelAction.load([]), const TravelAction.unlock('b')]);
      s = r.apply(s, const TravelAction.unlock('b'));
      expect(s.unlocked, ['c', 'a', 'b']);
      expect(r.apply(s, const TravelAction.unlock('a')).unlocked, ['c', 'a', 'b']);
      expect(r.result(s), isNull);
    });

    test('metro and taxi pay into paid/last; the next free action clears last', () {
      final r = TravelRules();
      var s = r.apply(r.start(cfg), const TravelAction.load(['a', 'b']));
      s = r.apply(s, const TravelAction.metro('a', 'b', 25000, 40));
      expect((s.paid, s.last), (40, (op: 'metro', amount: 40)));
      s = r.apply(s, const TravelAction.taxi(0, 60));
      expect((s.paid, s.last), (100, (op: 'taxi', amount: 60)));
      s = r.apply(s, const TravelAction.unlock('c'));
      expect(s.last, noTravelLast);
      expect(s.paid, 100);
    });

    test('illegal: unknown station, locked or equal ends, negative values, short cash, unknown op, by ≠ player', () {
      final r = TravelRules();
      final s = r.apply(r.start(cfg), const TravelAction.load(['a', 'b']));
      final bad = <Map<String, Object?>>[
        {'by': 'player', 'op': 'unlock', 'station': 'zz'},
        {'by': 'player', 'op': 'metro', 'from': 'a', 'to': 'c', 'distDm': 10, 'cash': 100},
        {'by': 'player', 'op': 'metro', 'from': 'a', 'to': 'a', 'distDm': 10, 'cash': 100},
        {'by': 'player', 'op': 'metro', 'from': 'a', 'to': 'b', 'distDm': -1, 'cash': 100},
        {'by': 'player', 'op': 'metro', 'from': 'a', 'to': 'b', 'distDm': 10, 'cash': -1},
        {'by': 'player', 'op': 'metro', 'from': 'a', 'to': 'b', 'distDm': 0, 'cash': 29},
        {'by': 'player', 'op': 'taxi', 'distDm': 0, 'cash': 59},
        {'by': 'player', 'op': 'taxi', 'distDm': -5, 'cash': 1000},
        {'by': 'player', 'op': 'taxi', 'distDm': 1.5, 'cash': 1000},
        {'by': 'player', 'op': 'fly'},
        {'by': 'ai', 'op': 'taxi', 'distDm': 0, 'cash': 1000},
      ];
      for (final a in bad) {
        expect(() => r.apply(s, r.actionFromJson(a)), throwsA(isA<IllegalAction>()), reason: jsonEncode(a));
      }
    });

    test('ids and spec versions: travel 1, save 3', () {
      expect((TravelRules().id, TravelRules().specVersion), ('travel', 1));
      expect(SaveRules().specVersion, 3);
    });
  });

  // ---------- the pure world part: three stations and two minigame spots on the x axis
  Spot spot(String id, String kind, int x, [String minigame = '']) => Spot(
    id: id,
    kind: kind,
    name: '$id name',
    x: x * 10,
    y: 0,
    parkX: x * 10,
    parkY: 0,
    parkHeading: 0,
    minigame: minigame,
  );
  final spots = [
    spot('st_w', 'subway', -300),
    spot('bar', 'bar', -100, 'oko'),
    spot('st_c', 'subway', 100),
    spot('pier', 'pier', 200, 'sipky'),
    spot('garage', 'garage', 250),
    spot('st_e', 'subway', 500),
  ];
  final tr = tuning.travel;
  ({int Function() get, void Function(int) set, List<int> cash}) wallet(int c) {
    final w = [c];
    return (get: () => w[0], set: (v) => w[0] = v, cash: w);
  }

  TravelWorld world(({int Function() get, void Function(int) set, List<int> cash}) w) =>
      TravelWorld(stationsOf(spots), tuning, getCash: w.get, setCash: w.set);

  group('fast travel in the world (specs/travel.md P1)', () {
    test('stations = subway spots in spots.pb order', () {
      final st = stationsOf(spots);
      expect(st.map((s) => s.id), ['st_w', 'st_c', 'st_e']);
      expect((st[1].x, st[1].y, st[1].name), (100.0, 0.0, 'st_c name'));
    });

    test('unlock by passing: layer 0 within travel.unlock_m, once; already unlocked stays', () {
      final w = world(wallet(0));
      expect(w.pass(100 + tr.unlockM + 1, 0, 0, tr.unlockM), isEmpty);
      expect(w.pass(100 + tr.unlockM - 1, 0, 1, tr.unlockM), isEmpty);
      expect(w.pass(100 + tr.unlockM - 1, 0, 0, tr.unlockM).map((s) => s.id), ['st_c']);
      expect(w.pass(100, 0, 0, tr.unlockM), isEmpty);
      expect(w.pass(-300, 0, 0, tr.unlockM).map((s) => s.id), ['st_w']);
      expect(w.unlocked, ['st_c', 'st_w']);
      // The save loads back through `load` (unknown stations drop).
      final w2 = world(wallet(0))..load(['st_w', 'gone', 'st_w']);
      expect(w2.unlocked, ['st_w']);
    });

    test('"Metro": only at an unlocked station with the "Hrát" conditions', () {
      final l = tuning.loop;
      final w = world(wallet(0));
      expect(w.stationAt(100, 0, 0, 0, l), isNull); // locked
      w.load(['st_c']);
      expect(w.stationAt(100 + l.spotRadiusM - 1, 0, 0, 0, l)?.id, 'st_c');
      expect(w.stationAt(100 + l.spotRadiusM + 1, 0, 0, 0, l), isNull);
      expect(w.stationAt(100, 0, l.stopSpeedMps + 0.1, 0, l), isNull);
      expect(w.stationAt(100, 0, 0, 1, l), isNull);
      expect(stationInReach(w.station('st_c')!, 100, 0, 0, 0, l), isTrue);
    });

    test('metro card: other unlocked stations in unlock order with fares, short cash greyed', () {
      final cash = wallet(0);
      final w = world(cash)..load(['st_e', 'st_c', 'st_w']);
      final fe = metroFare(w.config, 4000), fw = metroFare(w.config, 4000);
      cash.cash[0] = fe < fw ? fe : fw;
      final ch = w.metroChoices('st_c');
      expect([for (final c in ch) (c.point.id, c.distDm, c.fare)], [('st_e', 4000, fe), ('st_w', 4000, fw)]);
      expect(ch.every((c) => c.affordable), isTrue);
      cash.cash[0] = fe - 1;
      expect(w.metroChoices('st_c').map((c) => c.affordable), [false, false]);
      expect(w.anyLocked, isFalse);
      expect((world(wallet(0))..load(['st_c'])).anyLocked, isTrue);
    });

    test('metro and taxi take the fare from the cars-state cash; not enough = null, cash unchanged', () {
      final cash = wallet(1000);
      final w = world(cash)..load(['st_w', 'st_e']);
      final fare = metroFare(w.config, 8000);
      expect(w.metro('st_w', 'st_e'), fare);
      expect(cash.cash[0], 1000 - fare);
      expect(w.metro('st_w', 'st_c'), isNull); // locked
      cash.cash[0] = fare - 1;
      expect(w.metro('st_e', 'st_w'), isNull);
      expect(cash.cash[0], fare - 1);
      cash.cash[0] = 500;
      expect(w.taxi(1234), taxiFare(w.config, 1234));
      expect(cash.cash[0], 500 - taxiFare(w.config, 1234));
    });

    test('taxi spot targets: spots with a catalog minigame in spots.pb order', () {
      final catalog = {for (final e in minigameCatalog.entries) e.key.id: e.value};
      expect(taxiSpotTargets(spots, catalog).map((t) => '${t.kind.name}:${t.id}'), ['spot:bar', 'spot:pier']);
      expect(taxiSpotTargets([spot('x', 'bar', 0, 'nope')], catalog), isEmpty);
    });

    test('taxi list: sorted by distance from the car, fare per target, short cash greyed; ties keep the order', () {
      final c = TravelConfig.fromTuning(tuning.travel, const []);
      const tg = [
        TaxiTarget(kind: TaxiTargetKind.spot, id: 'bar', name: 'bar', x: -100, y: 0, heading: 0),
        TaxiTarget(kind: TaxiTargetKind.spot, id: 'pier', name: 'pier', x: 200, y: 0, heading: 0),
        TaxiTarget(kind: TaxiTargetKind.landmark, id: 'tower', name: 'tower', x: 30, y: 0, heading: 0),
      ];
      final list = taxiChoices(tg, 150, 0, taxiFare(c, 1200), c);
      expect(list.map((x) => x.point.id), ['pier', 'tower', 'bar']);
      expect(list.map((x) => x.distDm), [500, 1200, 2500]);
      expect(list.map((x) => x.fare), [taxiFare(c, 500), taxiFare(c, 1200), taxiFare(c, 2500)]);
      expect(list.map((x) => x.affordable), [true, true, taxiFare(c, 2500) <= taxiFare(c, 1200)]);
      final tie = taxiChoices(
        const [
          TravelPoint(id: 'x', name: 'x', x: 10, y: 0, heading: 0),
          TravelPoint(id: 'y', name: 'y', x: -10, y: 0, heading: 0),
        ],
        0,
        0,
        0,
        c,
      );
      expect(tie.map((x) => x.point.id), ['x', 'y']);
      expect(tie.every((x) => !x.affordable || x.fare == 0), isTrue);
    });

    test('not offered while wanted, during a minigame or the Taxi shift', () {
      expect(travelOffered(busy: false, inWorldGame: false, wanted: 0), isTrue);
      expect(travelOffered(busy: false, inWorldGame: false, wanted: 1), isFalse);
      expect(travelOffered(busy: true, inWorldGame: false, wanted: 0), isFalse);
      expect(travelOffered(busy: false, inWorldGame: true, wanted: 0), isFalse);
    });
  });

  group('save stations (specs/save.md v2, format 4 since v3)', () {
    final sc = SaveConfig.fromTuning(tuning, 'nyc', CarId.values.map((c) => c.id));
    final v2 = <String, Object?>{
      'version': 2,
      'cityId': 'nyc',
      'cash': 300,
      'cars': ['m0_coupe'],
      'car': 'm0_coupe',
      'stamps': <String>[],
      'best': <String, Object?>{},
      'plays': <String, Object?>{},
      'feed': {'prefs': <String, Object?>{}, 'visits': <String, Object?>{}, 'districts': <String>[]},
      'npc': {'vibe': <String, Object?>{}, 'contacts': <String>[], 'recent': <String>[]},
      'settings': {'scheme': 'b', 'night': false},
    };
    String fresh() => canonical(freshSave(sc));

    test('fresh save is version 4 with no stations', () {
      final s = freshSave(sc);
      expect(s['version'], 4);
      expect(s['stations'], isEmpty);
    });

    test('migration 2 → 3: everything kept, stations = [] (even when a v2 save carries some)', () {
      final s = normalizeSave(sc, v2);
      expect(s['version'], 4);
      expect([s['cash'], (s['settings'] as Map)['scheme'], s['stations']], [300, 'b', <String>[]]);
      expect(
        normalizeSave(sc, {
          ...v2,
          'stations': ['subway_times_sq'],
        })['stations'],
        <String>[],
      );
    });

    test('v3: stations without duplicates (first occurrence), missing = [], wrong type = fresh', () {
      expect(
        normalizeSave(sc, {
          ...v2,
          'version': 3,
          'stations': ['b', 'a', 'b'],
        })['stations'],
        ['b', 'a'],
      );
      expect(normalizeSave(sc, {...v2, 'version': 3})['stations'], <String>[]);
      expect(
        canonical(
          normalizeSave(sc, {
            ...v2,
            'version': 3,
            'stations': [1],
          }),
        ),
        fresh(),
      );
      expect(canonical(normalizeSave(sc, {...v2, 'version': 3, 'stations': 'a'})), fresh());
      expect(canonical(normalizeSave(sc, {...v2, 'version': 5})), fresh());
    });

    test('round trip of a v3 save through JSON is exact', () {
      final s = composeSave(
        sc,
        const SaveParts(
          cash: 77,
          cars: ['m0_coupe'],
          car: 'm0_coupe',
          stamps: ['district:soho'],
          best: {},
          plays: {'x': 1},
          stations: ['subway_fulton', 'subway_w4'],
        ),
      );
      final back = normalizeSave(sc, jsonDecode(jsonEncode(s)));
      expect(canonical(back), canonical(s));
      expect(back['stations'], ['subway_fulton', 'subway_w4']);
      expect(saveOf(back).stations, ['subway_fulton', 'subway_w4']);
      expect(canonical(saveOf(back).toJson()), canonical(s));
    });
  });
}
