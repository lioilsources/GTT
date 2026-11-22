import 'dart:io';

import 'package:game_loop/game_loop.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';
import 'package:shared_gen/citypack_pb.dart' show Spot;
import 'package:shared_gen/shared_gen.dart';
import 'package:test/test.dart';

// Port of web/test/booths.test.ts (specs/booths.md).
void main() {
  final tuning = Tuning.fromYaml(File('$repoRoot/content/tuning.yaml').readAsStringSync());
  const cfg = BoothsConfig(booths: 3, gapMin: 2, gapMax: 4, retry: 2, ringS: 3, bonus: 150, games: ['a', 'b']);
  BoothsAction tick(List<int> near) => BoothsAction.tick(near);

  /// Ticks with [near] until a booth rings (at most [n] ticks).
  BoothsState ringUp(BoothsRules r, BoothsState s, List<int> near, [int n = 50]) {
    for (var i = 0; i < n && s.ringing < 0; i++) {
      s = r.apply(s, tick(near));
    }
    return s;
  }

  group('booths vectors', () {
    test(
      'vectors/booths.json',
      () => expect(checkVectors(BoothsRules()), isEmpty),
      skip: !flutterDone('vectors/booths.json') ? 'pending in parity.yaml' : false,
    );
  });

  group('booths rules (specs/booths.md)', () {
    test('init: silence, a gap in [gapMin, gapMax], no offer', () {
      final r = BoothsRules();
      for (var seed = 0; seed < 40; seed++) {
        final s = r.start(cfg, seed);
        expect(s.ringing, -1);
        expect(s.next, inInclusiveRange(cfg.gapMin, cfg.gapMax));
        expect(s.offer, noBoothOffer);
        expect([s.left, s.answered, s.missed, s.paid, s.last], [0, 0, 0, 0, 0]);
      }
    });

    test('config from tuning', () {
      final b = tuning.booths;
      final c = BoothsConfig.fromTuning(b, 5, ['x']);
      expect(
        [c.booths, c.gapMin, c.gapMax, c.retry, c.ringS, c.bonus, c.games],
        [
          5,
          b.gapMinS,
          b.gapMaxS,
          b.retryS,
          b.ringS,
          b.bonus,
          ['x'],
        ],
      );
    });

    test('empty near at the attempt retries; with near a booth from near rings for ringS', () {
      final r = BoothsRules();
      var s = r.start(cfg, 3);
      final n0 = s.next;
      for (var i = 0; i < n0; i++) {
        s = r.apply(s, tick([]));
      }
      expect(s.ringing, -1);
      expect(s.next, cfg.retry);
      s = ringUp(r, s, [1, 2]);
      expect([1, 2], contains(s.ringing));
      expect(s.left, cfg.ringS);
      for (var i = 0; i < cfg.ringS; i++) {
        s = r.apply(s, tick([]));
      }
      expect(s.ringing, -1);
      expect(s.missed, 1);
    });

    test('no games: never rings', () {
      final r = BoothsRules();
      var s = r.start(
        const BoothsConfig(booths: 3, gapMin: 2, gapMax: 4, retry: 2, ringS: 3, bonus: 150, games: []),
        9,
      );
      for (var i = 0; i < 30; i++) {
        s = r.apply(s, tick([0, 1, 2]));
      }
      expect(s.ringing, -1);
    });

    test('answer: offer from games, bonus; illegal on a silent or another booth', () {
      final r = BoothsRules();
      var s = r.start(cfg, 12);
      expect(() => r.apply(s, const BoothsAction.answer(0)), throwsA(isA<IllegalAction>()));
      s = ringUp(r, s, [0, 1]);
      final other = s.ringing == 0 ? 1 : 0;
      expect(() => r.apply(s, BoothsAction.answer(other)), throwsA(isA<IllegalAction>()));
      expect(r.legalActions(s).map((a) => a.op), ['clear', 'tick', 'answer']);
      expect(r.legalActions(s).last, BoothsAction.answer(s.ringing));
      s = r.apply(s, BoothsAction.answer(s.ringing));
      expect(cfg.games, contains(s.offer.spot));
      expect(s.offer.bonus, cfg.bonus);
      expect([s.ringing, s.left, s.answered], [-1, 0, 1]);
      expect(r.legalActions(s), [const BoothsAction.clear(), const BoothsAction.tick([])]);
    });

    test('finish: bonus only on the offered spot with 1★ and not aborted; last resets on the next action', () {
      final r = BoothsRules();
      var s = ringUp(r, r.start(cfg, 4), [2]);
      s = r.apply(s, const BoothsAction.answer(2));
      final spot = s.offer.spot;
      final other = spot == 'a' ? 'b' : 'a';
      s = r.apply(s, BoothsAction.finish(other, 3, false));
      expect([s.last, s.offer.spot], [0, spot]);
      final zero = r.apply(s, BoothsAction.finish(spot, 0, false));
      expect([zero.last, zero.paid, zero.offer.spot], [0, 0, '']);
      final aborted = r.apply(s, BoothsAction.finish(spot, 3, true));
      expect([aborted.last, aborted.offer.spot], [0, '']);
      s = r.apply(s, BoothsAction.finish(spot, 1, false));
      expect([s.last, s.paid, s.offer.spot], [150, 150, '']);
      s = r.apply(s, const BoothsAction.clear());
      expect(s.last, 0);
    });

    test('illegal: bad near, bad finish, unknown op, by ≠ player', () {
      final r = BoothsRules();
      final s = r.start(cfg, 1);
      for (final near in [
        [1, 0],
        [1, 1],
        [3],
        [-1],
      ]) {
        expect(() => r.apply(s, tick(near)), throwsA(isA<IllegalAction>()), reason: '$near');
      }
      final bad = <Map<String, Object?>>[
        {
          'by': 'player',
          'op': 'tick',
          'near': [0.5],
        },
        {'by': 'player', 'op': 'answer', 'booth': 0.5},
        {'by': 'player', 'op': 'finish', 'spot': 'a', 'stars': 4, 'aborted': false},
        {'by': 'player', 'op': 'finish', 'spot': 'a', 'stars': -1, 'aborted': false},
        {'by': 'player', 'op': 'finish', 'spot': 'a', 'stars': 1, 'aborted': 'no'},
        {'by': 'player', 'op': 'finish', 'spot': 7, 'stars': 1, 'aborted': false},
        {'by': 'player', 'op': 'ring'},
        {'by': 'ai', 'op': 'clear'},
      ];
      for (final a in bad) {
        expect(() => r.apply(s, r.actionFromJson(a)), throwsA(isA<IllegalAction>()), reason: '$a');
      }
      expect(r.result(s), isNull);
    });
  });

  // ---------- synthetic city: two minigame spots and three booths on the x axis
  Spot spot(String id, String kind, int x, [String minigame = '']) =>
      Spot(id: id, kind: kind, name: id, x: x * 10, y: 0, parkX: x * 10, parkY: 0, parkHeading: 0, minigame: minigame);
  final spots = [
    spot('booth_w', 'booth', -300),
    spot('bar', 'bar', -100, 'oko'),
    spot('booth_c', 'booth', 100),
    spot('pier', 'pier', 200, 'sipky'),
    spot('booth_e', 'booth', 500),
  ];
  final catalog = {for (final e in minigameCatalog.entries) e.key.id: e.value};
  final b = tuning.booths;

  group('booths in the world', () {
    test('booths in spots.pb order; games = catalog minigame spots in order', () {
      final booths = boothsOf(spots);
      expect(booths.map((x) => x.id), ['booth_w', 'booth_c', 'booth_e']);
      expect((booths[1].x, booths[1].y), (100.0, 0.0));
      expect(boothGames(spots, catalog), ['bar', 'pier']);
    });

    test('near: ring_min_m ≤ d ≤ ring_max_m from the parking point, ascending', () {
      final booths = boothsOf(spots);
      // From x = 0: booth_w 300 m, booth_c 100 m, booth_e 500 m.
      expect(nearBooths(booths, 0, 0, b.ringMinM, b.ringMaxM), [0, 1]);
      // Standing next to booth_c (closer than ring_min_m): it is not near.
      expect(nearBooths(booths, 100 + b.ringMinM / 2, 0, b.ringMinM, b.ringMaxM), isNot(contains(1)));
      expect(nearBooths(booths, 100 + b.ringMinM, 0, b.ringMinM, b.ringMaxM), contains(1));
      expect(nearBooths(booths, 100 + b.ringMaxM, 0, b.ringMinM, b.ringMaxM), contains(1));
      expect(nearBooths(booths, 100 + b.ringMaxM + 1, 0, b.ringMinM, b.ringMaxM), isNot(contains(1)));
    });

    test('answer reach: the "Hrát" conditions (speed, layer 0, loop.spot_radius_m)', () {
      final booth = boothsOf(spots)[1];
      final l = tuning.loop;
      expect(boothInReach(booth, 100 + l.spotRadiusM - 1, 0, 0, 0, l), isTrue);
      expect(boothInReach(booth, 100 + l.spotRadiusM, 0, l.stopSpeedMps, 0, l), isTrue);
      expect(boothInReach(booth, 100 + l.spotRadiusM + 1, 0, 0, 0, l), isFalse);
      expect(boothInReach(booth, 100, 0, l.stopSpeedMps + 0.1, 0, l), isFalse);
      expect(boothInReach(booth, 100, 0, 0, 1, l), isFalse);
    });

    test('host: characters[fnv1a(boothId) mod n] like the loop opponent', () {
      expect(boothHost('east_village_bar', 6), 1);
      expect(boothHost('x', 0), -1);
    });

    test('ticks once per game second; rings a near booth, toast event; picks up the offer', () {
      final booths = boothsOf(spots);
      final w = BoothWorld(booths, tuning, boothGames(spots, catalog), 77);
      final rings = <String>[];
      w.onRing.add((x) => rings.add(x.id));
      List<int> near() => nearBooths(booths, 0, 0, b.ringMinM, b.ringMaxM);
      final next0 = w.state.next;
      w.update(0.5, near);
      w.update(0.49, near);
      expect(w.state.next, next0);
      w.update(0.01 + 1e-9, near);
      expect(w.state.next, next0 - 1);
      for (var i = 0; i < 200 * 60 && w.ringing == null; i++) {
        w.update(1 / 60, near);
      }
      expect(w.ringing, isNotNull);
      expect(['booth_w', 'booth_c'], contains(w.ringing!.id));
      expect(rings, [w.ringing!.id]);
      expect(w.answer(w.state.ringing == 0 ? 1 : 0), isNull);
      final offer = w.answer(w.state.ringing)!;
      expect(['bar', 'pier'], contains(offer.spot));
      expect(offer.bonus, b.bonus);
      expect(w.ringing, isNull);
      w.clear();
      expect(w.offer, isNull);
    });

    test('suppressed (navigation, minigame, Taxi, wanted): near is empty, a ringing booth rings out', () {
      final w = BoothWorld(boothsOf(spots), tuning, ['bar'], 5);
      for (var i = 0; i < 400 && w.ringing == null; i++) {
        w.update(1, () => []);
      }
      expect(w.ringing, isNull);
      expect(w.state.next, lessThanOrEqualTo(b.retryS));
      for (var i = 0; i < 400 && w.ringing == null; i++) {
        w.update(1, () => [1]);
      }
      expect(w.ringing!.id, 'booth_c');
      w.update(b.ringS.toDouble(), () => []);
      expect(w.ringing, isNull);
      expect(w.state.missed, 1);
    });

    test('game dt 0 (paused) stops the booth clock', () {
      final w = BoothWorld(boothsOf(spots), tuning, ['bar'], 8);
      final next0 = w.state.next;
      for (var i = 0; i < 300; i++) {
        w.update(0, () => [0]);
      }
      expect(w.state.next, next0);
    });

    test('bonus in the loop: finish after reward adds last to the cars-state cash and the outcome', () {
      final w = BoothWorld(boothsOf(spots), tuning, ['bar'], 21);
      for (var i = 0; i < 400 && w.ringing == null; i++) {
        w.update(1, () => [0]);
      }
      final offer = w.answer(w.state.ringing)!;
      expect(offer.spot, 'bar');
      var cash = 1000;
      final book = LoopBook(tuning, LoopPorts(getCash: () => cash, setCash: (c) => cash = c, stamp: (_, _) => false))
        ..bonus = w.finish;
      MinigameResult res(int stars, [bool aborted = false]) =>
          MinigameResult(stars: stars, score: 10, playedMs: 1000, aborted: aborted);
      LoopOutcome play(String spot, String mg, MinigameResult r) => book.finish(
        spot: spot,
        minigame: mg,
        engine: catalog[mg]!.engine,
        result: r,
        driveDm: 0,
        hasStamp: (_) => false,
      );
      // Another spot first: no bonus, the offer stays.
      final o0 = play('pier', 'sipky', res(3));
      expect(o0.booth, 0);
      expect(w.offer?.spot, 'bar');
      var before = cash;
      final o = play('bar', 'oko', res(1));
      expect(o.booth, b.bonus);
      expect(cash, before + o.cash.amount + b.bonus);
      expect(o.total, cash);
      expect(book.eco.cash, cash);
      expect(w.offer, isNull);
      expect(w.state.paid, b.bonus);
      // Aborted on the offered spot: no bonus, offer gone.
      for (var i = 0; i < 400 && w.ringing == null; i++) {
        w.update(1, () => [2]);
      }
      w.answer(w.state.ringing);
      expect(w.offer, isNotNull);
      before = cash;
      final o2 = play('bar', 'oko', res(3, true));
      expect(o2.booth, 0);
      expect(cash, before + o2.cash.amount);
      expect(w.offer, isNull);
    });
  });
}
