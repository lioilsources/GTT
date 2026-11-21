import 'package:flutter/widgets.dart';
import 'package:shared_gen/shared_gen.dart';

/// What a minigame needs from the app besides the contract context.
class MinigameEnv {
  const MinigameEnv({required this.tuning, required this.locale, this.opponent});

  final Tuning tuning;

  /// The NPC opponent (MinigameContext.opponentId) resolved by the launcher; its line shows on
  /// the result screen (specs/dialogue.md "Hláška soupeře").
  final MinigameOpponent? opponent;

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

/// An NPC opponent as the shell needs it; built by `npc_dialogue` from the character content.
class MinigameOpponent {
  const MinigameOpponent({required this.id, required this.name, required this.portrait, required this.line});

  final String id;
  final String name;

  /// Index into [Tokens.colorNpcPortraits] (placeholder portrait).
  final int portrait;

  /// The quip for the player's outcome ('player', 'ai', 'draw'), in the env locale.
  final String Function(String winner) line;
}
