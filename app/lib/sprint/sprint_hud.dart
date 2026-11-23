import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_gen/shared_gen.dart';

import '../minigames/world_hud.dart';
import 'sprint_controller.dart';

/// Sprint HUD (specs/minigames/sprint.md "HUD"): race time (`sprintTime`), par (`sprintPar`), gate
/// n/total (`sprintCp`), the destination, countdown and split line, and the end button (= give up).
/// The navigation pill leads to the next gate.
class SprintHud extends StatelessWidget {
  const SprintHud({super.key, required this.sprint});
  final SprintController sprint;

  @override
  Widget build(BuildContext context) {
    final loc = sprint.locale = worldLocale(context);
    String t(MessageKey k, [Map<String, Object> a = const {}]) => tr(loc, k, a);
    return SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([sprint, sprint.line]),
        builder: (context, _) {
          final r = sprint.race;
          final line = sprint.line.value;
          return Stack(
            children: [
              if (r != null)
                WorldHudRow(
                  endLabel: t(MessageKey.sprintEnd),
                  onEnd: sprint.quit,
                  pills: [
                    WorldPill(
                      text: t(MessageKey.sprintTime, {'time': worldClock(math.max(0, r.raceS))}),
                      color: Tokens.colorUiPill,
                    ),
                    WorldPill(
                      text: t(MessageKey.sprintPar, {'time': worldClock(r.state.parMs / 1000)}),
                      color: Tokens.colorUiPill,
                    ),
                    WorldPill(
                      text: t(MessageKey.sprintCp, {'n': r.state.passed, 'total': r.state.cps}),
                      color: Tokens.colorUiPill,
                    ),
                  ],
                ),
              if (line != null)
                WorldFlash(
                  text: line.text,
                  color: switch (line.good) {
                    true => Tokens.colorSprintAhead,
                    false => Tokens.colorSprintBehind,
                    null => Tokens.colorUiText,
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
