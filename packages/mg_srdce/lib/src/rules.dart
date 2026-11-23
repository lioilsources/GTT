import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/srdce.md, version 1. Pure Dart: no Flutter imports here.
class SrdceConfig {
  const SrdceConfig({
    required this.target,
    required this.maxDeals,
    required this.aiErrorPct,
    required this.starMargins,
  });

  factory SrdceConfig.fromTuning(TuningMinigamesSrdce t) => SrdceConfig(
    target: t.target,
    maxDeals: t.maxDeals,
    aiErrorPct: List.unmodifiable(t.aiErrorPct),
    starMargins: List.unmodifiable(t.starMargins),
  );

  factory SrdceConfig.fromJson(Map<String, Object?> j) => SrdceConfig(
    target: j['target'] as int,
    maxDeals: j['maxDeals'] as int,
    aiErrorPct: List.unmodifiable((j['aiErrorPct'] as List).cast<int>()),
    starMargins: List.unmodifiable((j['starMargins'] as List).cast<int>()),
  );

  final int target, maxDeals;
  final List<int> aiErrorPct, starMargins;
}

/// Card 0–51 as in Oko bere: rank = c mod 13 (0 = 2 … 12 = A), suit = c div 13 (♠ ♥ ♦ ♣).
int rankOf(int c) => c % 13;
int suitOf(int c) => c ~/ 13;
const srdceHearts = 1;
const twoOfClubs = 39;
const queenOfSpades = 10;

/// Penalty points of a card: hearts 1, the queen of spades 13.
int cardPoints(int c) => c == queenOfSpades
    ? 13
    : suitOf(c) == srdceHearts
    ? 1
    : 0;

/// A finished trick: cards in play order, who led it and who took it.
class SrdceTrick {
  const SrdceTrick({required this.cards, required this.leader, required this.winner});

  static const empty = SrdceTrick(cards: [], leader: -1, winner: -1);

  final List<int> cards;
  final int leader, winner;

  Map<String, Object?> toJson() => {
    'cards': [...cards],
    'leader': leader,
    'winner': winner,
  };
}

class SrdceState {
  const SrdceState({
    required this.hands,
    required this.trick,
    required this.leader,
    required this.turn,
    required this.taken,
    required this.scores,
    required this.deal,
    required this.tricks,
    required this.broken,
    required this.lastTrick,
    required this.over,
    required this.rng,
  });

  /// Four hands, ascending. Seat 0 is the player, 1–3 the opponents (left, across, right).
  final List<List<int>> hands;

  /// Cards of the trick in play, in play order (led by [leader]).
  final List<int> trick;
  final int leader, turn;

  /// Penalty points of the current deal and totals of finished deals, per seat.
  final List<int> taken, scores;
  final int deal, tricks;
  final bool broken;
  final SrdceTrick lastTrick;
  final bool over;
  final int rng;

  SrdceState copyWith({
    List<List<int>>? hands,
    List<int>? trick,
    int? leader,
    int? turn,
    List<int>? taken,
    List<int>? scores,
    int? deal,
    int? tricks,
    bool? broken,
    SrdceTrick? lastTrick,
    bool? over,
    int? rng,
  }) => SrdceState(
    hands: hands ?? this.hands,
    trick: trick ?? this.trick,
    leader: leader ?? this.leader,
    turn: turn ?? this.turn,
    taken: taken ?? this.taken,
    scores: scores ?? this.scores,
    deal: deal ?? this.deal,
    tricks: tricks ?? this.tricks,
    broken: broken ?? this.broken,
    lastTrick: lastTrick ?? this.lastTrick,
    over: over ?? this.over,
    rng: rng ?? this.rng,
  );

  Map<String, Object?> toJson() => {
    'hands': [
      for (final h in hands) [...h],
    ],
    'trick': [...trick],
    'leader': leader,
    'turn': turn,
    'taken': [...taken],
    'scores': [...scores],
    'deal': deal,
    'tricks': tricks,
    'broken': broken,
    'lastTrick': lastTrick.toJson(),
    'over': over,
    'rng': rng,
  };
}

/// {by: player|ai, card} or {by: timeout}.
class SrdceAction {
  const SrdceAction(this.by, this.card);
  const SrdceAction.timeout() : by = 'timeout', card = -1;

  final String by;
  final int card;

  Map<String, Object?> toJson() => by == 'timeout' ? {'by': by} : {'by': by, 'card': card};

  @override
  bool operator ==(Object other) => other is SrdceAction && other.by == by && other.card == card;

  @override
  int get hashCode => Object.hash(by, card);

  @override
  String toString() => toJson().toString();
}

class SrdceResult {
  const SrdceResult({required this.winner, required this.stars, required this.score, required this.scores});

  final String winner;
  final int stars, score;
  final List<int> scores;

  Map<String, Object?> toJson() => {
    'winner': winner,
    'stars': stars,
    'score': score,
    'scores': [...scores],
  };
}

String _byOf(int seat) => seat == 0 ? 'player' : 'ai';

class SrdceRules extends MgRules<SrdceState, SrdceAction, SrdceResult> {
  SrdceConfig? _cfg;

  SrdceConfig get _c => _cfg ?? (throw StateError('srdce: init first'));

  @override
  String get id => 'srdce';

  @override
  int get specVersion => 1;

  /// Starts a game; [config] is the vector form (see [SrdceConfig.fromJson]).
  @override
  SrdceState init(Map<String, Object?> config, int seed) => start(SrdceConfig.fromJson(config), seed);

  SrdceState start(SrdceConfig config, int seed) {
    _cfg = config;
    return _newDeal(
      SrdceState(
        hands: const [],
        trick: const [],
        leader: 0,
        turn: 0,
        taken: const [],
        scores: const [0, 0, 0, 0],
        deal: 1,
        tricks: 0,
        broken: false,
        lastTrick: SrdceTrick.empty,
        over: false,
        rng: Prng(seed).state,
      ),
    );
  }

  SrdceState _newDeal(SrdceState s) {
    final r = withRng(s.rng, (p) => p.shuffle([for (var i = 0; i < 52; i++) i]));
    final hands = [<int>[], <int>[], <int>[], <int>[]];
    for (var i = 0; i < r.value.length; i++) {
      hands[i % 4].add(r.value[i]);
    }
    for (final h in hands) {
      h.sort();
    }
    final leader = hands.indexWhere((h) => h.contains(twoOfClubs));
    return s.copyWith(
      hands: List.unmodifiable([for (final h in hands) List<int>.unmodifiable(h)]),
      taken: const [0, 0, 0, 0],
      trick: const [],
      tricks: 0,
      broken: false,
      leader: leader,
      turn: leader,
      rng: r.rng,
    );
  }

  /// Legal cards of the seat on turn, ascending.
  List<int> legalCards(SrdceState s) {
    if (s.over) return const [];
    final hand = s.hands[s.turn];
    if (s.trick.isEmpty) {
      if (s.tricks == 0) return hand.contains(twoOfClubs) ? const [twoOfClubs] : const [];
      if (s.broken || hand.every((c) => suitOf(c) == srdceHearts)) return [...hand];
      return [
        for (final c in hand)
          if (suitOf(c) != srdceHearts) c,
      ];
    }
    final led = suitOf(s.trick.first);
    final follow = [
      for (final c in hand)
        if (suitOf(c) == led) c,
    ];
    if (follow.isNotEmpty) return follow;
    if (s.tricks == 0) {
      final clean = [
        for (final c in hand)
          if (cardPoints(c) == 0) c,
      ];
      if (clean.isNotEmpty) return clean;
    }
    return [...hand];
  }

  @override
  List<SrdceAction> legalActions(SrdceState s) {
    final by = _byOf(s.turn);
    return [for (final c in legalCards(s)) SrdceAction(by, c)];
  }

  @override
  SrdceState apply(SrdceState s, SrdceAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(over: true);
    if (a.by != _byOf(s.turn) || !legalCards(s).contains(a.card)) throw IllegalAction(id, a);
    final hands = List<List<int>>.unmodifiable([
      for (var i = 0; i < 4; i++)
        i == s.turn ? List<int>.unmodifiable(s.hands[i].where((c) => c != a.card)) : s.hands[i],
    ]);
    final trick = List<int>.unmodifiable([...s.trick, a.card]);
    final n = s.copyWith(hands: hands, trick: trick, broken: s.broken || suitOf(a.card) == srdceHearts);
    if (trick.length < 4) return n.copyWith(turn: (s.turn + 1) % 4);
    final led = suitOf(trick.first);
    var wi = 0;
    for (var i = 1; i < 4; i++) {
      final c = trick[i];
      if (suitOf(c) == led && rankOf(c) > rankOf(trick[wi])) wi = i;
    }
    final winner = (s.leader + wi) % 4;
    final taken = [...s.taken];
    taken[winner] += trick.fold(0, (t, c) => t + cardPoints(c));
    final done = n.copyWith(
      taken: List.unmodifiable(taken),
      trick: const [],
      tricks: s.tricks + 1,
      leader: winner,
      turn: winner,
      lastTrick: SrdceTrick(cards: trick, leader: s.leader, winner: winner),
    );
    return done.tricks == 13 ? _endDeal(done) : done;
  }

  SrdceState _endDeal(SrdceState s) {
    final moon = s.taken.indexOf(26);
    final scores = List<int>.unmodifiable([
      for (var i = 0; i < 4; i++) s.scores[i] + (moon >= 0 ? (i == moon ? 0 : 26) : s.taken[i]),
    ]);
    final n = s.copyWith(scores: scores);
    if (scores.any((v) => v >= _c.target) || s.deal >= _c.maxDeals) return n.copyWith(over: true);
    return _newDeal(n.copyWith(deal: s.deal + 1));
  }

  int _value(SrdceState s, int c, int level) {
    final rank = rankOf(c);
    if (s.trick.isEmpty) return -rank - (suitOf(c) == srdceHearts ? 5 : 0);
    final led = suitOf(s.trick.first);
    if (suitOf(c) == led) {
      if (level <= 2) return -rank;
      final w = s.trick.where((x) => suitOf(x) == led).map(rankOf).reduce((a, b) => a > b ? a : b);
      if (rank < w) return 1000 + rank;
      if (c == queenOfSpades) return -1000;
      final pts = s.trick.fold(0, (t, x) => t + cardPoints(x));
      if (s.trick.length == 3 && pts == 0) return 500 + rank;
      return 100 - rank;
    }
    if (level <= 2) return rank;
    if (c == queenOfSpades) return 3000;
    if (suitOf(c) == srdceHearts) return 2000 + rank;
    return 1000 + rank;
  }

  @override
  SrdceAction aiAction(SrdceState s, int level, Prng ai) {
    final legal = legalCards(s);
    if (s.over || s.turn == 0 || legal.isEmpty) throw IllegalAction(id, const SrdceAction('ai', -1));
    final err = level >= 1 && level <= _c.aiErrorPct.length ? _c.aiErrorPct[level - 1] : 0;
    if (ai.nextInt(100) < err) return SrdceAction('ai', legal[ai.nextInt(legal.length)]);
    var best = legal.first;
    var bv = _value(s, best, level);
    for (final c in legal.skip(1)) {
      final v = _value(s, c, level);
      if (v > bv) {
        best = c;
        bv = v;
      }
    }
    return SrdceAction('ai', best);
  }

  @override
  SrdceResult? result(SrdceState s) {
    if (!s.over) return null;
    final me = s.scores[0];
    final best = [s.scores[1], s.scores[2], s.scores[3]].reduce((a, b) => a < b ? a : b);
    final winner = me < best
        ? 'player'
        : me == best
        ? 'draw'
        : 'ai';
    final m = _c.starMargins;
    final stars = winner != 'player'
        ? 0
        : best - me >= m[0]
        ? 3
        : best - me >= m[1]
        ? 2
        : 1;
    return SrdceResult(winner: winner, stars: stars, score: 100 - me < 0 ? 0 : 100 - me, scores: [...s.scores]);
  }

  @override
  SrdceAction actionFromJson(Map<String, Object?> j) =>
      j['by'] == 'timeout' ? const SrdceAction.timeout() : SrdceAction(j['by'] as String, j['card'] as int);

  @override
  Map<String, Object?> stateToJson(SrdceState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(SrdceResult r) => r.toJson();
}
