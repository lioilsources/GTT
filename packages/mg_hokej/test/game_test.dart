import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_hokej/mg_hokej.dart';
import 'package:shared_gen/shared_gen.dart';

void main() {
  testWidgets('the mallet follows the finger into the puck, give up reports aborted', (tester) async {
    final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
    final env = MinigameEnv(tuning: tuning, locale: 'en');
    MinigameResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: const HokejGame().build(
          MinigameContext(cityId: 'nyc', difficulty: 1, seed: 1, locale: 'en'),
          env,
          (r) => result = r,
        ),
      ),
    );
    expect(find.text('Move your mallet with your finger and strike the puck.'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump();
    expect(find.text('0 : 0'), findsOneWidget);
    // Drive the mallet straight up through the face-off spot.
    final rink = find.byKey(const ValueKey('rink'));
    final c = tester.getCenter(rink);
    final g = await tester.startGesture(c + Offset(0, tester.getSize(rink).height * 0.4));
    for (var i = 0; i < 60; i++) {
      await g.moveTo(c + Offset(0, tester.getSize(rink).height * (0.4 - i * 0.01)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    await tester.tap(find.text('Give up'));
    await tester.pump();
    expect(result?.aborted, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
