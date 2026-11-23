import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mg_prsi/mg_prsi.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';

const cfg = {
  'hand': 4,
  'roundsToWin': 3,
  'aiErrorPct': [40, 25, 12, 5, 0],
};

void main() {
  test('deal: alternate cards, one turned up, the player starts round 1', () {
    final r = PrsiRules();
    final s = r.init(cfg, 1);
    expect([s.player.length, s.ai.length, s.pile.length, s.deck.length], [4, 4, 1, 23]);
    expect({...s.deck, ...s.player, ...s.ai, ...s.pile}.length, 32);
    expect([s.turn, s.starter, s.round, s.last, s.suit], ['player', 'player', 1, '', suitOf(s.pile.last)]);
  });

  test('legal actions: match suit or rank, svršek anywhere with 4 suits, draw last', () {
    final r = PrsiRules();
    final b = r.init(cfg, 1).copyWith(turn: 'player', sevens: 0, ace: false);
    // Top: zelená 9 (10); hand: červená 9 (2), zelená 8 (9), kule svršek (21), žalud 10 (27).
    final s = b.copyWith(player: [27, 21, 9, 2], pile: [10], suit: 1);
    expect(r.legalActions(s), [
      const PrsiAction.play('player', 2),
      const PrsiAction.play('player', 9),
      const PrsiAction.play('player', 21, 0),
      const PrsiAction.play('player', 21, 1),
      const PrsiAction.play('player', 21, 2),
      const PrsiAction.play('player', 21, 3),
      const PrsiAction.draw('player'),
    ]);
    // Sevens: only sevens or draw; ace: only aces or stand (no svršek on either).
    expect(r.legalActions(s.copyWith(player: [8, 16, 21], sevens: 1)), [
      const PrsiAction.play('player', 8),
      const PrsiAction.play('player', 16),
      const PrsiAction.draw('player'),
    ]);
    expect(r.legalActions(s.copyWith(player: [15, 21], ace: true)), [
      const PrsiAction.play('player', 15),
      const PrsiAction.stand('player'),
    ]);
  });

  test('rejects illegal moves', () {
    final r = PrsiRules();
    final s = r.init(cfg, 1).copyWith(player: [27, 21, 9, 2], pile: [10], suit: 1, sevens: 0, ace: false);
    expect(() => r.apply(s, const PrsiAction.play('player', 27)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const PrsiAction.play('player', 21)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const PrsiAction.play('player', 2, 0)), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const PrsiAction.draw('ai')), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const PrsiAction.stand('player')), throwsA(isA<IllegalAction>()));
  });

  test('sevens stack, the penalty reshuffles the pile mid-draw', () {
    final r = PrsiRules();
    final b = r.init(cfg, 1);
    var s = b.copyWith(player: [0, 3], ai: [8, 4], pile: [11, 12, 13, 1], deck: [30], suit: 0, sevens: 0, ace: false);
    s = r.apply(s, const PrsiAction.play('player', 0));
    expect([s.sevens, s.suit, s.turn], [1, 0, 'ai']);
    s = r.apply(s, const PrsiAction.play('ai', 8));
    expect([s.sevens, s.turn], [2, 'player']);
    s = r.apply(s, const PrsiAction.draw('player'));
    // 30 from the deck, then pile [11, 12, 13, 1, 0] without its top 8 is shuffled into the deck.
    expect(
      [s.player.length, s.player.take(2).toList(), s.pile, s.deck.length, s.sevens, s.turn],
      [
        5,
        [3, 30],
        [8],
        2,
        0,
        'ai',
      ],
    );
    expect(s.rng, isNot(b.rng));
  });

  test('nothing to draw: the turn passes and rng stays', () {
    final r = PrsiRules();
    final s = r.init(cfg, 1).copyWith(deck: const [], pile: [5], player: [1, 2], sevens: 0, ace: false, suit: 0);
    final n = r.apply(s, const PrsiAction.draw('player'));
    expect(
      [n.player, n.turn, n.rng],
      [
        [1, 2],
        'ai',
        s.rng,
      ],
    );
  });

  test('last card ends the round; the game end keeps hands and the seven', () {
    final r = PrsiRules();
    final b = r.init(cfg, 1);
    final s = b.copyWith(player: [16], ai: [3, 4], pile: [17], suit: 2, sevens: 0, ace: false, playerWins: 2);
    final n = r.apply(s, const PrsiAction.play('player', 16));
    expect(
      [n.over, n.playerWins, n.last, n.turn, n.sevens, n.player, n.ai, n.pile],
      [
        true,
        3,
        'player',
        'player',
        1,
        <int>[],
        [3, 4],
        [17, 16],
      ],
    );
    expect(r.result(n)!.toJson(), {'winner': 'player', 'stars': 3, 'score': 300, 'playerWins': 3, 'aiWins': 0});
    final next = r.apply(s.copyWith(playerWins: 0), const PrsiAction.play('player', 16));
    expect([next.round, next.starter, next.turn, next.last, next.player.length], [2, 'ai', 'ai', 'player', 4]);
  });

  test('AI prefers a long suit, a svršek to its strongest suit', () {
    final r = PrsiRules();
    final b = r.init(cfg, 1).copyWith(turn: 'ai', sevens: 0, ace: false, player: [1, 2, 3, 4]);
    // Top červená 9 (2): červená 10 (3) is the first card that keeps two more červené.
    final s = b.copyWith(ai: [3, 4, 6, 10, 13], pile: [2], suit: 0);
    expect(r.aiAction(s, 5, aiPrng(1)), const PrsiAction.play('ai', 3));
    final q = b.copyWith(ai: [13, 26, 27], pile: [9], suit: 1);
    expect(r.aiAction(q, 5, aiPrng(1)), const PrsiAction.play('ai', 13, 3));
  });

  final vectors = File('$repoRoot/vectors/prsi.json').existsSync();
  test(
    'vectors/prsi.json',
    () => expect(checkVectors(PrsiRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/prsi.json') ? 'pending in parity.yaml' : false,
  );
}
