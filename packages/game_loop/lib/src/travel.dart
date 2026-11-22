// Fast travel by metro and taxi (specs/travel.md, version 1): the P0 rules (module `travel`) and the
// pure world helpers (stations, unlocking by passing, metro and taxi choices). Port of
// web/src/travel/rules.ts and web/src/travel/fast.ts; the road projection of taxi landmarks and the
// move itself need the world and live in the app.
import 'dart:math' as math;

import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/citypack_pb.dart' show Spot;
import 'package:shared_gen/shared_gen.dart';

class TravelConfig {
  const TravelConfig({
    required this.stations,
    required this.fareBase,
    required this.farePerKm,
    required this.taxiBase,
    required this.taxiPerKm,
  });

  /// Config from tuning and the station ids of the city (spots.pb order).
  factory TravelConfig.fromTuning(TuningTravel t, Iterable<String> stations) => TravelConfig(
    stations: List.unmodifiable(stations),
    fareBase: t.fareBase,
    farePerKm: t.farePerKm,
    taxiBase: t.taxiBase,
    taxiPerKm: t.taxiPerKm,
  );

  factory TravelConfig.fromJson(Map<String, Object?> j) => TravelConfig(
    stations: List.unmodifiable((j['stations'] as List).cast<String>()),
    fareBase: j['fareBase'] as int,
    farePerKm: j['farePerKm'] as int,
    taxiBase: j['taxiBase'] as int,
    taxiPerKm: j['taxiPerKm'] as int,
  );

  /// Station spot ids of the city in spots.pb order.
  final List<String> stations;
  final int fareBase, farePerKm, taxiBase, taxiPerKm;

  Map<String, Object?> toJson() => {
    'stations': stations,
    'fareBase': fareBase,
    'farePerKm': farePerKm,
    'taxiBase': taxiBase,
    'taxiPerKm': taxiPerKm,
  };
}

/// Metro fare: fareBase + distDm × farePerKm ÷ 10000 (integer division).
int metroFare(TravelConfig c, int distDm) => c.fareBase + (distDm * c.farePerKm) ~/ 10000;

/// Taxi fare: taxiBase + distDm × taxiPerKm ÷ 10000 (integer division).
int taxiFare(TravelConfig c, int distDm) => c.taxiBase + (distDm * c.taxiPerKm) ~/ 10000;

/// Straight distance of two points (metres) in whole dm: floor(sqrt(dx² + dy²)) of rounded dm.
int travelDistDm(double ax, double ay, double bx, double by) {
  int dm(double v) => (v * 10 + 0.5).floor();
  final dx = dm(bx) - dm(ax), dy = dm(by) - dm(ay);
  return math.sqrt((dx * dx + dy * dy).toDouble()).floor();
}

/// The last paid ride; `op == ''` after init, load and unlock.
typedef TravelLast = ({String op, int amount});

const TravelLast noTravelLast = (op: '', amount: 0);

class TravelState {
  const TravelState({required this.unlocked, required this.paid, required this.last});

  /// Unlocked stations in unlock order.
  final List<String> unlocked;

  /// Fares paid this session.
  final int paid;
  final TravelLast last;

  Map<String, Object?> toJson() => {
    'unlocked': unlocked,
    'paid': paid,
    'last': {'op': last.op, 'amount': last.amount},
  };
}

/// `op` is load ([unlocked]), unlock ([station]), metro ([from], [to], [distDm], [cash]) or taxi
/// ([distDm], [cash]).
class TravelAction {
  const TravelAction.load(List<String> this.unlocked)
    : op = 'load',
      station = null,
      from = null,
      to = null,
      distDm = null,
      cash = null;
  const TravelAction.unlock(String this.station)
    : op = 'unlock',
      unlocked = null,
      from = null,
      to = null,
      distDm = null,
      cash = null;
  const TravelAction.metro(String this.from, String this.to, int this.distDm, int this.cash)
    : op = 'metro',
      unlocked = null,
      station = null;
  const TravelAction.taxi(int this.distDm, int this.cash)
    : op = 'taxi',
      unlocked = null,
      station = null,
      from = null,
      to = null;

  final String op;
  final List<String>? unlocked;
  final String? station, from, to;
  final int? distDm, cash;

  Map<String, Object?> toJson() => switch (op) {
    'load' => {'by': 'player', 'op': op, 'unlocked': unlocked},
    'unlock' => {'by': 'player', 'op': op, 'station': station},
    'metro' => {'by': 'player', 'op': op, 'from': from, 'to': to, 'distDm': distDm, 'cash': cash},
    _ => {'by': 'player', 'op': op, 'distDm': distDm, 'cash': cash},
  };

  @override
  bool operator ==(Object other) =>
      other is TravelAction &&
      other.op == op &&
      other.station == station &&
      other.from == from &&
      other.to == to &&
      other.distDm == distDm &&
      other.cash == cash &&
      _sameList(other.unlocked, unlocked);
  @override
  int get hashCode =>
      Object.hash(op, station, from, to, distDm, cash, unlocked == null ? null : Object.hashAll(unlocked!));
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

// JSON number → int like TS Number.isInteger (5.0 counts, 1.5 does not).
int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is double && v.isFinite && v == v.truncateToDouble()) return v.toInt();
  return null;
}

class TravelRules extends MgRules<TravelState, TravelAction, Map<String, Object?>> {
  @override
  String get id => 'travel';
  @override
  int get specVersion => 1;

  TravelConfig? _cfg;
  TravelConfig get config => _cfg ?? (throw StateError('travel: init first'));

  TravelState start(TravelConfig c) {
    _cfg = c;
    return const TravelState(unlocked: [], paid: 0, last: noTravelLast);
  }

  @override
  TravelState init(Map<String, Object?> config, int seed) => start(TravelConfig.fromJson(config));

  @override
  List<TravelAction> legalActions(TravelState s) => [
    const TravelAction.load([]),
    for (final st in config.stations)
      if (!s.unlocked.contains(st)) TravelAction.unlock(st),
  ];

  @override
  TravelState apply(TravelState state, TravelAction a) {
    final c = config;
    switch (a.op) {
      case 'load':
        final list = a.unlocked;
        if (list == null) throw IllegalAction(id, a);
        final known = c.stations.toSet(), seen = <String>{};
        return TravelState(
          unlocked: [
            for (final x in list)
              if (known.contains(x) && seen.add(x)) x,
          ],
          paid: state.paid,
          last: noTravelLast,
        );
      case 'unlock':
        final st = a.station;
        if (st == null || !c.stations.contains(st)) throw IllegalAction(id, a);
        return TravelState(
          unlocked: state.unlocked.contains(st) ? [...state.unlocked] : [...state.unlocked, st],
          paid: state.paid,
          last: noTravelLast,
        );
      case 'metro':
        final from = a.from, to = a.to, d = a.distDm, cash = a.cash;
        if (from == null ||
            to == null ||
            d == null ||
            cash == null ||
            !state.unlocked.contains(from) ||
            !state.unlocked.contains(to) ||
            from == to ||
            d < 0 ||
            cash < 0) {
          throw IllegalAction(id, a);
        }
        final fare = metroFare(c, d);
        if (cash < fare) throw IllegalAction(id, a);
        return TravelState(unlocked: [...state.unlocked], paid: state.paid + fare, last: (op: 'metro', amount: fare));
      case 'taxi':
        final d = a.distDm, cash = a.cash;
        if (d == null || cash == null || d < 0 || cash < 0) throw IllegalAction(id, a);
        final fare = taxiFare(c, d);
        if (cash < fare) throw IllegalAction(id, a);
        return TravelState(unlocked: [...state.unlocked], paid: state.paid + fare, last: (op: 'taxi', amount: fare));
      default:
        throw IllegalAction(id, a);
    }
  }

  @override
  TravelAction aiAction(TravelState state, int level, Prng ai) => throw UnsupportedError('travel: no opponent');

  @override
  Map<String, Object?>? result(TravelState state) => null;

  /// Strict JSON: a wrong type (non-integer distance or cash, non-string station), an unknown op
  /// or `by ≠ player` is illegal.
  @override
  TravelAction actionFromJson(Map<String, Object?> j) {
    if (j['by'] != 'player') throw IllegalAction(id, j);
    switch (j['op']) {
      case 'load':
        final u = j['unlocked'];
        if (u is! List || u.any((x) => x is! String)) throw IllegalAction(id, j);
        return TravelAction.load(u.cast<String>());
      case 'unlock':
        final st = j['station'];
        if (st is! String) throw IllegalAction(id, j);
        return TravelAction.unlock(st);
      case 'metro':
        final from = j['from'], to = j['to'], d = _asInt(j['distDm']), cash = _asInt(j['cash']);
        if (from is! String || to is! String || d == null || cash == null) throw IllegalAction(id, j);
        return TravelAction.metro(from, to, d, cash);
      case 'taxi':
        final d = _asInt(j['distDm']), cash = _asInt(j['cash']);
        if (d == null || cash == null) throw IllegalAction(id, j);
        return TravelAction.taxi(d, cash);
      default:
        throw IllegalAction(id, j);
    }
  }

  @override
  Map<String, Object?> stateToJson(TravelState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(Map<String, Object?> r) => r;
}

// ---------- in the world (specs/travel.md P1)

/// A place the player can be moved to: parking point in metres and its heading.
class TravelPoint {
  const TravelPoint({required this.id, required this.name, required this.x, required this.y, required this.heading});
  final String id, name;
  final double x, y, heading;
}

/// A taxi destination: a minigame spot or a hero landmark.
enum TaxiTargetKind { spot, landmark }

class TaxiTarget extends TravelPoint {
  const TaxiTarget({
    required this.kind,
    required super.id,
    required super.name,
    required super.x,
    required super.y,
    required super.heading,
  });
  final TaxiTargetKind kind;
}

/// Stations = spots `kind: subway` in spots.pb order (parking point in metres).
List<TravelPoint> stationsOf(Iterable<Spot> spots) => [
  for (final s in spots)
    if (s.kind == 'subway')
      TravelPoint(id: s.id, name: s.name, x: s.parkX / 10, y: s.parkY / 10, heading: s.parkHeading),
];

/// Taxi spot destinations: spots with a catalog minigame, in spots.pb order.
List<TaxiTarget> taxiSpotTargets(Iterable<Spot> spots, Map<String, MinigameMeta> catalog) => [
  for (final s in spots)
    if (s.minigame.isNotEmpty && catalog.containsKey(s.minigame))
      TaxiTarget(
        kind: TaxiTargetKind.spot,
        id: s.id,
        name: s.name,
        x: s.parkX / 10,
        y: s.parkY / 10,
        heading: s.parkHeading,
      ),
];

/// A choice in the metro card or the taxi app.
class TravelChoice<P extends TravelPoint> {
  const TravelChoice({required this.point, required this.distDm, required this.fare, required this.affordable});
  final P point;
  final int distDm, fare;

  /// False = greyed: the cash does not cover the fare.
  final bool affordable;
}

/// Taxi list: targets with fare from the car, sorted by distance (ties keep the list order).
List<TravelChoice<P>> taxiChoices<P extends TravelPoint>(
  List<P> targets,
  double carX,
  double carY,
  int cash,
  TravelConfig c,
) {
  final out =
      [
        for (var i = 0; i < targets.length; i++)
          for (final d in [travelDistDm(carX, carY, targets[i].x, targets[i].y)])
            for (final fare in [taxiFare(c, d)])
              (i: i, choice: TravelChoice<P>(point: targets[i], distDm: d, fare: fare, affordable: cash >= fare)),
      ]..sort(
        (a, b) => a.choice.distDm != b.choice.distDm ? a.choice.distDm.compareTo(b.choice.distDm) : a.i.compareTo(b.i),
      );
  return [for (final x in out) x.choice];
}

/// True when the car may use a station like "Hrát" at a spot (specs/loop.md): standing, layer 0, in reach.
bool stationInReach(TravelPoint p, double x, double y, double speed, int layer, TuningLoop t) =>
    speed <= t.stopSpeedMps &&
    layer == 0 &&
    (p.x - x) * (p.x - x) + (p.y - y) * (p.y - y) <= t.spotRadiusM * t.spotRadiusM;

/// Fast travel is not offered during a minigame, the Taxi shift or while wanted (spec "Kdy ne").
bool travelOffered({required bool busy, required bool inWorldGame, required int wanted}) =>
    !busy && !inWorldGame && wanted <= 0;

/// The travel module of one session: unlocked stations, fares, cash through the cars state.
class TravelWorld {
  TravelWorld(this.stations, Tuning tuning, {required this.getCash, required this.setCash})
    : config = TravelConfig.fromTuning(tuning.travel, stations.map((s) => s.id)),
      _byId = {for (final s in stations) s.id: s} {
    state = rules.start(config);
  }

  final List<TravelPoint> stations;
  final TravelConfig config;
  final rules = TravelRules();
  late TravelState state;
  final Map<String, TravelPoint> _byId;

  /// The cash of the cars state (specs/travel.md "Hotovost").
  final int Function() getCash;
  final void Function(int) setCash;

  /// Stations from the save (unknown ones drop silently).
  void load(List<String> unlocked) => state = rules.apply(state, TravelAction.load([...unlocked]));

  List<String> get unlocked => state.unlocked;

  bool isUnlocked(String id) => state.unlocked.contains(id);

  TravelPoint? station(String id) => _byId[id];

  /// Unlocks every locked station whose parking point is within [unlockM] of a car on layer 0;
  /// returns the newly unlocked ones (toast, save).
  List<TravelPoint> pass(double x, double y, int layer, double unlockM) {
    if (layer != 0) return const [];
    final out = <TravelPoint>[];
    for (final s in stations) {
      if (isUnlocked(s.id) || (s.x - x) * (s.x - x) + (s.y - y) * (s.y - y) > unlockM * unlockM) continue;
      state = rules.apply(state, TravelAction.unlock(s.id));
      out.add(s);
    }
    return out;
  }

  /// The unlocked station within the "Hrát" reach of the car, or null.
  TravelPoint? stationAt(double x, double y, double speed, int layer, TuningLoop t) {
    for (final id in state.unlocked) {
      final s = _byId[id]!;
      if (stationInReach(s, x, y, speed, layer, t)) return s;
    }
    return null;
  }

  /// Metro card: the other unlocked stations in unlock order with the fare from [from].
  List<TravelChoice<TravelPoint>> metroChoices(String from) {
    final a = _byId[from];
    if (a == null) return const [];
    final cash = getCash();
    return [
      for (final id in state.unlocked)
        if (id != from)
          for (final p in [_byId[id]!])
            for (final d in [travelDistDm(a.x, a.y, p.x, p.y)])
              for (final fare in [metroFare(config, d)])
                TravelChoice(point: p, distDm: d, fare: fare, affordable: cash >= fare),
    ];
  }

  /// True when some station is still locked (the card shows the travelLocked hint).
  bool get anyLocked => state.unlocked.length < stations.length;

  /// Metro ride: pays the fare from the cars-state cash; null when it is not legal (cash, locked).
  int? metro(String from, String to) {
    final a = _byId[from], b = _byId[to];
    if (a == null || b == null) return null;
    return _pay(TravelAction.metro(from, to, travelDistDm(a.x, a.y, b.x, b.y), getCash()));
  }

  /// Taxi ride over [distDm]: pays the fare; null when the cash does not cover it.
  int? taxi(int distDm) => _pay(TravelAction.taxi(distDm, getCash()));

  int? _pay(TravelAction a) {
    try {
      state = rules.apply(state, a);
    } on IllegalAction {
      return null;
    }
    final fare = state.last.amount;
    setCash(a.cash! - fare);
    return fare;
  }
}
