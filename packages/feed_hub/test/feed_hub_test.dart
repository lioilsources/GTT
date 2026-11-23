import 'dart:io';
import 'dart:math' as math;

import 'package:drive_core/drive_core.dart' show RouteGraph;
import 'package:feed_hub/feed_hub.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rules_core/rules_core.dart' show IllegalAction;
import 'package:rules_core/vector_test_support.dart';
import 'package:shared_gen/citypack_pb.dart' as pb;
import 'package:world_engine/core.dart';

final tuning = Tuning.fromYaml(File('$repoRoot/content/tuning.yaml').readAsStringSync());

FeedCandidate cand(String spot, String engine, int distDm, {bool local = false, int visits = 0}) => FeedCandidate(
  spot: spot,
  game: engine == 'drive' ? 'taxi' : 'dama',
  engine: engine,
  local: local,
  district: '',
  distDm: distDm,
  visits: visits,
  landmark: false,
);

FeedConfig cfg(List<FeedCandidate> c, {int? deckSize}) {
  final f = FeedConfig.fromTuning(tuning.feed, c, {}, []);
  if (deckSize != null) f.n['deckSize'] = deckSize;
  return f;
}

/// 0 —e0— 1 —e1 (one-way 1→2)— 2 —e2— 3 along x, 100 m apart; e3 is an alley 1—3 to the north.
({pb.Graph pb, RoadGraph g, RouteGraph rg}) testGraph() {
  pb.Edge e(int a, int b, List<int> pts, int cls, int oneway, bool kept) =>
      pb.Edge(from: a, to: b, points: pts, class_4: pb.RoadClass.valueOf(cls), oneway: oneway, kept: kept, widthM: 10);
  final g = pb.Graph(
    names: [''],
    nodes: [
      for (final x in [0, 1000, 2000, 3000]) pb.Node(x: x, y: 0),
    ],
    edges: [
      e(0, 1, [0, 0, 500, 0, 1000, 0], 3, 0, true),
      e(1, 2, [1000, 0, 2000, 0], 3, 1, true),
      e(2, 3, [2000, 0, 2500, 0, 3000, 0], 3, 0, true),
      e(1, 3, [1000, 0, 2000, 800, 3000, 0], 7, 0, false),
    ],
  );
  return (pb: g, g: RoadGraph.fromPb(g), rg: RouteGraph.fromPb(g, tuning.route.classCost));
}

List<double> xs(List<double> p) => [for (var i = 0; i < p.length; i += 2) p[i]];

void main() {
  group('feed rules (specs/feed.md)', () {
    test('band score with integer falloff', () {
      final c = cfg([]);
      expect(bandScore(c, c['bandMinS'] - 1), c['nearPoints']);
      expect(bandScore(c, c['bandMaxS']), c['bandPoints']);
      expect(bandScore(c, c['bandMaxS'] + c['bandFalloffS'] ~/ 2), c['bandPoints'] ~/ 2);
      expect(bandScore(c, c['bandMaxS'] + 10 * c['bandFalloffS']), 0);
    });

    test('always deals a local game and a driving challenge', () {
      final s = FeedRules().deal(
        cfg([
          for (final id in ['a', 'b', 'c', 'd', 'e', 'f', 'g']) cand(id, 'board', 11000),
          cand('local', 'flick', 500000, local: true, visits: 4),
          cand('drive', 'drive', 500000, visits: 4),
        ]),
        3,
      );
      expect(s.deck, hasLength(6));
      expect(s.deck.map((c) => c.spot), containsAll(['local', 'drive']));
    });

    test('actions and the end of the deck', () {
      final r = FeedRules();
      var s = r.deal(cfg([cand('a', 'board', 9000), cand('b', 'dice', 9000)]), 1);
      expect(r.legalActions(s), [FeedOp.next, FeedOp.like, FeedOp.less, FeedOp.accept]);
      s = r.apply(s, FeedOp.like);
      expect(r.legalActions(s), [FeedOp.next, FeedOp.less, FeedOp.accept]);
      expect(() => r.apply(s, FeedOp.like), throwsA(isA<IllegalAction>()));
      s = r.apply(s, FeedOp.next);
      expect(r.legalActions(s), FeedOp.values);
      s = r.apply(s, FeedOp.less);
      expect(s.over, isTrue);
      expect(r.legalActions(s), isEmpty);
      expect(() => r.apply(s, FeedOp.prev), throwsA(isA<IllegalAction>()));
      expect(FeedRules().deal(cfg([]), 1).over, isTrue);
    });

    test('prev goes back without re-counting (v2), illegal on the first card', () {
      final r = FeedRules();
      final s0 = r.deal(cfg([cand('a', 'board', 9000), cand('b', 'dice', 9000), cand('c', 'flick', 9000)]), 2);
      expect(r.legalActions(s0), isNot(contains(FeedOp.prev)));
      expect(() => r.apply(s0, FeedOp.prev), throwsA(isA<IllegalAction>()));
      var s = r.apply(s0, FeedOp.like);
      final liked = s.deck[0].spot;
      s = r.apply(s, FeedOp.less);
      final prefs = Map.of(s.prefs);
      s = r.apply(s, FeedOp.prev);
      expect(s.at, 0);
      expect(s.prefs, prefs);
      expect(s.liked, [liked]);
      expect(r.legalActions(s), [FeedOp.next, FeedOp.less, FeedOp.accept]);
      s = r.apply(s, FeedOp.next);
      expect(s.at, 1);
      expect(s.prefs, prefs);
      expect(s.over, isFalse);
    });

    test('a one-card deck never allows prev', () {
      final r = FeedRules();
      final s = r.deal(cfg([cand('a', 'board', 9000)]), 1);
      expect(r.legalActions(s), [FeedOp.next, FeedOp.like, FeedOp.less, FeedOp.accept]);
      expect(r.apply(s, FeedOp.next).over, isTrue);
    });

    test('candidates: local flag, challenge placeholder, landmark nearby', () {
      final out = buildCandidates(
        cityId: 'nyc',
        spots: const [
          CandidateSpot('k', 'koulena', 0, 0),
          CandidateSpot('d', 'dama', -500, 0),
          CandidateSpot('p', '', 50, 0),
          CandidateSpot('u', 'unknown', 0, 0),
        ],
        catalog: {
          'koulena': MinigameMeta(id: 'koulena', engine: 'flick', targetLengthS: 1, cities: ['nyc'], casinoLike: false),
          'dama': MinigameMeta(id: 'dama', engine: 'board', targetLengthS: 1, cities: [], casinoLike: false),
        },
        districtAt: (x, y) => x < 0 ? 'West' : 'East',
        landmarks: const [(id: 'l1', x: 100, y: 0)],
        discovered: const {},
        visits: const {'k': 2},
        landmarkRadiusDm: 200,
        distDm: (_) => 1234,
      );
      expect(
        [for (final c in out) '${c.spot} ${c.game} ${c.engine} ${c.local} ${c.district} ${c.visits} ${c.landmark}'],
        ['k koulena flick true East 2 true', 'd dama board false West 0 false', 'p challenge drive false East 0 true'],
      );
    });

    final vectors = File('$repoRoot/vectors/feed.json').existsSync();
    test(
      'vectors/feed.json',
      () => expect(checkVectors(FeedRules()), isEmpty),
      skip: !vectors || !flutterDone('vectors/feed.json') ? 'pending in parity.yaml' : false,
    );
  });

  group('navigation (specs/phone.md)', () {
    final t = testGraph();
    final g = t.g, rg = t.rg;
    const spot = NavTarget(id: 's', name: 'Spot', edge: 2, parkX: 2800, parkY: 30);

    test('start end ahead of the car, one-ways, alleys', () {
      final hit = g.nearest(30, 0, maxDist: 10)!;
      expect(navStart(g, hit, 30, 0, 0, 60)!.node, 1);
      expect(navStart(g, hit, 30, 0, math.pi, 60)!.node, 0);
      final one = g.nearest(150, 0, maxDist: 5, where: (e) => e.index == 1)!;
      expect(navStart(g, one, 150, 0, math.pi, 60)!.node, 2);
      final alley = g.nearest(200, 80, maxDist: 5)!;
      expect(alley.edge.kept, isFalse);
      expect(navStart(g, alley, 200, 80, 0, 100)!.hit.edge.kept, isTrue);
    });

    test('goal end nearer the parking point', () {
      expect(navGoal(g, spot).node, 3);
      expect(navGoal(g, const NavTarget(id: 's', name: 'S', edge: 2, parkX: 2100, parkY: 30)).node, 2);
    });

    test('path, progress and arrival', () {
      final hit = g.nearest(30, 0, maxDist: 10)!;
      final n = Navigator(g, rg, tuning.route, tuning.nav);
      expect(n.start(spot, 30, 0, 0, hit), isTrue);
      expect(xs(n.path), [30, 50, 100, 200, 250, 300, 280, 280]);
      expect(n.remaining, closeTo(293, 1e-4));
      expect(n.update(120, 0, 0, g.nearest(120, 0, maxDist: 10), 0.016), isNull);
      expect(n.remaining, closeTo(203, 1e-4));
      expect(n.update(275, 2, 0, g.nearest(275, 2, maxDist: 10), 0.016), NavEvent.arrived);
    });

    test('straight along the spot edge when the parking point is ahead', () {
      final n = Navigator(g, rg, tuning.route, tuning.nav)..start(spot, 210, 0, 0, g.nearest(210, 0, maxDist: 10));
      expect(xs(n.path), [210, 250, 280, 280]);
    });

    test('reroute after staying off the route', () {
      final n = Navigator(g, rg, tuning.route, tuning.nav)..start(spot, 30, 0, 0, g.nearest(30, 0, maxDist: 10));
      final far = tuning.route.rerouteM + 5;
      expect(n.update(60, far, 0, g.nearest(60, 0, maxDist: 10), tuning.route.rerouteS / 2), isNull);
      expect(n.update(60, far, 0, g.nearest(60, 0, maxDist: 10), tuning.route.rerouteS), NavEvent.rerouted);
    });

    test('feed distance over the route or a stretched straight line', () {
      final lens = edgeLengthsDm(t.pb);
      final s = navStart(g, g.nearest(30, 0, maxDist: 10), 30, 0, 0, 60);
      expect(feedDistDm(rg, lens, s, navGoal(g, spot), 30, 0, spot, 140), 2000);
      const west = NavTarget(id: 'w', name: 'W', edge: 0, parkX: 400, parkY: 0);
      final back = navStart(g, g.nearest(250, 0, maxDist: 10), 250, 0, 0, 60)!.withNode(2);
      expect(feedDistDm(rg, lens, back, navGoal(g, west).withNode(1), 250, 0, west, 140), 2100 * 140 ~/ 100);
    });

    test('distance format and drive minutes', () {
      String f(double m, bool imp) {
        final d = formatDistance(m, imp, tuning.nav);
        return '${d.key.name} ${d.args.values.single}';
      }

      expect(f(234, false), 'distanceM 230');
      expect(f(1260, false), 'distanceKm 1.3');
      expect(f(100, true), 'distanceFt 350');
      expect(f(3218.7, true), 'distanceMi 2.0');
      expect([driveMinutes(0), driveMinutes(89), driveMinutes(90)], [1, 1, 2]);
    });

    test('edge arrow', () {
      expect(edgeArrow(100, 100, 400, 800, 20, 200, 576), isNull);
      final a = edgeArrow(200, -1000, 400, 800, 20, 200, 576)!;
      expect(a.x, closeTo(200, 1e-9));
      expect(a.y, closeTo(20, 1e-9));
      expect(a.angle, closeTo(-math.pi / 2, 1e-9));
      final b = edgeArrow(2000, 576, 400, 800, 20, 200, 576)!;
      expect([b.x, b.y], [380, 576]);
    });

    test('map fit, north up', () {
      final f = mapFit([0, 0, 100, 0, 100, 200, 0, 200], 120, 220, 10);
      expect(f.s, 1);
      expect([f.ox, f.oy], [10, 210]);
    });
  });

  test('pure: no Flutter or dart:ui imports in lib/', () {
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final src = f.readAsStringSync();
      expect(RegExp(r"^import '(package:flutter/|dart:ui)", multiLine: true).hasMatch(src), isFalse, reason: f.path);
    }
  });
}
