import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// App icon colour modes in picker order (specs/appicon.md v1 "Režimy"); `name` is the id.
enum AppIconMode { day, night, sunset, teal, japan }

const AppIconMode appIconDefault = AppIconMode.sunset;

/// The mode in an `app_icon.json` text (`{"mode": "<id>"}`); sunset for anything else.
AppIconMode parseAppIcon(String text) {
  try {
    final j = jsonDecode(text);
    final id = j is Map ? j['mode'] : null;
    return AppIconMode.values.firstWhere((m) => m.name == id, orElse: () => appIconDefault);
  } catch (_) {
    return appIconDefault;
  }
}

/// The chosen mode on this device: a device setting outside the save (specs/appicon.md "Uložení
/// volby"), F: `app_icon.json` in the documents dir.
abstract class AppIconStore {
  /// The mode; sunset when there is none or it cannot be read.
  Future<AppIconMode> read();
  Future<void> write(AppIconMode mode);
}

class FileAppIconStore implements AppIconStore {
  FileAppIconStore([Future<Directory> Function()? dir]) : _dir = dir ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _dir;

  Future<File> _file() async => File('${(await _dir()).path}/app_icon.json');

  @override
  Future<AppIconMode> read() async {
    try {
      final f = await _file();
      if (!await f.exists()) return appIconDefault;
      return parseAppIcon(await f.readAsString());
    } catch (_) {
      return appIconDefault;
    }
  }

  @override
  Future<void> write(AppIconMode mode) async {
    try {
      final f = await _file();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode({'mode': mode.name}), flush: true);
      await tmp.rename(f.path);
    } catch (_) {}
  }
}

/// In-memory store for tests.
class MemoryAppIconStore implements AppIconStore {
  MemoryAppIconStore([this.mode = appIconDefault]);
  AppIconMode mode;

  @override
  Future<AppIconMode> read() async => mode;

  @override
  Future<void> write(AppIconMode mode) async => this.mode = mode;
}

/// The native side (specs/appicon.md "Rozhraní F ↔ nativní část"): channel `metropole/app_icon`,
/// method `set` with the mode id. iOS switches the alternate icon at once (and shows its alert),
/// Android switches the launcher alias when the app goes to background.
const MethodChannel appIconChannel = MethodChannel('metropole/app_icon');

/// Asks the system for the icon of [mode]. Throws [PlatformException] when the system refuses;
/// without a native side (desktop, tests) it does nothing.
Future<void> setNativeAppIcon(AppIconMode mode) async {
  try {
    await appIconChannel.invokeMethod<bool>('set', mode.name);
  } on MissingPluginException {
    // No native side: the choice is only stored and shown in the picker.
  }
}

/// The current mode for the Settings app; [pick] changes it, asks the system and stores it.
class AppIconController extends ChangeNotifier {
  AppIconController({AppIconStore? store, Future<void> Function(AppIconMode mode)? native})
    : _store = store ?? FileAppIconStore(),
      _native = native ?? setNativeAppIcon;

  final AppIconStore _store;
  final Future<void> Function(AppIconMode mode) _native;
  bool _busy = false;

  AppIconMode get mode => _mode;
  AppIconMode _mode = appIconDefault;

  /// App start: reads the stored mode and sends it to the system again (the native side does
  /// nothing when that icon already shows).
  Future<void> load() async {
    _mode = await _store.read();
    notifyListeners();
    try {
      await _native(_mode);
    } catch (_) {
      // The icon stays as the system has it; the next pick tries again.
    }
  }

  /// Selects [mode]. False when it already is the current one, when another change is still in
  /// flight, or when the system refused (the selection then returns to the previous mode and
  /// nothing is stored).
  Future<bool> pick(AppIconMode mode) async {
    if (mode == _mode || _busy) return false;
    final previous = _mode;
    _busy = true;
    _mode = mode;
    notifyListeners();
    try {
      await _native(mode);
    } catch (_) {
      _mode = previous;
      _busy = false;
      notifyListeners();
      return false;
    }
    await _store.write(mode);
    _busy = false;
    return true;
  }
}
