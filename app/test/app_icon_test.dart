import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metropole/appicon/app_icon.dart';
import 'package:metropole/appicon/settings_screen.dart';
import 'package:shared_gen/shared_gen.dart';

/// specs/appicon.md v1 (parity F-083): five colour modes, sunset by default, the choice is a
/// device preference in app_icon.json and goes to the system over `metropole/app_icon`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('five modes in picker order, sunset is the default, every mode has a name', () {
    expect(AppIconMode.values.map((m) => m.name), ['day', 'night', 'sunset', 'teal', 'japan']);
    expect(appIconDefault, AppIconMode.sunset);
    for (final m in AppIconMode.values) {
      final key = MessageKey.values.firstWhere((k) => k.key == 'appIcon_${m.name}');
      for (final locale in ['cs', 'en']) {
        expect(tr(locale, key), isNotEmpty);
      }
    }
  });

  test('app_icon.json: the mode id; anything else is sunset', () async {
    expect(parseAppIcon('{"mode":"teal"}'), AppIconMode.teal);
    expect(parseAppIcon('{"mode":"neon"}'), AppIconMode.sunset);
    expect(parseAppIcon('{"mode":3}'), AppIconMode.sunset);
    expect(parseAppIcon('nope'), AppIconMode.sunset);

    final dir = await Directory.systemTemp.createTemp('appicon');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileAppIconStore(() async => dir);
    expect(await store.read(), AppIconMode.sunset);
    await store.write(AppIconMode.japan);
    expect(File('${dir.path}/app_icon.json').readAsStringSync(), '{"mode":"japan"}');
    expect(await FileAppIconStore(() async => dir).read(), AppIconMode.japan);

    final none = FileAppIconStore(() async => throw const FileSystemException('none'));
    expect(await none.read(), AppIconMode.sunset);
    await none.write(AppIconMode.day);
  });

  group('controller', () {
    test('load reads the stored mode and sends it to the system again', () async {
      final sent = <AppIconMode>[];
      final icons = AppIconController(store: MemoryAppIconStore(AppIconMode.night), native: (m) async => sent.add(m));
      expect(icons.mode, AppIconMode.sunset);
      await icons.load();
      expect(icons.mode, AppIconMode.night);
      expect(sent, [AppIconMode.night]);
    });

    test('load keeps the stored mode when the system refuses', () async {
      final icons = AppIconController(
        store: MemoryAppIconStore(AppIconMode.day),
        native: (m) async => throw PlatformException(code: 'rejected'),
      );
      await icons.load();
      expect(icons.mode, AppIconMode.day);
    });

    test('a pick asks the system and stores the mode; the current mode does nothing', () async {
      final sent = <AppIconMode>[];
      final store = MemoryAppIconStore();
      final icons = AppIconController(store: store, native: (m) async => sent.add(m));
      var notified = 0;
      icons.addListener(() => notified++);
      expect(await icons.pick(AppIconMode.sunset), isFalse);
      expect(sent, isEmpty);
      expect(await icons.pick(AppIconMode.teal), isTrue);
      expect(icons.mode, AppIconMode.teal);
      expect(sent, [AppIconMode.teal]);
      expect(store.mode, AppIconMode.teal);
      expect(notified, 1);
      expect(await icons.pick(AppIconMode.teal), isFalse);
      expect(sent, [AppIconMode.teal]);
    });

    test('a refused change returns to the previous mode and stores nothing', () async {
      final store = MemoryAppIconStore(AppIconMode.day);
      final icons = AppIconController(
        store: store,
        native: (m) async {
          if (m == AppIconMode.japan) throw PlatformException(code: 'rejected');
        },
      );
      await icons.load();
      expect(await icons.pick(AppIconMode.japan), isFalse);
      expect(icons.mode, AppIconMode.day);
      expect(store.mode, AppIconMode.day);
      expect(await icons.pick(AppIconMode.night), isTrue);
      expect(store.mode, AppIconMode.night);
    });
  });

  group('channel metropole/app_icon', () {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(appIconChannel, null));

    test('set carries the mode id', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(appIconChannel, (call) async {
        calls.add(call);
        return true;
      });
      await setNativeAppIcon(AppIconMode.teal);
      expect(calls.single.method, 'set');
      expect(calls.single.arguments, 'teal');
    });

    test('no native side: nothing happens; a refusal is an error', () async {
      await setNativeAppIcon(AppIconMode.day);
      messenger.setMockMethodCallHandler(appIconChannel, (call) async => throw PlatformException(code: 'rejected'));
      expect(() => setNativeAppIcon(AppIconMode.day), throwsA(isA<PlatformException>()));
    });
  });

  group('Settings app', () {
    Widget app(AppIconController icons) => MaterialApp(
      locale: const Locale('cs'),
      supportedLocales: const [Locale('cs'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: SettingsScreen(icons: icons)),
    );

    testWidgets('shows the title and five tiles; a tap selects, asks the system and stores', (tester) async {
      final sent = <AppIconMode>[];
      final store = MemoryAppIconStore();
      final icons = AppIconController(store: store, native: (m) async => sent.add(m));
      // A narrow phone: the five tiles and their names fit without overflow.
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(icons));
      expect(find.text(tr('cs', MessageKey.appIconTitle)), findsOneWidget);
      for (final m in AppIconMode.values) {
        expect(find.byKey(ValueKey('appIcon_${m.name}')), findsOneWidget);
      }
      expect(find.text('Západ slunce'), findsOneWidget);
      // Flutter tests run as Android: the note about the delayed change shows.
      expect(find.text(tr('cs', MessageKey.appIconLater)), findsOneWidget);
      bool selected(AppIconMode m) => tester
          .getSemantics(find.byKey(ValueKey('appIcon_${m.name}')))
          .flagsCollection
          .isSelected == Tristate.isTrue;
      expect(selected(AppIconMode.sunset), isTrue);
      expect(selected(AppIconMode.teal), isFalse);

      await tester.tap(find.byKey(const ValueKey('appIcon_teal')));
      await tester.pump();
      expect(icons.mode, AppIconMode.teal);
      expect(sent, [AppIconMode.teal]);
      expect(store.mode, AppIconMode.teal);
      expect(selected(AppIconMode.teal), isTrue);
      expect(selected(AppIconMode.sunset), isFalse);
    });

    testWidgets('a refused change leaves the previous tile selected', (tester) async {
      final store = MemoryAppIconStore();
      final icons = AppIconController(store: store, native: (m) async => throw PlatformException(code: 'rejected'));
      await tester.pumpWidget(app(icons));
      await tester.tap(find.byKey(const ValueKey('appIcon_night')));
      await tester.pump();
      expect(icons.mode, AppIconMode.sunset);
      expect(store.mode, AppIconMode.sunset);
    });

    testWidgets('iOS has no note under the tiles', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(app(AppIconController(store: MemoryAppIconStore(), native: (_) async {})));
      expect(find.text(tr('cs', MessageKey.appIconLater)), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  // The native projects are not built in CI (only by the release workflows), so their wiring is
  // checked as text: every mode has its icon and its switch on both platforms.
  group('native projects', () {
    String cap(String s) => s[0].toUpperCase() + s.substring(1);
    final modes = AppIconMode.values.map((m) => m.name).toList();

    test('Android: one launcher alias per mode, only sunset enabled, no launcher filter on the activity', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final activity = RegExp(r'<activity\s[\s\S]*?</activity>').firstMatch(manifest)!.group(0)!;
      expect(activity, isNot(contains('android.intent.category.LAUNCHER')));
      final aliases = RegExp(r'<activity-alias\s[\s\S]*?</activity-alias>').allMatches(manifest).map((m) => m.group(0)!).toList();
      expect(aliases, hasLength(modes.length));
      for (final mode in modes) {
        final alias = aliases.singleWhere((a) => a.contains('android:name=".Icon${cap(mode)}"'));
        final icon = mode == 'sunset' ? 'ic_launcher' : 'ic_launcher_$mode';
        expect(alias, contains('android:targetActivity=".MainActivity"'));
        expect(alias, contains('android:icon="@mipmap/$icon"'));
        expect(alias, contains('android:enabled="${mode == 'sunset'}"'));
        expect(alias, contains('android.intent.action.MAIN'));
        expect(alias, contains('android.intent.category.LAUNCHER'));
        const res = 'android/app/src/main/res';
        expect(File('$res/mipmap-anydpi-v26/$icon.xml').existsSync(), isTrue);
        for (final dpi in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
          expect(File('$res/mipmap-$dpi/$icon.png').existsSync(), isTrue);
          expect(File('$res/mipmap-$dpi/${icon}_background.png').existsSync(), isTrue);
          expect(File('$res/mipmap-$dpi/ic_launcher_foreground.png').existsSync(), isTrue);
        }
      }
      final kotlin = File('android/app/src/main/kotlin/com/ol1n/metropole/MainActivity.kt').readAsStringSync();
      expect(kotlin, contains('"${appIconChannel.name}"'));
      expect(kotlin, contains('listOf(${modes.map((m) => '"$m"').join(', ')})'));
      // Development builds keep a launcher filter on the activity for `flutter run`.
      for (final type in ['debug', 'profile']) {
        expect(File('android/app/src/$type/AndroidManifest.xml').readAsStringSync(), contains('android.intent.category.LAUNCHER'));
      }
    });

    test('iOS: sunset is the primary icon, the other modes are alternate icon sets', () {
      const assets = 'ios/Runner/Assets.xcassets';
      final alternates = modes.where((m) => m != 'sunset').map((m) => 'AppIcon-$m').toList();
      final project = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      final setting = 'ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES = "${alternates.join(' ')}";';
      expect(setting.allMatches(project), hasLength('ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;'.allMatches(project).length));
      expect(File('$assets/AppIcon.appiconset/Contents.json').existsSync(), isTrue);
      for (final name in alternates) {
        expect(File('$assets/$name.appiconset/Contents.json').readAsStringSync(), contains('"$name-1024.png"'));
        expect(File('$assets/$name.appiconset/$name-1024.png').existsSync(), isTrue);
      }
      final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      expect(swift, contains('"${appIconChannel.name}"'));
      expect(swift, contains('[${modes.map((m) => '"$m"').join(', ')}]'));
      expect(swift, contains(r'"AppIcon-\(mode)"'));
      expect(swift, contains('setAlternateIconName'));
    });
  });
}
