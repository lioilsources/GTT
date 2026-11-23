import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_bowling/mg_bowling.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  test('frame sheet marks strikes and spares', () {
    expect(frameSheet([]), '');
    expect(frameSheet([10, 7, 3, 4]), 'X · 7 / · 4');
    expect(frameSheet([...List.filled(18, 0), 10, 10, 10]), '${List.filled(9, '0 0').join(' · ')} · X X X');
  });

  testWidgets('slide, swipe up to roll, the sheet fills, give up reports aborted', (tester) async {
    final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    final env = MinigameEnv(tuning: tuning, locale: 'en');
    MinigameResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: const BowlingGame().build(
          MinigameContext(cityId: 'nyc', difficulty: 1, seed: 3, locale: 'en'),
          env,
          (r) => result = r,
        ),
      ),
    );
    expect(find.text('Slide the ball along the line, then flick it towards the pins.'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Score 0'), findsOneWidget);
    expect(find.text('Frame 1/10'), findsOneWidget);
    final lane = find.byKey(const ValueKey('lane'));
    final bottom = tester.getBottomLeft(lane) + Offset(tester.getSize(lane).width / 2, -20);
    // A short sideways slide, then a straight swipe up.
    await tester.dragFrom(bottom, const Offset(30, 0));
    await tester.pump();
    final g = await tester.startGesture(bottom);
    for (var i = 0; i < 8; i++) {
      await g.moveBy(const Offset(0, -40));
      await tester.pump();
    }
    expect(tester.widget<PowerBar>(find.byType(PowerBar)).power, greaterThan(0));
    await g.up();
    for (var i = 0; i <= tuning.minigames.bowling.maxSteps ~/ tuning.minigames.bowling.stepsPerFrame + 2; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final sheet = find.byWidgetPredicate((w) => w is Text && RegExp(r'^(X|\d)').hasMatch(w.data ?? ''));
    expect(sheet, findsOneWidget);
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    await tester.tap(find.text('Give up'));
    await tester.pump();
    expect(result?.aborted, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
