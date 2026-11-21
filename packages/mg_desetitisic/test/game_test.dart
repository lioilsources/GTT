import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_desetitisic/mg_desetitisic.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  testWidgets('rule cards, roll, select and keep a die, give up reports aborted', (tester) async {
    final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    final env = MinigameEnv(tuning: tuning, locale: 'en');
    // First seed whose opening roll has a single 1 or 5 to tap.
    var seed = 1;
    while (!rollDice(Prng(seed).state, 6).values.any((v) => v == 1 || v == 5)) {
      seed++;
    }
    final roll = rollDice(Prng(seed).state, 6).values;
    final pick = roll.indexWhere((v) => v == 1 || v == 5);
    final points = roll[pick] == 1 ? 100 : 50;
    MinigameResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: const DesetitisicGame().build(
          MinigameContext(cityId: 'nyc', difficulty: 3, seed: seed, locale: 'en'),
          env,
          (r) => result = r,
        ),
      ),
    );
    for (final label in ['Next', 'Next', 'Play']) {
      await tester.tap(find.text(label));
      await tester.pump();
    }
    expect(find.text('This turn: 0'), findsOneWidget);
    await tester.tap(find.text('Roll'));
    await tester.pump();
    expect(find.text('Keep 0'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('die-$pick')));
    await tester.pump();
    await tester.tap(find.text('Keep $points'));
    await tester.pump();
    expect(find.text('This turn: $points'), findsOneWidget);
    expect(find.text('Bank $points'), findsOneWidget);
    await tester.tap(find.text('Bank $points'));
    await tester.pump();
    expect(find.text('You $points · Opponent 0'), findsOneWidget);
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
