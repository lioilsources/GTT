import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/dialogue.md, version 1. Pure Dart: no Flutter imports here (guarded by a test).

const tones = ['flirt', 'joke', 'dry'];

/// Fixed context order (spec "Obsah").
const npcContexts = ['street', 'bar', 'shop', 'minigame_win', 'minigame_lose', 'crash', 'car_owner'];

class DialogueCharacterCfg {
  const DialogueCharacterCfg(this.id, this.tones);
  final String id;

  /// Vibe change per tone ('flirt', 'joke', 'dry').
  final Map<String, int> tones;
}

class DialogueSkitCfg {
  const DialogueSkitCfg(this.id, this.character, this.context, this.city, this.beats);
  final String id, character, context, city;
  final int beats;
}

class DialogueConfig {
  const DialogueConfig({
    required this.city,
    required this.recentK,
    required this.vibeMax,
    required this.vibeStart,
    required this.contactMinVibe,
    required this.contactBasePct,
    required this.contactStepPct,
    required this.contactMaxPct,
    required this.characters,
    required this.skits,
  });

  /// Runtime config: numbers from tuning `npc.*`, pool from the merged content (skits sorted by id).
  factory DialogueConfig.fromPack(NpcPack pack, TuningNpc t, String city) {
    final skits = [...pack.skits]..sort((a, b) => a.id.compareTo(b.id));
    return DialogueConfig(
      city: city,
      recentK: t.recentK,
      vibeMax: t.vibeMax,
      vibeStart: t.vibeStart,
      contactMinVibe: t.contactMinVibe,
      contactBasePct: t.contactBasePct,
      contactStepPct: t.contactStepPct,
      contactMaxPct: t.contactMaxPct,
      characters: [
        for (final c in pack.characters)
          DialogueCharacterCfg(c.id, {'flirt': c.tones.flirt, 'joke': c.tones.joke, 'dry': c.tones.dry}),
      ],
      skits: [for (final s in skits) DialogueSkitCfg(s.id, s.character, s.context, s.city ?? '', s.beats.length)],
    );
  }

  factory DialogueConfig.fromJson(Map<String, Object?> j) => DialogueConfig(
    city: j['city'] as String,
    recentK: j['recentK'] as int,
    vibeMax: j['vibeMax'] as int,
    vibeStart: j['vibeStart'] as int,
    contactMinVibe: j['contactMinVibe'] as int,
    contactBasePct: j['contactBasePct'] as int,
    contactStepPct: j['contactStepPct'] as int,
    contactMaxPct: j['contactMaxPct'] as int,
    characters: [
      for (final c in (j['characters'] as List).cast<Map<String, Object?>>())
        DialogueCharacterCfg(c['id'] as String, (c['tones'] as Map).cast<String, int>()),
    ],
    skits: [
      for (final s in (j['skits'] as List).cast<Map<String, Object?>>())
        DialogueSkitCfg(
          s['id'] as String,
          s['character'] as String,
          s['context'] as String,
          s['city'] as String,
          s['beats'] as int,
        ),
    ],
  );

  final String city;
  final int recentK, vibeMax, vibeStart, contactMinVibe, contactBasePct, contactStepPct, contactMaxPct;
  final List<DialogueCharacterCfg> characters;
  final List<DialogueSkitCfg> skits;
}

class DialogueState {
  const DialogueState({
    required this.rng,
    required this.recent,
    required this.vibe,
    required this.contacts,
    required this.skit,
    required this.character,
    required this.beat,
    required this.tones,
    required this.gained,
    required this.last,
    required this.completed,
    required this.newContact,
  });

  final int rng;
  final List<String> recent;
  final Map<String, int> vibe;
  final List<String> contacts;
  final String skit, character;
  final int beat;
  final List<String> tones;
  final int gained;
  final String last;
  final bool completed, newContact;

  DialogueState copyWith({
    int? rng,
    List<String>? recent,
    Map<String, int>? vibe,
    List<String>? contacts,
    String? skit,
    String? character,
    int? beat,
    List<String>? tones,
    int? gained,
    String? last,
    bool? completed,
    bool? newContact,
  }) => DialogueState(
    rng: rng ?? this.rng,
    recent: recent ?? this.recent,
    vibe: vibe ?? this.vibe,
    contacts: contacts ?? this.contacts,
    skit: skit ?? this.skit,
    character: character ?? this.character,
    beat: beat ?? this.beat,
    tones: tones ?? this.tones,
    gained: gained ?? this.gained,
    last: last ?? this.last,
    completed: completed ?? this.completed,
    newContact: newContact ?? this.newContact,
  );

  Map<String, Object?> toJson() => {
    'rng': rng,
    'recent': recent,
    'vibe': vibe,
    'contacts': contacts,
    'skit': skit,
    'character': character,
    'beat': beat,
    'tones': tones,
    'gained': gained,
    'last': last,
    'completed': completed,
    'newContact': newContact,
  };
}

/// `type` is 'start' (with [character], [context]), 'reply' (with [tone]) or 'leave'.
class DialogueAction {
  const DialogueAction.start(String this.character, String this.context) : type = 'start', tone = null;
  const DialogueAction.reply(String this.tone) : type = 'reply', character = null, context = null;
  const DialogueAction.leave() : type = 'leave', character = null, context = null, tone = null;

  final String type;
  final String? character, context, tone;

  Map<String, Object?> toJson() => {
    'by': 'player',
    'type': type,
    if (character != null) 'character': character,
    if (context != null) 'context': context,
    if (tone != null) 'tone': tone,
  };

  @override
  String toString() => toJson().toString();
}

class DialogueResult {
  const DialogueResult({
    required this.skit,
    required this.character,
    required this.completed,
    required this.gained,
    required this.vibe,
    required this.contact,
    required this.newContact,
  });

  final String skit, character;
  final bool completed;
  final int gained, vibe;
  final bool contact, newContact;

  Map<String, Object?> toJson() => {
    'skit': skit,
    'character': character,
    'completed': completed,
    'gained': gained,
    'vibe': vibe,
    'contact': contact,
    'newContact': newContact,
  };
}

class DialogueRules implements MgRules<DialogueState, DialogueAction, DialogueResult> {
  DialogueRules([this._cfg]);

  DialogueConfig? _cfg;

  @override
  String get id => 'dialogue';

  @override
  int get specVersion => 1;

  DialogueConfig get config => _cfg ?? (throw StateError('dialogue: init first'));

  @override
  DialogueState init(Map<String, Object?> config, int seed) => initWith(DialogueConfig.fromJson(config), seed);

  DialogueState initWith(DialogueConfig c, int seed) {
    _cfg = c;
    return DialogueState(
      rng: Prng(seed).state,
      recent: const [],
      vibe: {for (final ch in c.characters) ch.id: c.vibeStart},
      contacts: const [],
      skit: '',
      character: '',
      beat: 0,
      tones: const [],
      gained: 0,
      last: '',
      completed: false,
      newContact: false,
    );
  }

  /// Candidates for (character, context) in config order (spec "Výběr skitu" 1).
  List<String> candidates(String character, String context) => [
    for (final s in config.skits)
      if (s.character == character && s.context == context && (s.city.isEmpty || s.city == config.city)) s.id,
  ];

  @override
  List<DialogueAction> legalActions(DialogueState s) {
    if (s.skit.isEmpty) {
      return [
        for (final ch in config.characters)
          for (final x in npcContexts)
            if (candidates(ch.id, x).isNotEmpty) DialogueAction.start(ch.id, x),
      ];
    }
    return [for (final t in tones) DialogueAction.reply(t), const DialogueAction.leave()];
  }

  @override
  DialogueState apply(DialogueState s, DialogueAction a) => switch (a.type) {
    'start' => _start(s, a),
    'reply' => _reply(s, a),
    'leave' when s.skit.isNotEmpty => s.copyWith(last: s.skit, skit: '', completed: false, newContact: false),
    _ => throw IllegalAction(id, a),
  };

  DialogueState _start(DialogueState s, DialogueAction a) {
    if (s.skit.isNotEmpty) throw IllegalAction(id, a);
    final cand = candidates(a.character!, a.context!);
    if (cand.isEmpty) throw IllegalAction(id, a);
    final fresh = [
      for (final c in cand)
        if (!s.recent.contains(c)) c,
    ];
    var rng = s.rng;
    String skit;
    if (fresh.isNotEmpty) {
      final r = withRng(s.rng, (p) => p.nextInt(fresh.length));
      skit = fresh[r.value];
      rng = r.rng;
    } else {
      // Exhausted: the least recently played candidate (smallest index in the queue).
      skit = cand.reduce((best, c) => s.recent.indexOf(c) < s.recent.indexOf(best) ? c : best);
    }
    final recent = [...s.recent.where((x) => x != skit), skit];
    while (recent.length > config.recentK) {
      recent.removeAt(0);
    }
    return s.copyWith(
      rng: rng,
      recent: recent,
      skit: skit,
      character: a.character,
      beat: 0,
      tones: const [],
      gained: 0,
    );
  }

  DialogueState _reply(DialogueState s, DialogueAction a) {
    final c = config;
    if (s.skit.isEmpty || !tones.contains(a.tone)) throw IllegalAction(id, a);
    final ch = c.characters.where((x) => x.id == s.character).firstOrNull;
    final sk = c.skits.where((x) => x.id == s.skit).firstOrNull;
    if (ch == null || sk == null) throw IllegalAction(id, a);
    final old = s.vibe[s.character] ?? c.vibeStart;
    final now = (old + ch.tones[a.tone]!).clamp(0, c.vibeMax);
    final n = s.copyWith(
      vibe: {...s.vibe, s.character: now},
      gained: s.gained + now - old,
      tones: [...s.tones, a.tone!],
      beat: s.beat + 1,
    );
    if (n.beat < sk.beats) return n;
    // Skit completed: maybe a phone contact.
    var rng = n.rng;
    var contacts = n.contacts;
    var newContact = false;
    if (!contacts.contains(s.character) && now >= c.contactMinVibe) {
      final raw = c.contactBasePct + (now - c.contactMinVibe) * c.contactStepPct;
      final pct = raw < c.contactMaxPct ? raw : c.contactMaxPct;
      final r = withRng(rng, (p) => p.nextInt(100));
      rng = r.rng;
      if (r.value < pct) {
        contacts = [...contacts, s.character];
        newContact = true;
      }
    }
    return n.copyWith(rng: rng, contacts: contacts, newContact: newContact, completed: true, last: s.skit, skit: '');
  }

  @override
  DialogueAction aiAction(DialogueState state, int level, Prng ai) => throw UnsupportedError('dialogue: no AI');

  @override
  DialogueResult? result(DialogueState s) {
    if (s.skit.isNotEmpty || s.last.isEmpty) return null;
    return DialogueResult(
      skit: s.last,
      character: s.character,
      completed: s.completed,
      gained: s.gained,
      vibe: s.vibe[s.character] ?? 0,
      contact: s.contacts.contains(s.character),
      newContact: s.newContact,
    );
  }

  @override
  DialogueAction actionFromJson(Map<String, Object?> j) {
    if (j['by'] != 'player') throw IllegalAction(id, j);
    return switch (j['type']) {
      'start' => DialogueAction.start(j['character'] as String, j['context'] as String),
      'reply' => DialogueAction.reply(j['tone'] as String),
      'leave' => const DialogueAction.leave(),
      _ => throw IllegalAction(id, j),
    };
  }

  @override
  Map<String, Object?> stateToJson(DialogueState s) => s.toJson();

  @override
  Map<String, Object?> resultToJson(DialogueResult r) => r.toJson();
}

/// Player outcome on the minigame result screen → quip list (spec "Hláška soupeře").
String quipOutcome(String winner) => switch (winner) {
  'player' => 'win',
  'ai' => 'lose',
  _ => 'draw',
};

/// quips[outcome][Prng(seed).nextInt(n)].
int quipIndex(int count, int seed) => Prng(seed).nextInt(count);

/// The text in [locale], English when the locale is missing.
String npcText(NpcText t, String locale) => locale == 'cs' ? t.cs : t.en;
