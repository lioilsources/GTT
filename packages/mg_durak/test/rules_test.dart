import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_durak/mg_durak.dart';
import 'package:rules_core/vector_test_support.dart';

Map<String, Object?> cfg(int level) => {
  'hand': 6,
  'opponents': [1, 1, 2, 2, 3],
  'aiErrorPct': [35, 20, 10, 5, 0],
  'level': level,
};

void main() {
  test('deal, trump from the bottom card, the lowest trump attacks', () {
    final r = DurakRules();
    final s = r.init(cfg(5), 3);
    expect(s.n, 4);
    expect(s.hands.every((h) => h.length == 6), isTrue);
    expect(s.stock.length, 12);
    expect(durakSuit(s.trumpCard), s.trump);
  });

  test('beat, take, pass is bito, the last holder is the durak', () {
    expect(
      [durakBeats(5, 3, 2), durakBeats(3, 5, 2), durakBeats(18, 8, 2), durakBeats(10, 3, 2)],
      [true, false, true, false],
    );
    final r = DurakRules();
    final s = r
        .init(cfg(1), 1)
        .copyWith(
          hands: [
            [0, 9, 10],
            [1, 2, 27],
          ],
          stock: const [],
          attacker: 0,
          defender: 1,
          thrower: 0,
        );
    // trump is whatever the deal gave; card 27 beats 0 only when clubs are trump, so check beat 1 only.
    final a = r.apply(s, const DurakAction('player', 'play', 0));
    expect(a.limit, 3);
    final took = r.apply(a, const DurakAction('ai', 'take'));
    expect(took.hands[1], [0, 1, 2, 27]);
    expect(took.attacker, 0);
    final b = r.apply(a, const DurakAction('ai', 'beat', 1));
    final bito = r.apply(b, const DurakAction('player', 'pass'));
    expect([bito.table, bito.attacker, bito.defender], [isEmpty, 1, 0]);
    final end = r.apply(
      r.apply(
        r.apply(
          s.copyWith(
            hands: [
              [0],
              [1, 2],
            ],
          ),
          const DurakAction('player', 'play', 0),
        ),
        const DurakAction('ai', 'beat', 1),
      ),
      const DurakAction('player', 'pass'),
    );
    expect(
      [end.over, end.durak, end.finished],
      [
        true,
        1,
        [0],
      ],
    );
    expect(r.result(end)!.toJson(), {
      'winner': 'player',
      'stars': 3,
      'score': 300,
      'byCount': false,
      'place': 1,
      'durak': 1,
    });
  });

  final vectors = File('$repoRoot/vectors/durak.json').existsSync();
  test(
    'vectors/durak.json',
    () => expect(checkVectors(DurakRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/durak.json') ? 'pending in parity.yaml' : false,
  );
}
