// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Czech (`cs`).
class AppLocalizationsCs extends AppLocalizations {
  AppLocalizationsCs([String locale = 'cs']) : super(locale);

  @override
  String get appTitle => 'Metropole';

  @override
  String loading(String city) {
    return 'Načítám $city…';
  }

  @override
  String loadFailed(String error) {
    return 'Město se nepodařilo načíst: $error';
  }

  @override
  String speedMph(int speed) {
    return '$speed mph';
  }

  @override
  String speedKmh(int speed) {
    return '$speed km/h';
  }

  @override
  String get unnamedRoad => 'Vedlejší ulice';

  @override
  String get bridgeTag => 'most';

  @override
  String get tunnelTag => 'tunel';

  @override
  String get borderNotice => 'Tudy do New Jersey – příště!';

  @override
  String get dayNight => 'Den / noc';

  @override
  String get controlScheme => 'Ovládání';

  @override
  String get schemeA => 'A · tah palcem';

  @override
  String get schemeB => 'B · poloviny obrazovky';

  @override
  String get schemeC => 'C · volant + pedál';

  @override
  String get debugPanel => 'Ladění';

  @override
  String get copyYaml => 'Kopírovat tuning.yaml';

  @override
  String get copied => 'Zkopírováno do schránky';

  @override
  String get respawn => 'Zpět na start';

  @override
  String get close => 'Zavřít';

  @override
  String get worldSection => 'Svět (content/tuning.yaml)';

  @override
  String get carSection => 'Auto (content/cars)';

  @override
  String get aboutMaps => '© OpenStreetMap contributors · Overture Maps Foundation';
}
