import 'package:drive_core/drive_core.dart';
import 'package:flutter/material.dart';
import 'package:game_loop/game_loop.dart';
import 'package:shared_gen/shared_gen.dart';

import '../game/paint/car_painter.dart';
import '../l10n/app_localizations.dart';
import 'garage_controller.dart';

// The Tuning and Vzhled tabs of the garage (specs/garage.md "Garáž") and the pieces the phone app
// shares with them: the car preview, the level bar and the option names.

String slotName(AppLocalizations l, String slot) => switch (slot) {
  'engine' => l.garageSlotEngine,
  'tyres' => l.garageSlotTyres,
  'brakes' => l.garageSlotBrakes,
  'weight' => l.garageSlotWeight,
  _ => l.garageSlotDrift,
};

String slotEffect(AppLocalizations l, String slot, int pct) => switch (slot) {
  'engine' => l.garageEffectEngine(pct),
  'tyres' => l.garageEffectTyres(pct),
  'brakes' => l.garageEffectBrakes(pct),
  'weight' => l.garageEffectWeight(pct),
  _ => l.garageEffectDrift(pct),
};

String partName(AppLocalizations l, String part) => switch (part) {
  'paint' => l.garagePartPaint,
  'decal' => l.garagePartDecal,
  'wheels' => l.garagePartWheels,
  'glow' => l.garagePartGlow,
  _ => l.garagePartSmoke,
};

/// Name of a choice with a name (decal, wheels, and 0 = stock of the colour parts), else null.
String? optionName(AppLocalizations l, String part, int value) => switch ((part, value)) {
  ('decal', 0) => l.garageDecalNone,
  ('decal', 1) => l.garageDecalStripes,
  ('decal', 2) => l.garageDecalFlames,
  ('decal', _) => l.garageDecalChecker,
  ('wheels', 0) => l.garageWheelsStock,
  ('wheels', 1) => l.garageWheelsSport,
  ('wheels', _) => l.garageWheelsWhite,
  (_, 0) => l.garageStock,
  _ => null,
};

const _text = TextStyle(color: Color(Tokens.colorUiText));
const _muted = TextStyle(color: Color(Tokens.colorUiTextMuted));
const _bold = TextStyle(color: Color(Tokens.colorUiText), fontWeight: FontWeight.w700);

/// Level 0…max as [max] pills, filled `color.garage.level`, empty `color.garage.levelEmpty`.
class LevelBar extends StatelessWidget {
  const LevelBar({super.key, required this.level, required this.max});
  final int level, max;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < max; i++)
        Container(
          width: 18,
          height: 8,
          margin: const EdgeInsets.only(right: Tokens.spaceXs),
          decoration: BoxDecoration(
            color: Color(i < level ? Tokens.colorGarageLevel : Tokens.colorGarageLevelEmpty),
            borderRadius: BorderRadius.circular(Tokens.radiusPill),
          ),
        ),
    ],
  );
}

/// The car from above, drawn like in the world with [look] (the live preview of the Vzhled tab).
class CarPreview extends StatelessWidget {
  const CarPreview({super.key, required this.spec, required this.look, required this.tuning, this.height = 160});
  final CarSpec spec;
  final CarLook look;
  final Tuning tuning;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: CustomPaint(painter: _PreviewPainter(spec, look, tuning), size: Size.infinite),
  );
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.spec, this.look, this.tuning);
  final CarSpec spec;
  final CarLook look;
  final Tuning tuning;

  @override
  void paint(Canvas canvas, Size size) => paintCarPreview(
    canvas,
    size,
    spec,
    tuning,
    // Indoors in the garage: the underglow at full strength.
    (look: look, glowMarginM: tuning.garage.glowMarginM, glow: 1.0),
  );

  @override
  bool shouldRepaint(_PreviewPainter old) =>
      old.spec != spec ||
      old.look.paint != look.paint ||
      old.look.decal != look.decal ||
      old.look.rim != look.rim ||
      old.look.glow != look.glow;
}

/// Owned cars to pick from when there are several (the Tuning and Vzhled tabs).
class GarageCarPicker extends StatelessWidget {
  const GarageCarPicker({super.key, required this.garage, required this.car, required this.onPick});
  final GarageController garage;
  final String car;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final owned = garage.owned;
    if (owned.length < 2) return const SizedBox.shrink();
    return Wrap(
      spacing: Tokens.spaceSm,
      children: [
        for (final id in owned)
          ChoiceChip(
            key: ValueKey('garageCar:$id'),
            label: Text(garage.specs[id]!.name),
            selected: id == car,
            avatar: CircleAvatar(backgroundColor: Color(garage.lookOf(id).paint ?? paintArgb(garage.specs[id]!))),
            onSelected: (_) => onPick(id),
          ),
      ],
    );
  }
}

/// Tuning: one row per slot of [car] (name, level bar, the next level's effect, the button).
class TuningTab extends StatelessWidget {
  const TuningTab({super.key, required this.garage, required this.car, required this.onPick});
  final GarageController garage;
  final String car;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final slots = garage.world.slotsOf(car);
    final max = garage.world.config.maxLevel;
    // Few rows: built at once (not lazily), so every slot / part is there for the tests.
    return SingleChildScrollView(
      key: const ValueKey('garageTuning'),
      padding: const EdgeInsets.symmetric(vertical: Tokens.spaceSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GarageCarPicker(garage: garage, car: car, onPick: onPick),
          Text(garage.specs[car]!.name, style: _bold),
          const SizedBox(height: Tokens.spaceSm),
          if (slots.isEmpty) Text(l.garageNoSlots, key: const ValueKey('garageNoSlots'), style: _muted),
          for (final slot in slots) _slotRow(context, l, slot, max),
        ],
      ),
    );
  }

  Widget _slotRow(BuildContext context, AppLocalizations l, String slot, int max) {
    final level = garage.world.level(car, slot);
    final price = garage.upgradePrice(car, slot);
    final can = garage.canUpgrade(car, slot);
    return Padding(
      key: ValueKey('garageSlot:$slot'),
      padding: const EdgeInsets.symmetric(vertical: Tokens.spaceSm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(slotName(l, slot), style: _text),
                const SizedBox(height: Tokens.spaceXs),
                LevelBar(key: ValueKey('garageLevel:$slot'), level: level, max: max),
                if (price != null) ...[
                  const SizedBox(height: Tokens.spaceXs),
                  Text(
                    slotEffect(l, slot, garageEffectPct(garage.tuning.garage, slot)),
                    style: const TextStyle(color: Color(Tokens.colorUiTextMuted), fontSize: Tokens.fontFaint),
                  ),
                ],
              ],
            ),
          ),
          if (price == null)
            Text(l.garageMaxed, style: const TextStyle(color: Color(Tokens.colorGarageLevel)))
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FilledButton(
                  key: ValueKey('garageUpgrade:$slot'),
                  onPressed: can ? () => garage.upgrade(car, slot) : null,
                  child: Text(l.garageUpgrade(price)),
                ),
                if (!can)
                  Text(
                    l.garageNoCash,
                    style: const TextStyle(color: Color(Tokens.colorUiTextMuted), fontSize: Tokens.fontFaint),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Vzhled: the live preview, a row of choices per part, the price and the button of the picked one.
class LooksTab extends StatefulWidget {
  const LooksTab({super.key, required this.garage, required this.car, required this.onPick});
  final GarageController garage;
  final String car;
  final ValueChanged<String> onPick;

  @override
  State<LooksTab> createState() => _LooksTabState();
}

class _LooksTabState extends State<LooksTab> {
  /// The choice picked per part (not bought yet); missing = the current one.
  final Map<String, int> _picked = {};

  @override
  void didUpdateWidget(LooksTab old) {
    super.didUpdateWidget(old);
    if (old.car != widget.car) _picked.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final g = widget.garage, car = widget.car;
    final spec = g.specs[car]!;
    // Few rows: built at once (not lazily), so every slot / part is there for the tests.
    return SingleChildScrollView(
      key: const ValueKey('garageLooks'),
      padding: const EdgeInsets.symmetric(vertical: Tokens.spaceSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GarageCarPicker(garage: g, car: car, onPick: widget.onPick),
          CarPreview(key: const ValueKey('garagePreview'), spec: spec, look: g.lookOf(car, _picked), tuning: g.tuning),
          Text(spec.name, textAlign: TextAlign.center, style: _bold),
          for (final part in garageParts) _partRow(l, part, spec),
        ],
      ),
    );
  }

  Widget _partRow(AppLocalizations l, String part, CarSpec spec) {
    final g = widget.garage, car = widget.car;
    final n = g.world.config.parts[part] ?? 1;
    final current = g.world.look(car, part);
    final picked = _picked[part] ?? current;
    final price = g.lookPrice(part, picked);
    final can = g.canLook(car, part, picked);
    return Padding(
      key: ValueKey('garagePart:$part'),
      padding: const EdgeInsets.symmetric(vertical: Tokens.spaceSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(partName(l, part), style: _text),
          const SizedBox(height: Tokens.spaceXs),
          Wrap(
            spacing: Tokens.spaceSm,
            runSpacing: Tokens.spaceSm,
            children: [
              for (var v = 0; v < n; v++)
                _Option(
                  key: ValueKey('garageOption:$part:$v'),
                  swatch: lookSwatch(part, v, paintArgb(spec)),
                  // Stock glow and smoke: an empty ring (as client W); stock paint is named.
                  label: part == 'decal' || part == 'wheels' || (v == 0 && part == 'paint')
                      ? optionName(l, part, v)
                      : null,
                  current: v == current,
                  picked: v == picked,
                  onTap: () => setState(() => _picked[part] = v),
                ),
            ],
          ),
          const SizedBox(height: Tokens.spaceXs),
          Row(
            children: [
              Expanded(
                child: Text(
                  picked == current ? l.garageCurrent : (price == 0 ? l.garageFree : (can ? '' : l.garageNoCash)),
                  style: _muted,
                ),
              ),
              if (picked != current)
                FilledButton(
                  key: ValueKey('garageLookBuy:$part'),
                  onPressed: can
                      ? () {
                          if (g.buyLook(car, part, picked)) setState(() => _picked.remove(part));
                        }
                      : null,
                  child: Text(price == 0 ? l.garageFree : l.garageLookBuy(price)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A choice: a colour ring (paint, wheels, glow, smoke) and / or a name; the current one has a
/// gold ring, the picked one is filled.
class _Option extends StatelessWidget {
  const _Option({
    super.key,
    required this.swatch,
    required this.label,
    required this.current,
    required this.picked,
    required this.onTap,
  });
  final int? swatch;
  final String? label;
  final bool current, picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = Border.all(
      color: Color(current ? Tokens.colorGarageLevel : (picked ? Tokens.colorUiText : Tokens.colorGarageLevelEmpty)),
      width: current || picked ? 3 : 1,
    );
    final s = swatch;
    final dot = Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: s == null ? null : Color(s),
        border: label == null ? border : null,
      ),
    );
    final name = label;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Tokens.radiusPill),
      child: name == null
          ? dot
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceSm, vertical: Tokens.spaceXs),
              decoration: BoxDecoration(
                border: border,
                borderRadius: BorderRadius.circular(Tokens.radiusPill),
                color: picked ? const Color(Tokens.colorGarageLevelEmpty) : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (s != null) ...[
                    SizedBox.square(dimension: 18, child: FittedBox(child: dot)),
                    const SizedBox(width: Tokens.spaceXs),
                  ],
                  Text(name, style: _text),
                ],
              ),
            ),
    );
  }
}
