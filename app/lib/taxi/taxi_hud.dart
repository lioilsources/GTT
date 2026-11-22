import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:shared_gen/shared_gen.dart';

import '../l10n/app_localizations.dart';
import 'taxi_controller.dart';

/// Shift HUD (specs/minigames/taxi.md "HUD"): time left, fares, end-shift button and the passenger's
/// line. The destination pill is the navigation pill ([NavHud]).
class TaxiHud extends StatelessWidget {
  const TaxiHud({super.key, required this.taxi});
  final TaxiController taxi;

  static String clock(double s) {
    final n = s.ceil();
    return '${n ~/ 60}:${(n % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    taxi.locale = messageLocales.contains(lang) ? lang : 'en';
    return SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([taxi, taxi.line]),
        builder: (context, _) {
          final s = taxi.shift;
          final text = taxi.line.value;
          return Stack(
            children: [
              if (s != null)
                Positioned(
                  top: 140,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Pill(
                        text: l.taxiTime(clock(s.left)),
                        color: Color(s.left <= taxi.t.lowS ? Tokens.colorTaxiLow : Tokens.colorTaxiPill),
                      ),
                      const SizedBox(width: Tokens.spaceSm),
                      _Pill(text: l.taxiFare(s.state.fare), color: const Color(Tokens.colorTaxiPill)),
                      IconButton(
                        tooltip: l.taxiEnd,
                        icon: const Icon(Icons.close, color: Color(Tokens.colorUiText)),
                        style: IconButton.styleFrom(backgroundColor: const Color(Tokens.colorUiPill)),
                        onPressed: taxi.quit,
                      ),
                    ],
                  ),
                ),
              if (text != null)
                Align(
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
                      style: const TextStyle(
                        color: Color(Tokens.colorUiText),
                        fontSize: Tokens.fontHud,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(Tokens.radiusPill)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceMd, vertical: Tokens.spaceSm),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(Tokens.colorTaxiPillText),
          fontSize: Tokens.fontHud,
          fontWeight: FontWeight.w800,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ),
  );
}

/// Taxi in the Gallery (specs/minigames/taxi.md "Galerie a ladění"): it needs the world, so the card
/// says so and its button closes the Gallery and starts the shift at the taxi stand.
class TaxiGame implements Minigame {
  const TaxiGame();

  /// Set by the game screen: teleports to the taxi stand and starts the shift there.
  static void Function()? startInCity;

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.taxi]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) => Builder(
    builder: (context) => Scaffold(
      backgroundColor: const Color(Tokens.colorUiBackground),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(Tokens.spaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                env.t(MessageKey.mgTaxi),
                style: const TextStyle(
                  color: Color(Tokens.colorUiText),
                  fontSize: Tokens.fontHud,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Tokens.spaceMd),
              Text(
                env.t(MessageKey.taxiGallery),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(Tokens.colorUiTextMuted)),
              ),
              const SizedBox(height: Tokens.spaceLg),
              FilledButton(
                onPressed: startInCity == null
                    ? null
                    : () {
                        Navigator.of(context).popUntil((r) => r.isFirst);
                        startInCity?.call();
                      },
                child: Text(env.t(MessageKey.taxiGalleryGo)),
              ),
              TextButton(
                onPressed: () => onFinish(MinigameResult(stars: 0, score: 0, playedMs: 0, aborted: true)),
                child: Text(env.t(MessageKey.back)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
