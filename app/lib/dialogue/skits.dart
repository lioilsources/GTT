import 'package:flutter/material.dart';
import 'package:npc_dialogue/npc_dialogue.dart';
import 'package:shared_gen/shared_gen.dart';

/// Opens the debug list of skits (specs/dialogue.md "Ladění") from the tuning panel.
Future<void> openSkits(NavigatorState nav, Tuning tuning, String languageCode, {required String city}) async {
  final session = await ensureDialogueSession(tuning, city: city);
  final locale = messageLocales.contains(languageCode) ? languageCode : 'en';
  await nav.push(
    MaterialPageRoute<void>(
      builder: (_) => SkitsScreen(session: session, locale: locale),
    ),
  );
}
