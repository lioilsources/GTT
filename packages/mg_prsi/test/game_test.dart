import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_prsi/mg_prsi.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  testWidgets('rule cards, a svršek asks for the suit, give up reports aborted', (tester) async {
    final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    final env = MinigameEnv(tuning: tuning, locale: 'en');
    final cfg = PrsiConfig.fromTuning(tuning.minigames.prsi);
    // First seed whose opening hand holds a svršek and no seven or ace is turned up.
    var seed = 1;
    PrsiState s() => PrsiRules().start(cfg, seed);
    while (s().sevens > 0 || s().ace || !s().player.any((c) => rankOf(c) == prsiQueen)) {
      seed++;
    }
    final queen = s().player.firstWhere((c) => rankOf(c) == prsiQueen);
    MinigameResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: const PrsiGame().build(
          MinigameContext(cityId: 'nyc', difficulty: 3, seed: seed, locale: 'en'),
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
    expect(find.text('Rounds 0 : 0'), findsOneWidget);
    expect(find.text('Your turn'), findsOneWidget);
    expect(find.text('Draw'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('card-$queen')));
    await tester.pump();
    expect(find.text('Pick a suit'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('suit-2')));
    await tester.pump();
    expect(find.byKey(ValueKey('card-$queen')), findsNothing);
    expect(find.text('Bells'), findsOneWidget);
    expect(find.text('Opponent is thinking…'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    await tester.tap(find.text('Give up'));
    await tester.pump();
    expect(result?.aborted, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
