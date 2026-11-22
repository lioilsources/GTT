import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_kulicky/mg_kulicky.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  testWidgets('rule cards, a flick plays a marble, give up reports aborted', (tester) async {
    final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    final env = MinigameEnv(tuning: tuning, locale: 'en');
    MinigameResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: const KulickyGame().build(
          MinigameContext(cityId: 'prague', difficulty: 3, seed: 5, locale: 'en'),
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
    expect(find.text('Round 1/5 · you 0 : 0'), findsOneWidget);
    await tester.dragFrom(tester.getCenter(find.byType(GestureDetector).last), const Offset(20, -180));
    await tester.pump();
    expect(find.text('Opponent is thinking…'), findsOneWidget);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining(RegExp('Round (won!|lost)|Draw')), findsOneWidget);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Your turn'), findsOneWidget);
    expect(find.textContaining('Round 2/5'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    await tester.tap(find.text('Give up'));
    await tester.pump();
    expect(result?.aborted, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
