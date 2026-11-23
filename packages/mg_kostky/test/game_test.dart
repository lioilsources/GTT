import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_kostky/mg_kostky.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  testWidgets('rule cards, roll, hold, write chance, give up reports aborted', (tester) async {
    final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    final env = MinigameEnv(tuning: tuning, locale: 'en');
    const seed = 4;
    final rules = KostkyRules();
    final first = rules.apply(
      rules.start(KostkyConfig.fromTuning(tuning.minigames.kostky), seed),
      const KostkyAction.roll('player', []),
    );
    MinigameResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: const KostkyGame().build(
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
    expect(find.text('Round 1/13'), findsOneWidget);
    await tester.tap(find.text('Roll (3 left)'));
    await tester.pump();
    expect(find.text('Roll (2 left)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('die-0')));
    await tester.pump();
    await tester.tap(find.text('Roll (2 left)'));
    await tester.pump();
    final second = rules.apply(first, const KostkyAction.roll('player', [0]));
    final chance = second.dice.fold(0, (a, b) => a + b);
    expect(second.dice[0], first.dice[0]);
    await tester.ensureVisible(find.byKey(const ValueKey('cat-Chance')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('cat-Chance')));
    await tester.pump();
    // Written: the total shows the chance and the opponent is on turn.
    expect(find.text('$chance'), findsWidgets);
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
