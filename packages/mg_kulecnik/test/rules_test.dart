import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_kulecnik/mg_kulecnik.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  final tuning = Tuning.fromYaml(File('$repoRoot/content/tuning.yaml').readAsStringSync());
  final cfg = KulecnikConfig.fromTuning(tuning.minigames.kulecnik);

  test('racks fifteen balls in a triangle above the cue', () {
    final s = KulecnikRules().start(cfg);
    expect(s.balls.length, 16);
    expect([s.balls[0].x, s.balls[0].y], [cfg.tableW ~/ 2, cfg.tableH ~/ 4]);
    expect([s.balls[cfg.rack[0]].x, s.balls[cfg.rack[0]].y], [cfg.tableW ~/ 2, 3 * cfg.tableH ~/ 4]);
    expect(s.balls.every((b) => b.on), isTrue);
    expect(s.toJson()['last'], {'by': '', 'firstHit': -1, 'pots': <int>[], 'foul': false});
    expect(s.toJson()['playerGroup'], '');
  });

  test('rejects illegal shots', () {
    final r = KulecnikRules();
    final s = r.start(cfg);
    final cue = s.balls[0];
    expect(() => r.apply(s, KulecnikAction.shot('ai', 0, 0, 50)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, KulecnikAction.shot('player', 0, 0, 0)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, KulecnikAction.shot('player', 0, 0, 101)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, KulecnikAction.shot('player', cue.x, cue.y, 50)), throwsA(isA<IllegalAction>()));
    final over = r.apply(s, const KulecnikAction.timeout());
    expect([over.over, over.winner, over.turn, over.shots], [true, 'draw', 'player', 0]);
    expect(() => r.apply(over, KulecnikAction.shot('player', 0, 0, 50)), throwsA(isA<IllegalAction>()));
  });

  test('a shot that hits nothing is a foul and passes the turn', () {
    final r = KulecnikRules();
    final s = r.apply(r.start(cfg).copyWithShots(1), KulecnikAction.shot('player', 0, cfg.tableH ~/ 4, 1));
    expect([s.last.firstHit, s.last.foul, s.turn, s.shots], [-1, true, 'ai', 2]);
  });

  test('the AI breaks at the head ball and always draws two scatter numbers', () {
    final r = KulecnikRules();
    final s = r.start(cfg);
    final ai = aiPrng(7);
    final copy = aiPrng(7);
    final a = r.aiAction(s, 5, ai);
    final sc = cfg.aiScatter[4];
    copy
      ..nextInt(2 * sc + 1)
      ..nextInt(2 * sc + 1);
    expect(ai.state, copy.state);
    expect([a.by, a.op, a.power], ['ai', 'shot', 100]);
  });

  final vectors = File('$repoRoot/vectors/kulecnik.json').existsSync();
  test(
    'vectors/kulecnik.json',
    () => expect(checkVectors(KulecnikRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/kulecnik.json') ? 'pending in parity.yaml' : false,
  );
}

extension on KulecnikState {
  KulecnikState copyWithShots(int shots) => KulecnikState(
    balls: balls,
    turn: turn,
    playerGroup: playerGroup,
    shots: shots,
    last: last,
    winner: winner,
    over: over,
  );
}
