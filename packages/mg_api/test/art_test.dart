import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';

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
}
