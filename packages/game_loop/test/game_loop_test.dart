import 'dart:convert';
import 'dart:io';

import 'package:game_loop/game_loop.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';
import 'package:shared_gen/shared_gen.dart';
import 'package:test/test.dart';

void main() {
  final tuning = Tuning.fromYaml(File('$repoRoot/content/tuning.yaml').readAsStringSync());

  test(
    'vectors/economy.json',
    () => expect(checkVectors(EconomyRules()), isEmpty),
    skip: !flutterDone('vectors/economy.json') ? 'pending in parity.yaml' : false,
  );
  test(
    'vectors/save.json',
    () => expect(checkVectors(SaveRules()), isEmpty),
    skip: !flutterDone('vectors/save.json') ? 'pending in parity.yaml' : false,
  );

  test('the three-star trip money equals the feed card reward', () {
    final r = EconomyRules()..start(EconomyConfig.fromTuning(tuning, 0));
    const driveDm = 26400;
    final f = tuning.feed;
    final card = f.rewardBase + (driveDm ~/ f.driveDmPerS) * f.rewardPerMin ~/ 60;
    expect(r.reward(engine: 'cards', stars: 3, score: 0, first: false, driveDm: driveDm, aborted: false).trip, card);
  });

  test('fines and tows never go below zero', () {
    final r = EconomyRules();
    var s = r.start(EconomyConfig.fromTuning(tuning, 10));
    s = r.apply(s, const EconomyAction.tow());
    expect(s.cash, 0);
    s = r.apply(s, const EconomyAction.fine(5));
    expect((s.cash, s.paid), (0, 10));
    expect(() => r.apply(s, const EconomyAction.fine(-1)), throwsA(isA<IllegalAction>()));
  });

  group('loop helpers (specs/loop.md)', () {
    test('difficulty follows the card or the plays', () {
      expect(loopDifficulty(4, 9, tuning.feed), 4);
      expect(loopDifficulty(null, 0, tuning.feed), tuning.feed.difficultyBase);
      expect(loopDifficulty(null, 99, tuning.feed), tuning.feed.difficultyMax);
    });
    test('opponent by fnv1a of the spot (same numbers as web/test/loop.test.ts)', () {
      expect([opponentIndex('east_village_bar', 6), opponentIndex('pier_62', 6), opponentIndex('x', 0)], [1, 0, -1]);
    });
    test('better best', () {
      expect(betterBest(null, 0, 0), isTrue);
      expect(betterBest((stars: 2, score: 10), 2, 11), isTrue);
      expect(betterBest((stars: 2, score: 10), 1, 99), isFalse);
      expect(betterBest((stars: 2, score: 10), 3, 0), isTrue);
    });
    test('spot in reach only while standing', () {
      const spots = [LoopSpot('a', 'dama', 0, 0), LoopSpot('g', '', 1, 1)];
      expect(spotInReach(spots, 3, 4, 0, 0, tuning.loop)?.id, 'a');
      expect(spotInReach(spots, 3, 4, 10, 0, tuning.loop), isNull);
      expect(spotInReach(spots, 3, 4, 0, 1, tuning.loop), isNull);
      expect(nearestSpot(spots, 1, 1, 0.5), isNull);
    });
  });

  group('save (specs/save.md)', () {
    final cfg = SaveConfig.fromTuning(tuning, 'nyc', CarId.values.map((c) => c.id));
    test('migrates version 1', () {
      final s = normalizeSave(cfg, {
        'version': 1,
        'cityId': 'nyc',
        'cash': 90,
        'stamps': ['minigame:oko'],
        'cars': ['taxi_metro'],
        'best': {
          'oko': {'stars': 3, 'score': 300},
        },
      });
      final typed = saveOf(s);
      expect((typed.version, typed.cash, typed.car, typed.best['oko']!.stars), (2, 90, 'taxi_metro', 3));
      expect(typed.cars, ['taxi_metro']);
    });
    test('a JSON round trip is exact', () {
      final s = freshSave(cfg);
      expect(canonical(normalizeSave(cfg, jsonDecode(jsonEncode(s)))), canonical(s));
      expect(canonical(saveOf(s).toJson()), canonical(s));
    });
    test('garbage gives a fresh save', () {
      expect(canonical(normalizeSave(cfg, 'x')), canonical(freshSave(cfg)));
      expect(canonical(normalizeSave(cfg, {'version': 9})), canonical(freshSave(cfg)));
    });
  });
}
