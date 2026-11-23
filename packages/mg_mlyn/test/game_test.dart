import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_mlyn/mg_mlyn.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  testWidgets('rule cards, a stone by tap, the opponent answers, give up reports aborted', (tester) async {
    final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    final env = MinigameEnv(tuning: tuning, locale: 'en');
    MinigameResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: const MlynGame().build(
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
    expect(find.text('In hand 9 : 9'), findsOneWidget);
    expect(find.text('Your turn'), findsOneWidget);

    final rect = tester.getRect(find.byKey(const ValueKey('mlyn-board')));
    await tester.tapAt(rect.topLeft + mlynPoint(4, rect.width));
    await tester.pump();
    expect(find.text('In hand 8 : 9'), findsOneWidget);
    expect(find.text('Your turn'), findsNothing);
    await tester.pump(Duration(milliseconds: (tuning.minigames.mlyn.aiThinkS * 1000).round() + 50));
    expect(find.text('Your turn'), findsOneWidget);
    expect(find.text('In hand 8 : 8'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    await tester.tap(find.text('Give up'));
    await tester.pump();
    expect(result?.aborted, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
