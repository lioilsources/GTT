import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_kulecnik/mg_kulecnik.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  testWidgets('rule cards, a drag breaks, the shot plays out, give up reports aborted', (tester) async {
    final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    final env = MinigameEnv(tuning: tuning, locale: 'en');
    MinigameResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: const KulecnikGame().build(
          MinigameContext(cityId: 'nyc', difficulty: 3, seed: 4, locale: 'en'),
          env,
          (r) => result = r,
        ),
      ),
    );
    expect(find.text('Drag back from the white ball: the direction aims, the length sets the power.'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Open table'), findsOneWidget);
    expect(find.text('Your turn'), findsOneWidget);
    // Straight up from the cue ball, full length: the break.
    final table = find.byKey(const ValueKey('table'));
    final g = await tester.startGesture(tester.getCenter(table));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(0, -40));
      await tester.pump();
    }
    expect(tester.widget<PowerBar>(find.byType(PowerBar)).power, greaterThan(0));
    await g.up();
    await tester.pump();
    expect(find.text('Your turn'), findsOneWidget);
    expect(tester.widget<PowerBar>(find.byType(PowerBar)).power, 0);
    // Playback: at most max_steps / steps_per_frame frames.
    for (var i = 0; i <= tuning.minigames.kulecnik.maxSteps ~/ tuning.minigames.kulecnik.stepsPerFrame; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      find.text('Opponent is thinking…').evaluate().isNotEmpty || find.text('Your turn').evaluate().isNotEmpty,
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
