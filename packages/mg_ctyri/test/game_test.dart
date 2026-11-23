import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_ctyri/mg_ctyri.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  testWidgets('rule cards, drop a disc, the opponent answers, give up reports aborted', (tester) async {
    final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    final env = MinigameEnv(tuning: tuning, locale: 'en');
    MinigameResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: const CtyriGame().build(
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

    final rect = tester.getRect(find.byKey(const ValueKey('ctyri-board')));
    await tester.tapAt(rect.topLeft + Offset(3.5 * rect.width / cols, rect.height / 4));
    await tester.pump();
    expect(find.text('Your turn'), findsNothing);
    await tester.pump(Duration(milliseconds: (tuning.minigames.ctyri.aiThinkS * 1000).round() + 50));
    await tester.pump(const Duration(milliseconds: 300));
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
