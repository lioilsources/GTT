import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_srdce/mg_srdce.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  testWidgets('rule cards, lead the two of clubs, opponents follow, give up reports aborted', (tester) async {
    final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    final env = MinigameEnv(tuning: tuning, locale: 'en');
    final cfg = SrdceConfig.fromTuning(tuning.minigames.srdce);
    // First seed where the player holds the two of clubs and leads.
    var seed = 1;
    while (SrdceRules().start(cfg, seed).turn != 0) {
      seed++;
    }
    MinigameResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: const SrdceGame().build(
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
    expect(find.text('Deal 1 of ${cfg.maxDeals}'), findsOneWidget);
    expect(find.text('Your turn'), findsOneWidget);
    expect(find.byKey(const ValueKey('card-$twoOfClubs')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('card-$twoOfClubs')));
    await tester.pump();
    expect(find.byKey(const ValueKey('card-$twoOfClubs')), findsNothing);
    expect(find.text('Opponent is thinking…'), findsOneWidget);
    // The three opponents answer one by one and the first trick is complete.
    final think = (tuning.minigames.srdce.aiThinkS * 1000).round();
    for (var i = 0; i < 3; i++) {
      await tester.pump(Duration(milliseconds: think + 10));
    }
    final r = SrdceRules();
    final ai = aiPrng(seed);
    var s = r.apply(r.start(cfg, seed), const SrdceAction('player', twoOfClubs));
    for (var i = 0; i < 3; i++) {
      s = r.apply(s, r.aiAction(s, 3, ai));
    }
    expect(s.tricks, 1);
    expect(
      find.byWidgetPredicate(
        (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('card-'),
      ),
      findsNWidgets(12),
    );
    if (s.turn == 0) expect(find.text('Your turn'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    await tester.tap(find.text('Give up'));
    await tester.pump();
    expect(result?.aborted, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
