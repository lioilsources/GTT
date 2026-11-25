import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Flutter asset folders are not recursive: every art folder the client reads (specs/art.md:
/// cars, postcards, souvenirs, npc, ui, garage) has to be listed in pubspec.yaml, or the app shows
/// the placeholder although the art exists.
void main() {
  test('pubspec.yaml bundles every art folder the client reads', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync().map((l) => l.trim()).toSet();
    final missing = <String>[];
    void check(Directory d, String rel) {
      final entries = d.listSync();
      if (entries.any((f) => f is File && f.path.endsWith('.png')) && !pubspec.contains('- assets/shared/assets/$rel/')) {
        missing.add(rel);
      }
      for (final sub in entries.whereType<Directory>()) {
        check(sub, '$rel/${sub.uri.pathSegments.lastWhere((s) => s.isNotEmpty)}');
      }
    }

    // ui/app_icon is the launcher icon source, not read at run time.
    for (final root in ['cars', 'postcards', 'souvenirs', 'npc', 'garage']) {
      final d = Directory('../assets/$root');
      if (d.existsSync()) check(d, root);
    }
    expect(missing, isEmpty, reason: 'art folders missing in app/pubspec.yaml');
  });
}
