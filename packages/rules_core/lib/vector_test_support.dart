/// Shared vector replay for minigame packages: `package:rules_core/vector_test_support.dart`.
library;

import 'dart:convert';
import 'dart:io';

import 'rules_core.dart';

/// Repo root seen from a package directory (tests run in `packages/<name>`).
const repoRoot = '../..';

/// True when parity.yaml marks [vectorsPath] as done for Flutter (DUALSTACK 5.6). A tiny line
/// scanner, so pure packages need no YAML dependency.
bool flutterDone(String vectorsPath, {String root = repoRoot}) {
  final lines = File('$root/parity.yaml').readAsLinesSync();
  var inRow = false;
  var hasVectors = false;
  var done = false;
  for (final l in [...lines, '- end']) {
    if (l.startsWith('- ')) {
      if (inRow && hasVectors && done) return true;
      inRow = true;
      hasVectors = false;
      done = false;
    }
    final t = l.replaceFirst('- ', '  ').trim();
    if (t == 'vectors: $vectorsPath') hasVectors = true;
    if (t == 'flutter: done') done = true;
  }
  return false;
}

/// Replays every case of `vectors/<module>.json`; returns mismatch messages (empty = pass).
List<String> checkVectors<S, A, R>(MgRules<S, A, R> rules, {String root = repoRoot}) {
  final v = jsonDecode(File('$root/vectors/${rules.id}.json').readAsStringSync()) as Map<String, Object?>;
  final errors = <String>[];
  if (v['specVersion'] != rules.specVersion) {
    errors.add('specVersion ${v['specVersion']} != ${rules.specVersion}');
  }
  for (final c in (v['cases'] as List).cast<Map<String, Object?>>()) {
    final got = replayCase(rules, c);
    final steps = (c['steps'] as List).cast<Map<String, Object?>>();
    for (var i = 0; i < steps.length; i++) {
      if (canonical(got.states[i]) != canonical(steps[i]['state'])) {
        errors.add('${c['name']} step $i: ${canonical(got.states[i])} != ${canonical(steps[i]['state'])}');
        break;
      }
    }
    if (canonical(got.result) != canonical(c['result'])) {
      errors.add('${c['name']} result: ${canonical(got.result)} != ${canonical(c['result'])}');
    }
  }
  return errors;
}
