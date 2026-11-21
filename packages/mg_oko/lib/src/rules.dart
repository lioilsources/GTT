import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/minigames/oko.md, version 1. Pure Dart: no Flutter imports here.
class OkoConfig {
  const OkoConfig({required this.roundsToWin, required this.dealerStand});

  factory OkoConfig.fromTuning(TuningMinigamesOko t) =>
      OkoConfig(roundsToWin: t.roundsToWin, dealerStand: t.dealerStand);

  factory OkoConfig.fromJson(Map<String, Object?> j) =>
      OkoConfig(roundsToWin: j['roundsToWin'] as int, dealerStand: j['dealerStand'] as int);

  final int roundsToWin, dealerStand;
}

/// Card 0–51: rank = c mod 13 (0 = 2 … 8 = 10, 9 J, 10 Q, 11 K, 12 A), suit = c div 13 (♠ ♥ ♦ ♣).
int rankOf(int c) => c % 13;
int suitOf(int c) => c ~/ 13;

/// Aces count 11, then drop 10 per ace while the total is over 21.
int handTotal(List<int> cards) {
  var sum = 0, aces = 0;
  for (final c in cards) {
    final r = rankOf(c);
    if (r == 12) {
      sum += 11;
      aces++;
    } else {
      sum += r <= 8 ? r + 2 : 10;
    }
  }
  while (sum > 21 && aces > 0) {
    sum -= 10;
    aces--;
  }
  return sum;
}

/// Oko: 21 from two cards.
bool isNatural(List<int> cards) => cards.length == 2 && handTotal(cards) == 21;

/// The last finished round for the UI; outcome is 'win', 'lose', 'push' or '' before the first.
class OkoLast {
  const OkoLast({required this.player, required this.dealer, required this.outcome});

  static const empty = OkoLast(player: [], dealer: [], outcome: '');

  final List<int> player, dealer;
  final String outcome;

  Map<String, Object?> toJson() => {'player': player, 'dealer': dealer, 'outcome': outcome};
}

class OkoState {
  const OkoState({
    required this.deck,
    required this.player,
    required this.dealer,
    required this.playerWins,
    required this.dealerWins,
    required this.round,
    required this.phase,
    required this.last,
    required this.over,
    required this.rng,
  });

  /// Remaining cards in draw order (deck[0] is next).
  final List<int> deck, player, dealer;
  final int playerWins, dealerWins, round;

  /// 'play' or 'over'.
  final String phase;
  final OkoLast last;
  final bool over;
  final int rng;

  OkoState copyWith({
    List<int>? deck,
    List<int>? player,
    List<int>? dealer,
    int? playerWins,
    int? dealerWins,
    int? round,
    String? phase,
    OkoLast? last,
    bool? over,
    int? rng,
  }) => OkoState(
    deck: deck ?? this.deck,
    player: player ?? this.player,
    dealer: dealer ?? this.dealer,
    playerWins: playerWins ?? this.playerWins,
    dealerWins: dealerWins ?? this.dealerWins,
    round: round ?? this.round,
    phase: phase ?? this.phase,
    last: last ?? this.last,
    over: over ?? this.over,
    rng: rng ?? this.rng,
  );

  Map<String, Object?> toJson() => {
    'deck': deck,
    'player': player,
    'dealer': dealer,
    'playerWins': playerWins,
    'dealerWins': dealerWins,
    'round': round,
    'phase': phase,
    'last': last.toJson(),
    'over': over,
    'rng': rng,
  };
}

/// {by: player, op: hit|stand} or {by: timeout} (op = '').
class OkoAction {
  const OkoAction(this.by, this.op);
  const OkoAction.timeout() : by = 'timeout', op = '';

  static const hit = OkoAction('player', 'hit');
  static const stand = OkoAction('player', 'stand');

  final String by, op;

  Map<String, Object?> toJson() => by == 'timeout' ? {'by': by} : {'by': by, 'op': op};

  @override
  bool operator ==(Object other) => other is OkoAction && other.by == by && other.op == op;

  @override
  int get hashCode => Object.hash(by, op);

  @override
  String toString() => toJson().toString();
}

class OkoResult {
  const OkoResult({
    required this.winner,
    required this.stars,
    required this.score,
    required this.playerWins,
    required this.dealerWins,
  });

  final String winner;
  final int stars, score, playerWins, dealerWins;

  Map<String, Object?> toJson() => {
    'winner': winner,
    'stars': stars,
    'score': score,
    'playerWins': playerWins,
    'dealerWins': dealerWins,
  };
}

class OkoRules extends MgRules<OkoState, OkoAction, OkoResult> {
  OkoConfig? _cfg;

  OkoConfig get _c => _cfg ?? (throw StateError('oko: init first'));

  @override
  String get id => 'oko';

  @override
  int get specVersion => 1;

  /// Starts a game; [config] is the vector form (see [OkoConfig.fromJson]).
  @override
  OkoState init(Map<String, Object?> config, int seed) => start(OkoConfig.fromJson(config), seed);

  OkoState start(OkoConfig config, int seed) {
    _cfg = config;
    return _deal(
      OkoState(
        deck: const [],
        player: const [],
        dealer: const [],
        playerWins: 0,
        dealerWins: 0,
        round: 1,
        phase: 'play',
        last: OkoLast.empty,
        over: false,
        rng: Prng(seed).state,
      ),
    );
  }

  /// Shuffles a fresh deck from rng, deals player, banker, player, banker, then checks naturals.
  OkoState _deal(OkoState s) {
    final r = withRng(s.rng, (p) => p.shuffle([for (var i = 0; i < 52; i++) i]));
    final deck = r.value;
    final player = List<int>.unmodifiable([deck[0], deck[2]]);
    final dealer = List<int>.unmodifiable([deck[1], deck[3]]);
    final n = s.copyWith(
      deck: List.unmodifiable(deck.sublist(4)),
      player: player,
      dealer: dealer,
      phase: 'play',
      rng: r.rng,
    );
    final pn = isNatural(player), dn = isNatural(dealer);
    if (pn && dn) return _settle(n, 'push');
    if (pn) return _settle(n, 'win');
    if (dn) return _settle(n, 'lose');
    return n;
  }

  /// Scores a finished round; ends the game or deals the next round.
  OkoState _settle(OkoState s, String outcome) {
    final n = s.copyWith(
      playerWins: s.playerWins + (outcome == 'win' ? 1 : 0),
      dealerWins: s.dealerWins + (outcome == 'lose' ? 1 : 0),
      last: OkoLast(player: s.player, dealer: s.dealer, outcome: outcome),
    );
    if (n.playerWins >= _c.roundsToWin || n.dealerWins >= _c.roundsToWin) {
      return n.copyWith(over: true, phase: 'over');
    }
    return _deal(n.copyWith(round: s.round + 1));
  }

  /// The banker draws below dealerStand (soft totals included), then the hands are compared.
  OkoState _stand(OkoState s) {
    final deck = [...s.deck];
    final dealer = [...s.dealer];
    while (handTotal(dealer) < _c.dealerStand) {
      dealer.add(deck.removeAt(0));
    }
    final n = s.copyWith(deck: List.unmodifiable(deck), dealer: List.unmodifiable(dealer));
    final p = handTotal(s.player), d = handTotal(dealer);
    return _settle(
      n,
      d > 21 || p > d
          ? 'win'
          : p < d
          ? 'lose'
          : 'push',
    );
  }

  @override
  List<OkoAction> legalActions(OkoState s) =>
      s.phase == 'play' && !s.over ? const [OkoAction.hit, OkoAction.stand] : const [];

  @override
  OkoState apply(OkoState s, OkoAction a) {
    if (s.over || s.phase != 'play') throw IllegalAction(id, a);
    if (a.by == 'timeout') return s.copyWith(over: true, phase: 'over');
    if (a.by != 'player') throw IllegalAction(id, a);
    if (a.op == 'stand') return _stand(s);
    if (a.op != 'hit') throw IllegalAction(id, a);
    final n = s.copyWith(
      deck: List.unmodifiable(s.deck.sublist(1)),
      player: List.unmodifiable([...s.player, s.deck[0]]),
    );
    final total = handTotal(n.player);
    if (total > 21) return _settle(n, 'lose');
    if (total == 21) return _stand(n);
    return n;
  }

  /// The banker has no decisions; the contract still wants an AI move: the first legal action.
  @override
  OkoAction aiAction(OkoState s, int level, Prng ai) {
    final legal = legalActions(s);
    if (legal.isEmpty) throw IllegalAction(id, const {'by': 'ai'});
    return legal.first;
  }

  @override
  OkoResult? result(OkoState s) {
    if (!s.over) return null;
    final p = s.playerWins, d = s.dealerWins;
    final winner = p > d
        ? 'player'
        : p < d
        ? 'ai'
        : 'draw';
    final stars = winner != 'player'
        ? 0
        : d <= 2
        ? 3
        : d == 3
        ? 2
        : d == 4
        ? 1
        : 0;
    return OkoResult(winner: winner, stars: stars, score: 100 * p, playerWins: p, dealerWins: d);
  }

  @override
  OkoAction actionFromJson(Map<String, Object?> j) =>
      j['by'] == 'timeout' ? const OkoAction.timeout() : OkoAction(j['by'] as String, j['op'] as String);

  @override
  Map<String, Object?> stateToJson(OkoState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(OkoResult r) => r.toJson();
}
