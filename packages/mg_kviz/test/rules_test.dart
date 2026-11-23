import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_kviz/mg_kviz.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

Map<String, Object?> cfg(int n, {int rounds = 10}) => {
  'bank': [for (var i = 0; i < n; i++) i % 4],
  'rounds': rounds,
  'starCorrect': [9, 7, 5],
};

/// The shown index of the right option of the current question.
int right(KvizRules r, KvizState s) => [0, 1, 2, 3].firstWhere((d) => r.isRight(s, d));

void main() {
  final r = KvizRules();

  test('draws R distinct questions and a permutation of four options each', () {
    final s = r.init(cfg(40), 11);
    expect(s.order.length, 10);
    expect(s.order.toSet().length, 10);
    for (final p in s.perms) {
      expect([...p]..sort(), [0, 1, 2, 3]);
    }
    expect(r.legalActions(s).map((a) => a.answer), [0, 1, 2, 3, -1]);
  });

  test('all right = 3 stars, -1 is wrong, timeout ends the game', () {
    var s = r.init(cfg(40), 3);
    for (var k = 0; k < 10; k++) {
      s = r.apply(s, KvizAction(right(r, s)));
    }
    expect(r.result(s)!.toJson(), {'winner': 'player', 'stars': 3, 'score': 1000, 'correct': 10, 'rounds': 10});
    var t = r.init(cfg(40), 3);
    t = r.apply(t, const KvizAction(-1));
    expect(t.correct, 0);
    t = r.apply(t, const KvizAction.timeout());
    expect(r.result(t)!.toJson(), {'winner': 'ai', 'stars': 0, 'score': 0, 'correct': 0, 'rounds': 10});
    expect(() => r.apply(t, const KvizAction(0)), throwsA(isA<IllegalAction>()));
  });

  test('a small bank scales the thresholds down (truncated)', () {
    var s = r.init(cfg(5), 9);
    expect(s.order.length, 5);
    // need = [4, 3, 2]
    for (var k = 0; k < 5; k++) {
      s = r.apply(s, KvizAction(k < 3 ? right(r, s) : -1));
    }
    expect(r.result(s)!.toJson(), {'winner': 'player', 'stars': 2, 'score': 300, 'correct': 3, 'rounds': 5});
  });

  test('an empty bank ends in init', () {
    final s = r.init(cfg(0), 1);
    expect(s.over, isTrue);
    expect(r.result(s)!.rounds, 0);
  });

  test('the bundled NYC bank parses', () {
    final f = File('$repoRoot/content/quiz/nyc.json');
    final app = File('$repoRoot/app/assets/shared/content/quiz/nyc.json');
    final src = app.existsSync() ? app : f;
    if (!src.existsSync()) return;
    final b = QuizBank.fromJson(src.readAsStringSync());
    expect(b.questions.length, greaterThanOrEqualTo(4));
    for (final q in b.questions) {
      expect(q.options['en']!.length, 4);
      expect(q.options['cs']!.length, 4);
    }
  });

  final vectors = File('$repoRoot/vectors/kviz.json').existsSync();
  test(
    'vectors/kviz.json',
    () => expect(checkVectors(KvizRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/kviz.json') ? 'pending in parity.yaml' : false,
  );
}
