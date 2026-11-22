import 'package:flutter/material.dart';
import 'package:shared_gen/shared_gen.dart';

import 'phone_controller.dart';
import 'phone_sheet.dart' show phoneText;

/// The Travel app (specs/cities.md "Aplikace Cesty"): cities in `CityId` order with their passport
/// completion; tapping another city switches to it.
class TravelScreen extends StatefulWidget {
  const TravelScreen({super.key, required this.phone});
  final PhoneController phone;

  @override
  State<TravelScreen> createState() => _TravelScreenState();
}

class _TravelScreenState extends State<TravelScreen> {
  // Loaded lazily, only when the app opens.
  late final Map<CityId, Future<int>> _percent = {
    for (final c in CityId.values) c: widget.phone.passportPercent?.call(c) ?? Future.value(0),
  };

  @override
  Widget build(BuildContext context) {
    final phone = widget.phone;
    final here = CityId.byId(phone.game.city.id);
    return ListView(
      padding: const EdgeInsets.all(Tokens.spaceMd),
      children: [
        Text(
          phoneText(context, MessageKey.travelTitle),
          style: const TextStyle(color: Color(Tokens.colorUiTextMuted), fontSize: Tokens.fontHudSmall),
        ),
        const SizedBox(height: Tokens.spaceSm),
        for (final c in CityId.values)
          Padding(
            padding: const EdgeInsets.only(bottom: Tokens.spaceSm),
            child: _CityRow(
              city: c,
              here: c == here,
              percent: _percent[c]!,
              onTap: c == here || phone.onTravel == null ? null : () => phone.onTravel!(c),
            ),
          ),
      ],
    );
  }
}

class _CityRow extends StatelessWidget {
  const _CityRow({required this.city, required this.here, required this.percent, required this.onTap});
  final CityId city;
  final bool here;
  final Future<int> percent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(Tokens.colorPhoneBar),
    borderRadius: BorderRadius.circular(Tokens.radiusButton),
    child: InkWell(
      borderRadius: BorderRadius.circular(Tokens.radiusButton),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(Tokens.spaceMd),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    city.name,
                    style: const TextStyle(
                      color: Color(Tokens.colorUiText),
                      fontSize: Tokens.fontHud,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: Tokens.spaceXs),
                  FutureBuilder<int>(
                    future: percent,
                    builder: (context, snap) => Text(
                      phoneText(context, MessageKey.travelPassport, {'pct': snap.data ?? 0}),
                      style: const TextStyle(color: Color(Tokens.colorUiTextMuted), fontSize: Tokens.fontHudSmall),
                    ),
                  ),
                ],
              ),
            ),
            if (here)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(Tokens.colorPhoneTagLocal),
                  borderRadius: BorderRadius.circular(Tokens.radiusPill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceSm, vertical: Tokens.spaceXs),
                  child: Text(
                    phoneText(context, MessageKey.travelHere),
                    style: const TextStyle(color: Color(Tokens.colorUiText), fontSize: Tokens.fontFaint),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
