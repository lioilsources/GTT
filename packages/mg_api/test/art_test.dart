import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:shared_gen/shared_gen.dart' show CityId;

void main() {
  group('npcExpression (specs/art.md)', () {
    String e(int v) => npcExpression(v, contactMinVibe: 6, vibeStart: 2);
    test('happy from contactMinVibe', () {
      expect(e(6), 'happy');
      expect(e(10), 'happy');
    });
    test('annoyed below vibeStart', () {
      expect(e(1), 'annoyed');
      expect(e(0), 'annoyed');
    });
    test('neutral in between', () {
      expect(e(2), 'neutral');
      expect(e(5), 'neutral');
    });
  });

  group('ArtIndex', () {
    final idx = ArtIndex.fromJson(
      '["npc/maya.png","npc/maya_bust.png","npc/maya_happy.png","npc/ray_happy.png","postcards/nyc/chrysler.png"]',
    );
    test('portrait: expression, then <id>.png, then null', () {
      expect(idx.portrait('maya', 'happy'), 'npc/maya_happy.png');
      expect(idx.portrait('maya', 'annoyed'), 'npc/maya.png');
      expect(idx.portrait('maya'), 'npc/maya.png');
      expect(idx.portrait('ray', 'happy'), 'npc/ray_happy.png');
      expect(idx.portrait('ray', 'neutral'), isNull);
      expect(idx.portrait('nobody', 'happy'), isNull);
    });
    test('avatar and bust', () {
      expect(idx.avatar('maya'), 'npc/maya.png');
      expect(idx.avatar('ray'), isNull);
      expect(idx.bust('maya'), 'npc/maya_bust.png');
      expect(idx.bust('ray'), isNull);
    });
    test('postcard by city', () {
      expect(idx.postcard('nyc', 'chrysler'), 'postcards/nyc/chrysler.png');
      expect(idx.postcard('prague', 'chrysler'), isNull);
    });
    test('malformed or empty index = no art', () {
      expect(ArtIndex.fromJson('not json').isEmpty, isTrue);
      expect(ArtIndex.fromJson('{"a":1}').isEmpty, isTrue);
      expect(ArtIndex.empty.portrait('maya', 'happy'), isNull);
    });
    test('the synced index lists every expression the spec names', () {
      final f = File('../../app/assets/shared/assets/index.json');
      if (!f.existsSync()) return; // metro sync not run
      final synced = ArtIndex.fromJson(f.readAsStringSync());
      for (final ex in ['happy', 'neutral', 'annoyed']) {
        expect(synced.portrait('maya', ex), 'npc/maya_$ex.png');
      }
    });
  });

  group('NPC portraits per city (specs/art.md v4)', () {
    final idx = ArtIndex(const [
      'npc/maya.png', 'npc/maya_happy.png', 'npc/maya_annoyed.png', 'npc/maya_bust.png', //
      'npc/theo.png', 'npc/theo_happy.png', 'npc/theo_bust.png',
      'npc/tokyo/maya.png', 'npc/tokyo/maya_happy.png', 'npc/tokyo/maya_bust.png',
      'npc/prague/maya.png',
    ]);
    tearDown(() => artCity = null);

    test('the city file wins: dialogue portrait, contacts / rival, feed and booth bust', () {
      expect(idx.portrait('maya', 'happy', 'tokyo'), 'npc/tokyo/maya_happy.png');
      expect(idx.avatar('maya', city: 'tokyo'), 'npc/tokyo/maya.png');
      expect(idx.bust('maya', city: 'tokyo'), 'npc/tokyo/maya_bust.png');
    });

    test('falls back to the shared file, character by character and file by file', () {
      expect(idx.portrait('theo', 'happy', 'tokyo'), 'npc/theo_happy.png');
      expect(idx.avatar('theo', city: 'tokyo'), 'npc/theo.png');
      expect(idx.bust('theo', city: 'tokyo'), 'npc/theo_bust.png');
      expect(idx.avatar('maya', city: 'prague'), 'npc/prague/maya.png');
      expect(idx.bust('maya', city: 'prague'), 'npc/maya_bust.png');
      expect(idx.bust('ray', city: 'prague'), isNull);
      expect(idx.portrait('ray', 'neutral', 'prague'), isNull);
    });

    test('the local look wins over the expression: city <id>.png before the shared expression', () {
      expect(idx.portrait('maya', 'annoyed', 'tokyo'), 'npc/tokyo/maya.png');
      expect(idx.portrait('maya', 'happy', 'prague'), 'npc/prague/maya.png');
    });

    test('New York (no npc/nyc/ folder) and no city keep the shared files', () {
      for (final city in ['nyc', null]) {
        artCity = city;
        expect(idx.portrait('maya', 'happy'), 'npc/maya_happy.png');
        expect(idx.portrait('maya', 'neutral'), 'npc/maya.png');
        expect(idx.avatar('maya'), 'npc/maya.png');
        expect(idx.bust('maya'), 'npc/maya_bust.png');
      }
    });

    test('artCity is the default city: a city switch changes every lookup', () {
      expect(idx.bust('maya'), 'npc/maya_bust.png');
      artCity = 'tokyo';
      expect(idx.bust('maya'), 'npc/tokyo/maya_bust.png');
      expect(idx.avatar('maya'), 'npc/tokyo/maya.png');
      expect(idx.portrait('maya', 'happy'), 'npc/tokyo/maya_happy.png');
      artCity = 'prague';
      expect(idx.avatar('maya'), 'npc/prague/maya.png');
      expect(idx.bust('maya'), 'npc/maya_bust.png');
      artCity = 'nyc';
      expect(idx.avatar('maya'), 'npc/maya.png');
    });

    test('the art in the repo: Prague, Tokyo and Moscow have every character, New York the shared set', () {
      final dir = Directory('../../assets/npc');
      final list = [
        for (final f in dir.listSync(recursive: true).whereType<File>())
          if (f.path.endsWith('.png')) 'npc/${f.path.substring(dir.path.length + 1).replaceAll(r'\', '/')}',
      ];
      final repo = ArtIndex(list);
      final ids = [
        for (final p in list)
          if (RegExp(r'^npc/[a-z]+_bust\.png$').hasMatch(p)) p.substring(4, p.length - '_bust.png'.length),
      ];
      expect(ids.length, greaterThanOrEqualTo(6));
      for (final city in CityId.values) {
        final at = city == CityId.nyc ? 'npc' : 'npc/${city.id}';
        for (final id in ids) {
          expect(repo.avatar(id, city: city.id), '$at/$id.png');
          expect(repo.bust(id, city: city.id), '$at/${id}_bust.png');
          for (final e in ['happy', 'neutral', 'annoyed']) {
            expect(repo.portrait(id, e, city.id), '$at/${id}_$e.png');
          }
        }
      }
    });
  });

  test('ArtCache keeps the 24 most recently used', () {
    final c = ArtCache(24);
    for (var i = 0; i < 30; i++) {
      c.provider('npc/$i.png', 64);
    }
    c.provider('npc/6.png', 64); // touch: moves to the end
    c.provider('npc/30.png', 64); // evicts the oldest (7)
    expect(c.length, 24);
    expect(c.keys.first, ('npc/8.png', 64));
    expect(c.keys.last, ('npc/30.png', 64));
    expect(c.keys.contains(('npc/6.png', 64)), isTrue);
  });

  testWidgets('NpcAvatar falls back to initials without art', (tester) async {
    artIndex = ArtIndex.empty;
    await tester.pumpWidget(
      const MaterialApp(
        home: NpcAvatar(id: 'maya', initials: 'MA', index: 0, expression: 'happy'),
      ),
    );
    expect(find.text('MA'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('NpcAvatar shows the expression art from the index', (tester) async {
    artIndex = ArtIndex(['npc/maya_happy.png']);
    await tester.pumpWidget(
      const MaterialApp(
        home: NpcAvatar(id: 'maya', initials: 'MA', index: 0, expression: 'happy'),
      ),
    );
    final img = tester.widget<Image>(find.byType(Image));
    final p = img.image as ResizeImage;
    expect((p.imageProvider as AssetImage).assetName, 'assets/shared/assets/npc/maya_happy.png');
    artIndex = ArtIndex.empty;
  });

  testWidgets('NpcAvatar follows artCity (specs/art.md v4)', (tester) async {
    addTearDown(() {
      artIndex = ArtIndex.empty;
      artCity = null;
    });
    artIndex = ArtIndex(const ['npc/maya_happy.png', 'npc/tokyo/maya_happy.png', 'npc/maya.png']);
    String shown() =>
        ((tester.widget<Image>(find.byType(Image)).image as ResizeImage).imageProvider as AssetImage).assetName;
    Future<void> pump(String? expression) => tester.pumpWidget(
      MaterialApp(
        home: NpcAvatar(key: UniqueKey(), id: 'maya', initials: 'MA', index: 0, expression: expression),
      ),
    );
    artCity = 'tokyo';
    await pump('happy');
    expect(shown(), 'assets/shared/assets/npc/tokyo/maya_happy.png');
    // Contacts / rival in Tokyo: no npc/tokyo/maya.png here, so the shared portrait.
    await pump(null);
    expect(shown(), 'assets/shared/assets/npc/maya.png');
    artCity = 'nyc';
    await pump('happy');
    expect(shown(), 'assets/shared/assets/npc/maya_happy.png');
  });
}
