import 'package:flutter/material.dart';
import 'package:shared_gen/shared_gen.dart';

import '../l10n/app_localizations.dart';
import 'fast_travel.dart';

/// Fast travel HUD over the world (specs/travel.md): the "Metro" context button, the "station
/// unlocked" toast, the metro card and the line card of a move (both pause the game).
class FastTravelLayer extends StatelessWidget {
  const FastTravelLayer({super.key, required this.travel});
  final FastTravelController travel;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([travel, travel.metroCard, travel.cut, travel.metroHere, travel.unlockedToast]),
      builder: (context, _) {
        final from = travel.metroCard.value;
        final cut = travel.cut.value;
        final toast = travel.unlockedToast.value;
        return Stack(
          children: [
            SafeArea(
              child: Stack(
                children: [
                  if (toast != null)
                    Positioned(
                      top: 96,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: Center(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(Tokens.colorUiPill),
                              borderRadius: BorderRadius.circular(Tokens.radiusPill),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceMd, vertical: Tokens.spaceSm),
                              child: Text(
                                l.travelUnlocked(toast),
                                style: const TextStyle(
                                  color: Color(Tokens.colorTravelLine),
                                  fontSize: Tokens.fontHudSmall,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (travel.metroHere.value != null && from == null && cut == null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 148,
                      child: Center(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(Tokens.colorTravelEntry),
                            foregroundColor: const Color(Tokens.colorTravelCardText),
                          ),
                          onPressed: travel.openMetro,
                          child: Text(l.travelMetro),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (from != null)
              Positioned.fill(
                child: _MetroCard(travel: travel, from: from.name),
              ),
            if (cut != null) Positioned.fill(child: _LineCard(cut: cut)),
          ],
        );
      },
    );
  }
}

/// The metro card: every other unlocked station with its fare (greyed when the cash is short), the
/// travelLocked line while some station is locked, and "Zpět".
class _MetroCard extends StatelessWidget {
  const _MetroCard({required this.travel, required this.from});
  final FastTravelController travel;
  final String from;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final rows = travel.metroList();
    return ColoredBox(
      color: const Color(Tokens.colorUiPill),
      child: Center(
        child: Container(
          width: 360,
          margin: const EdgeInsets.all(Tokens.spaceLg),
          padding: const EdgeInsets.all(Tokens.spaceLg),
          decoration: BoxDecoration(
            color: const Color(Tokens.colorTravelCard),
            borderRadius: BorderRadius.circular(Tokens.radiusButton),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  from,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(Tokens.colorTravelCardText),
                    fontSize: Tokens.fontHud,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: Tokens.spaceMd),
                for (final ch in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Tokens.spaceSm),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(Tokens.colorTravelEntry),
                          foregroundColor: const Color(Tokens.colorTravelCardText),
                        ),
                        onPressed: ch.affordable ? () => travel.metro(ch.point.id) : null,
                        child: Text(l.travelFare(ch.fare, ch.point.name)),
                      ),
                    ),
                  ),
                if (travel.world?.anyLocked ?? false)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Tokens.spaceSm),
                    child: Text(
                      l.travelLocked,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(Tokens.colorUiTextMuted), fontSize: Tokens.fontHudSmall),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(onPressed: travel.closeMetro, child: Text(l.travelClose)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The line card of a move for travel.cut_s: metro or taxi icon, a line in color.travel.line and
/// the target's name.
class _LineCard extends StatelessWidget {
  const _LineCard({required this.cut});
  final TravelCut cut;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ColoredBox(
      color: const Color(Tokens.colorTravelCard),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(cut.metro ? Icons.subway : Icons.local_taxi, size: 56, color: const Color(Tokens.colorTravelCardText)),
            const SizedBox(height: Tokens.spaceMd),
            Container(
              width: 160,
              height: 6,
              decoration: BoxDecoration(
                color: const Color(Tokens.colorTravelLine),
                borderRadius: BorderRadius.circular(Tokens.radiusPill),
              ),
            ),
            const SizedBox(height: Tokens.spaceMd),
            Text(
              l.travelTo(cut.name),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(Tokens.colorTravelCardText),
                fontSize: Tokens.fontHud,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
