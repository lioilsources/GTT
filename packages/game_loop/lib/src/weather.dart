// Weather: clear, rain, fog (specs/weather.md, version 1): the P0 rules (module `weather`) and the
// pure world helpers (the 1 s game clock, the rain grip, the visual blend, the fog ramp).
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// Kinds in the fixed order of the spec (`weights`, `legalActions`).
enum WeatherKind { clear, rain, fog }

WeatherKind? weatherKindOf(Object? name) => switch (name) {
  'clear' => WeatherKind.clear,
  'rain' => WeatherKind.rain,
  'fog' => WeatherKind.fog,
  _ => null,
};

class WeatherConfig {
  const WeatherConfig({required this.weights, required this.minS, required this.maxS});

  factory WeatherConfig.fromTuning(TuningWeather t) =>
      WeatherConfig(weights: List.unmodifiable([t.weightClear, t.weightRain, t.weightFog]), minS: t.minS, maxS: t.maxS);

  factory WeatherConfig.fromJson(Map<String, Object?> j) => WeatherConfig(
    weights: List.unmodifiable((j['weights'] as List).cast<int>()),
    minS: j['minS'] as int,
    maxS: j['maxS'] as int,
  );

  /// Integer weights ≥ 0 of `clear`, `rain`, `fog`.
  final List<int> weights;
  final int minS, maxS;
}

class WeatherState {
  const WeatherState({required this.kind, required this.left, required this.changes, required this.rng});

  final WeatherKind kind;

  /// Seconds to the next change; [changes] = changes since init (tick and set).
  final int left, changes, rng;

  Map<String, Object?> toJson() => {'kind': kind.name, 'left': left, 'changes': changes, 'rng': rng};
}

/// `op` is tick or set ([kind]).
class WeatherAction {
  const WeatherAction.tick() : op = 'tick', kind = null;
  const WeatherAction.set(WeatherKind this.kind) : op = 'set';

  final String op;
  final WeatherKind? kind;

  Map<String, Object?> toJson() => {'by': 'player', 'op': op, if (kind != null) 'kind': kind!.name};

  @override
  bool operator ==(Object other) => other is WeatherAction && other.op == op && other.kind == kind;
  @override
  int get hashCode => Object.hash(op, kind);
  @override
  String toString() => toJson().toString();
}

class WeatherRules extends MgRules<WeatherState, WeatherAction, Map<String, Object?>> {
  @override
  String get id => 'weather';
  @override
  int get specVersion => 1;

  WeatherConfig? _cfg;
  WeatherConfig get config => _cfg ?? (throw StateError('weather: init first'));

  /// gap() = minS + rng.nextInt(maxS − minS + 1).
  int _gap(Prng r) => config.minS + r.nextInt(config.maxS - config.minS + 1);

  WeatherState start(WeatherConfig c, int seed) {
    _cfg = c;
    final r = Prng(seed);
    final left = _gap(r);
    return WeatherState(kind: WeatherKind.clear, left: left, changes: 0, rng: r.state);
  }

  @override
  WeatherState init(Map<String, Object?> config, int seed) => start(WeatherConfig.fromJson(config), seed);

  @override
  List<WeatherAction> legalActions(WeatherState s) => [
    const WeatherAction.tick(),
    for (final k in WeatherKind.values) WeatherAction.set(k),
  ];

  @override
  WeatherState apply(WeatherState s, WeatherAction a) {
    final w = config.weights;
    final r = Prng(s.rng);
    switch (a.op) {
      case 'tick':
        final left = s.left - 1;
        if (left > 0) return WeatherState(kind: s.kind, left: left, changes: s.changes, rng: s.rng);
        var kind = s.kind;
        var total = 0;
        for (final k in WeatherKind.values) {
          if (k != s.kind) total += w[k.index];
        }
        if (total > 0) {
          var x = r.nextInt(total);
          for (final k in WeatherKind.values) {
            if (k == s.kind) continue;
            if (x < w[k.index]) {
              kind = k;
              break;
            }
            x -= w[k.index];
          }
        }
        final gap = _gap(r);
        return WeatherState(kind: kind, left: gap, changes: s.changes + 1, rng: r.state);
      case 'set':
        final k = a.kind;
        if (k == null) throw IllegalAction(id, a);
        final gap = _gap(r);
        return WeatherState(kind: k, left: gap, changes: s.changes + 1, rng: r.state);
      default:
        throw IllegalAction(id, a);
    }
  }

  @override
  WeatherAction aiAction(WeatherState state, int level, Prng ai) => throw UnsupportedError('weather: no opponent');

  @override
  Map<String, Object?>? result(WeatherState state) => null;

  /// Strict JSON: an unknown op or kind, or `by ≠ player`, is illegal.
  @override
  WeatherAction actionFromJson(Map<String, Object?> j) {
    if (j['by'] != 'player') throw IllegalAction(id, j);
    switch (j['op']) {
      case 'tick':
        return const WeatherAction.tick();
      case 'set':
        final k = weatherKindOf(j['kind']);
        if (k == null) throw IllegalAction(id, j);
        return WeatherAction.set(k);
      default:
        throw IllegalAction(id, j);
    }
  }

  @override
  Map<String, Object?> stateToJson(WeatherState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(Map<String, Object?> r) => r;
}

// ---------- in the world (specs/weather.md P1)

/// Whether the module runs in [cityId]: `weather.enabled` and `weather.cities.<city>`.
bool weatherOn(TuningWeather t, String cityId) => t.enabled && t.cities.toJson()[cityId] == true;

/// Grip multiplier of the player's car: `rain_grip` in rain, 1 otherwise (fog keeps the grip).
double weatherGrip(WeatherKind kind, TuningWeather t) => kind == WeatherKind.rain ? t.rainGrip : 1.0;

/// Fog opacity at [d] = distance from the screen centre ÷ half the diagonal: `fog_center_alpha`
/// in the middle, `fog_edge_alpha` at d = 1, smoothstep from `fog_inner` to 1 in between.
double fogAlpha(double d, TuningWeather t) {
  final span = 1 - t.fogInner;
  final x = span <= 0 ? (d >= 1 ? 1.0 : 0.0) : ((d - t.fogInner) / span).clamp(0.0, 1.0);
  final s = x * x * (3 - 2 * x);
  return t.fogCenterAlpha + (t.fogEdgeAlpha - t.fogCenterAlpha) * s;
}

/// Visual amount of each kind (0..1, they sum to 1): on a change the old kind fades out and the new
/// one in, linearly over `blend_s` seconds and at the same time; a change mid-blend starts from
/// the current mix.
class WeatherMix {
  WeatherMix([WeatherKind kind = WeatherKind.clear]) {
    snap(kind);
  }

  final List<double> _a = List.filled(WeatherKind.values.length, 0);

  double of(WeatherKind k) => _a[k.index];
  double get rain => _a[WeatherKind.rain.index];
  double get fog => _a[WeatherKind.fog.index];

  /// True while the amounts are still moving towards [target].
  bool blending(WeatherKind target) => _a[target.index] < 1;

  void snap(WeatherKind kind) {
    for (var i = 0; i < _a.length; i++) {
      _a[i] = i == kind.index ? 1 : 0;
    }
  }

  /// Moves every amount towards [target] by dt / blendS (blendS ≤ 0 = at once).
  void step(WeatherKind target, double dt, double blendS) {
    if (blendS <= 0) return snap(target);
    final d = dt / blendS;
    for (var i = 0; i < _a.length; i++) {
      _a[i] = i == target.index ? (_a[i] + d).clamp(0.0, 1.0) : (_a[i] - d).clamp(0.0, 1.0);
    }
  }
}

/// The weather of one session: state, the game clock, the blend and change events. Nothing is saved.
class WeatherWorld {
  WeatherWorld(this.tuning, int seed) {
    state = rules.start(WeatherConfig.fromTuning(tuning), seed);
  }

  final TuningWeather tuning;
  final rules = WeatherRules();
  late WeatherState state;
  final mix = WeatherMix();

  /// Game seconds not yet ticked.
  double _acc = 0;

  /// Called when the kind changes (by a tick or [set]).
  final List<void Function(WeatherKind kind)> onChange = [];

  WeatherKind get kind => state.kind;

  /// Grip multiplier of the player's car now (switches at once on a change).
  double get grip => weatherGrip(kind, tuning);

  /// Advances the game clock by [stepDt] (0 while paused): one tick per whole second, and the blend.
  void update(double stepDt) {
    final dt = stepDt > 0 ? stepDt : 0.0;
    _acc += dt;
    while (_acc >= 1) {
      _acc -= 1;
      _apply(const WeatherAction.tick());
    }
    mix.step(kind, dt, tuning.blendS);
  }

  /// Debug and tests: the `set` action.
  void set(WeatherKind k) => _apply(WeatherAction.set(k));

  /// Debug panel: the next kind in the order clear, rain, fog.
  void cycle() => set(WeatherKind.values[(kind.index + 1) % WeatherKind.values.length]);

  void _apply(WeatherAction a) {
    final was = state.kind;
    state = rules.apply(state, a);
    if (state.kind != was) {
      for (final f in [...onChange]) {
        f(state.kind);
      }
    }
  }
}
