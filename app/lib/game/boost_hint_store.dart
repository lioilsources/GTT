import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// How many times the boost hint showed on this device (specs/controls.md v2 "Nápověda boostu"):
/// a device setting outside the save, F: `boost_hint.json` (`{"shown": n}`) in the documents dir.
abstract class BoostHintStore {
  /// The count; 0 when there is none or it cannot be read.
  Future<int> read();
  Future<void> write(int shown);
}

/// The count in a `boost_hint.json` text; 0 for anything else.
int parseBoostHint(String text) {
  try {
    final j = jsonDecode(text);
    final n = j is Map ? j['shown'] : null;
    return n is int && n > 0 ? n : 0;
  } catch (_) {
    return 0;
  }
}

class FileBoostHintStore implements BoostHintStore {
  FileBoostHintStore([Future<Directory> Function()? dir]) : _dir = dir ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _dir;

  Future<File> _file() async => File('${(await _dir()).path}/boost_hint.json');

  @override
  Future<int> read() async {
    try {
      final f = await _file();
      if (!await f.exists()) return 0;
      return parseBoostHint(await f.readAsString());
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<void> write(int shown) async {
    try {
      final f = await _file();
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode({'shown': shown}), flush: true);
      await tmp.rename(f.path);
    } catch (_) {}
  }
}

/// In-memory store for tests.
class MemoryBoostHintStore implements BoostHintStore {
  int shown = 0;

  @override
  Future<int> read() async => shown;

  @override
  Future<void> write(int n) async => shown = n;
}
