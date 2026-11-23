import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_prase/mg_prase.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  testWidgets('rule cards with the target, roll, bank, give up reports aborted', (tester) async {
    final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    final env = MinigameEnv(tuning: tuning, locale: 'en');
    // First seed whose opening roll is not a one.
    var seed = 1;
    while (Prng(Prng(seed).state).nextInt(6) == 0) {
      seed++;
    }
    final die = Prng(Prng(seed).state).nextInt(6) + 1;
    MinigameResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: const PraseGame().build(
          MinigameContext(cityId: 'nyc', difficulty: 3, seed: seed, locale: 'en'),
          env,
          (r) => result = r,
        ),
      ),
    );
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('First to ${tuning.minigames.prase.target} wins.'), findsOneWidget);
    await tester.tap(find.text('Play'));
    await tester.pump();
    expect(find.text('This turn 0'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Bank')).onPressed, isNull);
    await tester.tap(find.text('Roll'));
    await tester.pump();
    expect(find.text('This turn $die'), findsOneWidget);
    await tester.tap(find.text('Bank'));
    await tester.pump();
    expect(find.text('You $die · Opponent 0'), findsOneWidget);
    expect(find.text('Opponent is thinking…'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    await tester.tap(find.text('Give up'));
    await tester.pump();
    expect(result?.aborted, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
