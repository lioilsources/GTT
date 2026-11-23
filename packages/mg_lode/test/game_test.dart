import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_lode/mg_lode.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  testWidgets('rule cards, re-deal, a missed shot, the opponent fires, give up reports aborted', (tester) async {
    final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    final env = MinigameEnv(tuning: tuning, locale: 'en');
    MinigameResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: const LodeGame().build(
          MinigameContext(cityId: 'nyc', difficulty: 3, seed: 5, locale: 'en'),
          env,
          (r) => result = r,
        ),
      ),
    );
    for (final label in ['Next', 'Next', 'Play']) {
      await tester.tap(find.text(label));
      await tester.pump();
    }
    await tester.pump();
    expect(find.text('Shots 0'), findsOneWidget);
    expect(find.text('Your turn'), findsOneWidget);
    final n = tuning.minigames.lode.shuffles;
    await tester.tap(find.text('Re-deal ($n)'));
    await tester.pump();
    expect(find.text('Re-deal (${n - 1})'), findsOneWidget);

    // The AI fleet comes from the same seed; fire at a cell with no ship.
    final s = LodeRules().start(LodeConfig.fromTuning(tuning.minigames.lode), 5);
    final water = [for (var i = 0; i < 100; i++) i].firstWhere((i) => !s.aShips.any((sh) => sh.contains(i)));
    final rect = tester.getRect(find.byKey(const ValueKey('lode-rival')));
    final cell = rect.width / 10;
    await tester.tapAt(rect.topLeft + Offset((water % 10 + 0.5) * cell, (water ~/ 10 + 0.5) * cell));
    await tester.pump();
    expect(find.text('Shots 1'), findsOneWidget);
    expect(find.textContaining('Re-deal'), findsNothing);
    expect(find.text('Your turn'), findsNothing);
    // The AI fires until it misses; each shot waits ai_think_s.
    final think = Duration(milliseconds: (tuning.minigames.lode.aiThinkS * 1000).round() + 50);
    for (var k = 0; k < 30 && find.text('Your turn').evaluate().isEmpty; k++) {
      await tester.pump(think);
    }
    expect(find.text('Your turn'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    await tester.tap(find.text('Give up'));
    await tester.pump();
    expect(result?.aborted, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
