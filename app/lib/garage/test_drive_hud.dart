import 'package:flutter/material.dart';
import 'package:shared_gen/shared_gen.dart';

import '../game/metropole_game.dart';
import '../l10n/app_localizations.dart';

/// Test-drive HUD (specs/testdrive.md "Odpočet"): the countdown pill with its end button while a
/// test drive runs (the taxi HUD's place: they never run together) and the "test drive over" toast.
/// Redrawn with the game HUD (10×/s).
class TestDriveHud extends StatelessWidget {
  const TestDriveHud({super.key, required this.game});
  final MetropoleGame game;

  static String clock(double s) {
    final n = s.ceil();
    return '${n ~/ 60}:${(n % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SafeArea(
      child: ValueListenableBuilder(
        valueListenable: game.hud,
        builder: (context, _, _) {
          final t = game.fleet.testing;
          final over = game.testDriveOverS > 0;
          if (t == null && !over) return const SizedBox.shrink();
          return Stack(
            children: [
              if (t != null)
                Positioned(
                  top: 140,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      DecoratedBox(
                        key: const ValueKey('testDrivePill'),
                        decoration: BoxDecoration(
                          color: Color(
                            t.left <= game.tuning.cars.testDriveLowS
                                ? Tokens.colorTestDriveLow
                                : Tokens.colorTestDrivePill,
                          ),
                          borderRadius: BorderRadius.circular(Tokens.radiusPill),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceMd, vertical: Tokens.spaceSm),
                          child: Text(
                            l.testDriveLeft(clock(t.left)),
                            style: const TextStyle(
                              color: Color(Tokens.colorTestDrivePillText),
                              fontSize: Tokens.fontHud,
                              fontWeight: FontWeight.w800,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('testDriveEnd'),
                        tooltip: l.testDriveEnd,
                        icon: const Icon(Icons.close, color: Color(Tokens.colorUiText)),
                        style: IconButton.styleFrom(backgroundColor: const Color(Tokens.colorUiPill)),
                        onPressed: () => game.fleet.endTest(),
                      ),
                    ],
                  ),
                ),
              if (over)
                Align(
                  alignment: const Alignment(0, 0.35),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(Tokens.colorUiPill),
                      borderRadius: BorderRadius.circular(Tokens.radiusPill),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceMd, vertical: Tokens.spaceSm),
                      child: Text(
                        l.testDriveOver,
                        style: const TextStyle(color: Color(Tokens.colorUiText), fontWeight: FontWeight.w700),
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
