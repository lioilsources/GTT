import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/economy.md, version 1: loop reward, tow fee and police fine (P0, integers only).
/// Port of web/src/loop/economy.ts.
class EconomyConfig {
  const EconomyConfig({
    required this.cash,
    required this.base,
    required this.enginePct,
    required this.starPct,
    required this.scoreBands,
    required this.bandBonus,
    required this.firstBonus,
    required this.firstMinStars,
    required this.rewardBase,
    required this.rewardPerMin,
    required this.driveDmPerS,
    required this.towFee,
  });

  /// Config from tuning (economy.* and the feed's trip money) with the current cash.
  factory EconomyConfig.fromTuning(Tuning t, int cash) {
    final e = t.economy, f = t.feed;
    return EconomyConfig(
      cash: cash,
      base: e.base,
      enginePct: e.enginePct.toJson().cast<String, int>(),
      starPct: List.unmodifiable(e.starPct),
      scoreBands: List.unmodifiable(e.scoreBands),
      bandBonus: List.unmodifiable(e.bandBonus),
      firstBonus: e.firstBonus,
      firstMinStars: e.firstMinStars,
      rewardBase: f.rewardBase,
      rewardPerMin: f.rewardPerMin,
      driveDmPerS: f.driveDmPerS,
      towFee: e.towFee,
    );
  }

  factory EconomyConfig.fromJson(Map<String, Object?> j) => EconomyConfig(
    cash: j['cash'] as int,
    base: j['base'] as int,
    enginePct: (j['enginePct'] as Map).cast<String, int>(),
    starPct: (j['starPct'] as List).cast<int>(),
    scoreBands: (j['scoreBands'] as List).cast<int>(),
    bandBonus: (j['bandBonus'] as List).cast<int>(),
    firstBonus: j['firstBonus'] as int,
    firstMinStars: j['firstMinStars'] as int,
    rewardBase: j['rewardBase'] as int,
    rewardPerMin: j['rewardPerMin'] as int,
    driveDmPerS: j['driveDmPerS'] as int,
    towFee: j['towFee'] as int,
  );

  final int cash, base, firstBonus, firstMinStars, rewardBase, rewardPerMin, driveDmPerS, towFee;
  final Map<String, int> enginePct;
  final List<int> starPct, scoreBands, bandBonus;
}

/// The parts of the last economy action (for the result screen).
class EconomyLast {
  const EconomyLast(this.op, {this.amount = 0, this.base = 0, this.trip = 0, this.band = 0, this.first = 0});
  final String op;
  final int amount, base, trip, band, first;

  Map<String, Object?> toJson() => {
    'op': op,
    'amount': amount,
    'base': base,
    'trip': trip,
    'band': band,
    'first': first,
  };
}

class EconomyState {
  const EconomyState({required this.cash, required this.earned, required this.paid, required this.last});
  final int cash, earned, paid;
  final EconomyLast last;

  EconomyState withCash(int c) => EconomyState(cash: c, earned: earned, paid: paid, last: last);

  Map<String, Object?> toJson() => {'cash': cash, 'earned': earned, 'paid': paid, 'last': last.toJson()};
}

/// `op` is reward, tow or fine.
class EconomyAction {
  const EconomyAction.reward({
    required String this.engine,
    required int this.stars,
    required int this.score,
    required bool this.first,
    required int this.driveDm,
    required bool this.aborted,
  }) : op = 'reward',
       amount = null;
  const EconomyAction.tow()
    : op = 'tow',
      engine = null,
      stars = null,
      score = null,
      first = null,
      driveDm = null,
      aborted = null,
      amount = null;
  const EconomyAction.fine(int this.amount)
    : op = 'fine',
      engine = null,
      stars = null,
      score = null,
      first = null,
      driveDm = null,
      aborted = null;

  final String op;
  final String? engine;
  final int? stars, score, driveDm, amount;
  final bool? first, aborted;

  @override
  String toString() => 'economy $op';
}

class EconomyRules extends MgRules<EconomyState, EconomyAction, Map<String, Object?>> {
  @override
  String get id => 'economy';
  @override
  int get specVersion => 1;

  EconomyConfig? _cfg;
  EconomyConfig get _c => _cfg ?? (throw StateError('economy: init first'));

  EconomyState start(EconomyConfig c) {
    _cfg = c;
    return EconomyState(cash: c.cash, earned: 0, paid: 0, last: const EconomyLast(''));
  }

  @override
  EconomyState init(Map<String, Object?> config, int seed) => start(EconomyConfig.fromJson(config));

  /// The reward parts for a loop result (specs/economy.md "apply – reward").
  EconomyLast reward({
    required String engine,
    required int stars,
    required int score,
    required bool first,
    required int driveDm,
    required bool aborted,
  }) {
    final c = _c;
    if (aborted || stars == 0) return const EconomyLast('reward');
    final sp = stars < c.starPct.length ? c.starPct[stars] : 0;
    final pct = c.enginePct[engine] ?? 100;
    final base = (c.base * pct ~/ 100) * sp ~/ 100;
    final trip = driveDm > 0 ? (c.rewardBase + (driveDm ~/ c.driveDmPerS) * c.rewardPerMin ~/ 60) * sp ~/ 100 : 0;
    final k = c.scoreBands.where((b) => b <= score).length;
    final band = k < c.bandBonus.length ? c.bandBonus[k] : 0;
    final f = first && stars >= c.firstMinStars ? c.firstBonus : 0;
    return EconomyLast('reward', amount: base + trip + band + f, base: base, trip: trip, band: band, first: f);
  }

  @override
  List<EconomyAction> legalActions(EconomyState state) => [const EconomyAction.tow()];

  @override
  EconomyState apply(EconomyState s, EconomyAction a) {
    switch (a.op) {
      case 'reward':
        final stars = a.stars!;
        if (stars < 0 || stars > 3 || a.driveDm! < 0) throw IllegalAction(id, a);
        final last = reward(
          engine: a.engine!,
          stars: stars,
          score: a.score!,
          first: a.first!,
          driveDm: a.driveDm!,
          aborted: a.aborted!,
        );
        return EconomyState(cash: s.cash + last.amount, earned: s.earned + last.amount, paid: s.paid, last: last);
      case 'tow':
        return _pay(s, 'tow', _c.towFee);
      case 'fine':
        if (a.amount! < 0) throw IllegalAction(id, a);
        return _pay(s, 'fine', a.amount!);
    }
    throw IllegalAction(id, a);
  }

  EconomyState _pay(EconomyState s, String op, int amount) {
    final fee = amount < s.cash ? amount : s.cash;
    return EconomyState(
      cash: s.cash - fee,
      earned: s.earned,
      paid: s.paid + fee,
      last: EconomyLast(op, amount: fee),
    );
  }

  @override
  EconomyAction aiAction(EconomyState state, int level, Prng ai) => throw UnsupportedError('economy: no opponent');

  @override
  Map<String, Object?>? result(EconomyState state) => null;

  /// Strict JSON reading: wrong types are illegal actions (the web side checks the same).
  @override
  EconomyAction actionFromJson(Map<String, Object?> j) {
    if (j['by'] != 'player') throw IllegalAction(id, j);
    switch (j['op']) {
      case 'reward':
        final engine = j['engine'], stars = j['stars'], score = j['score'];
        final first = j['first'], driveDm = j['driveDm'], aborted = j['aborted'];
        if (engine is! String ||
            stars is! int ||
            score is! int ||
            first is! bool ||
            driveDm is! int ||
            aborted is! bool) {
          throw IllegalAction(id, j);
        }
        return EconomyAction.reward(
          engine: engine,
          stars: stars,
          score: score,
          first: first,
          driveDm: driveDm,
          aborted: aborted,
        );
      case 'tow':
        return const EconomyAction.tow();
      case 'fine':
        final amount = j['amount'];
        if (amount is! int) throw IllegalAction(id, j);
        return EconomyAction.fine(amount);
    }
    throw IllegalAction(id, j);
  }

  @override
  Map<String, Object?> stateToJson(EconomyState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(Map<String, Object?> r) => r;
}
