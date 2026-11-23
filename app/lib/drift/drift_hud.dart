import 'package:flutter/material.dart';
import 'package:shared_gen/shared_gen.dart';

import '../minigames/world_hud.dart';
import 'drift_controller.dart';

/// Drift HUD (specs/minigames/drift.md "HUD"): time left (`driftTime`), score (`driftScore`), the live
/// chain with its multiplier (`driftChain`, or `driftOutside` out of the ring), the banked flash
/// (`driftBank`) and the end button (= give up).
class DriftHud extends StatelessWidget {
  const DriftHud({super.key, required this.drift});
  final DriftController drift;

  @override
  Widget build(BuildContext context) {
    final loc = worldLocale(context);
    String t(MessageKey k, [Map<String, Object> a = const {}]) => tr(loc, k, a);
    return SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([drift, drift.flash]),
        builder: (context, _) {
          final s = drift.session;
          final bank = drift.flash.value;
          return Stack(
            children: [
              if (s != null)
                WorldHudRow(
                  endLabel: t(MessageKey.driftEnd),
                  onEnd: drift.quit,
                  pills: [
                    WorldPill(
                      text: t(MessageKey.driftTime, {'time': worldClock(s.left)}),
                      color: s.left <= drift.t.lowS ? Tokens.colorDriftLow : Tokens.colorUiPill,
                    ),
                    WorldPill(text: t(MessageKey.driftScore, {'score': s.state.score}), color: Tokens.colorUiPill),
                    WorldPill(
                      text: s.inZone
                          ? t(MessageKey.driftChain, {'points': s.state.chain, 'mult': s.state.mult})
                          : t(MessageKey.driftOutside),
                      color: Tokens.colorUiPill,
                      textColor: s.inZone ? Tokens.colorDriftChain : Tokens.colorDriftLow,
                    ),
                  ],
                ),
              if (bank != null)
                WorldFlash(text: t(MessageKey.driftBank, {'points': bank}), color: Tokens.colorDriftBank),
            ],
          );
        },
      ),
    );
  }
}
