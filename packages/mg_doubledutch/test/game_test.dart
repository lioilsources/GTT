import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_doubledutch/mg_doubledutch.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  testWidgets('rule cards, a tap on the beat, a missed beat trips, give up reports aborted', (tester) async {
    final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    final env = MinigameEnv(tuning: tuning, locale: 'en');
    final tm = tuning.minigames.doubledutch;
    MinigameResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: const DoubledutchGame().build(
          MinigameContext(cityId: 'nyc', difficulty: 1, seed: 5, locale: 'en'),
          env,
          (r) => result = r,
        ),
      ),
    );
    for (final label in ['Next', 'Next', 'Play']) {
      await tester.tap(find.text(label));
      await tester.pump();
    }
    expect(find.text('Trips 0/${tm.maxTrips}'), findsOneWidget);
    // Up to the first beat, then tap it (a tap is input 0; level 1 has no tricks).
    await tester.pump();
    for (var ms = 0; ms < tm.leadInMs; ms += 100) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const ValueKey('doubledutch-field')));
    await tester.pump();
    expect(find.textContaining(RegExp(r'^(Perfect!|Good|OK)$')), findsOneWidget);
    expect(find.text('Trips 0/${tm.maxTrips}'), findsOneWidget);
    // Let the next beat pass without input: a trip.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Trips 1/${tm.maxTrips}'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    await tester.tap(find.text('Give up'));
    await tester.pump();
    expect(result?.aborted, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
