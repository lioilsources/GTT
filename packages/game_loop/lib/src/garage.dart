// Tuning and cosmetics (specs/garage.md, version 2): the P0 rules (module `garage`), the config from
// tuning and the catalog, and the pure look resolution (colours from design/tokens.json).
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// Tuning slots of a car (schema `tuning_slots`), the order of the garage rows.
const garageSlots = ['engine', 'tyres', 'brakes', 'weight', 'drift'];

/// Look parts in their fixed order (specs/garage.md "Vzhled").
const garageParts = ['paint', 'decal', 'wheels', 'glow', 'smoke'];

/// Sprite ids of the decal choices 1… (specs/art.md v3 `garage/decals/<id>.png`; index = choice − 1).
const garageDecalIds = ['stripes', 'flames', 'checker', 'stars', 'lightning', 'waves', 'camo', 'halftone'];

/// Sprite ids of the wheel choices 1… (specs/art.md v3 `garage/wheels/<id>.png`; index = choice − 1).
const garageWheelIds = ['sport', 'whitewall', 'five_spoke', 'mesh', 'turbine', 'offroad'];

/// Number of decal choices (0 = none + one per sprite id): 9.
final garageDecalCount = 1 + garageDecalIds.length;

/// `{carId: {key: int}}`: upgrade levels per slot or look values per part.
typedef CarLevels = Map<String, Map<String, int>>;

class GarageConfig {
  const GarageConfig({
    required this.cars,
    required this.maxLevel,
    required this.prices,
    required this.parts,
    required this.lookPrices,
  });

  /// Config from tuning, the look tokens and the catalog ([cars] = carId → `tuning_slots`, catalog order).
  factory GarageConfig.fromTuning(TuningGarage t, Map<String, List<String>> cars) => GarageConfig(
    cars: Map.unmodifiable({for (final e in cars.entries) e.key: List<String>.unmodifiable(e.value)}),
    maxLevel: t.maxLevel,
    prices: Map.unmodifiable({
      'engine': List<int>.unmodifiable(t.priceEngine),
      'tyres': List<int>.unmodifiable(t.priceTyres),
      'brakes': List<int>.unmodifiable(t.priceBrakes),
      'weight': List<int>.unmodifiable(t.priceWeight),
      'drift': List<int>.unmodifiable(t.priceDrift),
    }),
    parts: Map.unmodifiable({
      'paint': 1 + Tokens.colorGaragePaints.length,
      'decal': garageDecalCount,
      'wheels': Tokens.colorGarageWheels.length,
      'glow': 1 + Tokens.colorGarageGlow.length,
      'smoke': 1 + Tokens.colorGarageSmoke.length,
    }),
    lookPrices: Map.unmodifiable({
      'paint': t.lookPricePaint,
      'decal': t.lookPriceDecal,
      'wheels': t.lookPriceWheels,
      'glow': t.lookPriceGlow,
      'smoke': t.lookPriceSmoke,
    }),
  );

  factory GarageConfig.fromJson(Map<String, Object?> j) => GarageConfig(
    cars: {for (final e in (j['cars'] as Map).entries) e.key as String: (e.value as List).cast<String>().toList()},
    maxLevel: j['maxLevel'] as int,
    prices: {for (final e in (j['prices'] as Map).entries) e.key as String: (e.value as List).cast<int>().toList()},
    parts: (j['parts'] as Map).cast<String, int>(),
    lookPrices: (j['lookPrices'] as Map).cast<String, int>(),
  );

  /// Every catalog car with its slots (JSON order). Ownership is checked by the UI.
  final Map<String, List<String>> cars;
  final int maxLevel;

  /// Price of the next level by slot: `prices[slot][current level]`.
  final Map<String, List<int>> prices;

  /// Number of choices per part (value 0 … parts[part] − 1).
  final Map<String, int> parts;

  /// Price of a look choice ≥ 1 per part (back to 0 is free).
  final Map<String, int> lookPrices;

  /// Price of the next level of [slot] at [level] (null at the maximum or without a price).
  int? upgradePrice(String slot, int level) {
    final p = prices[slot];
    if (p == null || level >= maxLevel || level < 0 || level >= p.length) return null;
    return p[level];
  }

  int lookPrice(String part, int value) => value == 0 ? 0 : (lookPrices[part] ?? 0);
}

/// The last purchase: op ∈ '', 'upgrade', 'look'; amount = paid.
typedef GarageLast = ({String op, int amount});

const GarageLast noGarageLast = (op: '', amount: 0);

class GarageState {
  const GarageState({required this.upgrades, required this.looks, required this.last});

  /// Only non-zero values; keys sorted.
  final CarLevels upgrades, looks;
  final GarageLast last;

  int level(String car, String slot) => upgrades[car]?[slot] ?? 0;
  int look(String car, String part) => looks[car]?[part] ?? 0;

  Map<String, Object?> toJson() => {
    'upgrades': _copy(upgrades),
    'looks': _copy(looks),
    'last': {'op': last.op, 'amount': last.amount},
  };
}

CarLevels _copy(CarLevels m) => {
  for (final e in m.entries) e.key: {...e.value},
};

/// Sorted keys, zeros and empty cars dropped (specs/garage.md "Stav").
CarLevels _clean(CarLevels m) {
  final out = <String, Map<String, int>>{};
  for (final car in m.keys.toList()..sort()) {
    final inner = m[car]!;
    final keys = inner.keys.where((k) => inner[k] != 0).toList()..sort();
    if (keys.isEmpty) continue;
    out[car] = Map.unmodifiable({for (final k in keys) k: inner[k]!});
  }
  return Map.unmodifiable(out);
}

/// `op` is load ([upgrades], [looks]), upgrade ([car], [slot], [cash]) or look ([car], [part], [value], [cash]).
class GarageAction {
  const GarageAction.load(CarLevels this.upgrades, CarLevels this.looks)
    : op = 'load',
      car = null,
      slot = null,
      part = null,
      value = null,
      cash = null;
  const GarageAction.upgrade(String this.car, String this.slot, int this.cash)
    : op = 'upgrade',
      upgrades = null,
      looks = null,
      part = null,
      value = null;
  const GarageAction.look(String this.car, String this.part, int this.value, int this.cash)
    : op = 'look',
      upgrades = null,
      looks = null,
      slot = null;

  final String op;
  final CarLevels? upgrades, looks;
  final String? car, slot, part;
  final int? value, cash;

  Map<String, Object?> toJson() => switch (op) {
    'load' => {'by': 'player', 'op': op, 'upgrades': _copy(upgrades!), 'looks': _copy(looks!)},
    'upgrade' => {'by': 'player', 'op': op, 'car': car, 'slot': slot, 'cash': cash},
    _ => {'by': 'player', 'op': op, 'car': car, 'part': part, 'value': value, 'cash': cash},
  };

  @override
  bool operator ==(Object other) => other is GarageAction && canonical(other.toJson()) == canonical(toJson());
  @override
  int get hashCode => canonical(toJson()).hashCode;
  @override
  String toString() => toJson().toString();
}

class GarageRules extends MgRules<GarageState, GarageAction, Map<String, Object?>> {
  @override
  String get id => 'garage';
  @override
  int get specVersion => 1;

  GarageConfig? _cfg;
  GarageConfig get config => _cfg ?? (throw StateError('garage: init first'));

  GarageState start(GarageConfig c) {
    _cfg = c;
    return const GarageState(upgrades: {}, looks: {}, last: noGarageLast);
  }

  /// `seed` is not used.
  @override
  GarageState init(Map<String, Object?> config, int seed) => start(GarageConfig.fromJson(config));

  /// load {} {}; upgrades by car id (code units) and slot order below the maximum; then looks by
  /// car id and the fixed part order, every value ≠ the current one; `cash` = the price.
  @override
  List<GarageAction> legalActions(GarageState s) {
    final c = config;
    final ids = c.cars.keys.toList()..sort();
    return [
      const GarageAction.load({}, {}),
      for (final car in ids)
        for (final slot in c.cars[car]!)
          if (c.upgradePrice(slot, s.level(car, slot)) case final price?) GarageAction.upgrade(car, slot, price),
      for (final car in ids)
        for (final part in garageParts)
          if (c.parts[part] case final n?)
            for (var v = 0; v < n; v++)
              if (v != s.look(car, part)) GarageAction.look(car, part, v, c.lookPrice(part, v)),
    ];
  }

  @override
  GarageState apply(GarageState state, GarageAction a) {
    final c = config;
    switch (a.op) {
      case 'load':
        final up = a.upgrades, lk = a.looks;
        if (up == null || lk == null) throw IllegalAction(id, a);
        final upgrades = <String, Map<String, int>>{};
        for (final e in up.entries) {
          final slots = c.cars[e.key];
          if (slots == null) continue;
          upgrades[e.key] = {
            for (final s in e.value.entries)
              if (slots.contains(s.key)) s.key: s.value.clamp(0, c.maxLevel),
          };
        }
        final looks = <String, Map<String, int>>{};
        for (final e in lk.entries) {
          if (!c.cars.containsKey(e.key)) continue;
          looks[e.key] = {
            for (final p in e.value.entries)
              if (c.parts[p.key] case final n? when p.value >= 0 && p.value < n) p.key: p.value,
          };
        }
        return GarageState(upgrades: _clean(upgrades), looks: _clean(looks), last: noGarageLast);
      case 'upgrade':
        final car = a.car, slot = a.slot, cash = a.cash;
        final slots = car == null ? null : c.cars[car];
        if (slots == null || slot == null || !slots.contains(slot) || cash == null) throw IllegalAction(id, a);
        final lvl = state.level(car!, slot);
        final price = c.upgradePrice(slot, lvl);
        if (price == null || cash < 0 || cash < price) throw IllegalAction(id, a);
        final up = _copy(state.upgrades);
        (up[car] ??= {})[slot] = lvl + 1;
        return GarageState(upgrades: _clean(up), looks: state.looks, last: (op: 'upgrade', amount: price));
      case 'look':
        final car = a.car, part = a.part, value = a.value, cash = a.cash;
        final n = part == null ? null : c.parts[part];
        if (car == null || !c.cars.containsKey(car) || n == null || value == null || cash == null) {
          throw IllegalAction(id, a);
        }
        if (value < 0 || value >= n || value == state.look(car, part!)) throw IllegalAction(id, a);
        final price = c.lookPrice(part, value);
        if (cash < 0 || cash < price) throw IllegalAction(id, a);
        final lk = _copy(state.looks);
        (lk[car] ??= {})[part] = value;
        return GarageState(upgrades: state.upgrades, looks: _clean(lk), last: (op: 'look', amount: price));
      default:
        throw IllegalAction(id, a);
    }
  }

  @override
  GarageAction aiAction(GarageState state, int level, Prng ai) => throw UnsupportedError('garage: no opponent');

  @override
  Map<String, Object?>? result(GarageState state) => null;

  /// Strict JSON: a non-integer value, a map that is not an object, a wrong id type, an unknown op
  /// or `by ≠ player` is illegal.
  @override
  GarageAction actionFromJson(Map<String, Object?> j) {
    if (j['by'] != 'player') throw IllegalAction(id, j);
    switch (j['op']) {
      case 'load':
        final up = _levels(j['upgrades']), lk = _levels(j['looks']);
        if (up == null || lk == null) throw IllegalAction(id, j);
        return GarageAction.load(up, lk);
      case 'upgrade':
        final car = j['car'], slot = j['slot'], cash = j['cash'];
        if (car is! String || slot is! String || cash is! int) throw IllegalAction(id, j);
        return GarageAction.upgrade(car, slot, cash);
      case 'look':
        final car = j['car'], part = j['part'], value = j['value'], cash = j['cash'];
        if (car is! String || part is! String || value is! int || cash is! int) throw IllegalAction(id, j);
        return GarageAction.look(car, part, value, cash);
      default:
        throw IllegalAction(id, j);
    }
  }

  @override
  Map<String, Object?> stateToJson(GarageState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(Map<String, Object?> r) => r;
}

/// `{carId: {key: int}}` from JSON, null when it is not objects of integers.
CarLevels? _levels(Object? v) {
  if (v is! Map) return null;
  final out = <String, Map<String, int>>{};
  for (final e in v.entries) {
    final inner = e.value;
    if (e.key is! String || inner is! Map) return null;
    final m = <String, int>{};
    for (final x in inner.entries) {
      if (x.key is! String || x.value is! int) return null;
      m[x.key as String] = x.value as int;
    }
    out[e.key as String] = m;
  }
  return out;
}

// ---------- looks (specs/garage.md "Kreslení"), colours as 0xAARRGGBB

/// The look of one car, resolved to colours; [paint] / [rim] / [glow] null = the catalog drawing.
class CarLook {
  const CarLook({this.paint, this.decal = 0, this.rim, this.glow, this.smoke, this.wheels = 0});

  /// Resolves the part values of [values] (missing = 0; out-of-range values fall back to 0).
  factory CarLook.of(Map<String, int>? values) {
    int v(String part) => values?[part] ?? 0;
    int? pick(List<int> list, int i) => i >= 0 && i < list.length ? list[i] : null;
    final d = v('decal');
    final w = v('wheels');
    final rim = pick(Tokens.colorGarageWheels, w);
    return CarLook(
      paint: v('paint') >= 1 ? pick(Tokens.colorGaragePaints, v('paint') - 1) : null,
      decal: d >= 0 && d < garageDecalCount ? d : 0,
      rim: rim ?? Tokens.colorGarageWheels.first,
      wheels: rim == null ? 0 : w,
      glow: v('glow') >= 1 ? pick(Tokens.colorGarageGlow, v('glow') - 1) : null,
      smoke: v('smoke') >= 1 ? pick(Tokens.colorGarageSmoke, v('smoke') - 1) : null,
    );
  }

  final int? paint, rim, glow, smoke;

  /// 0 none, 1 stripes, 2 flames, 3 checker, 4 stars, 5 lightning, 6 waves, 7 camo, 8 halftone.
  final int decal;

  /// The wheels choice (0 stock; ≥ 1 a garage wheel sprite `garageWheelIds[wheels − 1]` when indexed).
  final int wheels;

  static const stock = CarLook();
}

/// Swatch colour of choice [value] of [part] in the garage ([catalogPaint] for paint 0; null = no swatch).
int? lookSwatch(String part, int value, int catalogPaint) => switch (part) {
  'paint' => value == 0 ? catalogPaint : _at(Tokens.colorGaragePaints, value - 1),
  'wheels' => _at(Tokens.colorGarageWheels, value),
  'glow' => value == 0 ? null : _at(Tokens.colorGarageGlow, value - 1),
  'smoke' => value == 0 ? null : _at(Tokens.colorGarageSmoke, value - 1),
  _ => null,
};

int? _at(List<int> l, int i) => i >= 0 && i < l.length ? l[i] : null;

/// Percent shown in `garageEffect<Slot>` for the next level (the slot's main step × 100, rounded).
int garageEffectPct(TuningGarage t, String slot) => switch (slot) {
  'engine' => (t.enginePowerStep * 100).round(),
  'tyres' => (t.tyresStep * 100).round(),
  'brakes' => (t.brakesStep * 100).round(),
  'weight' => (t.weightMassStep * 100).round(),
  _ => (t.driftStep * 100).round(),
};

/// The garage of one session: rules and state. Cash goes in from and back to the cars state
/// (the caller), like the shops.
class GarageWorld {
  GarageWorld(this.config, {CarLevels upgrades = const {}, CarLevels looks = const {}}) {
    state = rules.start(config);
    load(upgrades, looks);
  }

  final GarageConfig config;
  final rules = GarageRules();
  late GarageState state;

  void load(CarLevels upgrades, CarLevels looks) => state = rules.apply(state, GarageAction.load(upgrades, looks));

  List<String> slotsOf(String car) => config.cars[car] ?? const [];

  int level(String car, String slot) => state.level(car, slot);
  int look(String car, String part) => state.look(car, part);
  Map<String, int> levels(String car) => state.upgrades[car] ?? const {};
  Map<String, int> looks(String car) => state.looks[car] ?? const {};

  /// Price of the next level, null at the maximum or for a slot the car has not.
  int? upgradePrice(String car, String slot) =>
      slotsOf(car).contains(slot) ? config.upgradePrice(slot, level(car, slot)) : null;

  bool canUpgrade(String car, String slot, int cash) {
    final p = upgradePrice(car, slot);
    return p != null && cash >= 0 && cash >= p;
  }

  bool canLook(String car, String part, int value, int cash) {
    final n = config.parts[part];
    if (!config.cars.containsKey(car) || n == null || value < 0 || value >= n || value == look(car, part)) {
      return false;
    }
    final p = config.lookPrice(part, value);
    return cash >= 0 && cash >= p;
  }

  /// Buys the next level; returns the amount paid, null when not possible.
  int? upgrade(String car, String slot, int cash) {
    if (!canUpgrade(car, slot, cash)) return null;
    state = rules.apply(state, GarageAction.upgrade(car, slot, cash));
    return state.last.amount;
  }

  /// Sets a look; returns the amount paid (0 for back to stock), null when not possible.
  int? setLook(String car, String part, int value, int cash) {
    if (!canLook(car, part, value, cash)) return null;
    state = rules.apply(state, GarageAction.look(car, part, value, cash));
    return state.last.amount;
  }
}
