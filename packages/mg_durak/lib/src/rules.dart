import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/durak.md, version 1: podkidnoy durak, 36 cards. Pure Dart: no Flutter imports here.
class DurakConfig {
  const DurakConfig({required this.hand, required this.opponents, required this.aiErrorPct, required this.level});

  factory DurakConfig.fromTuning(TuningMinigamesDurak t, int level) => DurakConfig(
    hand: t.hand,
    opponents: List.unmodifiable(t.opponents),
    aiErrorPct: List.unmodifiable(t.aiErrorPct),
    level: level,
  );

  factory DurakConfig.fromJson(Map<String, Object?> j) => DurakConfig(
    hand: j['hand'] as int,
    opponents: List.unmodifiable((j['opponents'] as List).cast<int>()),
    aiErrorPct: List.unmodifiable((j['aiErrorPct'] as List).cast<int>()),
    level: j['level'] as int,
  );

  final int hand;
  final List<int> opponents, aiErrorPct;
  final int level;
}

/// An attack card and the card that beat it (−1 while unbeaten).
typedef DurakPair = ({int a, int d});

class DurakState {
  const DurakState({
    required this.n,
    required this.hands,
    required this.stock,
    required this.trump,
    required this.trumpCard,
    required this.table,
    required this.attacker,
    required this.defender,
    required this.thrower,
    required this.passes,
    required this.limit,
    required this.finished,
    required this.over,
    required this.durak,
    required this.byCount,
    required this.rng,
  });

  final int n;
  final List<List<int>> hands;
  final List<int> stock;
  final int trump, trumpCard;
  final List<DurakPair> table;
  final int attacker, defender, thrower, passes, limit;
  final List<int> finished;
  final bool over;
  final int durak;
  final bool byCount;
  final int rng;

  DurakState copyWith({
    List<List<int>>? hands,
    List<int>? stock,
    List<DurakPair>? table,
    int? attacker,
    int? defender,
    int? thrower,
    int? passes,
    int? limit,
    List<int>? finished,
    bool? over,
    int? durak,
    bool? byCount,
  }) => DurakState(
    n: n,
    hands: hands ?? this.hands,
    stock: stock ?? this.stock,
    trump: trump,
    trumpCard: trumpCard,
    table: table ?? this.table,
    attacker: attacker ?? this.attacker,
    defender: defender ?? this.defender,
    thrower: thrower ?? this.thrower,
    passes: passes ?? this.passes,
    limit: limit ?? this.limit,
    finished: finished ?? this.finished,
    over: over ?? this.over,
    durak: durak ?? this.durak,
    byCount: byCount ?? this.byCount,
    rng: rng,
  );

  Map<String, Object?> toJson() => {
    'n': n,
    'hands': hands,
    'stock': stock,
    'trump': trump,
    'trumpCard': trumpCard,
    'table': [
      for (final p in table) {'a': p.a, 'd': p.d},
    ],
    'attacker': attacker,
    'defender': defender,
    'thrower': thrower,
    'passes': passes,
    'limit': limit,
    'finished': finished,
    'over': over,
    'durak': durak,
    'byCount': byCount,
    'rng': rng,
  };
}

/// {by, op: play|beat, card}, {by, op: take|pass} or {by: timeout}.
class DurakAction {
  const DurakAction(this.by, this.op, [this.card = -1]);
  const DurakAction.timeout() : by = 'timeout', op = '', card = -1;

  final String by, op;
  final int card;

  bool get hasCard => op == 'play' || op == 'beat';

  Map<String, Object?> toJson() => by == 'timeout'
      ? {'by': by}
      : hasCard
      ? {'by': by, 'op': op, 'card': card}
      : {'by': by, 'op': op};

  @override
  bool operator ==(Object other) => other is DurakAction && other.by == by && other.op == op && other.card == card;

  @override
  int get hashCode => Object.hash(by, op, card);

  @override
  String toString() => toJson().toString();
}

class DurakResult {
  const DurakResult({
    required this.winner,
    required this.stars,
    required this.score,
    required this.byCount,
    required this.place,
    required this.durak,
  });

  final String winner;
  final int stars, score;
  final bool byCount;
  final int place, durak;

  Map<String, Object?> toJson() => {
    'winner': winner,
    'stars': stars,
    'score': score,
    'byCount': byCount,
    'place': place,
    'durak': durak,
  };
}

/// Card 0–35: rank = c mod 9 (0 = 6 … 8 = A), suit = c div 9 (♠ ♥ ♦ ♣).
int durakRank(int c) => c % 9;
int durakSuit(int c) => c ~/ 9;

bool durakBeats(int a, int b, int trump) {
  if (durakSuit(a) == durakSuit(b)) return durakRank(a) > durakRank(b);
  return durakSuit(a) == trump && durakSuit(b) != trump;
}

int _price(int c, int trump) => (durakSuit(c) == trump ? 9 : 0) + durakRank(c);
String _byOf(int seat) => seat == 0 ? 'player' : 'ai';

class DurakRules extends MgRules<DurakState, DurakAction, DurakResult> {
  DurakConfig? _cfg;
  DurakConfig get _c => _cfg ?? (throw StateError('durak: init first'));

  @override
  String get id => 'durak';

  @override
  int get specVersion => 1;

  @override
  DurakState init(Map<String, Object?> config, int seed) => start(DurakConfig.fromJson(config), seed);

  DurakState start(DurakConfig config, int seed) {
    _cfg = config;
    final n = config.opponents[config.level.clamp(1, 5) - 1] + 1;
    final r = Prng(seed);
    final deck = r.shuffle([for (var i = 0; i < 36; i++) i]);
    final hands = [for (var i = 0; i < n; i++) <int>[]];
    for (var k = 0; k < config.hand * n; k++) {
      hands[k % n].add(deck[k]);
    }
    for (final h in hands) {
      h.sort();
    }
    final stock = deck.sublist(config.hand * n);
    final trumpCard = stock.last;
    final trump = durakSuit(trumpCard);
    var attacker = 0, low = 99;
    for (var i = 0; i < n; i++) {
      for (final c in hands[i]) {
        if (durakSuit(c) == trump && durakRank(c) < low) {
          low = durakRank(c);
          attacker = i;
        }
      }
    }
    return DurakState(
      n: n,
      hands: hands,
      stock: stock,
      trump: trump,
      trumpCard: trumpCard,
      table: const [],
      attacker: attacker,
      defender: (attacker + 1) % n,
      thrower: attacker,
      passes: 0,
      limit: 0,
      finished: const [],
      over: false,
      durak: -1,
      byCount: false,
      rng: r.state,
    );
  }

  /// The seat to act: the defender while a card lies unbeaten, else the thrower.
  int turn(DurakState s) => s.table.any((p) => p.d < 0) ? s.defender : s.thrower;

  List<int> _throwers(DurakState s) => [
    for (var k = 0; k < s.n; k++)
      if ((s.attacker + k) % s.n != s.defender && !s.finished.contains((s.attacker + k) % s.n)) (s.attacker + k) % s.n,
  ];

  bool _canPlay(DurakState s, int c) {
    if (s.table.isEmpty) return true;
    if (s.table.length >= s.limit) return false;
    final r = durakRank(c);
    return s.table.any((p) => durakRank(p.a) == r || (p.d >= 0 && durakRank(p.d) == r));
  }

  @override
  List<DurakAction> legalActions(DurakState s) {
    if (s.over) return const [];
    final seat = turn(s);
    final by = _byOf(seat);
    final hand = s.hands[seat];
    final open = s.table.where((p) => p.d < 0);
    if (seat == s.defender && open.isNotEmpty) {
      final a = open.first.a;
      return [
        for (final c in hand)
          if (durakBeats(c, a, s.trump)) DurakAction(by, 'beat', c),
        DurakAction(by, 'take'),
      ];
    }
    return [
      for (final c in hand)
        if (_canPlay(s, c)) DurakAction(by, 'play', c),
      if (s.table.isNotEmpty) DurakAction(by, 'pass'),
    ];
  }

  @override
  DurakState apply(DurakState s, DurakAction a) {
    if (s.over) throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(over: true, byCount: true);
    if (!legalActions(s).contains(a)) throw IllegalAction(id, a);
    final seat = turn(s);
    final hands = [for (final h in s.hands) List<int>.of(h)];
    switch (a.op) {
      case 'play':
        hands[seat].remove(a.card);
        final limit = s.table.isEmpty ? (s.hands[s.defender].length < 6 ? s.hands[s.defender].length : 6) : s.limit;
        return s.copyWith(hands: hands, table: [...s.table, (a: a.card, d: -1)], limit: limit, passes: 0);
      case 'beat':
        hands[seat].remove(a.card);
        final table = [for (final p in s.table) p.d < 0 ? (a: p.a, d: a.card) : p];
        return s.copyWith(hands: hands, table: table, thrower: s.attacker, passes: 0);
      case 'take':
        for (final p in s.table) {
          hands[seat].add(p.a);
          if (p.d >= 0) hands[seat].add(p.d);
        }
        hands[seat].sort();
        return _endRound(s.copyWith(hands: hands), true);
    }
    final th = _throwers(s);
    final passes = s.passes + 1;
    if (passes >= th.length) return _endRound(s.copyWith(passes: passes), false);
    return s.copyWith(passes: passes, thrower: th[(th.indexOf(s.thrower) + 1) % th.length]);
  }

  DurakState _endRound(DurakState s, bool took) {
    final order = [..._throwers(s), s.defender];
    final hands = [for (final h in s.hands) List<int>.of(h)];
    final stock = List<int>.of(s.stock);
    for (final i in order) {
      while (hands[i].length < _c.hand && stock.isNotEmpty) {
        hands[i].add(stock.removeAt(0));
      }
      hands[i].sort();
    }
    final finished = List<int>.of(s.finished);
    if (stock.isEmpty) {
      for (final i in order) {
        if (hands[i].isEmpty && !finished.contains(i)) finished.add(i);
      }
    }
    final base = s.copyWith(hands: hands, stock: stock, table: const [], passes: 0, limit: 0, finished: finished);
    final live = [
      for (var i = 0; i < s.n; i++)
        if (!finished.contains(i)) i,
    ];
    if (live.length <= 1) return base.copyWith(over: true, durak: live.isEmpty ? -1 : live.first);
    int next(int from) {
      for (var k = 1; k <= s.n; k++) {
        final i = (from + k) % s.n;
        if (!finished.contains(i)) return i;
      }
      return from;
    }

    final attacker = !took && !finished.contains(s.defender) ? s.defender : next(s.defender);
    return base.copyWith(attacker: attacker, defender: next(attacker), thrower: attacker);
  }

  @override
  DurakAction aiAction(DurakState s, int level, Prng ai) {
    if (s.over) throw IllegalAction(id, {'by': 'ai'});
    final legal = legalActions(s);
    if (ai.nextInt(100) < _c.aiErrorPct[level.clamp(1, 5) - 1]) return legal[ai.nextInt(legal.length)];
    int cheapest(List<int> cards) {
      var best = cards.first;
      for (final x in cards) {
        if (_price(x, s.trump) < _price(best, s.trump)) best = x;
      }
      return best;
    }

    List<int> cardsOf(String op) => [
      for (final l in legal)
        if (l.op == op) l.card,
    ];
    final by = legal.first.by;
    if (legal.any((l) => l.op == 'take')) {
      final beat = cardsOf('beat');
      return beat.isNotEmpty ? DurakAction(by, 'beat', cheapest(beat)) : DurakAction(by, 'take');
    }
    final plays = cardsOf('play');
    if (s.table.isEmpty) return DurakAction(by, 'play', cheapest(plays));
    final ok = [
      for (final x in plays)
        if (durakSuit(x) != s.trump || s.stock.isEmpty) x,
    ];
    return ok.isNotEmpty ? DurakAction(by, 'play', cheapest(ok)) : DurakAction(by, 'pass');
  }

  @override
  DurakResult? result(DurakState s) {
    if (!s.over) return null;
    final place = s.finished.indexOf(0) + 1;
    String winner;
    int stars;
    if (s.byCount) {
      final mine = s.hands[0].length;
      var ok = place > 0;
      if (!ok) {
        ok = true;
        for (var i = 1; i < s.n; i++) {
          if (!s.finished.contains(i) && s.hands[i].length <= mine) ok = false;
        }
      }
      winner = ok ? 'player' : 'ai';
      stars = ok ? 1 : 0;
    } else if (s.durak == 0) {
      winner = 'ai';
      stars = 0;
    } else if (place == 1) {
      winner = 'player';
      stars = 3;
    } else if (s.durak < 0) {
      winner = 'draw';
      stars = 1;
    } else {
      winner = 'player';
      stars = 2;
    }
    return DurakResult(
      winner: winner,
      stars: stars,
      score: stars * 100,
      byCount: s.byCount,
      place: place,
      durak: s.durak,
    );
  }

  @override
  DurakAction actionFromJson(Map<String, Object?> j) {
    if (j['by'] == 'timeout') return const DurakAction.timeout();
    final op = j['op'] as String;
    return DurakAction(j['by'] as String, op, op == 'play' || op == 'beat' ? j['card'] as int : -1);
  }

  @override
  Map<String, Object?> stateToJson(DurakState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(DurakResult r) => r.toJson();
}
