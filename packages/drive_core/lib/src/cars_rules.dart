import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/cars.md, version 1: car ownership, switching and the garage (P0, module `cars`).
/// Port of web/src/cars/rules.ts.
class CarsConfig {
  const CarsConfig({required this.prices, required this.cash, required this.owned, required this.driving});

  /// Start config from tuning (`cars.start_*`) and the prices of the loaded car specs.
  factory CarsConfig.fromTuning(TuningCars t, Map<String, int> prices) => CarsConfig(
    prices: Map.unmodifiable(prices),
    cash: t.startCash,
    owned: List.unmodifiable(t.startOwned),
    driving: t.startCar,
  );

  factory CarsConfig.fromJson(Map<String, Object?> j) => CarsConfig(
    prices: Map.unmodifiable((j['prices'] as Map).cast<String, int>()),
    cash: j['cash'] as int,
    owned: List.unmodifiable((j['owned'] as List).cast<String>()),
    driving: j['driving'] as String,
  );

  final Map<String, int> prices;
  final int cash;
  final List<String> owned;
  final String driving;
}

class CarsState {
  const CarsState({
    required this.cash,
    required this.owned,
    required this.driving,
    required this.stolen,
    required this.thefts,
  });

  final int cash;
  final List<String> owned;
  final String driving;
  final bool stolen;
  final int thefts;

  CarsState copyWith({int? cash, List<String>? owned, String? driving, bool? stolen, int? thefts}) => CarsState(
    cash: cash ?? this.cash,
    owned: owned ?? this.owned,
    driving: driving ?? this.driving,
    stolen: stolen ?? this.stolen,
    thefts: thefts ?? this.thefts,
  );

  Map<String, Object?> toJson() => {
    'cash': cash,
    'owned': owned,
    'driving': driving,
    'stolen': stolen,
    'thefts': thefts,
  };
}

/// `op` is board, select or buy; `owner` ("player" or "npc") only for board.
class CarsAction {
  const CarsAction(this.op, this.car, [this.owner]);
  const CarsAction.board(String car, String owner) : this('board', car, owner);
  const CarsAction.select(String car) : this('select', car);
  const CarsAction.buy(String car) : this('buy', car);

  final String op;
  final String car;
  final String? owner;

  Map<String, Object?> toJson() => {'by': 'player', 'op': op, 'car': car, 'owner': ?owner};

  @override
  bool operator ==(Object other) => other is CarsAction && other.op == op && other.car == car && other.owner == owner;
  @override
  int get hashCode => Object.hash(op, car, owner);
  @override
  String toString() => toJson().toString();
}

class CarsRules extends MgRules<CarsState, CarsAction, Map<String, Object?>> {
  @override
  String get id => 'cars';
  @override
  int get specVersion => 1;

  CarsConfig? _cfg;
  Map<String, int> get _prices => (_cfg ?? (throw StateError('cars: init first'))).prices;

  CarsState start(CarsConfig c) {
    _cfg = c;
    return CarsState(cash: c.cash, owned: List.unmodifiable(c.owned), driving: c.driving, stolen: false, thefts: 0);
  }

  @override
  CarsState init(Map<String, Object?> config, int seed) => start(CarsConfig.fromJson(config));

  /// Cars the player could buy now (garage API for M1-S11), alphabetical by id.
  List<String> buyable(CarsState s) =>
      (_prices.keys.toList()..sort()).where((c) => !s.owned.contains(c) && s.cash >= _prices[c]!).toList();

  @override
  List<CarsAction> legalActions(CarsState s) => [
    for (final c in s.owned)
      if (c != s.driving || s.stolen) CarsAction.select(c),
    for (final c in buyable(s)) CarsAction.buy(c),
  ];

  @override
  CarsState apply(CarsState s, CarsAction a) {
    if (!_prices.containsKey(a.car)) throw IllegalAction(id, a);
    switch (a.op) {
      case 'board':
        if (a.owner == 'player') {
          if (!s.owned.contains(a.car)) throw IllegalAction(id, a);
          return s.copyWith(driving: a.car, stolen: false);
        }
        if (a.owner != 'npc') throw IllegalAction(id, a);
        return s.copyWith(driving: a.car, stolen: true, thefts: s.thefts + 1);
      case 'select':
        if (!s.owned.contains(a.car) || (a.car == s.driving && !s.stolen)) throw IllegalAction(id, a);
        return s.copyWith(driving: a.car, stolen: false);
      case 'buy':
        final price = _prices[a.car]!;
        if (s.owned.contains(a.car) || s.cash < price) throw IllegalAction(id, a);
        return s.copyWith(owned: List.unmodifiable([...s.owned, a.car]), cash: s.cash - price);
    }
    throw IllegalAction(id, a);
  }

  @override
  CarsAction aiAction(CarsState state, int level, Prng ai) => throw UnsupportedError('cars: no opponent');

  @override
  Map<String, Object?>? result(CarsState state) => null;

  @override
  CarsAction actionFromJson(Map<String, Object?> j) {
    if (j['by'] != 'player') throw IllegalAction(id, j);
    return CarsAction(j['op'] as String, j['car'] as String, j['owner'] as String?);
  }

  @override
  Map<String, Object?> stateToJson(CarsState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(Map<String, Object?> r) => r;
}
