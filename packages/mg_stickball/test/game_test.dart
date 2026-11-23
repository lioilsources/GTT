import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_stickball/mg_stickball.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  testWidgets('rule cards, a pitch and a swing, give up reports aborted', (tester) async {
    final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    final env = MinigameEnv(tuning: tuning, locale: 'en');
    MinigameResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: const StickballGame().build(
          MinigameContext(cityId: 'nyc', difficulty: 1, seed: 5, locale: 'en'),
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
    expect(find.text('Runs 0'), findsOneWidget);
    expect(find.text('B 0 · S 0 · O 0'), findsOneWidget);
    // Wind-up (1.1 s) and most of the flight, then tap the mid band.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final r = tester.getRect(find.byKey(const ValueKey('stickball-field')));
    await tester.tapAt(Offset(r.center.dx, r.top + r.height * 0.69));
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining(RegExp(r'B \d · S \d · O \d')), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    await tester.tap(find.text('Give up'));
    await tester.pump();
    expect(result?.aborted, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
