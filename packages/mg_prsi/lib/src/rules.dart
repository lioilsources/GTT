import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/prsi.md, version 1. Pure Dart: no Flutter imports here.
class PrsiConfig {
  const PrsiConfig({required this.hand, required this.roundsToWin, required this.aiErrorPct});

  factory PrsiConfig.fromTuning(TuningMinigamesPrsi t) =>
      PrsiConfig(hand: t.hand, roundsToWin: t.roundsToWin, aiErrorPct: List.unmodifiable(t.aiErrorPct));

  factory PrsiConfig.fromJson(Map<String, Object?> j) => PrsiConfig(
    hand: j['hand'] as int,
    roundsToWin: j['roundsToWin'] as int,
    aiErrorPct: List.unmodifiable((j['aiErrorPct'] as List).cast<int>()),
  );

  final int hand, roundsToWin;
  final List<int> aiErrorPct;
}

/// Card 0–31: suit = c div 8 (červené, zelené, kule, žaludy), rank = c mod 8
/// (7, 8, 9, 10, spodek, svršek, král, eso).
int suitOf(int c) => c ~/ 8;
int rankOf(int c) => c % 8;
const prsiSeven = 0;
const prsiQueen = 5;
const prsiAce = 7;

class PrsiState {
  const PrsiState({
    required this.deck,
    required this.player,
    required this.ai,
    required this.pile,
    required this.suit,
    required this.sevens,
    required this.ace,
    required this.turn,
    required this.starter,
    required this.round,
    required this.playerWins,
    required this.aiWins,
    required this.last,
    required this.over,
    required this.rng,
  });

  /// Draw pile (top = first), hands in drawing order, discard pile (top = last).
  final List<int> deck, player, ai, pile;

  /// Suit in force (0–3): the top card's, or the one chosen with a svršek.
  final int suit;

  /// Sevens in a row nobody has taken yet; the side on turn draws 2 × sevens.
  final int sevens;

  /// The top ace still holds (stand, or answer with an ace).
  final bool ace;

  /// 'player' or 'ai'.
  final String turn, starter;
  final int round, playerWins, aiWins;

  /// '' | 'player' | 'ai': winner of the last finished round (UI).
  final String last;
  final bool over;
  final int rng;

  List<int> hand(String side) => side == 'player' ? player : ai;

  PrsiState copyWith({
    List<int>? deck,
    List<int>? player,
    List<int>? ai,
    List<int>? pile,
    int? suit,
    int? sevens,
    bool? ace,
    String? turn,
    String? starter,
    int? round,
    int? playerWins,
    int? aiWins,
    String? last,
    bool? over,
    int? rng,
  }) => PrsiState(
    deck: deck ?? this.deck,
    player: player ?? this.player,
    ai: ai ?? this.ai,
    pile: pile ?? this.pile,
    suit: suit ?? this.suit,
    sevens: sevens ?? this.sevens,
    ace: ace ?? this.ace,
    turn: turn ?? this.turn,
    starter: starter ?? this.starter,
    round: round ?? this.round,
    playerWins: playerWins ?? this.playerWins,
    aiWins: aiWins ?? this.aiWins,
    last: last ?? this.last,
    over: over ?? this.over,
    rng: rng ?? this.rng,
  );

  Map<String, Object?> toJson() => {
    'deck': [...deck],
    'player': [...player],
    'ai': [...ai],
    'pile': [...pile],
    'suit': suit,
    'sevens': sevens,
    'ace': ace,
    'turn': turn,
    'starter': starter,
    'round': round,
    'playerWins': playerWins,
    'aiWins': aiWins,
    'last': last,
    'over': over,
    'rng': rng,
  };
}

/// {by, op: play, card, suit} | {by, op: draw} | {by, op: stand} | {by: timeout}.
class PrsiAction {
  const PrsiAction(this.by, this.op, {this.card = -1, this.suit = -1});
  const PrsiAction.play(this.by, this.card, [this.suit = -1]) : op = 'play';
  const PrsiAction.draw(this.by) : op = 'draw', card = -1, suit = -1;
  const PrsiAction.stand(this.by) : op = 'stand', card = -1, suit = -1;
  const PrsiAction.timeout() : by = 'timeout', op = '', card = -1, suit = -1;

  final String by, op;
  final int card;

  /// Chosen suit for a svršek (0–3), −1 for every other card.
  final int suit;

  Map<String, Object?> toJson() => by == 'timeout'
      ? {'by': by}
      : op == 'play'
      ? {'by': by, 'op': op, 'card': card, 'suit': suit}
      : {'by': by, 'op': op};

  @override
  bool operator ==(Object other) =>
      other is PrsiAction && other.by == by && other.op == op && other.card == card && other.suit == suit;

  @override
  int get hashCode => Object.hash(by, op, card, suit);

  @override
  String toString() => toJson().toString();
}

class PrsiResult {
  const PrsiResult({
    required this.winner,
    required this.stars,
    required this.score,
    required this.playerWins,
    required this.aiWins,
  });

  final String winner;
  final int stars, score, playerWins, aiWins;

  Map<String, Object?> toJson() => {
    'winner': winner,
    'stars': stars,
    'score': score,
    'playerWins': playerWins,
    'aiWins': aiWins,
  };
}

String _other(String side) => side == 'player' ? 'ai' : 'player';

/// Mutable working copy for one apply (lists are copied in, frozen on the way out).
class _Table {
  _Table(PrsiState s) : deck = [...s.deck], player = [...s.player], ai = [...s.ai], pile = [...s.pile], rng = s.rng;

  List<int> deck, pile;
  final List<int> player, ai;
  int rng;

  List<int> hand(String side) => side == 'player' ? player : ai;

  /// Draws up to [n] cards one by one: before each card an empty deck takes the pile without its
  /// top card, shuffled from rng (no shuffle and no rng use when nothing lies under the top card).
  void draw(String side, int n) {
    for (var k = 0; k < n; k++) {
      if (deck.isEmpty && pile.length > 1) {
        final top = pile.last;
        final r = withRng(rng, (p) => p.shuffle(pile.sublist(0, pile.length - 1)));
        deck = r.value;
        rng = r.rng;
        pile = [top];
      }
      if (deck.isEmpty) return;
      hand(side).add(deck.removeAt(0));
    }
  }

  PrsiState into(PrsiState s) => s.copyWith(
    deck: List.unmodifiable(deck),
    player: List.unmodifiable(player),
    ai: List.unmodifiable(ai),
    pile: List.unmodifiable(pile),
    rng: rng,
  );
}

class PrsiRules extends MgRules<PrsiState, PrsiAction, PrsiResult> {
  PrsiConfig? _cfg;

  PrsiConfig get _c => _cfg ?? (throw StateError('prsi: init first'));

  @override
  String get id => 'prsi';

  @override
  int get specVersion => 1;

  /// Starts a game; [config] is the vector form (see [PrsiConfig.fromJson]).
  @override
  PrsiState init(Map<String, Object?> config, int seed) => start(PrsiConfig.fromJson(config), seed);

  PrsiState start(PrsiConfig config, int seed) {
    _cfg = config;
    return _deal(
      PrsiState(
        deck: const [],
        player: const [],
        ai: const [],
        pile: const [],
        suit: 0,
        sevens: 0,
        ace: false,
        turn: 'player',
        starter: 'player',
        round: 1,
        playerWins: 0,
        aiWins: 0,
        last: '',
        over: false,
        rng: Prng(seed).state,
      ),
    );
  }

  /// New deal for s.round: shuffle, hand × (player, AI), turn up deck[0]; starter by round parity.
  PrsiState _deal(PrsiState s0) {
    final r = withRng(s0.rng, (p) => p.shuffle([for (var i = 0; i < 32; i++) i]));
    final t = _Table(s0.copyWith(deck: r.value, player: const [], ai: const [], pile: const [], rng: r.rng));
    for (var i = 0; i < _c.hand; i++) {
      t.draw('player', 1);
      t.draw('ai', 1);
    }
    final up = t.deck.removeAt(0);
    t.pile = [up];
    final starter = s0.round.isOdd ? 'player' : 'ai';
    return t
        .into(s0)
        .copyWith(
          suit: suitOf(up),
          sevens: rankOf(up) == prsiSeven ? 1 : 0,
          ace: rankOf(up) == prsiAce,
          starter: starter,
          turn: starter,
        );
  }

  @override
  List<PrsiAction> legalActions(PrsiState s) {
    if (s.over) return const [];
    final by = s.turn;
    final hand = [...s.hand(by)]..sort();
    if (s.sevens > 0) {
      return [
        for (final c in hand)
          if (rankOf(c) == prsiSeven) PrsiAction.play(by, c),
        PrsiAction.draw(by),
      ];
    }
    if (s.ace) {
      return [
        for (final c in hand)
          if (rankOf(c) == prsiAce) PrsiAction.play(by, c),
        PrsiAction.stand(by),
      ];
    }
    final topRank = rankOf(s.pile.last);
    return [
      for (final c in hand)
        if (rankOf(c) == prsiQueen)
          for (var su = 0; su < 4; su++) PrsiAction.play(by, c, su)
        else if (rankOf(c) == topRank || suitOf(c) == s.suit)
          PrsiAction.play(by, c),
      PrsiAction.draw(by),
    ];
  }

  @override
  PrsiState apply(PrsiState s, PrsiAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(over: true);
    if (!legalActions(s).contains(a)) throw IllegalAction(id, a);
    final side = s.turn;
    final t = _Table(s);
    switch (a.op) {
      case 'play':
        final hand = t.hand(side)..remove(a.card);
        t.pile.add(a.card);
        final rank = rankOf(a.card);
        final suit = rank == prsiQueen ? a.suit : suitOf(a.card);
        final n = t.into(s).copyWith(suit: suit, sevens: rank == prsiSeven ? s.sevens + 1 : 0, ace: rank == prsiAce);
        if (hand.isEmpty) return _endRound(n, side);
        return n.copyWith(turn: _other(side));
      case 'draw':
        t.draw(side, s.sevens > 0 ? 2 * s.sevens : 1);
        return t.into(s).copyWith(sevens: 0, turn: _other(side));
      default: // stand
        return s.copyWith(ace: false, turn: _other(side));
    }
  }

  PrsiState _endRound(PrsiState s, String winner) {
    final n = winner == 'player'
        ? s.copyWith(playerWins: s.playerWins + 1, last: winner)
        : s.copyWith(aiWins: s.aiWins + 1, last: winner);
    if (n.playerWins >= _c.roundsToWin || n.aiWins >= _c.roundsToWin) return n.copyWith(over: true);
    return _deal(n.copyWith(round: s.round + 1));
  }

  /// Heuristic value of a legal action for the AI (spec "AI"); h = AI hand without the card.
  int _value(PrsiState s, PrsiAction a, int level) {
    if (a.op != 'play') return 0;
    final h = [...s.ai]..remove(a.card);
    final near = level >= 3 && s.player.length <= 2;
    int ofSuit(int su) => h.where((c) => suitOf(c) == su).length;
    return switch (rankOf(a.card)) {
      prsiQueen => 50 + 10 * ofSuit(a.suit),
      prsiSeven => 100 + (near ? 30 : 0),
      prsiAce => 100 + (near ? 20 : 0),
      _ => 100 + 5 * ofSuit(suitOf(a.card)),
    };
  }

  @override
  PrsiAction aiAction(PrsiState s, int level, Prng ai) {
    final legal = legalActions(s);
    if (s.turn != 'ai' || legal.isEmpty) throw IllegalAction(id, const PrsiAction('ai', ''));
    final err = level >= 1 && level <= _c.aiErrorPct.length ? _c.aiErrorPct[level - 1] : 0;
    if (ai.nextInt(100) < err) return legal[ai.nextInt(legal.length)];
    var best = legal.first;
    var bv = _value(s, best, level);
    for (final a in legal.skip(1)) {
      final v = _value(s, a, level);
      if (v > bv) {
        best = a;
        bv = v;
      }
    }
    return best;
  }

  @override
  PrsiResult? result(PrsiState s) {
    if (!s.over) return null;
    final p = s.playerWins, a = s.aiWins;
    final winner = p > a
        ? 'player'
        : p < a
        ? 'ai'
        : 'draw';
    final stars = winner != 'player'
        ? 0
        : a == 0
        ? 3
        : a == 1
        ? 2
        : 1;
    return PrsiResult(winner: winner, stars: stars, score: 100 * p, playerWins: p, aiWins: a);
  }

  @override
  PrsiAction actionFromJson(Map<String, Object?> j) {
    if (j['by'] == 'timeout') return const PrsiAction.timeout();
    final by = j['by'] as String, op = j['op'] as String;
    return op == 'play' ? PrsiAction.play(by, j['card'] as int, (j['suit'] as int?) ?? -1) : PrsiAction(by, op);
  }

  @override
  Map<String, Object?> stateToJson(PrsiState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(PrsiResult r) => r.toJson();
}
