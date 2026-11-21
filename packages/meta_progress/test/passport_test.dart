import 'dart:io';

import 'package:meta_progress/meta_progress.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';
import 'package:shared_gen/shared_gen.dart';
import 'package:test/test.dart';

const cfg = <String, Object?>{
  'landmarks': ['a', 'b'],
  'districts': ['d1', 'd2'],
  'minigames': ['sirky'],
  'photos': <String>[],
  'weights': [3, 1, 3, 2],
  'starsForStamp': 3,
};

void main() {
  final r = PassportRules();
  final tuning = Tuning.fromYaml(File('$repoRoot/content/tuning.yaml').readAsStringSync());

  test('counts points and floors the percent', () {
    var s = r.init(cfg, 0);
    expect(s.total, 11);
    s = r.apply(s, const PassportAction('landmark', 'a'));
    expect(s.last, 'landmark:a');
    expect(r.result(s).percent, 27);
    s = r.apply(s, const PassportAction('landmark', 'a'));
    expect(s.last, '');
    expect(s.points, 3);
  });

  test('stamps a minigame only at 3 stars', () {
    var s = r.init(cfg, 0);
    s = r.apply(s, const PassportAction('minigame', 'sirky', stars: 2));
    expect(s.stamps, isEmpty);
    s = r.apply(s, const PassportAction('minigame', 'sirky', stars: 3));
    expect(s.stamps, ['minigame:sirky']);
  });

  test('rejects unknown ids and bad stars', () {
    final s = r.init(cfg, 0);
    expect(() => r.apply(s, const PassportAction('landmark', 'zz')), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const PassportAction('minigame', 'sirky', stars: 4)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const PassportAction('minigame', 'sirky')), throwsA(isA<IllegalAction>()));
  });

  test('restores saved stamps and lists the missing ones', () {
    final s = r.init({
      ...cfg,
      'stamps': ['district:d2', 'landmark:x', 'district:d2'],
    }, 0);
    expect(s.stamps, ['district:d2']);
    expect(r.legalActions(s).map((a) => '${a.kind}:${a.id}'), [
      'landmark:a',
      'landmark:b',
      'district:d1',
      'minigame:sirky',
    ]);
  });

  test('district ids', () {
    expect(districtId("Hell's Kitchen"), 'hells_kitchen');
    expect(districtId('DUMBO'), 'dumbo');
    expect(districtId('Upper West Side'), 'upper_west_side');
    expect(districtId(' St. Mark’s  Place '), 'st_marks_place');
  });

  test('postcard picture', () {
    expect(fnv1a(''), 0x811c9dc5);
    expect(fnv1a('a'), 0xe40c292c);
    final tall = postcardShapes('one_wtc', 541);
    expect(tall.whereType<PostcardPoly>(), hasLength(1));
    expect(tall.whereType<PostcardRect>().where((s) => s.w == 6), hasLength(44));
    final low = postcardShapes('city_hall', 32);
    expect(low.whereType<PostcardPoly>(), isEmpty);
    expect(low.whereType<PostcardRect>().where((s) => s.w == 6), hasLength(16));
    expect(postcardShapes('central_park', 0).whereType<PostcardCircle>(), hasLength(5));
  });

  group('tracker', () {
    const city = PassportCity(
      landmarks: [
        (id: 'empire_state', name: 'Empire State Building', x: 1000, y: 0, heightM: 381, hero: true),
        (id: 'chrysler', name: 'Chrysler Building', x: 1200, y: 0, heightM: 319, hero: true),
        (id: 'bryant_park', name: 'Bryant Park', x: 0, y: 0, heightM: 0, hero: false),
        (id: 'park_432', name: '432 Park Avenue', x: 0, y: 0, heightM: 426, hero: true),
      ],
      districts: ['Midtown', "Hell's Kitchen", 'Midtown'],
      spotMinigames: ['', 'sirky', 'dama', 'sirky'],
    );

    test('builds the catalog from heroes with a postcard', () {
      final t = PassportTracker(city, tuning.passport);
      expect(t.state.catalog, {
        'landmark': ['empire_state', 'chrysler'],
        'district': ['midtown', 'hells_kitchen'],
        'minigame': ['sirky', 'dama'],
        'photo': <String>[],
      });
    });

    test('discovers one landmark per tick and districts by name', () {
      final t = PassportTracker(city, tuning.passport, ['district:midtown']);
      final seen = <String>[];
      t.onStamp((e) => seen.add('$e'));
      expect(t.update(500, 0, 'Midtown'), isEmpty);
      t.update(110, 0, "Hell's Kitchen");
      t.update(110, 0, null);
      expect(seen, ['landmark:empire_state', 'district:hells_kitchen', 'landmark:chrysler']);
      expect(t.minigame('dama', 3), isTrue);
      expect(t.stamps, [
        'district:midtown',
        'landmark:empire_state',
        'district:hells_kitchen',
        'landmark:chrysler',
        'minigame:dama',
      ]);
    });
  });

  test('20 postcards with title and text', () {
    final titles = MessageKey.values.where((k) => RegExp(r'^lm_.+_title$').hasMatch(k.key)).toList();
    expect(titles, hasLength(20));
    for (final k in titles) {
      final id = k.key.substring(3, k.key.length - 6);
      expect(postcardTextKey(id), isNotNull, reason: id);
      expect(tr('cs', postcardTextKey(id)!), isNot(tr('en', postcardTextKey(id)!)), reason: id);
    }
  });

  test('pure: no Flutter or dart:ui', () {
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      expect(
        RegExp(r"^(import|export) '(package:flutter|dart:ui)", multiLine: true).hasMatch(f.readAsStringSync()),
        isFalse,
        reason: f.path,
      );
    }
  });

  final vectors = File('$repoRoot/vectors/passport.json').existsSync();
  test(
    'vectors/passport.json',
    () => expect(checkVectors(PassportRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/passport.json') ? 'pending in parity.yaml' : false,
  );
}
