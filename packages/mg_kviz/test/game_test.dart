import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_kviz/mg_kviz.dart';
import 'package:shared_gen/shared_gen.dart';

const bankJson = '''
{"questions": [
  {"id": "a", "q": {"en": "Question A?", "cs": "Otázka A?"},
   "options": {"en": ["a0", "a1", "a2", "a3"], "cs": ["a0", "a1", "a2", "a3"]}, "answer": 0},
  {"id": "b", "q": {"en": "Question B?", "cs": "Otázka B?"},
   "options": {"en": ["b0", "b1", "b2", "b3"], "cs": ["b0", "b1", "b2", "b3"]}, "answer": 1},
  {"id": "c", "q": {"en": "Question C?", "cs": "Otázka C?"},
   "options": {"en": ["c0", "c1", "c2", "c3"], "cs": ["c0", "c1", "c2", "c3"]}, "answer": 2},
  {"id": "d", "q": {"en": "Question D?", "cs": "Otázka D?"},
   "options": {"en": ["d0", "d1", "d2", "d3"], "cs": ["d0", "d1", "d2", "d3"]}, "answer": 3}
]}
''';

Future<void> start(WidgetTester tester, KvizGame game, void Function(MinigameResult) onFinish) async {
  final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
  final env = MinigameEnv(tuning: tuning, locale: 'en');
  await tester.pumpWidget(
    MaterialApp(
      home: game.build(MinigameContext(cityId: 'nyc', difficulty: 3, seed: 5, locale: 'en'), env, onFinish),
    ),
  );
  for (final label in ['Next', 'Next', 'Play']) {
    await tester.tap(find.text(label));
    await tester.pump();
  }
  await tester.pump();
}

void main() {
  testWidgets('answers flash and advance, the timer answers -1, the quiz ends on the result', (tester) async {
    final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    MinigameResult? result;
    await start(tester, KvizGame(loadBank: (_) => Future.value(bankJson)), (r) => result = r);
    expect(find.text('Question 1 of 4'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('kviz-option-0')));
    await tester.pump();
    expect(find.textContaining(RegExp('Right!|Not quite')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('Question 2 of 4'), findsOneWidget);

    // The question timer runs out: answer -1, then the next question.
    await tester.pump(Duration(seconds: tuning.minigames.kviz.questionS, milliseconds: 100));
    expect(find.text('Not quite'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text('Question 3 of 4'), findsOneWidget);

    for (var k = 0; k < 2; k++) {
      await tester.tap(find.byKey(const ValueKey('kviz-option-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
    }
    expect(find.text('Back'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pump();
    expect(result?.aborted, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a city without a bank shows the not-yet text', (tester) async {
    await start(tester, KvizGame(loadBank: (_) => Future.error(StateError('no bank'))), (_) {});
    expect(find.text('Not in this client yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
