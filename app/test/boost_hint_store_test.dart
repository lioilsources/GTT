import 'dart:io';

import 'package:drive_core/drive_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metropole/game/boost_hint_store.dart';
import 'package:world_engine/core.dart';

/// specs/controls.md v2 "Nápověda boostu": the count lives in boost_hint.json, so the hint shown
/// once does not show again on the next start (and never after max or after boost).
void main() {
  final t = Tuning.fromYaml(File('../content/tuning.yaml').readAsStringSync()).controls;

  test('shown once, then not again on the next start', () async {
    final dir = await Directory.systemTemp.createTemp('boost');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileBoostHintStore(() async => dir);
    expect(await store.read(), 0);
    final first = BoostHint(t, await store.read());
    expect(first.step(1 / 60, 0, false), BoostHintEvent.show);
    await store.write(first.shown);
    expect(File('${dir.path}/boost_hint.json').readAsStringSync(), '{"shown":1}');
    final next = BoostHint(t, await FileBoostHintStore(() async => dir).read());
    expect(next.shown, 1);
    expect(next.step(1 / 60, 0, false), isNull);
  });

  test('bad files and a missing directory count from 0', () async {
    expect(parseBoostHint('nope'), 0);
    expect(parseBoostHint('{"shown":-2}'), 0);
    expect(parseBoostHint('{"shown":2}'), 2);
    final none = FileBoostHintStore(() async => throw const FileSystemException('none'));
    expect(await none.read(), 0);
    await none.write(3);
  });
}
