import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mg_api/mg_api.dart' show loadArtIndex;

import 'cities/cities.dart';
import 'l10n/app_localizations.dart';
import 'ui/game_screen.dart';
import 'package:shared_gen/shared_gen.dart';

/// Time since `main` started; the benchmark reports the first playable frame against it (specs/bench.md).
final Stopwatch appClock = Stopwatch();

Future<void> main() async {
  appClock.start();
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Generated art (specs/art.md): what exists comes from index.json only; missing = placeholders.
  await loadArtIndex(rootBundle);
  // Start city (specs/cities.md): no URL parameter on F, then the last city, then the first
  // bundled one (the app bundles every CityId, metro.yaml bundle_cities).
  final city = pickStartCity(null, await FileCityStore().read(), CityId.values);
  runApp(MetropoleApp(city: city));
}

class MetropoleApp extends StatelessWidget {
  const MetropoleApp({super.key, this.city = CityId.nyc});

  final CityId city;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (c) => AppLocalizations.of(c).appTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(Tokens.colorBrandAccent),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: GameScreen(city: city),
    );
  }
}
