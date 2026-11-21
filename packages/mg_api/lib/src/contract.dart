import 'package:flutter/widgets.dart';
import 'package:shared_gen/shared_gen.dart';

/// What a minigame needs from the app besides the contract context.
class MinigameEnv {
  const MinigameEnv({required this.tuning, required this.locale});

  final Tuning tuning;

  /// Language code ('cs', 'en'); texts come from the shared message table.
  final String locale;

  String t(MessageKey key, [Map<String, Object> args = const {}]) => tr(locale, key, args);
}

/// A minigame: its catalog metadata and a widget that plays one game and reports the result.
abstract class Minigame {
  MinigameMeta get meta;

  /// [onFinish] is called once: after the result screen (Back) or on give-up.
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish);
}

/// The fields every rules result carries (specs/minigames/README.md "Výsledek").
class RulesOutcome {
  const RulesOutcome({required this.winner, required this.stars, required this.score});

  /// 'player', 'ai' or 'draw'.
  final String winner;
  final int stars;
  final int score;
}
