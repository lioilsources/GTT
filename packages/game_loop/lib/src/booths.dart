// Ringing phone booths (specs/booths.md, version 1): the P0 rules (module `booths`) and the pure
// world helpers (booth list, reach, the 1 s game tick). Port of web/src/booths/rules.ts and
// web/src/booths/booths.ts.
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/citypack_pb.dart' show Spot;
import 'package:shared_gen/shared_gen.dart';

import 'logic.dart' show opponentIndex;

class BoothsConfig {
  const BoothsConfig({
    required this.booths,
    required this.gapMin,
    required this.gapMax,
    required this.retry,
    required this.ringS,
    required this.bonus,
    required this.games,
  });

  /// Config from tuning, the number of booths and the minigame spots of the city.
  factory BoothsConfig.fromTuning(TuningBooths t, int booths, List<String> games) => BoothsConfig(
    booths: booths,
    gapMin: t.gapMinS,
    gapMax: t.gapMaxS,
    retry: t.retryS,
    ringS: t.ringS,
    bonus: t.bonus,
    games: List.unmodifiable(games),
  );

  factory BoothsConfig.fromJson(Map<String, Object?> j) => BoothsConfig(
    booths: j['booths'] as int,
    gapMin: j['gapMin'] as int,
    gapMax: j['gapMax'] as int,
    retry: j['retry'] as int,
    ringS: j['ringS'] as int,
    bonus: j['bonus'] as int,
    games: List.unmodifiable((j['games'] as List).cast<String>()),
  );

  final int booths, gapMin, gapMax, retry, ringS, bonus;

  /// Spot ids with a catalog minigame, in spot order (the feed's candidates).
  final List<String> games;
}

/// The offer of the last answered call; `spot == ''` = none.
typedef BoothOffer = ({String spot, int bonus});

const BoothOffer noBoothOffer = (spot: '', bonus: 0);

class BoothsState {
  const BoothsState({
    required this.ringing,
    required this.left,
    required this.next,
    required this.answered,
    required this.missed,
    required this.offer,
    required this.paid,
    required this.last,
    required this.rng,
  });

  final int ringing, left, next, answered, missed;
  final BoothOffer offer;
  final int paid, last, rng;

  BoothsState copyWith({
    int? ringing,
    int? left,
    int? next,
    int? answered,
    int? missed,
    BoothOffer? offer,
    int? paid,
    int? last,
    int? rng,
  }) => BoothsState(
    ringing: ringing ?? this.ringing,
    left: left ?? this.left,
    next: next ?? this.next,
    answered: answered ?? this.answered,
    missed: missed ?? this.missed,
    offer: offer ?? this.offer,
    paid: paid ?? this.paid,
    last: last ?? this.last,
    rng: rng ?? this.rng,
  );

  Map<String, Object?> toJson() => {
    'ringing': ringing,
    'left': left,
    'next': next,
    'answered': answered,
    'missed': missed,
    'offer': {'spot': offer.spot, 'bonus': offer.bonus},
    'paid': paid,
    'last': last,
    'rng': rng,
  };
}

/// `op` is tick ([near]), answer ([booth]), finish ([spot], [stars], [aborted]) or clear.
class BoothsAction {
  const BoothsAction.tick(List<int> this.near) : op = 'tick', booth = null, spot = null, stars = null, aborted = null;
  const BoothsAction.answer(int this.booth) : op = 'answer', near = null, spot = null, stars = null, aborted = null;
  const BoothsAction.finish(String this.spot, int this.stars, bool this.aborted)
    : op = 'finish',
      near = null,
      booth = null;
  const BoothsAction.clear() : op = 'clear', near = null, booth = null, spot = null, stars = null, aborted = null;

  final String op;
  final List<int>? near;
  final int? booth;
  final String? spot;
  final int? stars;
  final bool? aborted;

  Map<String, Object?> toJson() => switch (op) {
    'tick' => {'by': 'player', 'op': op, 'near': near},
    'answer' => {'by': 'player', 'op': op, 'booth': booth},
    'finish' => {'by': 'player', 'op': op, 'spot': spot, 'stars': stars, 'aborted': aborted},
    _ => {'by': 'player', 'op': op},
  };

  @override
  bool operator ==(Object other) =>
      other is BoothsAction &&
      other.op == op &&
      other.booth == booth &&
      other.spot == spot &&
      other.stars == stars &&
      other.aborted == aborted &&
      _sameList(other.near, near);
  @override
  int get hashCode => Object.hash(op, booth, spot, stars, aborted, near == null ? null : Object.hashAll(near!));
  @override
  String toString() => toJson().toString();
}

bool _sameList(List<int>? a, List<int>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class BoothsRules extends MgRules<BoothsState, BoothsAction, Map<String, Object?>> {
  @override
  String get id => 'booths';
  @override
  int get specVersion => 1;

  BoothsConfig? _cfg;
  BoothsConfig get config => _cfg ?? (throw StateError('booths: init first'));

  /// gap() = gapMin + rng.nextInt(gapMax − gapMin + 1).
  int _gap(Prng r) => config.gapMin + r.nextInt(config.gapMax - config.gapMin + 1);

  BoothsState start(BoothsConfig c, int seed) {
    _cfg = c;
    final r = Prng(seed);
    final next = _gap(r);
    return BoothsState(
      ringing: -1,
      left: 0,
      next: next,
      answered: 0,
      missed: 0,
      offer: noBoothOffer,
      paid: 0,
      last: 0,
      rng: r.state,
    );
  }

  @override
  BoothsState init(Map<String, Object?> config, int seed) => start(BoothsConfig.fromJson(config), seed);

  @override
  List<BoothsAction> legalActions(BoothsState s) => [
    const BoothsAction.clear(),
    const BoothsAction.tick([]),
    if (s.ringing >= 0) BoothsAction.answer(s.ringing),
  ];

  /// `near`: ascending, no duplicates, every index in [0, booths).
  bool _validNear(List<int> near) {
    var prev = -1;
    for (final b in near) {
      if (b <= prev || b >= config.booths) return false;
      prev = b;
    }
    return true;
  }

  @override
  BoothsState apply(BoothsState state, BoothsAction a) {
    final c = config;
    final r = Prng(state.rng);
    var s = state.copyWith(last: 0);
    switch (a.op) {
      case 'tick':
        final near = a.near;
        if (near == null || !_validNear(near)) throw IllegalAction(id, a);
        if (s.ringing >= 0) {
          final left = s.left - 1;
          s = left == 0
              ? s.copyWith(left: 0, ringing: -1, missed: s.missed + 1, next: _gap(r))
              : s.copyWith(left: left);
          break;
        }
        final next = s.next - 1;
        if (next > 0) {
          s = s.copyWith(next: next);
        } else if (near.isEmpty || c.games.isEmpty) {
          s = s.copyWith(next: c.retry);
        } else {
          s = s.copyWith(next: next, ringing: near[r.nextInt(near.length)], left: c.ringS);
        }
      case 'answer':
        final b = a.booth;
        if (b == null || s.ringing < 0 || b != s.ringing) throw IllegalAction(id, a);
        s = s.copyWith(
          offer: (spot: c.games[r.nextInt(c.games.length)], bonus: c.bonus),
          ringing: -1,
          left: 0,
          answered: s.answered + 1,
          next: _gap(r),
        );
      case 'finish':
        final stars = a.stars, spot = a.spot, aborted = a.aborted;
        if (spot == null || stars == null || stars < 0 || stars > 3 || aborted == null) throw IllegalAction(id, a);
        if (s.offer.spot != '' && spot == s.offer.spot) {
          final last = stars >= 1 && !aborted ? s.offer.bonus : 0;
          s = s.copyWith(last: last, paid: s.paid + last, offer: noBoothOffer);
        }
      case 'clear':
        s = s.copyWith(offer: noBoothOffer);
      default:
        throw IllegalAction(id, a);
    }
    return s.copyWith(rng: r.state);
  }

  @override
  BoothsAction aiAction(BoothsState state, int level, Prng ai) => throw UnsupportedError('booths: no opponent');

  @override
  Map<String, Object?>? result(BoothsState state) => null;

  /// Strict JSON: a wrong type (non-integer index, non-bool `aborted`, non-string `spot`), an
  /// unknown op or `by ≠ player` is illegal.
  @override
  BoothsAction actionFromJson(Map<String, Object?> j) {
    if (j['by'] != 'player') throw IllegalAction(id, j);
    switch (j['op']) {
      case 'tick':
        final near = j['near'];
        if (near is! List || near.any((b) => b is! int)) throw IllegalAction(id, j);
        return BoothsAction.tick(near.cast<int>());
      case 'answer':
        final b = j['booth'];
        if (b is! int) throw IllegalAction(id, j);
        return BoothsAction.answer(b);
      case 'finish':
        final spot = j['spot'], stars = j['stars'], aborted = j['aborted'];
        if (spot is! String || stars is! int || aborted is! bool) throw IllegalAction(id, j);
        return BoothsAction.finish(spot, stars, aborted);
      case 'clear':
        return const BoothsAction.clear();
      default:
        throw IllegalAction(id, j);
    }
  }

  @override
  Map<String, Object?> stateToJson(BoothsState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(Map<String, Object?> r) => r;
}

// ---------- in the world (specs/booths.md P1)

/// A booth: spot `kind: booth`, parking point in metres.
class Booth {
  const Booth({required this.id, required this.name, required this.x, required this.y, required this.heading});
  final String id, name;
  final double x, y, heading;
}

/// Booths in spots.pb order; index b = order among `kind = booth` spots.
List<Booth> boothsOf(Iterable<Spot> spots) => [
  for (final s in spots)
    if (s.kind == 'booth') Booth(id: s.id, name: s.name, x: s.parkX / 10, y: s.parkY / 10, heading: s.parkHeading),
];

/// Spot ids with a catalog minigame, in spot order (the feed's candidates, specs/feed.md).
List<String> boothGames(Iterable<Spot> spots, Map<String, MinigameMeta> catalog) => [
  for (final s in spots)
    if (s.minigame.isNotEmpty && catalog.containsKey(s.minigame)) s.id,
];

/// Indices of booths with minM ≤ distance(player, parking point) ≤ maxM, ascending.
List<int> nearBooths(List<Booth> booths, double x, double y, double minM, double maxM) => [
  for (var i = 0; i < booths.length; i++)
    for (final d2 in [(booths[i].x - x) * (booths[i].x - x) + (booths[i].y - y) * (booths[i].y - y)])
      if (d2 >= minM * minM && d2 <= maxM * maxM) i,
];

/// Same conditions as "Hrát" at a spot (specs/loop.md): standing, layer 0, parking point in reach.
bool boothInReach(Booth b, double x, double y, double speed, int layer, TuningLoop t) =>
    speed <= t.stopSpeedMps &&
    layer == 0 &&
    (b.x - x) * (b.x - x) + (b.y - y) * (b.y - y) <= t.spotRadiusM * t.spotRadiusM;

/// Host of a booth call: characters[fnv1a(boothId) mod n], −1 without characters (as the loop opponent).
int boothHost(String boothId, int count) => opponentIndex(boothId, count);

/// The booths module of one session: state, game clock and its events. Nothing is saved.
class BoothWorld {
  BoothWorld(this.booths, Tuning tuning, List<String> games, int seed) {
    state = rules.start(BoothsConfig.fromTuning(tuning.booths, booths.length, games), seed);
  }

  final List<Booth> booths;
  final rules = BoothsRules();
  late BoothsState state;

  /// Game seconds not yet ticked.
  double _acc = 0;

  /// Called when a booth starts ringing (HUD toast).
  final List<void Function(Booth b)> onRing = [];

  Booth? get ringing => state.ringing >= 0 && state.ringing < booths.length ? booths[state.ringing] : null;

  BoothOffer? get offer => state.offer.spot != '' ? state.offer : null;

  /// Advances the game clock by [stepDt] (0 while paused) and ticks once per whole second;
  /// [near] gives the booths in reach at that tick (empty while ringing is suppressed).
  void update(double stepDt, List<int> Function() near) {
    _acc += stepDt > 0 ? stepDt : 0;
    while (_acc >= 1) {
      _acc -= 1;
      final was = state.ringing;
      state = rules.apply(state, BoothsAction.tick(near()));
      final b = ringing;
      if (was < 0 && b != null) {
        for (final f in [...onRing]) {
          f(b);
        }
      }
    }
  }

  /// Picks up the ringing booth; returns the offer, null when it no longer rings.
  BoothOffer? answer(int booth) {
    if (state.ringing < 0 || booth != state.ringing) return null;
    state = rules.apply(state, BoothsAction.answer(booth));
    return offer;
  }

  /// Loop result on a spot; returns the bonus (`last`).
  int finish(String spot, int stars, bool aborted) {
    state = rules.apply(state, BoothsAction.finish(spot, stars.clamp(0, 3), aborted));
    return state.last;
  }

  void clear() => state = rules.apply(state, const BoothsAction.clear());
}
