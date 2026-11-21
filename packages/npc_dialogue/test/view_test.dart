import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:npc_dialogue/npc_dialogue.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules_test.dart' show loadPack, loadTuning;

void main() {
  testWidgets('plays a skit through the dialogue view', (tester) async {
    final s = DialogueSession(loadPack(), loadTuning().npc, 'nyc', 3);
    expect(s.startSkit('maya', 'street'), isTrue);
    var closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DialogueView(session: s, locale: 'en', onClose: () => closed++),
      ),
    );
    expect(find.text(s.beat!.npc.en), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text(s.beat!.replies.flirt.en));
      await tester.pump();
    }
    expect(s.result()!.completed, isTrue);
    await tester.tap(find.text(tr('en', MessageKey.npcDone)));
    expect(closed, 1);
  });
}
