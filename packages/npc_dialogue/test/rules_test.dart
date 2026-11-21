import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:npc_dialogue/npc_dialogue.dart';
import 'package:rules_core/rules_core.dart';
import 'package:rules_core/vector_test_support.dart';
import 'package:shared_gen/shared_gen.dart';
import 'package:yaml/yaml.dart';

const cfg = {
  'city': 'nyc',
  'recentK': 2,
  'vibeMax': 10,
  'vibeStart': 0,
  'contactMinVibe': 4,
  'contactBasePct': 30,
  'contactStepPct': 20,
  'contactMaxPct': 90,
  'characters': [
    {
      'id': 'a',
      'tones': {'flirt': 3, 'joke': 1, 'dry': -2},
    },
  ],
  'skits': [
    {'id': 'a_street_1', 'character': 'a', 'context': 'street', 'city': '', 'beats': 2},
    {'id': 'a_street_2', 'character': 'a', 'context': 'street', 'city': 'prg', 'beats': 2},
  ],
};

// Shared with web/test/dialogue.test.ts (same Prng, same expectation).
const quip2 = [1, 0, 1, 0, 0];

Object? _plain(Object? v) => jsonDecode(jsonEncode(v));

NpcPack loadPack() {
  final chars = loadYaml(File('$repoRoot/content/npc/characters.yaml').readAsStringSync()) as YamlMap;
  final skits = Directory('$repoRoot/content/npc/skits')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.yaml'))
      .map((f) => _plain(loadYaml(f.readAsStringSync())))
      .toList();
  return NpcPack.fromJson({'characters': _plain(chars['characters']), 'skits': skits});
}

Tuning loadTuning() => Tuning.fromYaml(File('$repoRoot/content/tuning.yaml').readAsStringSync());

void main() {
  test('starts idle with vibeStart for every character', () {
    final r = DialogueRules();
    final s = r.init(cfg, 1);
    expect(s.skit, '');
    expect(s.vibe, {'a': 0});
    expect(r.legalActions(s).map((a) => a.toJson()), [
      {'by': 'player', 'type': 'start', 'character': 'a', 'context': 'street'},
    ]);
    expect(r.result(s), isNull);
  });

  test('filters the pool by city and rejects illegal actions', () {
    final r = DialogueRules();
    final s = r.init(cfg, 1);
    expect(r.candidates('a', 'street'), ['a_street_1']);
    expect(() => r.apply(s, const DialogueAction.start('a', 'bar')), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const DialogueAction.reply('joke')), throwsA(isA<IllegalAction>()));
    expect(() => r.apply(s, const DialogueAction.leave()), throwsA(isA<IllegalAction>()));
    final run = r.apply(s, const DialogueAction.start('a', 'street'));
    expect(() => r.apply(run, const DialogueAction.start('a', 'street')), throwsA(isA<IllegalAction>()));
    expect(r.legalActions(run).map((a) => a.tone ?? a.type), ['flirt', 'joke', 'dry', 'leave']);
  });

  test('clamps vibe and counts only the real change', () {
    final r = DialogueRules();
    var s = r.apply(r.init(cfg, 1), const DialogueAction.start('a', 'street'));
    s = r.apply(s, const DialogueAction.reply('dry'));
    expect(s.vibe['a'], 0);
    expect(s.gained, 0);
    s = r.apply(s, const DialogueAction.reply('flirt'));
    expect(r.result(s)!.toJson(), {
      'skit': 'a_street_1',
      'character': 'a',
      'completed': true,
      'gained': 3,
      'vibe': 3,
      'contact': false,
      'newContact': false,
    });
  });

  test('picks quips with Prng(seed)', () {
    expect([1, 2, 3, 42, 1000].map((s) => quipIndex(2, s)), quip2);
    expect([quipOutcome('player'), quipOutcome('ai'), quipOutcome('draw')], ['win', 'lose', 'draw']);
  });

  test('rules and session stay pure Dart', () {
    for (final f in ['lib/src/rules.dart', 'lib/src/session.dart']) {
      final src = File(f).readAsStringSync();
      expect(src.contains('package:flutter'), isFalse, reason: f);
      expect(src.contains('dart:ui'), isFalse, reason: f);
    }
  });

  group('content', () {
    final pack = loadPack();
    final tuning = loadTuning();

    test('6 adult characters, 30 skits of 5 beats', () {
      expect(pack.characters, hasLength(6));
      expect(pack.characters.every((c) => c.age >= 21), isTrue);
      expect(pack.skits, hasLength(30));
      expect(pack.skits.every((s) => s.beats.length == 5), isTrue);
    });

    test('plays every skit to the end in a session', () {
      final s = DialogueSession(pack, tuning.npc, 'nyc', 7);
      var played = 0;
      for (final c in pack.characters) {
        for (final x in ['street', 'minigame_win', 'minigame_lose']) {
          expect(s.canStart(c.id, x), isTrue, reason: '${c.id} $x');
        }
        for (final x in npcContexts) {
          for (var k = 0; k < s.rules.candidates(c.id, x).length; k++) {
            expect(s.startSkit(c.id, x), isTrue);
            var i = 0;
            while (s.beat != null) {
              s.reply(tones[i++ % 3]);
            }
            expect(s.result()!.completed, isTrue);
            played++;
          }
        }
      }
      expect(played, 30);
    });

    test('opponent line in both locales', () {
      final maya = pack.characters.firstWhere((c) => c.id == 'maya');
      expect(initials(maya.name), 'M');
      final s = DialogueSession(pack, tuning.npc, 'nyc', 1);
      expect(s.quip('maya', 'player', 42, 'en'), maya.quips.win[quipIndex(maya.quips.win.length, 42)].en);
      expect(opponentFor(s, 'maya', 42, 'cs')!.line('draw'), maya.quips.draw.first.cs);
      expect(opponentFor(s, 'nobody', 42, 'cs'), isNull);
    });
  });

  final vectors = File('$repoRoot/vectors/dialogue.json').existsSync();
  test(
    'vectors/dialogue.json',
    () => expect(checkVectors(DialogueRules()), isEmpty),
    skip: !vectors || !flutterDone('vectors/dialogue.json') ? 'pending in parity.yaml' : false,
  );
}
