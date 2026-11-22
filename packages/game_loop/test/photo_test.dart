import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:game_loop/game_loop.dart';
import 'package:meta_progress/meta_progress.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';
import 'package:shared_gen/citypack_pb.dart' show Spot, Spots;
import 'package:shared_gen/shared_gen.dart';
import 'package:test/test.dart';

// Port of web/test/photo.test.ts (specs/photo.md): rules, the pure world part and the Passport
// catalog. The CameraRig inverse and the mode itself are tested in the app.
void main() {
  final tuning = Tuning.fromYaml(File('$repoRoot/content/tuning.yaml').readAsStringSync());
  const a = PhotoSpot(id: 'a', x: 1000, y: 2000, r: 300);
  const b = PhotoSpot(id: 'b', x: -500, y: 400, r: 100);
  const cfg = PhotoConfig(spots: [a, b], loosePct: 400);
  PhotoAction shoot(String spot, int cx, int cy, int hw, [int? hh]) =>
      PhotoAction.shoot(spot, (cx: cx, cy: cy, hw: hw, hh: hh ?? hw));
  Map<String, Object?> state(List<String> taken, String spot, String verdict) => {
    'taken': taken,
    'last': {'spot': spot, 'verdict': verdict},
  };

  group('photo vectors', () {
    test(
      'vectors/photo.json',
      () => expect(checkVectors(PhotoRules()), isEmpty),
      skip: !flutterDone('vectors/photo.json') ? 'pending in parity.yaml' : false,
    );
  });

  group('photo rules (specs/photo.md)', () {
    test('init: nothing taken, empty last; config from tuning', () {
      final r = PhotoRules();
      expect(r.init(cfg.toJson(), 7).toJson(), state([], '', ''));
      expect(PhotoConfig.fromTuning(tuning.photo, [a]).toJson(), {
        'spots': [a.toJson()],
        'loosePct': tuning.photo.loosePct,
      });
      expect(r.result(r.start(cfg)), isNull);
      expect((r.id, r.specVersion), ('photo', 1));
    });

    test('load: only known ids, no duplicates, list order; last empty', () {
      final r = PhotoRules();
      var s = r.apply(r.start(cfg), shoot('a', 1000, 2000, 300));
      s = r.apply(s, const PhotoAction.load(['b', 'gone', 'a', 'b']));
      expect(s.toJson(), state(['b', 'a'], '', ''));
    });

    test('shoot: ok, again, cut (off centre, too small, short side), loose with the inclusive limit', () {
      final r = PhotoRules();
      var s = r.apply(r.start(cfg), shoot('a', 1000, 2000, 300));
      expect(s.toJson(), state(['a'], 'a', 'ok'));
      s = r.apply(s, shoot('a', 1000, 2000, 400, 500));
      expect(s.last.verdict, 'again');
      expect(s.taken, ['a']);
      expect(r.apply(s, shoot('b', -499, 400, 100)).last.verdict, 'cut');
      expect(r.apply(s, shoot('b', -500, 400, 99)).last.verdict, 'cut');
      expect(r.apply(s, shoot('b', -500, 400, 1000, 99)).last.verdict, 'cut');
      expect(r.apply(s, shoot('b', -500, 400, 401)).last.verdict, 'loose');
      expect(r.apply(s, shoot('b', -500, 400, 400)).toJson(), state(['a', 'b'], 'b', 'ok'));
    });

    test('distance is floor(sqrt(dx² + dy²))', () {
      expect([isqrt(0), isqrt(1), isqrt(2), isqrt(24), isqrt(25), isqrt(26)], [0, 1, 1, 4, 5, 5]);
      expect(isqrt(4503599627370495), 67108863);
      const c = PhotoSpot(id: 'c', x: 0, y: 0, r: 50);
      // d = floor(sqrt(2)) = 1: 1 + 50 ≤ 51 fits.
      expect(frameVerdict(c, 400, (cx: 1, cy: 1, hw: 51, hh: 51)), 'fits');
      expect(frameVerdict(c, 400, (cx: 3, cy: 4, hw: 54, hh: 54)), 'cut');
    });

    test('illegal: unknown spot, hw or hh < 1, non-integers, unknown op, by ≠ player, bad load', () {
      final r = PhotoRules();
      final s = r.start(cfg);
      Map<String, Object?> j(String spot, num cx, num cy, num hw, [num? hh]) => {
        'by': 'player',
        'op': 'shoot',
        'spot': spot,
        'cx': cx,
        'cy': cy,
        'hw': hw,
        'hh': hh ?? hw,
      };
      final bad = <Map<String, Object?>>[
        j('zzz', 1000, 2000, 300),
        j('a', 1000, 2000, 0, 300),
        j('a', 1000, 2000, 300, 0),
        j('a', 1000, 2000, -5),
        j('a', 1000.5, 2000, 300),
        j('a', 1000, 2000, 300.5),
        {'by': 'player', 'op': 'shoot', 'spot': 1, 'cx': 0, 'cy': 0, 'hw': 1, 'hh': 1},
        {'by': 'player', 'op': 'snap'},
        {'by': 'ai', 'op': 'load', 'taken': <String>[]},
        {
          'by': 'player',
          'op': 'load',
          'taken': [1],
        },
        {'by': 'player', 'op': 'load'},
      ];
      for (final x in bad) {
        expect(() => r.apply(s, r.actionFromJson(x)), throwsA(isA<IllegalAction>()), reason: jsonEncode(x));
      }
      expect(r.actionFromJson(j('a', 1000.0, 2000, 300)), shoot('a', 1000, 2000, 300));
    });

    test('legalActions: load [] and the exact view of every spot, all legal', () {
      final r = PhotoRules();
      final s = r.start(cfg);
      final acts = r.legalActions(s);
      expect(acts, [const PhotoAction.load([]), shoot('a', 1000, 2000, 300), shoot('b', -500, 400, 100)]);
      for (final x in acts) {
        expect(() => r.apply(s, x), returnsNormally);
      }
      expect(acts[1].toJson(), {'by': 'player', 'op': 'shoot', 'spot': 'a', 'cx': 1000, 'cy': 2000, 'hw': 300, 'hh': 300});
    });
  });

  Spot spot(String id, String kind, {int parkX = 0, int parkY = 0, int lookX = 0, int lookY = 0, int subjectDm = 0}) =>
      Spot(
        id: id,
        kind: kind,
        name: 'Spot $id',
        parkX: parkX,
        parkY: parkY,
        parkHeading: 0.5,
        lookX: lookX,
        lookY: lookY,
        subjectDm: subjectDm,
      );
  final spots = [
    spot('p1', 'photo', parkX: 100, parkY: 200, lookX: 600, lookY: 200, subjectDm: 400),
    spot('bar', 'bar'),
    spot('p2', 'photo', parkX: -1000, lookX: -1000, lookY: 1000, subjectDm: 300),
    spot('p0', 'photo'),
  ];

  group('photo spots in the world (specs/photo.md P1)', () {
    test('photo spots in spots.pb order, metres and dm', () {
      final p = photoSpotsOf(spots);
      expect(p.map((x) => x.id), ['p1', 'p2']);
      final p1 = p[0];
      expect(
        (p1.x, p1.y, p1.lookX, p1.lookY, p1.subjectM, p1.lookXDm, p1.lookYDm, p1.subjectDm, p1.heading),
        (10.0, 20.0, 60.0, 20.0, 40.0, 600, 200, 400, 0.5),
      );
    });

    test('reach: the "Hrát" conditions; the nearest spot in reach', () {
      final p = photoSpotsOf(spots);
      final l = tuning.loop;
      expect(photoInReach(p[0], 10, 20, 0, 0, l), isTrue);
      expect(photoInReach(p[0], 10, 20, l.stopSpeedMps + 1, 0, l), isFalse);
      expect(photoInReach(p[0], 10, 20, 0, 1, l), isFalse);
      expect(photoInReach(p[0], 10 + l.spotRadiusM + 0.1, 20, 0, 0, l), isFalse);
      expect(photoSpotAt(p, -100, 0, 0, 0, l)?.id, 'p2');
      expect(photoSpotAt(p, 500, 500, 0, 0, l), isNull);
    });

    test('blocked during a minigame, the Taxi shift and while wanted', () {
      expect(photoBlocked(busy: false, inWorldGame: false, wanted: 0), isNull);
      expect(photoBlocked(busy: true, inWorldGame: false, wanted: 0), PhotoBlock.busy);
      expect(photoBlocked(busy: false, inWorldGame: true, wanted: 0), PhotoBlock.busy);
      expect(photoBlocked(busy: false, inWorldGame: false, wanted: 2), PhotoBlock.wanted);
    });

    test('view width: max(view_width_m.slow, 2 × subject × view_factor)', () {
      expect(photoViewWidth(tuning, 1), tuning.viewWidthM.slow);
      expect(photoViewWidth(tuning, 100), closeTo(200 * tuning.photo.viewFactor, 1e-9));
    });

    test('rigForCentre puts the point mid-screen (screenToWorld of the centre)', () {
      const w = 400.0, h = 800.0;
      final at = rigForCentre(55, 66, 1.1, 180, w, h, tuning);
      final c = screenToWorld((x: at.x, y: at.y, heading: 1.1, viewWidth: 180), w / 2, h / 2, w, h, tuning);
      expect(c.x, closeTo(55, 1e-6));
      expect(c.y, closeTo(66, 1e-6));
    });

    test('frame → shot: centre to world dm, half sides ÷ scale, rounding, at least 1', () {
      const RigPose rig = (x: 0, y: 0, heading: math.pi / 2, viewWidth: 100);
      const w = 400.0, h = 800.0; // 4 px per metre, north up
      final ax = w * tuning.carAnchor.x, ay = h * tuning.carAnchor.y;
      // A 40 × 20 px frame centred 40 px right and 80 px above the anchor: (10 m, 20 m), half sides 5 m and 2.5 m.
      expect(frameToShot(rig, ax + 20, ay - 70, ax + 60, ay - 90, w, h, tuning), (cx: 100, cy: 200, hw: 50, hh: 25));
      // A tap: zero size → 1 dm.
      expect(frameToShot(rig, ax, ay, ax, ay, w, h, tuning), (cx: 0, cy: 0, hw: 1, hh: 1));
      expect([toDm(1.04), toDm(1.05), toDm(-1.04), toDm(-1.06)], [10, 11, -10, -11]);
    });

    test('glide: from the start pose to the target over the seconds, smooth', () {
      final g = PhotoGlide(
        (x: 0, y: 0, heading: 1, viewWidth: 50),
        () => (x: 10, y: 20, heading: 1, viewWidth: 150),
        0.6,
      );
      expect(g.pose(), (x: 0.0, y: 0.0, heading: 1.0, viewWidth: 50.0));
      g.step(0.3);
      expect(g.pose().x, closeTo(5, 1e-9));
      expect(g.done, isFalse);
      g.step(0.4);
      expect(g.done, isTrue);
      expect(g.pose(), (x: 10.0, y: 20.0, heading: 1.0, viewWidth: 150.0));
    });

    test('PhotoWorld: loads photo:* stamps, shoots in dm', () {
      final pw = PhotoWorld(photoSpotsOf(spots), tuning)..loadStamps(['landmark:x', 'photo:p2', 'photo:gone', 'photo:p2']);
      expect(pw.state.taken, ['p2']);
      expect(pw.isTaken('p2'), isTrue);
      expect(pw.shoot('nope', (cx: 0, cy: 0, hw: 1, hh: 1)), isNull);
      expect(pw.shoot('p1', (cx: 600, cy: 200, hw: 10, hh: 10)), 'cut');
      expect(pw.shoot('p1', (cx: 600, cy: 200, hw: 400, hh: 600)), 'ok');
      expect(pw.shoot('p2', (cx: -1000, cy: 1000, hw: 300, hh: 300)), 'again');
      expect(pw.state.taken, ['p2', 'p1']);
    });

    test('passport catalog photo = photo spot ids in spot order; visit photo stamps once', () {
      final city = PassportCity(
        landmarks: const [],
        districts: const [],
        spotMinigames: [for (final s in spots) s.minigame],
        photos: [
          for (final s in spots)
            if (s.kind == 'photo') (id: s.id, name: s.name),
        ],
      );
      final tr = PassportTracker(city, tuning.passport, ['photo:p2', 'photo:gone']);
      expect(tr.state.catalog['photo'], ['p1', 'p2', 'p0']);
      expect(tr.stamps, ['photo:p2']);
      expect(tr.photoNames['p1'], 'Spot p1');
      final events = <String>[];
      tr.onStamp((e) => events.add('${e.kind}:${e.id}'));
      expect(tr.photo('p1'), isTrue);
      expect(tr.photo('p1'), isFalse);
      expect(tr.photo('bar'), isFalse);
      expect(events, ['photo:p1']);
      expect(tr.result.kinds['photo'], (2, 3));
    });
  });

  final pack = File('$repoRoot/build/packs/nyc/spots.pb');
  group('photo spots in NYC', () {
    test('the pack has photo spots with a view; their exact view is ok', () {
      final items = Spots.fromBuffer(gzip.decode(pack.readAsBytesSync())).items;
      final points = photoSpotsOf(items);
      expect(points.length, items.where((s) => s.kind == 'photo').length);
      expect(points, isNotEmpty);
      final pw = PhotoWorld(points, tuning);
      for (final p in points) {
        final d = math.sqrt((p.lookX - p.x) * (p.lookX - p.x) + (p.lookY - p.y) * (p.lookY - p.y));
        expect(d, lessThanOrEqualTo(1500));
        expect(pw.shoot(p.id, (cx: p.lookXDm, cy: p.lookYDm, hw: p.subjectDm, hh: p.subjectDm)), 'ok');
      }
    }, skip: pack.existsSync() ? false : 'no NYC pack in build/packs');
  });
}
