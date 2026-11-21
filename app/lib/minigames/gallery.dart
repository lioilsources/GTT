import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:shared_gen/shared_gen.dart';

import '../l10n/app_localizations.dart';
import 'registry.dart';

/// Debug Gallery (METROPOLE_PLAN 9.2): every catalog minigame, playable without driving.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key, required this.tuning});

  final Tuning tuning;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  // A fresh seed per game; Random is fine here, the rules themselves are seeded.
  final Random _random = Random();
  int _level = 3;
  late int _seed = _newSeed();

  int _newSeed() => _random.nextInt(1 << 32);

  void _open(MinigameId id, Minigame game) {
    final locale = Localizations.localeOf(context).languageCode;
    final env = MinigameEnv(tuning: widget.tuning, locale: messageLocales.contains(locale) ? locale : 'en');
    final ctx = MinigameContext(cityId: CityId.nyc.id, difficulty: _level, seed: _seed, locale: env.locale);
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
