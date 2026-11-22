import 'dart:convert';
import 'dart:io';

import 'package:game_loop/game_loop.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';
import 'package:shared_gen/citypack_pb.dart' show Spot;
import 'package:shared_gen/shared_gen.dart';
import 'package:test/test.dart';

// specs/shops.md v1 (module shops) and specs/save.md v3 (save format 4, souvenirs).
void main() {
  final tuning = Tuning.fromYaml(File('$repoRoot/content/tuning.yaml').readAsStringSync());
  const cfg = ShopsConfig(
    snackPct: 25,
    beerLimit: 2,
    beerS: 3,
    snackS: 4,
    items: [
      (id: 'food_a', kind: 'food', price: 15),
      (id: 'souvenir_a', kind: 'souvenir', price: 120),
      (id: 'bar_a', kind: 'bar', price: 10),
    ],
  );

  group('shops vectors', () {
    test(
      'vectors/shops.json',
      () => expect(checkVectors(ShopsRules()), isEmpty),
      skip: !flutterDone('vectors/shops.json') ? 'pending in parity.yaml' : false,
    );
    test(
      'vectors/save.json',
      () => expect(checkVectors(SaveRules()), isEmpty),
      skip: !flutterDone('vectors/save.json') ? 'pending in parity.yaml' : false,
    );
  });

  group('shops rules (specs/shops.md)', () {
    test('id, spec version; init is empty and ignores the seed', () {
      final r = ShopsRules();
      expect((r.id, r.specVersion), ('shops', 1));
      final a = r.init(_json(cfg), 1), b = r.init(_json(cfg), 99);
      expect(r.stateToJson(a), r.stateToJson(b));
      expect(r.stateToJson(a), {
        'snackLeft': 0,
        'beers': 0,
        'beerLeft': 0,
        'drunk': false,
        'owned': <String>[],
        'last': {'op': '', 'amount': 0},
      });
      expect(r.result(a), isNull);
      expect(() => r.aiAction(a, 1, Prng(1)), throwsUnsupportedError);
    });

    test('config from tuning: prices by kind, items in venue order', () {
      final t = tuning.shops;
      final c = ShopsConfig.fromTuning(t, const [(id: 'f', kind: 'food'), (id: 's', kind: 'souvenir'), (id: 'b', kind: 'bar')]);
      expect([c.snackPct, c.beerLimit, c.beerS, c.snackS], [t.snackPct, t.beerLimit, t.beerS, t.snackS]);
      expect(c.items.map((i) => i.price), [t.priceFood, t.priceSouvenir, t.priceBeer]);
    });

    test('legalActions: load [], tick, finish 1★, reward 0, buy per item without owned souvenirs', () {
      final r = ShopsRules();
      var s = r.start(cfg);
      expect(r.legalActions(s).map((a) => a.toJson()['op']), ['load', 'tick', 'finish', 'reward', 'buy', 'buy', 'buy']);
      s = r.apply(s, const ShopsAction.buy('souvenir_a', 500));
      final buys = r.legalActions(s).where((a) => a.op == 'buy').map((a) => (a.shop, a.cash));
      expect(buys, [('food_a', 15), ('bar_a', 10)]);
    });

    test('illegal: unknown shop, short or negative cash, owned souvenir, bad reward / finish, wrong JSON', () {
      final r = ShopsRules();
      var s = r.start(cfg);
      s = r.apply(s, const ShopsAction.buy('souvenir_a', 120));
      for (final a in [
        const ShopsAction.buy('nope', 100),
        const ShopsAction.buy('food_a', 14),
        const ShopsAction.buy('food_a', -1),
        const ShopsAction.buy('souvenir_a', 500),
        const ShopsAction.reward(-1),
        const ShopsAction.finish(4, false),
        const ShopsAction.finish(-1, false),
      ]) {
        expect(() => r.apply(s, a), throwsA(isA<IllegalAction>()), reason: '$a');
      }
      for (final j in [
        {'by': 'ai', 'op': 'tick'},
        {'by': 'player', 'op': 'fly'},
        {'by': 'player', 'op': 'buy', 'shop': 'food_a', 'cash': 1.5},
        {'by': 'player', 'op': 'load', 'owned': [1]},
        {'by': 'player', 'op': 'finish', 'stars': 1, 'aborted': 'no'},
        {'by': 'player', 'op': 'reward'},
      ]) {
        expect(() => r.actionFromJson(j), throwsA(isA<IllegalAction>()), reason: jsonEncode(j));
      }
    });

    test('snack bonus once, floor division; beers wear off; drunk until a won loop', () {
      final r = ShopsRules();
      var s = r.apply(r.start(cfg), const ShopsAction.buy('food_a', 15));
      s = r.apply(s, const ShopsAction.reward(99));
      expect((s.last.op, s.last.amount, s.snackLeft), ('reward', 24, 0));
      s = r.apply(s, const ShopsAction.reward(99));
      expect(s.last.amount, 0);
      for (var i = 0; i < 3; i++) {
        s = r.apply(s, const ShopsAction.buy('bar_a', 10));
      }
      expect((s.beers, s.drunk), (3, true));
      s = r.apply(s, const ShopsAction.tick());
      expect((s.beers, s.beerLeft), (3, 3));
      s = r.apply(s, const ShopsAction.finish(3, true));
      expect(s.drunk, isTrue);
      s = r.apply(s, const ShopsAction.finish(0, false));
      expect(s.drunk, isTrue);
      s = r.apply(s, const ShopsAction.finish(1, false));
      expect((s.drunk, s.beers, s.beerLeft, s.last), (false, 0, 0, noShopsLast));
    });
  });

  // ---------- in the world: a synthetic city on the x axis
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
    spot('bar_1', 'bar', -100, 'oko'),
    spot('food_1', 'food', 0),
    spot('park', 'park', 50, 'dama'),
    spot('souv_1', 'souvenir', 100),
    spot('bar_2', 'bar', 200),
    spot('bar_3', 'bar', 300, 'sipky'),
    spot('bar_4', 'bar', 400, 'oko'),
    spot('bar_5', 'bar', 500, 'nope'),
  ];

  group('shops in the world', () {
    test('venues in spots.pb order; bar games distinct, catalog only, spot order', () {
      final shops = shopsOf(spots);
      expect(shops.map((s) => s.id), ['bar_1', 'food_1', 'souv_1', 'bar_2', 'bar_3', 'bar_4', 'bar_5']);
      expect((shops[2].x, shops[2].kind), (100.0, 'souvenir'));
      expect(barGames(shops, const ['oko', 'sipky', 'dama']), ['oko', 'sipky']);
    });

    test('module on: enabled, the city flag and venues', () {
      final t = Tuning.fromYaml(File('$repoRoot/content/tuning.yaml').readAsStringSync()).shops;
      expect(shopsOn(t, 'nyc', 3), t.enabled && t.cities.nyc);
      expect(shopsOn(t, 'nyc', 0), isFalse);
      expect(shopsOn(t, 'atlantis', 3), isFalse);
      t.enabled = false;
      expect(shopsOn(t, 'nyc', 3), isFalse);
    });

    test('reach = the "Hrát" conditions', () {
      final s = shopsOf(spots)[1];
      final l = tuning.loop;
      expect(shopInReach(s, 0, 0, 0, 0, l), isTrue);
      expect(shopInReach(s, l.spotRadiusM, 0, 0, 0, l), isTrue);
      expect(shopInReach(s, l.spotRadiusM + 0.1, 0, 0, 0, l), isFalse);
      expect(shopInReach(s, 0, 0, l.stopSpeedMps + 0.1, 0, l), isFalse);
      expect(shopInReach(s, 0, 0, 0, 1, l), isFalse);
    });

    test('ShopWorld: load drops unknown, game seconds tick, buy only when possible', () {
      final w = ShopWorld(shopsOf(spots), tuning.shops, owned: const ['souv_1', 'gone', 'food_1']);
      expect(w.owned, ['souv_1']);
      expect(w.canBuy('souv_1', 1 << 20), isFalse);
      expect(w.buy('food_1', 0), 0);
      expect(w.snack, isFalse);
      expect(w.buy('food_1', 1000), tuning.shops.priceFood);
      expect(w.snack, isTrue);
      w.update(tuning.shops.snackS - 0.5);
      expect(w.snack, isTrue);
      w.update(0.5);
      expect(w.snack, isFalse);
      var sober = 0;
      w.onSober.add(() => sober++);
      for (var i = 0; i <= tuning.shops.beerLimit; i++) {
        w.buy('bar_2', 1000);
      }
      expect(w.drunk, isTrue);
      w.finish(0, false);
      expect((w.drunk, sober), (true, 0));
      w.finish(2, false);
      expect((w.drunk, sober), (false, 1));
    });
  });

  group('the loop pays the snack bonus (specs/shops.md "Hotovost")', () {
    test('bonus = reward × snackPct ÷ 100 added to the cash; finish sobers', () {
      final cash = [0];
      final book = LoopBook(tuning, LoopPorts(getCash: () => cash[0], setCash: (v) => cash[0] = v, stamp: (_, _) => false));
      final w = ShopWorld(shopsOf(spots), tuning.shops);
      book
        ..snack = w.reward
        ..shopsFinish = w.finish;
      w.buy('food_1', 1000);
      for (var i = 0; i <= tuning.shops.beerLimit; i++) {
        w.buy('bar_2', 1000);
      }
      final o = book.finish(
        spot: 'bar_1',
        minigame: 'oko',
        engine: 'cards',
        result: MinigameResult(stars: 3, score: 100, playedMs: 1000, aborted: false),
        driveDm: 0,
        hasStamp: (_) => false,
      );
      expect(o.cash.amount, greaterThan(0));
      expect(o.snack, o.cash.amount * tuning.shops.snackPct ~/ 100);
      expect(o.total, o.cash.amount + o.snack);
      expect(w.drunk, isFalse);
      expect(w.snack, isFalse);
    });
  });

  group('save v4 (specs/save.md v3)', () {
    final sc = SaveConfig.fromTuning(tuning, 'nyc', CarId.values.map((c) => c.id));
    test('fresh save is version 4 with no souvenirs; spec version 3', () {
      final s = freshSave(sc);
      expect(s['version'], 4);
      expect(s['souvenirs'], isEmpty);
      expect(SaveRules().specVersion, 3);
    });

    test('round trip of souvenirs through JSON is exact', () {
      final s = composeSave(
        sc,
        const SaveParts(
          cash: 5,
          cars: ['m0_coupe'],
          car: 'm0_coupe',
          stamps: [],
          best: {},
          plays: {},
          souvenirs: ['souvenir_canal', 'souvenir_soho', 'souvenir_canal'],
        ),
      );
      expect(s['souvenirs'], ['souvenir_canal', 'souvenir_soho']);
      final back = normalizeSave(sc, jsonDecode(jsonEncode(s)));
      expect(canonical(back), canonical(s));
      expect(saveOf(back).souvenirs, ['souvenir_canal', 'souvenir_soho']);
    });
  });
}

Map<String, Object?> _json(ShopsConfig c) => {
  'snackPct': c.snackPct,
  'beerLimit': c.beerLimit,
  'beerS': c.beerS,
  'snackS': c.snackS,
  'items': [
    for (final i in c.items) {'id': i.id, 'kind': i.kind, 'price': i.price},
  ],
};
