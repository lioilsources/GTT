import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_cihly/mg_cihly.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  testWidgets('the paddle follows the finger, a missed ball costs a life, give up reports aborted', (tester) async {
    final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    final env = MinigameEnv(tuning: tuning, locale: 'en');
    final tm = tuning.minigames.cihly;
    MinigameResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: const CihlyGame().build(
          MinigameContext(cityId: 'nyc', difficulty: 3, seed: 6, locale: 'en'),
          env,
          (r) => result = r,
        ),
      ),
    );
    expect(find.text('Slide your finger to move the paddle.'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Lives ${tm.lives}'), findsOneWidget);
    // A seed whose serve flies past a paddle parked in the left corner (checked on the rules).
    final cfg = CihlyConfig.fromTuning(tm, 3);
    final rules = CihlyRules();
    var s = rules.apply(rules.apply(rules.start(cfg, 6), CihlyAction.tick(tm.serveTicks)), const CihlyAction.move(0));
    for (var i = 0; i < 3000 && s.lives == tm.lives; i++) {
      s = rules.apply(s, const CihlyAction.tick(1));
    }
    expect(s.lives, tm.lives - 1);
    // Wait out the serve with the paddle in the middle, then park it in the left corner.
    for (var i = 0; i < 1000 * tm.serveTicks ~/ tm.tickHz ~/ 16 + 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final field = find.byKey(const ValueKey('field'));
    final g = await tester.startGesture(tester.getBottomLeft(field) + const Offset(2, -2));
    for (var i = 0; i < 3000 && find.text('Lives ${tm.lives}').evaluate().isNotEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    expect(find.text('Lives ${tm.lives - 1}'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    await tester.tap(find.text('Give up'));
    await tester.pump();
    expect(result?.aborted, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
