import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metropole/main.dart';
import 'package:metropole/ui/game_screen.dart';
import 'package:mg_api/mg_api.dart' show artCity;
import 'package:shared_gen/shared_gen.dart';

/// NPC portraits per city (specs/art.md v4 "Portréty podle města"): the app bundles every city
/// folder and the game screen names the city the lookups use.
void main() {
  test('pubspec.yaml bundles every NPC art folder (asset dirs are not recursive)', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync().map((l) => l.trim()).toSet();
    final npc = Directory('../assets/npc');
    final cities = [
      for (final d in npc.listSync().whereType<Directory>())
        if (d.listSync().any((f) => f.path.endsWith('.png'))) d.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
    ];
    expect(cities, containsAll(['prague', 'tokyo', 'moscow']));
    expect(pubspec, contains('- assets/shared/assets/npc/'));
    for (final c in cities) {
      expect(pubspec, contains('- assets/shared/assets/npc/$c/'), reason: 'npc/$c/ is not bundled');
      expect(CityId.values.map((v) => v.id), contains(c), reason: 'npc/$c/ is not a city id');
    }
  });

  testWidgets('the game screen sets the art city; a city switch moves it to the new city', (tester) async {
    addTearDown(() => artCity = null);
    await tester.pumpWidget(const MetropoleApp(city: CityId.tokyo));
    await tester.pump();
    expect(artCity, 'tokyo');
    // The Travel app replaces the screen (GameScreen._travel): the new screen takes over, and the
    // old one leaving does not reset it.
    tester.state<NavigatorState>(find.byType(Navigator)).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const GameScreen(city: CityId.prague, from: CityId.tokyo)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(GameScreen), findsOneWidget);
    expect(artCity, 'prague');
  });
}
