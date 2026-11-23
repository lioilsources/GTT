import 'dart:io';

import 'package:drive_core/drive_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:world_engine/core.dart';

// specs/controls.md v2: Boost in schemes B and C, the boost hint.
final tuning = Tuning.fromYaml(File('../../content/tuning.yaml').readAsStringSync());
final t = tuning.controls;
const w = 400.0, h = 860.0;

ScreenPt centre(ScreenRect r) => (x: r.left + r.width / 2, y: r.top + r.height / 2);

ControlInput read(ControlScheme s) {
  final out = ControlInput();
  s.update(out);
  return out;
}

void main() {
  group('scheme B boost', () {
    test('the Boost button boosts and steers nothing; a second thumb still steers', () {
      final b = ControlScheme.create(ControlSchemeId.b, t);
      b.down(1, centre(SchemeB.boostButton(w, h)), w, h);
      var o = read(b);
      expect(o.boost, isTrue);
      expect(o.steer, 0);
      expect(o.brake, 0);
      b.down(2, (x: w * 0.9, y: h * 0.5), w, h);
      o = read(b);
      expect(o.boost, isTrue);
      expect(o.steer, 1);
      b.up(1);
      o = read(b);
      expect(o.boost, isFalse);
      expect(o.steer, 1);
    });
    test('a steering finger sliding over the button keeps steering', () {
      final b = ControlScheme.create(ControlSchemeId.b, t);
      b.down(1, (x: w * 0.1, y: h * 0.8), w, h);
      b.move(1, centre(SchemeB.boostButton(w, h)), w, h);
      final o = read(b);
      expect(o.boost, isFalse);
      expect(o.steer, -1);
    });
  });

  group('scheme C boost', () {
    test('the Boost button above the pedal boosts, the wheel still steers', () {
      final c = ControlScheme.create(ControlSchemeId.c, t) as SchemeC;
      c.down(1, centre(SchemeC.boostButton(w, h)), w, h);
      expect(c.boostHeld, isTrue);
      var o = read(c);
      expect(o.boost, isTrue);
      expect(o.brake, 0);
      final ctr = SchemeC.wheelCentre(w, h), r = SchemeC.wheelRadius(w);
      c.down(2, (x: ctr.x, y: ctr.y - r), w, h);
      c.move(2, (x: ctr.x + r, y: ctr.y), w, h);
      o = read(c);
      expect(o.boost, isTrue);
      expect(o.steer, greaterThan(0.5));
      c.up(1);
      expect(read(c).boost, isFalse);
    });
    test('the brake pedal is not boost', () {
      final c = ControlScheme.create(ControlSchemeId.c, t);
      c.down(1, centre(SchemeC.pedal(w, h)), w, h);
      final o = read(c);
      expect(o.brake, 1);
      expect(o.boost, isFalse);
    });
  });

  group('boost hint', () {
    test('shows on the first drive, again after cruise without boost, at most max times', () {
      final hint = BoostHint(t, 0);
      expect(hint.step(0, 0, false), isNull); // paused
      expect(hint.step(1 / 60, 0, false), BoostHintEvent.show);
      expect(hint.shown, 1);
      for (var i = 0; i < 100; i++) {
        expect(hint.step(1, t.boostHintMinSpeedMps - 1, false), isNull);
      }
      var shows = 1;
      for (var i = 0; i < 1000; i++) {
        if (hint.step(1, 14, false) == BoostHintEvent.show) shows++;
      }
      expect(shows, t.boostHintMax);
      expect(hint.shown, t.boostHintMax);
    });
    test('the second show waits boost_hint_after_s of cruise', () {
      final hint = BoostHint(t, 1);
      final n = t.boostHintAfterS.ceil();
      for (var i = 0; i < n - 1; i++) {
        expect(hint.step(1, 14, false), isNull);
      }
      expect(hint.step(1, 14, false), BoostHintEvent.show);
    });
    test('using boost stops the hint for good', () {
      final hint = BoostHint(t, 0);
      expect(hint.step(1 / 60, 0, true), BoostHintEvent.used);
      expect(hint.shown, t.boostHintMax);
      expect(hint.step(1 / 60, 30, true), isNull);
      for (var i = 0; i < 1000; i++) {
        expect(hint.step(1, 14, false), isNull);
      }
    });
    test('a restart with the stored count does not show it again right away', () {
      final first = BoostHint(t, 0);
      expect(first.step(1 / 60, 0, false), BoostHintEvent.show);
      final next = BoostHint(t, first.shown);
      expect(next.step(1 / 60, 0, false), isNull);
    });
    test('text follows the scheme, keyboard wins', () {
      expect(BoostHint.textFor(ControlSchemeId.a, keyboard: false), MessageKey.boostHintA);
      expect(BoostHint.textFor(ControlSchemeId.b, keyboard: false), MessageKey.boostHintB);
      expect(BoostHint.textFor(ControlSchemeId.c, keyboard: false), MessageKey.boostHintC);
      expect(BoostHint.textFor(ControlSchemeId.b, keyboard: true), MessageKey.boostHintKeys);
    });
  });
}
