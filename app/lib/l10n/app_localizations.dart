import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_cs.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('cs'), Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Metropole'**
  String get appTitle;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading {city}…'**
  String loading(String city);

  /// No description provided for @loadFailed.
  ///
  /// In en, this message translates to:
  /// **'The city failed to load: {error}'**
  String loadFailed(String error);

  /// No description provided for @speedMph.
  ///
  /// In en, this message translates to:
  /// **'{speed} mph'**
  String speedMph(int speed);

  /// No description provided for @speedKmh.
  ///
  /// In en, this message translates to:
  /// **'{speed} km/h'**
  String speedKmh(int speed);

  /// No description provided for @unnamedRoad.
  ///
  /// In en, this message translates to:
  /// **'Side street'**
  String get unnamedRoad;

  /// No description provided for @bridgeTag.
  ///
  /// In en, this message translates to:
  /// **'bridge'**
  String get bridgeTag;

  /// No description provided for @tunnelTag.
  ///
  /// In en, this message translates to:
  /// **'tunnel'**
  String get tunnelTag;

  /// No description provided for @borderNotice.
  ///
  /// In en, this message translates to:
  /// **'This way to New Jersey – next time!'**
  String get borderNotice;

  /// No description provided for @dayNight.
  ///
  /// In en, this message translates to:
  /// **'Day / night'**
  String get dayNight;

  /// No description provided for @controlScheme.
  ///
  /// In en, this message translates to:
  /// **'Controls'**
  String get controlScheme;

  /// No description provided for @schemeA.
  ///
  /// In en, this message translates to:
  /// **'A · thumb drag'**
  String get schemeA;

  /// No description provided for @schemeB.
  ///
  /// In en, this message translates to:
  /// **'B · screen halves'**
  String get schemeB;

  /// No description provided for @schemeC.
  ///
  /// In en, this message translates to:
  /// **'C · wheel + pedal'**
  String get schemeC;

  /// No description provided for @debugPanel.
  ///
  /// In en, this message translates to:
  /// **'Tuning'**
  String get debugPanel;

  /// No description provided for @copyYaml.
  ///
  /// In en, this message translates to:
  /// **'Copy tuning.yaml'**
  String get copyYaml;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copied;

  /// No description provided for @respawn.
  ///
  /// In en, this message translates to:
  /// **'Back to start'**
  String get respawn;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @worldSection.
  ///
  /// In en, this message translates to:
  /// **'World (content/tuning.yaml)'**
  String get worldSection;

  /// No description provided for @carSection.
  ///
  /// In en, this message translates to:
  /// **'Car (content/cars)'**
  String get carSection;

  /// No description provided for @aboutMaps.
  ///
  /// In en, this message translates to:
  /// **'© OpenStreetMap contributors · Overture Maps Foundation'**
  String get aboutMaps;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['cs', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'cs':
      return AppLocalizationsCs();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
