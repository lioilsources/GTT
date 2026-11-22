import 'package:flutter/material.dart';
import 'package:shared_gen/shared_gen.dart';

import '../phone/phone_sheet.dart' show phoneText;
import 'fast_travel.dart';

/// The Taxi phone app (specs/phone.md v4, specs/travel.md "Taxi"): targets sorted by distance from
/// the car with their fares; greyed when the cash is short or fast travel is not offered (Taxi
/// shift); only the travelWanted line while wanted.
class TaxiScreen extends StatelessWidget {
  const TaxiScreen({super.key, required this.travel});
  final FastTravelController travel;

  @override
  Widget build(BuildContext context) {
    if (travel.wanted > 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Tokens.spaceLg),
          child: Text(
            phoneText(context, MessageKey.travelWanted),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(Tokens.colorUiTextMuted), fontSize: Tokens.fontHudSmall),
          ),
        ),
      );
    }
    final can = travel.offered;
    final rows = travel.taxiList();
    return ListView(
      padding: const EdgeInsets.all(Tokens.spaceMd),
      children: [
        for (final ch in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: Tokens.spaceSm),
            child: _Row(
              text: phoneText(context, MessageKey.travelFare, {'name': ch.point.name, 'fare': ch.fare}),
              onTap: can && ch.affordable ? () => travel.taxi(ch.point.id) : null,
            ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.text, required this.onTap});
  final String text;
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
        child: Text(
          text,
          style: TextStyle(
            color: Color(onTap == null ? Tokens.colorUiTextFaint : Tokens.colorUiText),
            fontSize: Tokens.fontHud,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}
