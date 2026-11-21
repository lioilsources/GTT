import 'prng.dart';

/// A minigame rules module (specs/minigames/README.md): the DUALSTACK 5.4 shape plus the JSON
/// bridge that vectors need. States are immutable values; `apply` returns a new one.
abstract class MgRules<S, A, R> {
  String get id;
  int get specVersion;

  S init(Map<String, Object?> config, int seed);
  List<A> legalActions(S state);

  /// Pure; throws [IllegalAction] on an action the state does not allow.
  S apply(S state, A action);

  /// The opponent decides with its own stream [ai] (see [aiPrng]); never the state's rng.
  A aiAction(S state, int level, Prng ai);

  /// Null while the game runs.
  R? result(S state);

  A actionFromJson(Map<String, Object?> json);
  Map<String, Object?> stateToJson(S state);
  Map<String, Object?> resultToJson(R result);
}

/// The opponent's own random stream, one per game.
Prng aiPrng(int seed) => Prng((seed ^ 0x5BD1E995) & 0xFFFFFFFF);

/// Runs [f] on a generator restored from a state's `rng` field; returns the value and the new rng.
({T value, int rng}) withRng<T>(int rng, T Function(Prng r) f) {
  final r = Prng(rng);
  final v = f(r);
  return (value: v, rng: r.state);
}

class IllegalAction implements Exception {
  IllegalAction(this.module, this.action);
  final String module;
  final Object? action;
  @override
  String toString() => '$module: illegal action $action';
}

/// Replays one vector case; AI steps written only as {by: ai, level} are decided by aiAction.
({List<Map<String, Object?>> states, Map<String, Object?>? result}) replayCase<S, A, R>(
  MgRules<S, A, R> rules,
  Map<String, Object?> testCase,
) {
  final seed = testCase['seed'] as int;
  final ai = aiPrng(seed);
  var s = rules.init((testCase['config'] as Map).cast<String, Object?>(), seed);
  final states = <Map<String, Object?>>[];
  for (final step in (testCase['steps'] as List).cast<Map<String, Object?>>()) {
    final a = (step['action'] as Map).cast<String, Object?>();
    final A action = a['by'] == 'ai' && a.keys.every((k) => k == 'by' || k == 'level')
        ? rules.aiAction(s, a['level'] as int, ai)
        : rules.actionFromJson(a);
    s = rules.apply(s, action);
    states.add(rules.stateToJson(s));
  }
  final r = rules.result(s);
  return (states: states, result: r == null ? null : rules.resultToJson(r));
}
