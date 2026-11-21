import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_sipky/mg_sipky.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  testWidgets('rule cards, a throw, give up reports aborted', (tester) async {
    final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    final env = MinigameEnv(tuning: tuning, locale: 'en');
    MinigameResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: const SipkyGame().build(
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
    expect(find.text('You 301 · Opponent 301'), findsOneWidget);
    expect(find.text('Dart 1/3'), findsOneWidget);
    final board = tester.getCenter(find.byType(GestureDetector).last);
    final g = await tester.startGesture(board + const Offset(0, -10));
    await tester.pump(const Duration(milliseconds: 100));
    await g.moveBy(const Offset(0, -30));
    await tester.pump(const Duration(milliseconds: 100));
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Dart 2/3'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    await tester.tap(find.text('Give up'));
    await tester.pump();
    expect(result?.aborted, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
