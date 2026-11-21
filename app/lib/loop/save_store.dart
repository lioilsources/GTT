import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Save storage of client F (specs/save.md "Úložiště"): `save-<cityId>.json` in the app documents
/// directory, written through a temporary file and a rename.
abstract class SaveStore {
  /// The raw JSON value, or null when there is none or it cannot be read.
  Future<Object?> read(String cityId);
  Future<void> write(String cityId, Map<String, Object?> save);
}

class FileSaveStore implements SaveStore {
  FileSaveStore([Future<Directory> Function()? dir]) : _dir = dir ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _dir;
  Future<void> _last = Future.value();

  Future<File> _file(String cityId) async => File('${(await _dir()).path}/save-$cityId.json');

  @override
  Future<Object?> read(String cityId) async {
    try {
      final f = await _file(cityId);
      if (!await f.exists()) return null;
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String cityId, Map<String, Object?> save) {
    final text = jsonEncode(save);
    // Writes run one after another so an older snapshot never overwrites a newer one.
    return _last = _last
        .then((_) async {
          final f = await _file(cityId);
          final tmp = File('${f.path}.tmp');
          await tmp.writeAsString(text, flush: true);
          await tmp.rename(f.path);
        })
        .catchError((Object _) {});
  }
}

/// In-memory store for tests.
class MemorySaveStore implements SaveStore {
  final data = <String, String>{};

  @override
  Future<Object?> read(String cityId) async {
    final t = data[cityId];
    return t == null ? null : jsonDecode(t);
  }

  @override
  Future<void> write(String cityId, Map<String, Object?> save) async => data[cityId] = jsonEncode(save);
}
