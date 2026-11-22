import 'package:forge2d/forge2d.dart';
import 'package:world_engine/core.dart';

import 'car.dart';
import 'cars_rules.dart';
import 'drive_world.dart';
import 'parked.dart';

/// Hook payloads for later features: police reads `stolen`, dialogues play the owner's quip.
typedef CarEvent = ({String car, double x, double y});

/// The garage's parking point (spot kind `garage`), metres.
typedef GaragePoint = ({String id, double x, double y, double heading});

/// Cars of one session (specs/cars.md): the P0 ownership state, parked cars as dynamic bodies,
/// boarding and the garage. No UI; the HUD asks [candidate] / [atGarage] and calls [board] / [select].
/// Port of web/src/cars/fleet.ts.
class CarFleet {
  CarFleet(this.drive, this.specs, this.tuning, this.garage) {
    state = rules.start(CarsConfig.fromTuning(tuning.cars, {for (final e in specs.entries) e.key: e.value.price}));
    // Traffic drives round parked cars (specs/traffic.md step 8).
    drive.traffic?.parked = parked;
  }

  final DriveWorld drive;
  final Map<String, CarSpec> specs;
  final Tuning tuning;
  final GaragePoint? garage;
  final rules = CarsRules();
  late CarsState state;
  final List<ParkedCar> parked = [];
  final Map<ParkedCar, Body> _bodies = {};

  /// Bumped when the parked set changes.
  int version = 0;

  final List<void Function(CarEvent)> onStolen = [];
  final List<void Function(CarEvent)> onOwnerQuip = [];
  final List<void Function(String car)> onCarChanged = [];

  /// A car bought in the garage (M1-S11: the loop saves).
  final List<void Function(String car, int price)> onBought = [];

  CarSpec get spec => specs[state.driving]!;

  // ---------- parked cars

  void addChunk(ChunkData c) {
    final key = City.chunkKey(c.x, c.y);
    if (parked.any((p) => p.chunk == key)) return;
    final car = drive.car;
    final kept = [
      for (final p in parked)
        if (p.chunk == null) (x: p.x, y: p.y),
    ];
    for (final p in generateParked(drive.city.graph, c.x, c.y, key, tuning, specs, kept, (x: car.x, y: car.y))) {
      _add(p);
    }
  }

  void removeChunk(ChunkData c) {
    final key = City.chunkKey(c.x, c.y);
    for (final p in parked.where((q) => q.chunk == key).toList()) {
      _remove(p);
    }
  }

  /// Forgets cars the player left behind once they are far away (cars.parked.forget_m).
  void update() {
    // Pushed cars: copy the pose of awake bodies back (specs/cars.md).
    for (final MapEntry(key: p, value: b) in _bodies.entries) {
      if (!b.isAwake) continue;
      final q = b.position, a = b.angle;
      if ((q.x - p.x).abs() + (q.y - p.y).abs() + (a - p.heading).abs() < 1e-3) continue;
      p
        ..x = q.x
        ..y = q.y
        ..heading = a;
      version++;
    }
    final c = drive.car, f = tuning.cars.parked.forgetM;
    for (final p in parked.toList()) {
      if (p.chunk == null && (p.x - c.x) * (p.x - c.x) + (p.y - c.y) * (p.y - c.y) > f * f) _remove(p);
    }
  }

  void _add(ParkedCar p) {
    final s = specs[p.carId];
    if (s == null) return;
    final d = tuning.drive, t = tuning.cars.parked;
    final hl = s.lengthM * tuning.carScale / 2, hw = s.widthM * tuning.carScale / 2;
    p
      ..hl = hl
      ..hw = hw;
    final body = drive.world.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: Vector2(p.x, p.y),
        rotation: Rot.fromAngle(p.heading),
        linearDamping: t.linearDamping,
        angularDamping: t.angularDamping,
      ),
    );
    body.createShape(
      Polygon.box(hl, hw),
      ShapeDef(
        density: s.mass * t.massFactor / (4 * hl * hw),
        filter: Filter(categoryBits: catParked, maskBits: catCar | catBuildings | catParked | catTraffic | catTram),
        material: SurfaceMaterial(friction: d.carFriction, restitution: d.carRestitution),
      ),
    );
    _bodies[p] = body;
    parked.add(p);
    version++;
  }

  void _remove(ParkedCar p) {
    if (!parked.remove(p)) return;
    _bodies.remove(p)?.destroy();
    version++;
  }

  // ---------- boarding

  bool _stopped(double limit) => drive.car.layer == 0 && drive.car.speed <= limit;

  /// The parked car the player can switch to now, or null.
  ParkedCar? candidate() {
    final t = tuning.cars;
    if (!_stopped(t.boardSpeedMps)) return null;
    return boardCandidate(parked, drive.car.x, drive.car.y, t.boardDistanceM);
  }

  ParkedCar? _seen;
  double _boardAge = double.infinity;
  double _garageAge = double.infinity;

  /// The parked car the context button boards now (set by [action]).
  ParkedCar? get boardTarget => _seen;

  /// The context button with hysteresis (cars.action_hold_s, specs/cars.md): call once per HUD
  /// tick with the time since the last call. Returns 'board', 'garage' or null; board wins.
  String? action(double dt) {
    final t = tuning.cars, c = drive.car;
    final now = candidate();
    if (now != null) {
      _seen = now;
      _boardAge = 0;
    } else {
      _boardAge += dt;
    }
    _garageAge = atGarage() ? 0 : _garageAge + dt;
    final s = _seen;
    double d2(double x, double y) => (x - c.x) * (x - c.x) + (y - c.y) * (y - c.y);
    if (s != null &&
        _boardAge <= t.actionHoldS &&
        c.layer == 0 &&
        parked.contains(s) &&
        d2(s.x, s.y) <= t.boardDistanceM * t.boardDistanceM) {
      return 'board';
    }
    final g = garage;
    if (g != null && _garageAge <= t.actionHoldS && c.layer == 0 && d2(g.x, g.y) <= t.garageRadiusM * t.garageRadiusM) {
      return 'garage';
    }
    if (_boardAge > t.actionHoldS) _seen = null;
    return null;
  }

  String get _currentOwner => state.owned.contains(state.driving) && !state.stolen ? 'player' : 'npc';

  /// "Přesednout": the current car stays parked, the player drives the parked one.
  void board(ParkedCar p) {
    final c = drive.car;
    final left = ParkedCar(carId: state.driving, owner: _currentOwner, x: c.x, y: c.y, heading: c.heading);
    state = rules.apply(state, CarsAction.board(p.carId, p.owner));
    _remove(p);
    drive.replaceCar(spec, p.x, p.y, p.heading);
    _add(left);
    if (p.owner == 'npc') {
      final e = (car: p.carId, x: p.x, y: p.y);
      for (final f in onStolen) {
        f(e);
      }
      for (final f in onOwnerQuip) {
        f(e);
      }
    }
    for (final f in onCarChanged) {
      f(p.carId);
    }
  }

  // ---------- garage

  bool atGarage() {
    final g = garage;
    if (g == null || !_stopped(tuning.cars.garageSpeedMps)) return false;
    final c = drive.car, r = tuning.cars.garageRadiusM;
    return (c.x - g.x) * (c.x - g.x) + (c.y - g.y) * (c.y - g.y) <= r * r;
  }

  /// Owned cars in the garage list, in the order they were acquired.
  List<String> get owned => state.owned;

  bool canSelect(String car) => rules.legalActions(state).contains(CarsAction.select(car));

  /// Cars for sale (M1-S11 shows them once there is cash).
  List<String> buyable() => rules.buyable(state);

  void buy(String car) {
    final before = state.cash;
    state = rules.apply(state, CarsAction.buy(car));
    for (final f in onBought) {
      f(car, before - state.cash);
    }
  }

  /// Cash lives in the cars state (specs/economy.md); the economy writes it back here.
  void setCash(int cash) => state = state.copyWith(cash: cash < 0 ? 0 : cash);

  /// Loads a saved ownership state (specs/save.md); swaps the driven body when the car differs.
  void restore({required int cash, required List<String> owned, required String driving}) {
    final own = owned.where(specs.containsKey).toList();
    if (own.isEmpty) return;
    final car = own.contains(driving) ? driving : own.first;
    state = rules.start(
      CarsConfig(
        prices: {for (final e in specs.entries) e.key: e.value.price},
        cash: cash < 0 ? 0 : cash,
        owned: List.unmodifiable(own),
        driving: car,
      ),
    );
    if (drive.spec.id != car) {
      final c = drive.car;
      drive.replaceCar(spec, c.x, c.y, c.heading);
      for (final f in onCarChanged) {
        f(car);
      }
    }
  }

  /// Drive out of the garage with an owned car; the current one stays inside (or is towed away).
  void select(String car) {
    final g = garage;
    if (g == null) return;
    state = rules.apply(state, CarsAction.select(car));
    for (final p in parked.where((q) => q.chunk == null && q.owner == 'player' && q.carId == car).toList()) {
      _remove(p);
    }
    drive.replaceCar(spec, g.x, g.y, g.heading);
    for (final f in onCarChanged) {
      f(car);
    }
  }
}
