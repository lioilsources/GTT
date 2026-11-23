import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_posuvne/mg_posuvne.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  testWidgets('rule cards, a tap slides a tile, give up reports aborted', (tester) async {
    final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    final env = MinigameEnv(tuning: tuning, locale: 'en');
    MinigameResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: const PosuvneGame().build(
          MinigameContext(cityId: 'nyc', difficulty: 1, seed: 7, locale: 'en'),
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
    final s = PosuvneRules().start(PosuvneConfig.fromTuning(tuning.minigames.posuvne, 1), 7);
    expect(find.text('Moves 0 · par ${s.par}'), findsOneWidget);
    final p = neighbours(s.gap).first;
    await tester.tap(find.byKey(ValueKey('posuvne-tile-$p')));
    await tester.pump();
    expect(find.text('Moves 1 · par ${s.par}'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    await tester.tap(find.text('Give up'));
    await tester.pump();
    expect(result?.aborted, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
