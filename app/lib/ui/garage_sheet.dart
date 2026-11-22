import 'package:drive_core/drive_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_gen/shared_gen.dart';

import '../l10n/app_localizations.dart';

/// Garage list (specs/cars.md "Garáž"): owned cars; picking one drives out with it.
/// Below them the cars for sale with prices (specs/economy.md "Nákup auta"), and the free air
/// refill for a car with a hop tank (specs/hop.md "Doplnění").
Future<void> showGarage(BuildContext context, CarFleet fleet) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: const Color(Tokens.colorUiSheet),
  isScrollControlled: true,
  builder: (context) => StatefulBuilder(builder: (context, setState) {
    final l = AppLocalizations.of(context);
    final buyable = fleet.buyable().toSet();
    final sale = [
      for (final s in fleet.specs.values)
        if (!fleet.owned.contains(s.id)) s,
    ]..sort((a, b) => a.price != b.price ? a.price.compareTo(b.price) : a.id.compareTo(b.id));
    String cls(String c) => switch (c) {
      'coupe' => l.carClassCoupe,
      'hatchback' => l.carClassHatchback,
      'muscle' => l.carClassMuscle,
      'taxi' => l.carClassTaxi,
      'pickup' => l.carClassPickup,
      'sedan' => l.carClassSedan,
      'micro' => l.carClassMicro,
      _ => '',
    };
    final drive = fleet.drive;
    final hopFull = hopCharges(drive.spec);
    return SafeArea(
      child: SingleChildScrollView(
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
            if (hopFull != null) ...[
              if (drive.hop.charges == 0)
                Text(l.hopEmpty, style: const TextStyle(color: Color(Tokens.colorUiTextMuted))),
              FilledButton.tonal(
                key: const ValueKey('hopRefill'),
                onPressed: drive.hop.canRefill(drive.spec) ? () => setState(() => drive.refillHop()) : null,
                child: Text('${l.hopRefill}  ${drive.hop.charges}/$hopFull'),
              ),
            ],
            for (final id in fleet.owned)
              if (fleet.specs[id] case final spec?)
                ListTile(
                  leading: CircleAvatar(backgroundColor: Color(paintArgb(spec)), radius: 10),
                  title: Text(spec.name, style: const TextStyle(color: Color(Tokens.colorUiText))),
                  // Classes without a label yet (sedan, micro) show the name only.
                  subtitle: cls(spec.class_).isEmpty
                      ? null
                      : Text(cls(spec.class_), style: const TextStyle(color: Color(Tokens.colorUiTextMuted))),
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
            if (sale.isNotEmpty) ...[
              const SizedBox(height: Tokens.spaceSm),
              Text(
                l.garageForSale,
                style: const TextStyle(color: Color(Tokens.colorUiText), fontWeight: FontWeight.w700),
              ),
              for (final spec in sale)
                ListTile(
                  leading: CircleAvatar(backgroundColor: Color(paintArgb(spec)), radius: 10),
                  title: Text(spec.name, style: const TextStyle(color: Color(Tokens.colorUiText))),
                  // Classes without a label yet (sedan, micro) show the name only.
                  subtitle: cls(spec.class_).isEmpty
                      ? null
                      : Text(cls(spec.class_), style: const TextStyle(color: Color(Tokens.colorUiTextMuted))),
                  trailing: OutlinedButton(
                    onPressed: buyable.contains(spec.id) ? () => setState(() => fleet.buy(spec.id)) : null,
                    child: Text(l.garageBuy(spec.price)),
                  ),
                ),
            ],
            Text(l.cashHud(fleet.state.cash), style: const TextStyle(color: Color(Tokens.colorLoopCash))),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l.close)),
          ],
        ),
      ),
    );
  }),
);
