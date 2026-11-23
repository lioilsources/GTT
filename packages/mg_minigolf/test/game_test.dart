import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_minigolf/mg_minigolf.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  testWidgets('drag from the ball to putt, the stroke counts, give up reports aborted', (tester) async {
    final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    final env = MinigameEnv(tuning: tuning, locale: 'en');
    final par = tuning.minigames.minigolf.h1[2];
    MinigameResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: const MinigolfGame().build(
          MinigameContext(cityId: 'nyc', difficulty: 2, seed: 8, locale: 'en'),
          env,
          (r) => result = r,
        ),
      ),
    );
    expect(find.text(tr('en', MessageKey.minigolfRules1)), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Hole 1/6 · par $par'), findsOneWidget);
    expect(find.text('Strokes 0'), findsOneWidget);
    final course = find.byKey(const ValueKey('course'));
    final g = await tester.startGesture(tester.getCenter(course));
    for (var i = 0; i < 4; i++) {
      await g.moveBy(const Offset(0, -30));
      await tester.pump();
    }
    expect(tester.widget<PowerBar>(find.byType(PowerBar)).power, greaterThan(0));
    await g.up();
    for (var i = 0; i <= tuning.minigames.minigolf.maxSteps ~/ tuning.minigames.minigolf.stepsPerFrame + 2; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.text('Strokes 1').evaluate().isNotEmpty || find.textContaining('Hole 2/6').evaluate().isNotEmpty,
      isTrue,
    );
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    await tester.tap(find.text('Give up'));
    await tester.pump();
    expect(result?.aborted, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
