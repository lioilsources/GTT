import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_dama/mg_dama.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  testWidgets('rule cards, a move by taps, the opponent answers, give up reports aborted', (tester) async {
    final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    final env = MinigameEnv(tuning: tuning, locale: 'en');
    MinigameResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: const DamaGame().build(
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
    expect(find.text('Pieces 12 : 12'), findsOneWidget);
    expect(find.text('Your turn'), findsOneWidget);

    // Square i sits at row i ~/ 4, column 2 * (i % 4) + (1 - row % 2); tap 22 then 17.
    final board = find.byKey(const ValueKey('dama-board'));
    final rect = tester.getRect(board);
    Offset at(int i) {
      final cell = rect.width / 8;
      final r = i ~/ 4, c = 2 * (i % 4) + (1 - r % 2);
      return rect.topLeft + Offset((c + 0.5) * cell, (r + 0.5) * cell);
    }

    await tester.tapAt(at(22));
    await tester.pump();
    await tester.tapAt(at(17));
    await tester.pump();
    expect(find.text('Your turn'), findsNothing);
    await tester.pump(Duration(milliseconds: (tuning.minigames.dama.aiThinkS * 1000).round() + 50));
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
