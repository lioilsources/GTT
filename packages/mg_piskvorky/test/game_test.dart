import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_piskvorky/mg_piskvorky.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  testWidgets('rule cards, select and confirm a square, the opponent answers, give up reports aborted', (
    tester,
  ) async {
    final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    final env = MinigameEnv(tuning: tuning, locale: 'en');
    MinigameResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: const PiskvorkyGame().build(
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
    expect(find.text('Your turn'), findsOneWidget);

    final n = tuning.minigames.piskvorky.size;
    final rect = tester.getRect(find.byKey(const ValueKey('piskvorky-board')));
    final cell = rect.width / n;
    final centre = rect.topLeft + Offset((n ~/ 2 + 0.5) * cell, (n ~/ 2 + 0.5) * cell);
    await tester.tapAt(centre);
    await tester.pump();
    expect(find.text('Tap again to place'), findsOneWidget);
    await tester.tapAt(centre);
    await tester.pump();
    expect(find.text('Your turn'), findsNothing);
    await tester.pump(Duration(milliseconds: (tuning.minigames.piskvorky.aiThinkS * 1000).round() + 50));
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
