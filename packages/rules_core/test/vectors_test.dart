import 'dart:convert';
import 'dart:io';

import 'package:rules_core/rules_core.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

final root = '../..';

void main() {
  final parity = loadYaml(File('$root/parity.yaml').readAsStringSync()) as YamlList;
  // Vectors are replayed only for rows where Flutter is done (DUALSTACK 5.6).
  final done = {
    for (final r in parity.cast<YamlMap>())
      if (r['vectors'] != null && r['flutter'] == 'done') r['vectors'] as String,
  };

  for (final f in Directory('$root/vectors').listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
    final v = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
    final module = v['module'] as String;
    final replay = replayers[module];
    final name = 'vectors/${f.uri.pathSegments.last}';
    group(module, skip: !done.contains(name) || replay == null ? 'pending in parity.yaml' : null, () {
      for (final c in (v['cases'] as List).cast<Map<String, Object?>>()) {
        test(c['name'] as String, () {
          final states = replay!(c);
          final steps = (c['steps'] as List).cast<Map<String, Object?>>();
          for (var i = 0; i < steps.length; i++) {
            expect(canonical(states[i]), canonical(steps[i]['state']), reason: 'step $i');
          }
        });
      }
    });
  }

  test('plan reference values', () {
    final r = Prng(1);
    expect([for (var i = 0; i < 5; i++) r.nextU32()], [270369, 67634689, 2647435461, 307599695, 2398689233]);
    expect(Prng(1).shuffle(List.generate(10, (i) => i)), [3, 1, 0, 2, 6, 7, 8, 5, 4, 9]);
    final d = Prng(42);
    expect([for (var i = 0; i < 8; i++) d.nextInt(6) + 1], [1, 5, 4, 3, 1, 1, 1, 5]);
  });
}
