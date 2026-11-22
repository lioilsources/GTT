import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:npc_dialogue/npc_dialogue.dart';
import 'package:shared_gen/shared_gen.dart';

import '../l10n/app_localizations.dart';
import 'registry.dart';

/// Debug Gallery (METROPOLE_PLAN 9.2): every catalog minigame, playable without driving.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key, required this.tuning, required this.cityId});

  final Tuning tuning;

  /// The current city (specs/cities.md "Co je po městech").
  final String cityId;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  // A fresh seed per game; Random is fine here, the rules themselves are seeded.
  final Random _random = Random();
  int _level = 3;

  // NPC opponent for the result-screen line (specs/dialogue.md); 0 = none.
  int _opponent = 0;
  DialogueSession? _npc;
  late int _seed = _newSeed();

  int _newSeed() => _random.nextInt(1 << 32);

  @override
  void initState() {
    super.initState();
    ensureDialogueSession(widget.tuning, city: widget.cityId).then((s) {
      if (mounted) setState(() => _npc = s);
    });
  }

  List<String> get _opponents => ['', ...?_npc?.pack.characters.map((c) => c.id)];

  void _open(MinigameId id, Minigame game) {
    final locale = Localizations.localeOf(context).languageCode;
    final lang = messageLocales.contains(locale) ? locale : 'en';
    final opponentId = _opponents[_opponent % _opponents.length];
    final env = MinigameEnv(
      tuning: widget.tuning,
      locale: lang,
      opponent: opponentFor(_npc, opponentId.isEmpty ? null : opponentId, _seed, lang),
    );
    final ctx = MinigameContext(
      cityId: widget.cityId,
      difficulty: _level,
      seed: _seed,
      locale: env.locale,
      opponentId: opponentId.isEmpty ? null : opponentId,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => game.build(ctx, env, (r) {
          debugPrint('[metro minigame] ${id.id} ${r.toJson()}');
          Navigator.of(routeContext).pop();
          setState(() => _seed = _newSeed());
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const muted = TextStyle(color: Color(Tokens.colorUiTextMuted));
    return Scaffold(
      backgroundColor: const Color(Tokens.colorUiBackground),
      appBar: AppBar(
        backgroundColor: const Color(Tokens.colorUiBackground),
        foregroundColor: const Color(Tokens.colorUiText),
        title: Text(l.gallery, style: const TextStyle(color: Color(Tokens.colorBrandAccent))),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Tokens.spaceMd),
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.tune, color: Color(Tokens.colorUiText)),
                onPressed: () => setState(() => _level = _level % 5 + 1),
              ),
              Text(l.difficulty(_level), style: muted),
              const SizedBox(width: Tokens.spaceMd),
              IconButton(
                icon: const Icon(Icons.casino, color: Color(Tokens.colorUiText)),
                onPressed: () => setState(() => _seed = _newSeed()),
              ),
              Text(l.seed(_seed), style: muted),
            ],
          ),
          if (_npc case final npc?)
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.face, color: Color(Tokens.colorUiText)),
                  onPressed: () => setState(() => _opponent = (_opponent + 1) % _opponents.length),
                ),
                Text(
                  _opponents[_opponent % _opponents.length].isEmpty
                      ? l.npcNoOpponent
                      : l.npcOpponent(npc.character(_opponents[_opponent % _opponents.length])!.name),
                  style: muted,
                ),
              ],
            ),
          for (final id in MinigameId.values)
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.spaceSm),
              child: Material(
                color: const Color(Tokens.colorUiPill),
                borderRadius: BorderRadius.circular(Tokens.radiusButton),
                child: ListTile(
                  enabled: minigames.containsKey(id),
                  title: Text(
                    _name(l, id),
                    style: TextStyle(
                      color: Color(minigames.containsKey(id) ? Tokens.colorUiText : Tokens.colorUiTextFaint),
                    ),
                  ),
                  trailing: Text(
                    minigames.containsKey(id)
                        ? '${minigameCatalog[id]!.engine} · ${minigameCatalog[id]!.targetLengthS ~/ 60} min'
                        : l.notYet,
                    style: muted,
                  ),
                  onTap: minigames[id] == null ? null : () => _open(id, minigames[id]!),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _name(AppLocalizations l, MinigameId id) => switch (id) {
    MinigameId.sirky => l.mg_sirky,
    MinigameId.oko => l.mg_oko,
    MinigameId.dama => l.mg_dama,
    MinigameId.desetitisic => l.mg_desetitisic,
    MinigameId.sipky => l.mg_sipky,
    MinigameId.strelnice => l.mg_strelnice,
    MinigameId.taxi => l.mg_taxi,
    MinigameId.koulena => l.mg_koulena,
  };
}
