import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_koulena/mg_koulena.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  testWidgets('rule cards, a flick rolls a ball, give up reports aborted', (tester) async {
    final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    final env = MinigameEnv(tuning: tuning, locale: 'en');
    MinigameResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: const KoulenaGame().build(
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
    expect(find.text('Series 1/3 · ball 1/9'), findsOneWidget);
    await tester.dragFrom(tester.getCenter(find.byType(GestureDetector).last), const Offset(0, -180));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Series 1/3 · ball 2/9'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    await tester.tap(find.text('Give up'));
    await tester.pump();
    expect(result?.aborted, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
