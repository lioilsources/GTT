import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_had/mg_had.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  test('a swipe turns along its main axis once it is long enough', () {
    expect(swipeDir(const Offset(10, -5)), isNull);
    expect(swipeDir(const Offset(30, 5)), 1);
    expect(swipeDir(const Offset(-30, 5)), 3);
    expect(swipeDir(const Offset(5, 30)), 2);
    expect(swipeDir(const Offset(5, -30)), 0);
  });

  testWidgets('the snake runs on its own, a swipe turns it into the wall, the game ends', (tester) async {
    final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    final env = MinigameEnv(tuning: tuning, locale: 'en');
    MinigameResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: const HadGame().build(
          MinigameContext(cityId: 'nyc', difficulty: 5, seed: 2, locale: 'en'),
          env,
          (r) => result = r,
        ),
      ),
    );
    expect(find.text('Swipe to turn the snake.'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Length 3'), findsOneWidget);
    expect(find.text('Score 0'), findsOneWidget);
    // Turn left: the snake heads for the side wall and crashes there.
    final g = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('grid'))));
    await g.moveBy(const Offset(-40, 0));
    await g.up();
    for (var i = 0; i < 60 * 20 && result == null && find.text('Back').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Back'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pump();
    expect(result?.aborted, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
