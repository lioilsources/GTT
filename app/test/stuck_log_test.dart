import 'dart:convert';
import 'dart:io';

import 'package:drive_core/drive_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metropole/game/stuck_log.dart';

/// specs/flow.md "Měření zaseknutí": the debug build appends one JSON line per stuck event.
void main() {
  test('stuck.log gets one line per event, in order', () async {
    final dir = await Directory.systemTemp.createTemp('stuck');
    addTearDown(() => dir.delete(recursive: true));
    final log = StuckLogFile('nyc', () async => dir);
    log.append(const StuckEvent(1, StuckKind.auto1, 1.24, 2));
    await log.append(const StuckEvent(2, StuckKind.button, -3, 4.06));
    final lines = File('${dir.path}/stuck.log').readAsLinesSync();
    expect(lines, hasLength(2));
    final a = jsonDecode(lines[0]) as Map, b = jsonDecode(lines[1]) as Map;
    expect([a['city'], a['x'], a['y'], a['kind']], ['nyc', 1.2, 2, 'auto1']);
    expect([b['x'], b['y'], b['kind']], [-3, 4.1, 'button']);
    expect(a['t'], isA<int>());
  });

  test('a missing documents directory is ignored', () async {
    final log = StuckLogFile('nyc', () async => throw const FileSystemException('none'));
    await log.append(const StuckEvent(1, StuckKind.road, 0, 0));
  });
}
