import 'package:shared_gen/shared_gen.dart';

import 'controls.dart';

/// What [BoostHint.step] asks the client to do.
enum BoostHintEvent { show, used }

/// The boost hint (specs/controls.md v2 "Nápověda boostu"): a toast on the first drive and again
/// after a stretch of cruise without boost, at most `boost_hint_max` times per device. Pure logic;
/// [shown] is what the client persists.
class BoostHint {
  BoostHint(this.tuning, this.shown);

  final TuningControls tuning;
  int shown;
  double _cruise = 0;

  /// One frame of game time (0 while paused).
  BoostHintEvent? step(double dt, double speed, bool boost) {
    final max = tuning.boostHintMax;
    if (boost) {
      if (shown >= max) return null;
      shown = max;
      return BoostHintEvent.used;
    }
    if (shown >= max || dt <= 0) return null;
    if (shown > 0) {
      if (speed.abs() >= tuning.boostHintMinSpeedMps) _cruise += dt;
      if (_cruise < tuning.boostHintAfterS) return null;
    }
    shown += 1;
    _cruise = 0;
    return BoostHintEvent.show;
  }

  /// The hint text for the active scheme; [keyboard] = a desktop platform.
  static MessageKey textFor(ControlSchemeId scheme, {required bool keyboard}) {
    if (keyboard) return MessageKey.boostHintKeys;
    return switch (scheme) {
      ControlSchemeId.a => MessageKey.boostHintA,
      ControlSchemeId.b => MessageKey.boostHintB,
      ControlSchemeId.c => MessageKey.boostHintC,
    };
  }
}
