import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meta_progress/meta_progress.dart';
import 'package:metropole/l10n/app_localizations.dart';
import 'package:metropole/ui/passport.dart';
import 'package:world_engine/world_engine.dart';

Widget _app(Widget child, [String locale = 'en']) => MaterialApp(
  locale: Locale(locale),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

void main() {
  final tuning = Tuning.fromYaml(File('../content/tuning.yaml').readAsStringSync());
  const city = PassportCity(
    landmarks: [
      (id: 'empire_state', name: 'Empire State Building', x: 0, y: 0, heightM: 381, hero: true),
      (id: 'central_park', name: 'Central Park', x: 5000, y: 0, heightM: 0, hero: true),
    ],
    districts: ['Midtown', "Hell's Kitchen"],
    spotMinigames: ['sirky'],
  );

  testWidgets('passport screen shows completion and stamps', (tester) async {
    final t = PassportTracker(city, tuning.passport)..update(0, 0, 'Midtown');
    await tester.pumpWidget(
      _app(
        PassportScreen(
          tracker: t,
          cityName: 'New York',
          about: const AboutInfo(overtureRelease: 'r', builtAt: 'b'),
        ),
      ),
    );
    // 3 + 1 of 2·3 + 2·1 + 1·3 = 11 → 36 %.
    expect(find.text('New York: 36 % complete'), findsOneWidget);
    expect(find.text('Empire State Building'), findsOneWidget);
    expect(find.text("Hell's Kitchen"), findsOneWidget);
    await tester.tap(find.text('Empire State Building'));
    await tester.pumpAndSettle();
    expect(find.text('STAMPED IN YOUR PASSPORT'), findsOneWidget);
  });

  testWidgets('about the maps lists the licences in Czech', (tester) async {
    await tester.pumpWidget(
      _app(const AboutMapsScreen(info: AboutInfo(overtureRelease: '2026-11-18.0', builtAt: 'x')), 'cs'),
    );
    expect(find.text('O mapách'), findsOneWidget);
    expect(find.textContaining('ODbL 1.0'), findsWidgets);
    expect(find.textContaining('2026-11-18.0'), findsOneWidget);
  });
}
