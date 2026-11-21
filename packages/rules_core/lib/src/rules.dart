import 'prng.dart';

/// The shape every P0 rules module has in both clients (DUALSTACK 5.4).
/// States and actions hold only ints, strings, bools, lists and maps.
abstract interface class RulesModule<S, A, R> {
  String get id;
  int get specVersion;
  S init(Map<String, Object?> config, int seed);
  List<A> legalActions(S state);

  /// Pure: returns a new state.
  S apply(S state, A action);

  /// AI budget is depth or iterations, never time; ties go to the first legal action.
  A aiAction(S state, int level, Prng rng);

  /// Null while the game runs.
  R? result(S state);
}
