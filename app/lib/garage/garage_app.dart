import 'package:flutter/material.dart';
import 'package:game_loop/game_loop.dart';
import 'package:shared_gen/shared_gen.dart';

import '../l10n/app_localizations.dart';
import '../ui/garage_sheet.dart' show SouvenirShelf;
import 'garage_controller.dart';
import 'garage_tabs.dart';

/// Phone app Garáž (specs/garage.md "Garáž", specs/phone.md): the owned cars with their levels and
/// looks, read only, and the shelf; buying happens only at the garage.
class GarageAppScreen extends StatelessWidget {
  const GarageAppScreen({super.key, required this.garage});
  final GarageController garage;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: garage,
      builder: (context, _) {
        final max = garage.world.config.maxLevel;
        final shelf = garage.shelf;
        return ListView(
          key: const ValueKey('garageApp'),
          padding: const EdgeInsets.all(Tokens.spaceLg),
          children: [
            Text(
              l.garageTitle,
              style: const TextStyle(
                color: Color(Tokens.colorUiText),
                fontSize: Tokens.fontHud,
                fontWeight: FontWeight.w700,
              ),
            ),
            for (final id in garage.owned)
              Padding(
                key: ValueKey('garageAppCar:$id'),
                padding: const EdgeInsets.symmetric(vertical: Tokens.spaceSm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 56,
                      child: CarPreview(
                        spec: garage.specs[id]!,
                        look: garage.lookOf(id),
                        tuning: garage.tuning,
                        height: 96,
                      ),
                    ),
                    const SizedBox(width: Tokens.spaceMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            garage.specs[id]!.name,
                            style: const TextStyle(color: Color(Tokens.colorUiText), fontWeight: FontWeight.w700),
                          ),
                          ...[
                            if (garage.world.slotsOf(id).isEmpty)
                              Text(l.garageNoSlots, style: const TextStyle(color: Color(Tokens.colorUiTextMuted))),
                            for (final slot in garage.world.slotsOf(id))
                              Row(
                                children: [
                                  SizedBox(
                                    width: 120,
                                    child: Text(
                                      slotName(l, slot),
                                      style: const TextStyle(
                                        color: Color(Tokens.colorUiTextMuted),
                                        fontSize: Tokens.fontFaint,
                                      ),
                                    ),
                                  ),
                                  LevelBar(level: garage.world.level(id, slot), max: max),
                                ],
                              ),
                            for (final part in garageParts)
                              if (garage.world.look(id, part) case final v when v != 0)
                                Row(
                                  children: [
                                    Text(
                                      '${partName(l, part)}: ${optionName(l, part, v) ?? ''}',
                                      style: const TextStyle(
                                        color: Color(Tokens.colorUiTextMuted),
                                        fontSize: Tokens.fontFaint,
                                      ),
                                    ),
                                    if (part != 'decal' && part != 'wheels')
                                      if (lookSwatch(part, v, 0) case final c?)
                                        CircleAvatar(radius: 5, backgroundColor: Color(c)),
                                  ],
                                ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (shelf != null) ...[const SizedBox(height: Tokens.spaceSm), SouvenirShelf(items: shelf())],
          ],
        );
      },
    );
  }
}
