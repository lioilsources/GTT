// Soak test for acceptance M1-A1 ("10 smyček za sebou bez pádu a bez zaseknutí", specs/loop.md):
// feed → minigame rules with scripted moves → loop result → save → load, over the pure modules.
// Mirrors web/test/loop.test.ts.
import 'dart:io';

import 'package:drive_core/drive_core.dart';
import 'package:feed_hub/feed_hub.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_loop/game_loop.dart';
import 'package:meta_progress/meta_progress.dart';
import 'package:metropole/loop/save_store.dart';
import 'package:mg_dama/mg_dama.dart';
import 'package:mg_desetitisic/mg_desetitisic.dart';
import 'package:mg_koulena/mg_koulena.dart';
import 'package:mg_oko/mg_oko.dart';
import 'package:mg_sipky/mg_sipky.dart';
import 'package:mg_sirky/mg_sirky.dart';
import 'package:mg_strelnice/mg_strelnice.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// Scripted play through the pure rules: the AI moves for both sides (sipky aims like the AI).
Map<String, Object?> playOut<S, A, R>(
  MgRules<S, A, R> rules,
  S Function(int seed) init,
  Map<String, Object?> Function(A) json,
  String id,
  int seed,
  int level,
) {
  final ai = aiPrng(seed);
  final me = aiPrng(seed ^ 0x1234);
  var s = init(seed);
  for (var i = 0; i < 20000; i++) {
    final r = rules.result(s);
    if (r != null) return rules.resultToJson(r);
    final legal = rules.legalActions(s);
    A a;
    if (id == 'sipky') {
      final j = rules.stateToJson(s);
      if (j['turn'] == 'player') {
        final (x, y) = sipkyAiTarget(j['player'] as int);
        a = rules.actionFromJson({'by': 'player', 'x': x, 'y': y});
      } else {
        a = rules.aiAction(s, level, ai);
      }
    } else if (legal.isEmpty || json(legal.first)['by'] == 'ai') {
      a = rules.aiAction(s, level, ai);
    } else {
      final want = rules.aiAction(s, 5, me);
      final w = canonical(json(want));
      a = legal.any((x) => canonical(json(x)) == w) ? want : legal.first;
    }
    s = rules.apply(s, a);
  }
  final end = rules.result(rules.apply(s, rules.actionFromJson({'by': 'timeout'})));
  if (end == null) throw StateError('$id: no result after timeout');
  return rules.resultToJson(end);
}

void main() {
  final tuning = Tuning.fromYaml(File('../content/tuning.yaml').readAsStringSync());
  final m = tuning.minigames;
  final games = <String, Map<String, Object?> Function(int seed, int level)>{
    'sirky': (s, l) {
      final r = SirkyRules();
      return playOut(r, (seed) => r.start(SirkyConfig.fromTuning(m.sirky), seed), (a) => a.toJson(), 'sirky', s, l);
    },
    'oko': (s, l) {
      final r = OkoRules();
      return playOut(r, (seed) => r.start(OkoConfig.fromTuning(m.oko), seed), (a) => a.toJson(), 'oko', s, l);
    },
    'dama': (s, l) {
      final r = DamaRules();
      return playOut(r, (seed) => r.start(DamaConfig.fromTuning(m.dama), seed), (a) => a.toJson(), 'dama', s, l);
    },
    'desetitisic': (s, l) {
      final r = DesetitisicRules();
      return playOut(
        r,
        (seed) => r.start(DesetitisicConfig.fromTuning(m.desetitisic), seed),
        (a) => a.toJson(),
        'desetitisic',
        s,
        l,
      );
    },
    'sipky': (s, l) {
      final r = SipkyRules();
      return playOut(r, (seed) => r.start(SipkyConfig.fromTuning(m.sipky), seed), (a) => a.toJson(), 'sipky', s, l);
    },
    'koulena': (s, l) {
      final r = KoulenaRules();
      return playOut(
        r,
        (seed) => r.start(KoulenaConfig.fromTuning(m.koulena), seed),
        (a) => a.toJson(),
        'koulena',
        s,
        l,
      );
    },
    'strelnice': (s, l) {
      final r = StrelniceRules();
      return playOut(
        r,
        (seed) => r.start(StrelniceConfig.fromTuning(m.strelnice), seed),
        (a) => a.toJson(),
        'strelnice',
        s,
        l,
      );
    },
  };

  const spotGames = {
    'east_village_bar': 'sirky',
    'little_italy_club': 'oko',
    'washington_square': 'dama',
    'columbus_park': 'desetitisic',
    'hells_kitchen_pub': 'sipky',
    'pier_62': 'strelnice',
    'seaport_boardwalk': 'koulena',
    'penn_taxi_stand': 'taxi',
    'midtown_garage': '',
  };
  final spotIds = spotGames.keys.toList();
  final spots = [
    for (var i = 0; i < spotIds.length; i++) CandidateSpot(spotIds[i], spotGames[spotIds[i]]!, i * 1000, 500),
  ];
  final passportCity = PassportCity(
    landmarks: const [],
    districts: const ['SoHo'],
    spotMinigames: spotGames.values.toList(),
  );

  test('10 loops in a row stay consistent through feed → minigame → result → save → load', () async {
    const prices = {
      'hatch_pip': 6000,
      'm0_coupe': 0,
      'muscle_brute': 30000,
      'pickup_hauler': 18000,
      'taxi_metro': 15000,
    };
    final carsRules = CarsRules();
    var cars = carsRules.start(CarsConfig.fromTuning(tuning.cars, prices));
    final passport = PassportTracker(passportCity, tuning.passport);
    final book = LoopBook(
      tuning,
      LoopPorts(
        getCash: () => cars.cash,
        setCash: (c) => cars = cars.copyWith(cash: c),
        stamp: passport.minigame,
      ),
    );
    final cfg = SaveConfig.fromTuning(tuning, 'nyc', CarId.values.map((c) => c.id));
    final store = MemorySaveStore();
    final feed = FeedRules();
    var prefs = <String, int>{};
    final visits = <String, int>{};
    var paid = 0;
    final threeStar = <String>{};
    final bestSeen = <String, BestScore>{};

    for (var loop = 0; loop < 10; loop++) {
      final candidates = buildCandidates(
        cityId: 'nyc',
        spots: spots,
        catalog: {for (final e in minigameCatalog.entries) e.key.id: e.value},
        districtAt: (_, _) => '',
        landmarks: const [],
        discovered: const {},
        visits: visits,
        landmarkRadiusDm: tuning.feed.landmarkRadiusDm,
        distDm: (id) => 5000 + 700 * spotIds.indexOf(id),
      );
      var deck = feed.deal(FeedConfig.fromTuning(tuning.feed, candidates, prefs, const []), 100 + loop);
      while (!deck.over && !games.containsKey(deck.deck[deck.at].game)) {
        deck = feed.apply(deck, FeedOp.next);
      }
      expect(deck.over, isFalse);
      deck = feed.apply(deck, FeedOp.accept);
      prefs = deck.prefs;
      final card = deck.deck.firstWhere((c) => c.spot == deck.accepted);
      visits[card.spot] = (visits[card.spot] ?? 0) + 1;
      final game = spotGames[card.spot]!;
      final level = loopDifficulty(card.difficulty, book.plays[card.spot] ?? 0, tuning.feed);
      final aborted = loop == 4;
      final r = games[game]!(7 + loop * 31, level);
      final result = aborted
          ? MinigameResult(stars: 0, score: 0, playedMs: 1, aborted: true)
          : MinigameResult(stars: r['stars'] as int, score: r['score'] as int, playedMs: 1000, aborted: false);
      final before = cars.cash;
      final o = book.finish(
        spot: card.spot,
        minigame: game,
        engine: minigameCatalog[MinigameId.values.firstWhere((x) => x.id == game)]!.engine,
        result: result,
        driveDm: card.distDm,
        hasStamp: (id) => passport.has('minigame', id),
      );
      expect(cars.cash - before, o.cash.amount);
      expect(o.cash.amount, o.cash.base + o.cash.trip + o.cash.band + o.cash.first);
      if (aborted) expect(o.cash.amount, 0);
      paid += o.cash.amount;
      if (!aborted) {
        if (result.stars >= tuning.passport.starsForStamp) threeStar.add(game);
        if (betterBest(bestSeen[game], result.stars, result.score)) {
          bestSeen[game] = (stars: result.stars, score: result.score);
        }
      }

      // Save → load round trip.
      final snap = composeSave(
        cfg,
        SaveParts(
          cash: cars.cash,
          cars: cars.owned,
          car: cars.driving,
          stamps: passport.stamps,
          best: book.best,
          plays: book.plays,
          feed: (prefs: prefs, visits: {...visits}, districts: const []),
          npc: (vibe: {'mia': loop}, contacts: const [], recent: const []),
          settings: (scheme: 'b', night: loop.isOdd),
        ),
      );
      await store.write('nyc', snap);
      final loaded = normalizeSave(cfg, await store.read('nyc'));
      expect(canonical(loaded), canonical(snap));
      final s = saveOf(loaded);
      final cars2 = carsRules.start(CarsConfig(prices: prices, cash: s.cash, owned: s.cars, driving: s.car));
      final passport2 = PassportTracker(passportCity, tuning.passport)..restore(s.stamps);
      final book2 = LoopBook(tuning, LoopPorts(getCash: () => cars2.cash, setCash: (_) {}, stamp: (_, _) => false))
        ..restore({for (final e in s.best.entries) e.key: (stars: e.value.stars, score: e.value.score)}, s.plays);
      final again = composeSave(
        cfg,
        SaveParts(
          cash: cars2.cash,
          cars: cars2.owned,
          car: cars2.driving,
          stamps: passport2.stamps,
          best: book2.best,
          plays: book2.plays,
          feed: (prefs: s.feed.prefs, visits: s.feed.visits, districts: s.feed.districts),
          npc: (vibe: s.npc.vibe, contacts: s.npc.contacts, recent: s.npc.recent),
          settings: (scheme: s.settings.scheme, night: s.settings.night),
        ),
      );
      expect(canonical(again), canonical(snap));
    }

    expect(cars.cash, tuning.cars.startCash + paid);
    expect(
      (passport.stamps.where((x) => x.startsWith('minigame:')).toList()..sort()),
      ([for (final g in threeStar) 'minigame:$g']..sort()),
    );
    expect(book.best.keys.toSet(), bestSeen.keys.toSet());
    for (final e in bestSeen.entries) {
      expect(book.best[e.key], e.value);
    }
    expect(book.plays.values.fold(0, (a, b) => a + b), 9);
    expect(paid, greaterThan(0));
    expect(threeStar, isNotEmpty);
    final buy = carsRules.buyable(cars).firstOrNull;
    if (buy != null) expect(carsRules.apply(cars, CarsAction.buy(buy)).cash, cars.cash - prices[buy]!);
  });
}
