import 'dart:convert';

import 'prng.dart';

/// Replays one vector case and returns the state after each step.
typedef Replayer = List<Map<String, Object?>> Function(Map<String, Object?> testCase);

/// Modules this client can replay; keys are vector module ids.
final Map<String, Replayer> replayers = {
  'prng': (c) {
    final r = Prng(c['seed'] as int);
    return [
      for (final s in (c['steps'] as List).cast<Map<String, Object?>>())
        () {
          final a = s['action'] as Map<String, Object?>;
          final Object value = switch (a['op']) {
            'nextU32' => r.nextU32(),
            'nextInt' => r.nextInt(a['n'] as int),
            'shuffle' => r.shuffle([...(a['items'] as List).cast<int>()]),
            _ => throw FormatException('prng: unknown op ${a['op']}'),
          };
          return <String, Object?>{'value': value, 'x': r.state};
        }(),
    ];
  },
};

/// Canonical JSON (sorted keys) so state comparison never depends on map order.
String canonical(Object? v) {
  if (v is List) return '[${v.map(canonical).join(',')}]';
  if (v is Map) {
    final keys = v.keys.cast<String>().toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${canonical(v[k])}').join(',')}}';
  }
  return jsonEncode(v);
}
