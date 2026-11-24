import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_sachy/mg_sachy.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  testWidgets('rule cards, first moves, give up reports aborted', (tester) async {
    final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    final env = MinigameEnv(tuning: tuning, locale: 'en');
    MinigameResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: const SachyGame().build(
          MinigameContext(cityId: 'moscow', difficulty: 3, seed: 5, locale: 'en'),
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
    expect(find.text('Material 25 : 25'), findsOneWidget);
    expect(find.text('Your turn'), findsOneWidget);
    final rect = tester.getRect(find.byKey(const ValueKey('sachy-board')));
    final cell = rect.width / 5;
    Future<void> tapCell(int i) => tester.tapAt(rect.topLeft + Offset((i % 5 + 0.5) * cell, (i ~/ 5 + 0.5) * cell));
    await tapCell(17); // pawn
    await tester.pump();
    await tapCell(12);
    await tester.pump();
    expect(find.text('Your turn'), findsNothing);
    await tester.pump(Duration(milliseconds: (tuning.minigames.sachy.aiThinkS * 1000).round() + 50));
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
