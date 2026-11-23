import 'dart:async';
import 'dart:io';

import 'package:drive_core/drive_core.dart';
import 'package:path_provider/path_provider.dart';

/// The debug build's local stuck log (specs/flow.md "Měření zaseknutí"): one JSON line per stuck
/// event appended to `stuck.log` in the app documents directory. Nothing is sent anywhere;
/// `metro stuckmap <city> <stuck.log>` reads the file.
class StuckLogFile {
  StuckLogFile(this.city, [Future<Directory> Function()? dir]) : _dir = dir ?? getApplicationDocumentsDirectory;

  final String city;
  final Future<Directory> Function() _dir;
  Future<void> _last = Future.value();

  /// Appends [e] (writes run one after another, in event order).
  Future<void> append(StuckEvent e) {
    final line = '${stuckLine(DateTime.now().millisecondsSinceEpoch / 1000, city, e)}\n';
    return _last = _last.then((_) async {
      try {
        final d = await _dir();
        await File('${d.path}/stuck.log').writeAsString(line, mode: FileMode.append, flush: true);
      } catch (_) {
        // No documents directory (tests, a sandbox): the log is a debug aid only.
      }
    });
  }
}
