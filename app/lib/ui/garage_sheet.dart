import 'package:drive_core/drive_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_gen/shared_gen.dart';

import '../l10n/app_localizations.dart';

/// Garage list (specs/cars.md "Garáž"): owned cars; picking one drives out with it.
/// Buying (`fleet.buyable()`) comes with cash in M1-S11.
Future<void> showGarage(BuildContext context, CarFleet fleet) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: const Color(Tokens.colorUiSheet),
  builder: (context) {
    final l = AppLocalizations.of(context);
    String cls(String c) => switch (c) {
      'coupe' => l.carClassCoupe,
      'hatchback' => l.carClassHatchback,
      'muscle' => l.carClassMuscle,
      'taxi' => l.carClassTaxi,
      'pickup' => l.carClassPickup,
      _ => '',
    };
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Tokens.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.garageTitle,
              style: const TextStyle(
                color: Color(Tokens.colorUiText),
                fontSize: Tokens.fontHud,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Tokens.spaceSm),
            for (final id in fleet.owned)
              if (fleet.specs[id] case final spec?)
                ListTile(
                  leading: CircleAvatar(backgroundColor: Color(paintArgb(spec)), radius: 10),
                  title: Text(spec.name, style: const TextStyle(color: Color(Tokens.colorUiText))),
                  subtitle: Text(cls(spec.class_), style: const TextStyle(color: Color(Tokens.colorUiTextMuted))),
                  trailing: fleet.canSelect(id)
                      ? FilledButton(
                          onPressed: () {
                            fleet.select(id);
                            Navigator.of(context).pop();
                          },
                          child: Text(l.garageTakeOut),
                        )
                      : Text(l.garageDriving, style: const TextStyle(color: Color(Tokens.colorUiTextMuted))),
                ),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.close)),
          ],
        ),
      ),
    );
  },
);
