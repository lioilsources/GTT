import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_oko/mg_oko.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  testWidgets('rule cards, stand, the banker draws and the round is lost, give up reports aborted', (tester) async {
    final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    final env = MinigameEnv(tuning: tuning, locale: 'en');
    MinigameResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: const OkoGame().build(
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
    // Seed 5: no natural at the deal, the player holds 15, the banker shows one card.
    expect(find.text('You  15'), findsOneWidget);
    expect(find.text('Rounds 0 : 0'), findsOneWidget);
    expect(find.text('Your turn'), findsOneWidget);
    await tester.tap(find.text('Stand'));
    await tester.pump();
    // The banker draws one card after dealer_draw_s, then the outcome flashes.
    await tester.pump(Duration(milliseconds: (tuning.minigames.oko.dealerDrawS * 1000).round() + 50));
    expect(find.text('Round lost'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Rounds 0 : 1'), findsOneWidget);
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
