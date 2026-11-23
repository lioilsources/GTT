import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_krtek/mg_krtek.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  test('holes sit in a grid three wide, centred', () {
    final cells = holeCells(const Size(300, 300), 9);
    expect(cells.first.c, const Offset(50, 50));
    expect(cells[4].c, const Offset(150, 150));
    expect(cells.last.r, 36);
  });

  testWidgets('a tap on the first mole scores, give up reports aborted', (tester) async {
    final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    final env = MinigameEnv(tuning: tuning, locale: 'en');
    final tm = tuning.minigames.krtek;
    // Where and what the first mole is (same rules, same seed).
    final rules = KrtekRules();
    final first = rules.apply(rules.start(KrtekConfig.fromTuning(tm, 1), 5), KrtekAction.tick(tm.firstSpawn));
    final hole = first.holes.indexWhere((h) => h.kind != '');
    final kind = first.holes[hole].kind;
    MinigameResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: const KrtekGame().build(
          MinigameContext(cityId: 'nyc', difficulty: 1, seed: 5, locale: 'en'),
          env,
          (r) => result = r,
        ),
      ),
    );
    expect(find.text('Tap the moles as they pop up.'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump();
    expect(find.text('${tm.gameTicks ~/ tm.tickHz} s'), findsOneWidget);
    for (var i = 0; i < 1000 * (tm.firstSpawn + 2) ~/ tm.tickHz ~/ 16 + 2; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final holes = find.byKey(const ValueKey('holes'));
    final cell = holeCells(tester.getSize(holes), tm.holes)[hole];
    await tester.tapAt(tester.getTopLeft(holes) + cell.c);
    await tester.pump();
    final score = switch (kind) {
      'gold' => tm.goldPoints,
      'mole' => tm.points,
      _ => 0,
    };
    expect(find.text('Score $score'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    await tester.tap(find.text('Give up'));
    await tester.pump();
    expect(result?.aborted, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
