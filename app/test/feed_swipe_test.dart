import 'dart:io';

import 'package:feed_hub/feed_hub.dart' hide Navigator;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metropole/phone/feed_screen.dart';
import 'package:shared_gen/shared_gen.dart';

/// Feed card gestures (specs/phone.md v5) on the [FeedPager] with plain test cards.
void main() {
  final tuning = Tuning.fromYaml(File('../content/tuning.yaml').readAsStringSync());
  final ph = tuning.phone;
  FeedCandidate cand(String spot) => FeedCandidate(
    spot: spot,
    game: 'dama',
    engine: 'board',
    local: false,
    district: '',
    distDm: 9000,
    visits: 0,
    landmark: false,
  );

  group('gesture maths', () {
    test('axis lock after feed_axis_lock_px by the larger component', () {
      final l = ph.feedAxisLockPx;
      expect(feedLockAxis(l - 1, -(l - 1), l), isNull);
      expect(feedLockAxis(3, -l, l), FeedAxis.vertical);
      expect(feedLockAxis(-l - 1, l, l), FeedAxis.horizontal);
    });

    test('release velocity over the last feed_velocity_ms', () {
      final w = ph.feedVelocityMs.toDouble();
      final s = [(t: 0.0, p: 0.0), (t: 1000 - w - 1, p: -500.0), (t: 1000 - w, p: -100.0), (t: 1000.0, p: -200.0)];
      expect(feedReleaseVelocity(s, ph.feedVelocityMs), closeTo(-100 * 1000 / w, 1e-9));
      expect(feedReleaseVelocity(const [], ph.feedVelocityMs), 0);
    });

    test('rubber band, vertical and sideways release, tilt and hint', () {
      const h = 800.0;
      expect(feedStripOffset(-120, false, true, ph), -120);
      expect(feedStripOffset(120, false, true, ph), closeTo(120 * ph.feedRubber, 1e-9));
      final far = h * ph.feedCommitPct / 100 + 1, near = far - 2;
      expect(feedVerticalRelease(-far, 0, h, true, true, ph), FeedOp.next);
      expect(feedVerticalRelease(far, 0, h, true, true, ph), FeedOp.prev);
      expect(feedVerticalRelease(-near, 0, h, true, true, ph), isNull);
      expect(feedVerticalRelease(-near, -ph.feedFlickPxS - 1, h, true, true, ph), FeedOp.next);
      expect(feedVerticalRelease(far, ph.feedFlickPxS + 1, h, false, true, ph), isNull);
      expect(feedSideRelease(ph.swipePx + 1, 0, ph), FeedOp.accept);
      expect(feedSideRelease(-ph.swipePx - 1, 0, ph), FeedOp.less);
      expect(feedSideRelease(ph.swipePx - 1, 0, ph), isNull);
      expect(feedSideRelease(5, -ph.feedFlickPxS - 1, ph), isNull);
      expect(feedTiltDeg(400, 400, ph), closeTo(ph.feedTiltDeg, 1e-9));
      expect(feedHintOpacity(ph.swipePx / 2, ph), closeTo(0.5, 1e-9));
      expect(feedHintOpacity(-3 * ph.swipePx, ph), 1);
    });
  });

  group('FeedPager', () {
    late FeedRules rules;
    late FeedState state;
    late List<FeedOp> ops;

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => FeedPager(
              state: state,
              tuning: ph,
              goLabel: 'GO',
              lessLabel: 'LESS',
              onAction: (op) {
                ops.add(op);
                setState(() => state = rules.apply(state, op));
              },
              card: (s, at) => ColoredBox(
                color: Colors.purple,
                child: Center(child: Text('card $at${s.liked.contains(s.deck[at].spot) ? ' liked' : ''}')),
              ),
              done: () => const Center(child: Text('done')),
            ),
          ),
        ),
      );
    }

    setUp(() {
      rules = FeedRules();
      state = rules.deal(
        FeedConfig.fromTuning(
          tuning.feed,
          [
            for (final s in ['a', 'b', 'c']) cand(s),
          ],
          {},
          [],
        ),
        4,
      );
      ops = [];
    });

    testWidgets('mid-drag shows the current and the next card, release past the threshold commits next', (
      tester,
    ) async {
      await pump(tester);
      final screen = tester.getRect(find.byType(FeedPager));
      expect(tester.getRect(find.text('card 1')).top, greaterThanOrEqualTo(screen.bottom));
      final g = await tester.startGesture(screen.center);
      await g.moveBy(const Offset(0, -20));
      await g.moveBy(const Offset(0, -180));
      await tester.pump();
      Rect page(String t) => tester.getRect(find.ancestor(of: find.text(t), matching: find.byType(ColoredBox)).first);
      final cur = page('card 0').intersect(screen), next = page('card 1').intersect(screen);
      // Both cards are on screen, the current one moved up 1:1 with the finger.
      expect(cur.height, closeTo(screen.height - 200, 0.5));
      expect(next.height, closeTo(200, 0.5));
      expect(next.top, closeTo(cur.bottom, 0.5));
      await g.moveBy(Offset(0, -screen.height * ph.feedCommitPct / 100));
      await g.up();
      await tester.pumpAndSettle();
      expect(ops, [FeedOp.next]);
      expect(state.at, 1);
      expect(screen.contains(tester.getRect(find.text('card 1')).center), isTrue);
    });

    testWidgets('drag down goes back (prev), but rubber-bands on the first card', (tester) async {
      await pump(tester);
      final screen = tester.getRect(find.byType(FeedPager));
      var g = await tester.startGesture(screen.center);
      await g.moveBy(const Offset(0, 20));
      await g.moveBy(const Offset(0, 300));
      await tester.pump();
      expect(tester.getRect(find.text('card 0')).center.dy - screen.center.dy, closeTo(320 * ph.feedRubber, 0.5));
      await g.up();
      await tester.pumpAndSettle();
      expect(ops, isEmpty);
      expect(tester.getRect(find.text('card 0')).center, screen.center);

      state = rules.apply(state, FeedOp.next);
      await pump(tester);
      await tester.pump();
      g = await tester.startGesture(screen.center);
      await g.moveBy(const Offset(0, 20));
      await g.moveBy(Offset(0, screen.height * ph.feedCommitPct / 100 + 10));
      await g.up();
      await tester.pumpAndSettle();
      expect(ops, [FeedOp.prev]);
      expect(state.at, 0);
    });

    testWidgets('sideways drag tilts with a hint; small moves spring back; past swipe_px = less', (tester) async {
      await pump(tester);
      final screen = tester.getRect(find.byType(FeedPager));
      var g = await tester.startGesture(screen.center);
      await g.moveBy(Offset(ph.swipePx / 2, 0));
      await tester.pump();
      final go = tester.widget<Opacity>(find.ancestor(of: find.text('GO'), matching: find.byType(Opacity)).first);
      expect(go.opacity, closeTo(0.5, 1e-6));
      await g.up();
      await tester.pumpAndSettle();
      expect(ops, isEmpty);

      g = await tester.startGesture(screen.center);
      await g.moveBy(Offset(-ph.swipePx - 20, 0));
      await g.up();
      await tester.pumpAndSettle();
      expect(ops, [FeedOp.less]);
      expect(state.at, 1);
    });

    testWidgets('double tap likes; the heart stays after going back', (tester) async {
      await pump(tester);
      final screen = tester.getRect(find.byType(FeedPager));
      await tester.tapAt(screen.center);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(screen.center);
      await tester.pump();
      expect(ops, [FeedOp.like]);
      expect(find.text('card 0 liked'), findsOneWidget);
    });
  });
}
