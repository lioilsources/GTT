// Shops and bars (specs/shops.md, version 1): the P0 rules (module `shops`) and the pure world
// helpers (venue list, reach, bar minigames, the 1 s game tick).
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/citypack_pb.dart' show Spot;
import 'package:shared_gen/shared_gen.dart';

import 'logic.dart' show opponentIndex;

/// Venue kinds (spot `kind`).
const shopKinds = ['food', 'souvenir', 'bar'];

typedef ShopItem = ({String id, String kind, int price});

class ShopsConfig {
  const ShopsConfig({
    required this.snackPct,
    required this.beerLimit,
    required this.beerS,
    required this.snackS,
    required this.items,
  });

  /// Config from tuning and the venues of the city (spots.pb order, [shopsOf]).
  factory ShopsConfig.fromTuning(TuningShops t, Iterable<({String id, String kind})> venues) => ShopsConfig(
    snackPct: t.snackPct,
    beerLimit: t.beerLimit,
    beerS: t.beerS,
    snackS: t.snackS,
    items: List.unmodifiable([
      for (final v in venues) (id: v.id, kind: v.kind, price: shopPrice(t, v.kind)),
    ]),
  );

  factory ShopsConfig.fromJson(Map<String, Object?> j) => ShopsConfig(
    snackPct: j['snackPct'] as int,
    beerLimit: j['beerLimit'] as int,
    beerS: j['beerS'] as int,
    snackS: j['snackS'] as int,
    items: List.unmodifiable([
      for (final i in (j['items'] as List).cast<Map<String, Object?>>())
        (id: i['id'] as String, kind: i['kind'] as String, price: i['price'] as int),
    ]),
  );

  final int snackPct, beerLimit, beerS, snackS;
  final List<ShopItem> items;

  ShopItem? item(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }
}

/// Price by kind: shops.price_food / price_souvenir / price_beer (a bar sells beer).
int shopPrice(TuningShops t, String kind) => switch (kind) {
  'food' => t.priceFood,
  'souvenir' => t.priceSouvenir,
  _ => t.priceBeer,
};

/// The last action: op ∈ '', 'buy', 'reward'; amount = paid / bonus.
typedef ShopsLast = ({String op, int amount});

const ShopsLast noShopsLast = (op: '', amount: 0);

class ShopsState {
  const ShopsState({
    required this.snackLeft,
    required this.beers,
    required this.beerLeft,
    required this.drunk,
    required this.owned,
    required this.last,
  });

  final int snackLeft, beers, beerLeft;
  final bool drunk;
  final List<String> owned;
  final ShopsLast last;

  ShopsState copyWith({
    int? snackLeft,
    int? beers,
    int? beerLeft,
    bool? drunk,
    List<String>? owned,
    ShopsLast? last,
  }) => ShopsState(
    snackLeft: snackLeft ?? this.snackLeft,
    beers: beers ?? this.beers,
    beerLeft: beerLeft ?? this.beerLeft,
    drunk: drunk ?? this.drunk,
    owned: owned ?? this.owned,
    last: last ?? this.last,
  );

  Map<String, Object?> toJson() => {
    'snackLeft': snackLeft,
    'beers': beers,
    'beerLeft': beerLeft,
    'drunk': drunk,
    'owned': [...owned],
    'last': {'op': last.op, 'amount': last.amount},
  };
}

/// `op` is load ([owned]), tick, buy ([shop], [cash]), reward ([amount]) or finish ([stars], [aborted]).
class ShopsAction {
  const ShopsAction.load(List<String> this.owned)
    : op = 'load',
      shop = null,
      cash = null,
      amount = null,
      stars = null,
      aborted = null;
  const ShopsAction.tick() : op = 'tick', owned = null, shop = null, cash = null, amount = null, stars = null, aborted = null;
  const ShopsAction.buy(String this.shop, int this.cash)
    : op = 'buy',
      owned = null,
      amount = null,
      stars = null,
      aborted = null;
  const ShopsAction.reward(int this.amount)
    : op = 'reward',
      owned = null,
      shop = null,
      cash = null,
      stars = null,
      aborted = null;
  const ShopsAction.finish(int this.stars, bool this.aborted)
    : op = 'finish',
      owned = null,
      shop = null,
      cash = null,
      amount = null;

  final String op;
  final List<String>? owned;
  final String? shop;
  final int? cash, amount, stars;
  final bool? aborted;

  Map<String, Object?> toJson() => switch (op) {
    'load' => {'by': 'player', 'op': op, 'owned': owned},
    'buy' => {'by': 'player', 'op': op, 'shop': shop, 'cash': cash},
    'reward' => {'by': 'player', 'op': op, 'amount': amount},
    'finish' => {'by': 'player', 'op': op, 'stars': stars, 'aborted': aborted},
    _ => {'by': 'player', 'op': op},
  };

  @override
  bool operator ==(Object other) =>
      other is ShopsAction &&
      other.op == op &&
      other.shop == shop &&
      other.cash == cash &&
      other.amount == amount &&
      other.stars == stars &&
      other.aborted == aborted &&
      _sameList(other.owned, owned);
  @override
  int get hashCode =>
      Object.hash(op, shop, cash, amount, stars, aborted, owned == null ? null : Object.hashAll(owned!));
  @override
  String toString() => toJson().toString();
}

bool _sameList(List<String>? a, List<String>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class ShopsRules extends MgRules<ShopsState, ShopsAction, Map<String, Object?>> {
  @override
  String get id => 'shops';
  @override
  int get specVersion => 1;

  ShopsConfig? _cfg;
  ShopsConfig get config => _cfg ?? (throw StateError('shops: init first'));

  ShopsState start(ShopsConfig c) {
    _cfg = c;
    return const ShopsState(snackLeft: 0, beers: 0, beerLeft: 0, drunk: false, owned: [], last: noShopsLast);
  }

  /// `seed` is not used.
  @override
  ShopsState init(Map<String, Object?> config, int seed) => start(ShopsConfig.fromJson(config));

  @override
  List<ShopsAction> legalActions(ShopsState s) => [
    const ShopsAction.load([]),
    const ShopsAction.tick(),
    const ShopsAction.finish(1, false),
    const ShopsAction.reward(0),
    for (final i in config.items)
      if (!(i.kind == 'souvenir' && s.owned.contains(i.id))) ShopsAction.buy(i.id, i.price),
  ];

  @override
  ShopsState apply(ShopsState state, ShopsAction a) {
    final c = config;
    var s = state.copyWith(last: noShopsLast);
    switch (a.op) {
      case 'load':
        final owned = a.owned;
        if (owned == null) throw IllegalAction(id, a);
        final seen = <String>{};
        s = s.copyWith(
          owned: List.unmodifiable([
            for (final o in owned)
              if (c.item(o)?.kind == 'souvenir' && seen.add(o)) o,
          ]),
        );
      case 'tick':
        s = s.copyWith(snackLeft: s.snackLeft > 0 ? s.snackLeft - 1 : 0);
        if (!s.drunk && s.beers > 0) {
          final left = s.beerLeft - 1;
          if (left <= 0) {
            final beers = s.beers - 1;
            s = s.copyWith(beers: beers, beerLeft: beers > 0 ? c.beerS : 0);
          } else {
            s = s.copyWith(beerLeft: left);
          }
        }
      case 'buy':
        final shop = a.shop, cash = a.cash;
        final item = shop == null ? null : c.item(shop);
        if (item == null || cash == null || cash < 0 || cash < item.price) throw IllegalAction(id, a);
        if (item.kind == 'souvenir' && s.owned.contains(item.id)) throw IllegalAction(id, a);
        switch (item.kind) {
          case 'food':
            s = s.copyWith(snackLeft: c.snackS);
          case 'souvenir':
            s = s.copyWith(owned: List.unmodifiable([...s.owned, item.id]));
          case 'bar':
            if (s.beers == 0) s = s.copyWith(beerLeft: c.beerS);
            final beers = s.beers + 1;
            s = s.copyWith(beers: beers, drunk: s.drunk || beers > c.beerLimit);
          default:
            throw IllegalAction(id, a);
        }
        s = s.copyWith(last: (op: 'buy', amount: item.price));
      case 'reward':
        final amount = a.amount;
        if (amount == null || amount < 0) throw IllegalAction(id, a);
        var bonus = 0;
        if (s.snackLeft > 0) {
          bonus = amount * c.snackPct ~/ 100;
          s = s.copyWith(snackLeft: 0);
        }
        s = s.copyWith(last: (op: 'reward', amount: bonus));
      case 'finish':
        final stars = a.stars, aborted = a.aborted;
        if (stars == null || stars < 0 || stars > 3 || aborted == null) throw IllegalAction(id, a);
        if (s.drunk && stars >= 1 && !aborted) s = s.copyWith(drunk: false, beers: 0, beerLeft: 0);
      default:
        throw IllegalAction(id, a);
    }
    return s;
  }

  @override
  ShopsAction aiAction(ShopsState state, int level, Prng ai) => throw UnsupportedError('shops: no opponent');

  @override
  Map<String, Object?>? result(ShopsState state) => null;

  /// Strict JSON: a wrong type (non-integer cash, non-bool `aborted`, non-string id), an unknown op
  /// or `by ≠ player` is illegal.
  @override
  ShopsAction actionFromJson(Map<String, Object?> j) {
    if (j['by'] != 'player') throw IllegalAction(id, j);
    switch (j['op']) {
      case 'load':
        final owned = j['owned'];
        if (owned is! List || owned.any((o) => o is! String)) throw IllegalAction(id, j);
        return ShopsAction.load(owned.cast<String>());
      case 'tick':
        return const ShopsAction.tick();
      case 'buy':
        final shop = j['shop'], cash = j['cash'];
        if (shop is! String || cash is! int) throw IllegalAction(id, j);
        return ShopsAction.buy(shop, cash);
      case 'reward':
        final amount = j['amount'];
        if (amount is! int) throw IllegalAction(id, j);
        return ShopsAction.reward(amount);
      case 'finish':
        final stars = j['stars'], aborted = j['aborted'];
        if (stars is! int || aborted is! bool) throw IllegalAction(id, j);
        return ShopsAction.finish(stars, aborted);
      default:
        throw IllegalAction(id, j);
    }
  }

  @override
  Map<String, Object?> stateToJson(ShopsState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(Map<String, Object?> r) => r;
}

// ---------- in the world (specs/shops.md P1)

/// A venue: spot `kind` food / souvenir / bar, parking point in metres; [minigame] only at bars.
class Shop {
  const Shop({
    required this.id,
    required this.kind,
    required this.name,
    required this.x,
    required this.y,
    required this.heading,
    this.minigame = '',
  });
  final String id, kind, name, minigame;
  final double x, y, heading;

  bool get isBar => kind == 'bar';
}

/// Venues in spots.pb order.
List<Shop> shopsOf(Iterable<Spot> spots) => [
  for (final s in spots)
    if (shopKinds.contains(s.kind))
      Shop(
        id: s.id,
        kind: s.kind,
        name: s.name,
        x: s.parkX / 10,
        y: s.parkY / 10,
        heading: s.parkHeading,
        minigame: s.kind == 'bar' ? s.minigame : '',
      ),
];

/// Whether the module runs in [cityId]: `shops.enabled`, `shops.cities.<city>` and at least one venue.
bool shopsOn(TuningShops t, String cityId, int venues) {
  if (!t.enabled || venues == 0) return false;
  final cities = t.cities.toJson();
  return cities[cityId] == true;
}

/// Every distinct catalog minigame of the city's `kind: bar` spots, in spot order (bar card).
List<String> barGames(List<Shop> shops, Iterable<String> catalog) {
  final known = catalog.toSet();
  final seen = <String>{};
  return [
    for (final s in shops)
      if (s.isBar && s.minigame.isNotEmpty && known.contains(s.minigame) && seen.add(s.minigame)) s.minigame,
  ];
}

/// Same conditions as "Hrát" at a spot (specs/loop.md): standing, layer 0, parking point in reach.
bool shopInReach(Shop s, double x, double y, double speed, int layer, TuningLoop t) =>
    speed <= t.stopSpeedMps &&
    layer == 0 &&
    (s.x - x) * (s.x - x) + (s.y - y) * (s.y - y) <= t.spotRadiusM * t.spotRadiusM;

/// Host of a venue card: characters[fnv1a(spotId) mod n], −1 without characters.
int shopHost(String shopId, int count) => opponentIndex(shopId, count);

/// The shops module of one session: state and game clock. Only `owned` is saved.
class ShopWorld {
  ShopWorld(this.shops, TuningShops t, {List<String> owned = const []})
    : config = ShopsConfig.fromTuning(t, [for (final s in shops) (id: s.id, kind: s.kind)]) {
    state = rules.start(config);
    state = rules.apply(state, ShopsAction.load(owned));
  }

  final List<Shop> shops;
  final ShopsConfig config;
  final rules = ShopsRules();
  late ShopsState state;

  /// Game seconds not yet ticked.
  double _acc = 0;

  /// Called when the player sobers up (after a won loop).
  final List<void Function()> onSober = [];

  bool get drunk => state.drunk;
  int get beers => state.beers;
  bool get snack => state.snackLeft > 0;
  List<String> get owned => state.owned;

  int price(String shopId) => config.item(shopId)?.price ?? 0;

  bool owns(String shopId) => state.owned.contains(shopId);

  /// Whether [cash] buys at [shopId] (known venue, enough cash, souvenir not owned yet).
  bool canBuy(String shopId, int cash) {
    final i = config.item(shopId);
    if (i == null || cash < 0 || cash < i.price) return false;
    return !(i.kind == 'souvenir' && owns(shopId));
  }

  /// Advances the game clock by [stepDt] (0 while paused) and ticks once per whole second.
  void update(double stepDt) {
    _acc += stepDt > 0 ? stepDt : 0;
    while (_acc >= 1) {
      _acc -= 1;
      state = rules.apply(state, const ShopsAction.tick());
    }
  }

  /// Buys at [shopId] with [cash]; returns the amount paid, 0 when the purchase is not possible.
  int buy(String shopId, int cash) {
    if (!canBuy(shopId, cash)) return 0;
    state = rules.apply(state, ShopsAction.buy(shopId, cash));
    return state.last.amount;
  }

  /// The loop's cash reward → the snack bonus (0 without a snack).
  int reward(int amount) {
    state = rules.apply(state, ShopsAction.reward(amount < 0 ? 0 : amount));
    return state.last.amount;
  }

  /// Loop result; fires [onSober] when it sobers the player up.
  void finish(int stars, bool aborted) {
    final was = state.drunk;
    state = rules.apply(state, ShopsAction.finish(stars.clamp(0, 3), aborted));
    if (was && !state.drunk) {
      for (final f in [...onSober]) {
        f();
      }
    }
  }
}
