import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:shared_gen/shared_gen.dart';

import '../l10n/app_localizations.dart';
import '../loop/loop_controller.dart';
import 'booths_controller.dart';

/// Booth HUD over the world (specs/booths.md): the "Zvednout" context button (in the place of
/// "Hrát", which yields to it), the ringing toast and the offer card.
class BoothsLayer extends StatelessWidget {
  const BoothsLayer({super.key, required this.booths});
  final BoothsController booths;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final locale = messageLocales.contains(lang) ? lang : 'en';
    return SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([booths, booths.card, booths.answerable, booths.ringingToast]),
        builder: (context, _) {
          final c = booths.card.value;
          return Stack(
            children: [
              if (booths.ringingToast.value)
                Align(
                  alignment: const Alignment(0, -0.55),
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(Tokens.colorUiPill),
                        borderRadius: BorderRadius.circular(Tokens.radiusPill),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceMd, vertical: Tokens.spaceSm),
                        child: Text(
                          l.boothRinging,
                          style: const TextStyle(
                            color: Color(Tokens.colorBoothRing),
                            fontSize: Tokens.fontHudSmall,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (booths.answerable.value && c == null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 148,
                  child: Center(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(Tokens.colorBoothBody),
                        foregroundColor: const Color(Tokens.colorUiText),
                      ),
                      onPressed: () {
                        if (booths.canAnswer()) booths.answer();
                      },
                      child: Text(l.boothAnswer),
                    ),
                  ),
                ),
              if (c != null)
                Positioned.fill(
                  child: _OfferCard(booths: booths, card: c, locale: locale),
                ),
            ],
          );
        },
      ),
    );
  }
}

const _cardW = 360.0;

/// The offer after "Zvednout": host, minigame, place and bonus; "Jedu" / "Nechat být".
class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.booths, required this.card, required this.locale});
  final BoothsController booths;
  final BoothCard card;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final o = card.offer;
    final mg = booths.gameOf(o);
    final key = mg.isEmpty ? null : LoopController.nameKey(mg);
    final game = key == null ? o.spot : tr(locale, key);
    final id = booths.hostId(card.booth);
    final bust = id == null ? null : artIndex.bust(id);
    return ColoredBox(
      color: const Color(Tokens.colorUiPill),
      child: Center(
        child: Container(
          width: _cardW,
          margin: const EdgeInsets.all(Tokens.spaceLg),
          padding: const EdgeInsets.all(Tokens.spaceLg),
          decoration: BoxDecoration(
            color: const Color(Tokens.colorUiSheet),
            borderRadius: BorderRadius.circular(Tokens.radiusButton),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                card.booth.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(Tokens.colorUiText),
                  fontSize: Tokens.fontHud,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Tokens.spaceSm),
              // The host bust above the call (specs/art.md); without the file the card stays text only.
              if (bust != null)
                HostBust(path: bust, height: _cardW * hostBustHeight, fallback: const SizedBox.shrink()),
              Text(
                l.boothCall(o.bonus, game, booths.hostName(card.booth), booths.phone.spotName(o.spot)),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(Tokens.colorUiText)),
              ),
              const SizedBox(height: Tokens.spaceMd),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: booths.go, child: Text(l.boothGo)),
              ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(onPressed: booths.skip, child: Text(l.boothSkip)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
