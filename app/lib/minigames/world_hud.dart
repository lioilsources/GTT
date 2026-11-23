import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:shared_gen/shared_gen.dart';

/// Shared pieces of the world minigame HUDs (Drift, Sprint): pills, the end button, a flash line
/// and the Gallery card.

/// m:ss rounded up to whole seconds.
String worldClock(double s) {
  final n = s.ceil();
  return '${n ~/ 60}:${(n % 60).toString().padLeft(2, '0')}';
}

/// The UI language for generated texts.
String worldLocale(BuildContext context) {
  final lang = Localizations.localeOf(context).languageCode;
  return messageLocales.contains(lang) ? lang : 'en';
}

class WorldPill extends StatelessWidget {
  const WorldPill({super.key, required this.text, required this.color, this.textColor = Tokens.colorUiText});
  final String text;
  final int color, textColor;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: Color(color), borderRadius: BorderRadius.circular(Tokens.radiusPill)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceMd, vertical: Tokens.spaceSm),
      child: Text(
        text,
        style: TextStyle(
          color: Color(textColor),
          fontSize: Tokens.fontHud,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ),
  );
}

/// The row of pills with the end button, under the top HUD.
class WorldHudRow extends StatelessWidget {
  const WorldHudRow({super.key, required this.pills, required this.endLabel, required this.onEnd});
  final List<Widget> pills;
  final String endLabel;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) => Positioned(
    top: 140,
    left: 0,
    right: 0,
    child: Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Tokens.spaceSm,
      runSpacing: Tokens.spaceSm,
      children: [
        ...pills,
        IconButton(
          tooltip: endLabel,
          icon: const Icon(Icons.close, color: Color(Tokens.colorUiText)),
          style: IconButton.styleFrom(backgroundColor: const Color(Tokens.colorUiPill)),
          onPressed: onEnd,
        ),
      ],
    ),
  );
}

/// A short centred line (banked chain, split).
class WorldFlash extends StatelessWidget {
  const WorldFlash({super.key, required this.text, required this.color});
  final String text;
  final int color;

  @override
  Widget build(BuildContext context) => Align(
    alignment: const Alignment(0, -0.4),
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: Tokens.spaceLg),
      padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceMd, vertical: Tokens.spaceSm),
      decoration: BoxDecoration(
        color: const Color(Tokens.colorUiPill),
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(color), fontSize: Tokens.fontHud, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

/// A world minigame (engine `drive`) in the Gallery: it needs the city, so the card says so and its
/// button closes the Gallery and starts it at its spot (specs/minigames/drift.md, sprint.md
/// "Galerie a ladění"). The game screen sets [startInCity] per id.
class WorldCardGame implements Minigame {
  const WorldCardGame(this.id, this.text, this.go);
  final MinigameId id;
  final MessageKey text, go;

  /// Set by the game screen: moves the car to the game's spot and starts it there.
  static final Map<MinigameId, void Function()> startInCity = {};

  @override
  MinigameMeta get meta => minigameCatalog[id]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) => Builder(
    builder: (context) {
      final start = startInCity[id];
      return Scaffold(
        backgroundColor: const Color(Tokens.colorUiBackground),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(Tokens.spaceLg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  env.t(MessageKey.values.firstWhere((k) => k.key == 'mg_${id.id}')),
                  style: const TextStyle(
                    color: Color(Tokens.colorUiText),
                    fontSize: Tokens.fontHud,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: Tokens.spaceMd),
                Text(
                  env.t(text),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(Tokens.colorUiTextMuted)),
                ),
                const SizedBox(height: Tokens.spaceLg),
                FilledButton(
                  onPressed: start == null
                      ? null
                      : () {
                          Navigator.of(context).popUntil((r) => r.isFirst);
                          start();
                        },
                  child: Text(env.t(go)),
                ),
                TextButton(
                  onPressed: () => onFinish(MinigameResult(stars: 0, score: 0, playedMs: 0, aborted: true)),
                  child: Text(env.t(MessageKey.back)),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
