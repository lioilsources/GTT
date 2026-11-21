import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// One play session of NPC dialogue (specs/dialogue.md): the rules state (vibe, contacts, recent
/// skits) plus the content to show. Pure Dart. Other features call [startSkit] and show
/// `DialogueView` on top.
class DialogueSession {
  DialogueSession(this.pack, this.tuning, String city, int seed) : rules = DialogueRules() {
    state = rules.initWith(DialogueConfig.fromPack(pack, tuning, city), seed);
    for (final c in pack.characters) {
      _chars[c.id] = c;
    }
    for (final s in pack.skits) {
      _skits[s.id] = s;
    }
  }

  final NpcPack pack;
  final TuningNpc tuning;
  final DialogueRules rules;
  late DialogueState state;
  final Map<String, NpcCharacter> _chars = {};
  final Map<String, NpcSkit> _skits = {};

  NpcCharacter? character(String id) => _chars[id];

  bool canStart(String characterId, String context) =>
      state.skit.isEmpty && rules.candidates(characterId, context).isNotEmpty;

  /// Picks and starts a skit; false when none fits (or one is running).
  bool startSkit(String characterId, String context) {
    if (!canStart(characterId, context)) return false;
    state = rules.apply(state, DialogueAction.start(characterId, context));
    return true;
  }

  bool get running => state.skit.isNotEmpty;

  /// The skit running now, or the one that just ended.
  NpcSkit? get skit => _skits[running ? state.skit : state.last];

  /// The beat waiting for a reply (null when the skit is over).
  NpcBeat? get beat => running ? skit?.beats[state.beat] : null;

  void reply(String tone) => state = rules.apply(state, DialogueAction.reply(tone));

  void leave() {
    if (running) state = rules.apply(state, const DialogueAction.leave());
  }

  DialogueResult? result() => rules.result(state);

  int vibe(String characterId) => state.vibe[characterId] ?? 0;

  /// The quip of [characterId] for the player's outcome ('player', 'ai', 'draw').
  String? quip(String characterId, String winner, int seed, String locale) {
    final c = _chars[characterId];
    return c == null ? null : quipOf(c, winner, seed, locale);
  }
}

String quipOf(NpcCharacter c, String winner, int seed, String locale) {
  final list = switch (quipOutcome(winner)) {
    'win' => c.quips.win,
    'lose' => c.quips.lose,
    _ => c.quips.draw,
  };
  return npcText(list[quipIndex(list.length, seed)], locale);
}

/// Up to two initials for the placeholder portrait.
String initials(String name) {
  final words = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final all = words.map((w) => w[0].toUpperCase()).join();
  return all.length > 2 ? all.substring(0, 2) : all;
}

/// Text helpers for tone texts by tone name.
NpcText toneText(NpcToneTexts t, String tone) => switch (tone) {
  'flirt' => t.flirt,
  'joke' => t.joke,
  _ => t.dry,
};
