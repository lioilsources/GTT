// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Metropole';

  @override
  String loading(String city) {
    return 'Loading $city…';
  }

  @override
  String loadFailed(String error) {
    return 'The city failed to load: $error';
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
  String get unnamedRoad => 'Side street';

  @override
  String get bridgeTag => 'bridge';

  @override
  String get tunnelTag => 'tunnel';

  @override
  String get borderNotice => 'This way to New Jersey – next time!';

  @override
  String get dayNight => 'Day / night';

  @override
  String get controlScheme => 'Controls';

  @override
  String get schemeA => 'A · thumb drag';

  @override
  String get schemeB => 'B · screen halves';

  @override
  String get schemeC => 'C · wheel + pedal';

  @override
  String get debugPanel => 'Tuning';

  @override
  String get copyYaml => 'Copy tuning.yaml';

  @override
  String get copied => 'Copied to clipboard';

  @override
  String get respawn => 'Back to start';

  @override
  String get close => 'Close';

  @override
  String get worldSection => 'World (content/tuning.yaml)';

  @override
  String get carSection => 'Car (content/cars)';

  @override
  String get aboutMaps => '© OpenStreetMap contributors · Overture Maps Foundation';
}
