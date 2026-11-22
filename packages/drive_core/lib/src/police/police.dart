import 'dart:math' as math;

import 'package:world_engine/core.dart';

import '../drive_world.dart';
import '../fleet.dart';
import '../traffic/traffic.dart';
import 'roadblock.dart';
import 'rules.dart';
import 'sense.dart';

/// `wantedChanged`: [reason] is an offence kind, "escape" or "busted".
typedef WantedChange = ({int level, int prev, String reason});

/// Police of one session (specs/police.md): the P0 wanted rules driven at `police.tick_hz`, patrol
/// cars flagged among the traffic, line of sight, sidewalk and hit-and-run detection, pursuit and
/// capture. No UI; the HUD listens to the hooks. Port of web/src/police/police.ts.
class Police {
  Police(this.drive, this.tuning, [CarFleet? fleet]) {
    state = rules.start(PoliceConfig.fromTuning(tuning.police));
    if (!tuning.police.enabled) return;
    final tr = drive.traffic;
    if (tr != null) {
      _unsub.add(
        tr.onHit((_, _) {
          _crashX = drive.car.x;
          _crashY = drive.car.y;
          offence('crash');
        }),
      );
    }
    if (fleet != null) {
      void stolen(CarEvent _) => offence('theft');
      fleet.onStolen.add(stolen);
      _unsub.add(() => fleet.onStolen.remove(stolen));
    }
  }

  final DriveWorld drive;
  final Tuning tuning;
  final rules = PoliceRules();
  late PoliceState state;

  /// True while some patrol sees the player (refreshed every tick).
  bool seen = false;

  /// Hooks for later features (specs/police.md "Události").
  final List<void Function(WantedChange)> onWantedChanged = [];
  final List<void Function(String kind)> onOffence = [];
  final List<void Function(int amount)> onFined = [];

  /// `roadblock {x, y}`: a roadblock was put up there (specs/roadblock.md "HUD"); the HUD shows
  /// `policeRoadblock`.
  final List<void Function(double x, double y)> onRoadblock = [];

  /// The two standing patrols of the current roadblock; empty when none stands.
  List<TrafficCar> get roadblock => List.unmodifiable(_block);

  /// Where the current roadblock stands (meaningful only while [roadblock] is not empty).
  double get roadblockX => _blockX;
  double get roadblockY => _blockY;

  final Map<int, List<BuildingData>> _buildings = {};
  final Expando<double> _uturnAt = Expando();
  final List<void Function()> _unsub = [];
  double _acc = 0;
  double _time = 0;
  double _pickTimer = 0;
  double _sidewalkT = 0;
  bool _sidewalkArmed = true;
  double _crashX = 0;
  double _crashY = 0;

  // Roadblock (specs/roadblock.md): its cars and point, age, cooldown left, time since the last try.
  final List<TrafficCar> _block = [];
  double _blockX = 0;
  double _blockY = 0;
  double _blockAge = 0;
  double _blockCool = 0;
  double _blockTry = double.infinity;

  int get wantedLevel => state.level;
  bool get enabled => tuning.police.enabled;

  void dispose() {
    for (final u in _unsub) {
      u();
    }
    _unsub.clear();
  }

  // ---------- buildings for the line of sight

  void addChunk(ChunkData c) => _buildings[City.chunkKey(c.x, c.y)] = c.buildings;
  void removeChunk(ChunkData c) => _buildings.remove(City.chunkKey(c.x, c.y));

  Iterable<BuildingData> _buildingsAlong(double ax, double ay, double bx, double by) sync* {
    final cm = drive.city.chunkM;
    // One chunk of slack: a building belongs to one chunk but may reach into the next.
    final x0 = (math.min(ax, bx) / cm).floor() - 1, x1 = (math.max(ax, bx) / cm).floor() + 1;
    final y0 = (math.min(ay, by) / cm).floor() - 1, y1 = (math.max(ay, by) / cm).floor() + 1;
    for (var cx = x0; cx <= x1; cx++) {
      for (var cy = y0; cy <= y1; cy++) {
        final list = _buildings[City.chunkKey(cx, cy)];
        if (list != null) yield* list;
      }
    }
  }

  /// Patrol [p] sees the player (specs/police.md "Dohled").
  bool sees(TrafficCar p) {
    final c = drive.car;
    if (!inView(p.x, p.y, p.layer, c.x, c.y, c.layer, tuning.police.viewM)) return false;
    return !sightBlocked(p.x, p.y, c.x, c.y, _buildingsAlong(p.x, p.y, c.x, c.y));
  }

  bool _anySees() {
    final tr = drive.traffic;
    if (tr == null) return false;
    for (final p in tr.cars) {
      if (p.police && sees(p)) return true;
    }
    return false;
  }

  // ---------- rules

  void _act(PoliceAction a) {
    final prev = state;
    final s = state = rules.apply(prev, a);
    if (s.offences > prev.offences) {
      for (final f in onOffence) {
        f(s.last);
      }
    }
    if (s.busted > prev.busted) {
      for (final f in onFined) {
        f(s.fined - prev.fined);
      }
    }
    if (s.level != prev.level) {
      final reason = s.busted > prev.busted
          ? 'busted'
          : s.level > prev.level
          ? s.last
          : 'escape';
      for (final f in onWantedChanged) {
        f((level: s.level, prev: prev.level, reason: reason));
      }
    }
  }

  /// An offence happened now; a patrol has to see it to count.
  void offence(String kind) {
    if (!enabled) return;
    _act(PoliceAction.offence(kind, seen: _anySees()));
  }

  /// Per frame with the (scaled) driving dt; runs whole ticks at `police.tick_hz`.
  void update(double dt) {
    if (!enabled || drive.traffic == null) return;
    final step = 1 / tuning.police.tickHz;
    _acc = math.min(_acc + dt, step * 10);
    while (_acc >= step) {
      _acc -= step;
      _tick(step);
    }
  }

  void _tick(double step) {
    final t = tuning.police, c = drive.car;
    _time += step;
    _roadblocks(step);
    _patrols(step);
    seen = _anySees();

    // Sidewalk: on the band for sidewalk_s in one go → one offence, re-armed after leaving it.
    final walk =
        c.layer == 0 &&
        c.speed >= t.sidewalkMinMps &&
        onSidewalk(drive.city.graph.near(c.x, c.y, tuning.layers.searchM), tuning);
    if (walk) {
      _sidewalkT += step;
      if (_sidewalkArmed && _sidewalkT >= t.sidewalkS) {
        _sidewalkArmed = false;
        _act(PoliceAction.offence('sidewalk', seen: seen));
      }
    } else {
      _sidewalkT = 0;
      _sidewalkArmed = true;
    }

    final dx = c.x - _crashX, dy = c.y - _crashY;
    final away = dx * dx + dy * dy > t.hitRunM * t.hitRunM;
    _act(PoliceAction.tick(seen: seen, near: _near(), away: away));
  }

  /// A patrol is within capture_m of the slow player (same layer), while wanted.
  bool _near() {
    final t = tuning.police, c = drive.car;
    if (state.level == 0 || c.speed > t.captureMps) return false;
    for (final p in drive.traffic!.cars) {
      final dx = p.x - c.x, dy = p.y - c.y;
      if (p.police && p.layer == c.layer && dx * dx + dy * dy <= t.captureM * t.captureM) return true;
    }
    return false;
  }

  // ---------- patrols

  void _patrols(double step) {
    final t = tuning.police, tr = drive.traffic!, c = drive.car;
    final level = state.level;
    final want = t.patrols.isEmpty ? 0 : t.patrols[math.min(level, t.patrols.length - 1)];
    var n = 0;
    for (final p in tr.cars) {
      // Roadblock patrols stand: they neither count towards patrols[level] nor chase.
      if (!p.police || p.blocking) continue;
      n++;
      final dx = c.x - p.x, dy = c.y - p.y;
      final d2 = dx * dx + dy * dy;
      p.pursuing = level > 0 && d2 <= t.pursuitM * t.pursuitM;
      if (!p.pursuing) continue;
      p
        ..goalX = c.x
        ..goalY = c.y
        ..pursuitMps = t.pursuitMps.isEmpty ? 0 : t.pursuitMps[math.min(level, t.pursuitMps.length - 1)]
        ..goalStopM = t.captureM / 2;
      // Goal behind and far enough: turn around on the edge, at most once per uturn_s.
      final behind = math.cos(p.heading) * dx + math.sin(p.heading) * dy < 0;
      if (behind && d2 > t.uturnM * t.uturnM && _time - (_uturnAt[p] ?? double.negativeInfinity) >= t.uturnS) {
        _uturnAt[p] = _time;
        tr.turnAround(p);
      }
    }
    _pickTimer += step;
    if (n >= want || _pickTimer < t.pickIntervalS) return;
    _pickTimer = 0;
    final min2 = t.pickMinM * t.pickMinM;
    for (final p in tr.cars) {
      final dx = p.x - c.x, dy = p.y - c.y;
      if (p.police || dx * dx + dy * dy < min2) continue;
      p.police = true;
      return;
    }
  }

  // ---------- roadblock (specs/roadblock.md)

  /// Removes the roadblock (if any) and starts its cooldown. The client calls it on a player
  /// respawn (not on a car swap); a traffic reset is noticed by the police itself.
  void clearRoadblock() {
    if (_block.isEmpty) return;
    final tr = drive.traffic;
    for (final c in _block) {
      tr?.removeCar(c);
    }
    _block.clear();
    _blockCool = tuning.police.roadblock.cooldownS;
  }

  void _roadblocks(double step) {
    final rb = tuning.police.roadblock, tr = drive.traffic!, c = drive.car;
    final level = state.level;
    _blockCool = math.max(0, _blockCool - step);
    _blockTry += step;
    if (_block.isNotEmpty) {
      _blockAge += step;
      final dx = c.x - _blockX, dy = c.y - _blockY;
      final gone = _block.any((b) => !tr.cars.contains(b));
      if (gone || dx * dx + dy * dy > rb.clearM * rb.clearM || level < rb.level || _blockAge > rb.ttlS) {
        clearRoadblock();
      }
      return;
    }
    if (level < rb.level || _blockCool > 0 || _blockTry < tuning.police.pickIntervalS) return;
    _blockTry = 0;
    _tryRoadblock();
  }

  void _tryRoadblock() {
    final rb = tuning.police.roadblock, tr = drive.traffic!, c = drive.car;
    final spot = roadblockSpot(
      drive.city.graph,
      c.x,
      c.y,
      c.heading,
      c.layer,
      tuning.layers.searchM,
      rb.aheadM,
      rb.probeM,
    );
    // A spot in a pedestrian zone gives up too.
    if (spot == null || drive.zones.contains(spot.x, spot.y)) return;
    final half = drive.city.graph.edges[spot.edge].length / 2;
    // The pose is set below; addCar refuses a one-way edge against its direction, so try both.
    TrafficCar? add() => tr.addCar(spot.edge, 1, half, 0) ?? tr.addCar(spot.edge, -1, half, 0);
    final a = add();
    if (a == null) return;
    final b = add();
    if (b == null) {
      tr.removeCar(a);
      return;
    }
    // Normal of the edge (left of from → to) and the heading across the road.
    final nx = -spot.uy, ny = spot.ux;
    final h = math.atan2(spot.uy, spot.ux) + math.pi / 2;
    final l = rb.lateralM;
    for (final (car, side) in [(a, 1.0), (b, -1.0)]) {
      car
        ..police = true
        ..blocking = true
        ..pursuing = false;
      tr.setPose(car, spot.x + nx * l * side, spot.y + ny * l * side, h);
    }
    _block
      ..add(a)
      ..add(b);
    _blockX = spot.x;
    _blockY = spot.y;
    _blockAge = 0;
    for (final f in onRoadblock) {
      f(spot.x, spot.y);
    }
  }
}
