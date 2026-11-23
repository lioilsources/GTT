import 'package:drive_core/drive_core.dart';
import 'package:flutter/material.dart';

import '../game/metropole_game.dart';
import '../l10n/app_localizations.dart';
import 'package:shared_gen/shared_gen.dart';

/// Street · district on top, speed bottom-left, FPS overlay, day/night and tuning buttons.
class Hud extends StatelessWidget {
  const Hud({
    super.key,
    required this.game,
    required this.scheme,
    required this.onNight,
    required this.onTuning,
    this.onPhone,
    this.onPassport,
    this.onCarAction,
    this.onHop,
    this.onToRoad,
  });

  final MetropoleGame game;
  final ControlSchemeId scheme;
  final VoidCallback onNight;
  final VoidCallback onTuning;
  final VoidCallback? onPhone;
  final VoidCallback? onPassport;

  /// The context button next to a parked car or in the garage (specs/cars.md).
  final void Function(CarAction action)? onCarAction;

  /// The "Hop" button of a car with an air tank (specs/hop.md "Ovládání").
  final VoidCallback? onHop;

  /// "Na silnici" after `flow.rescue.button_after_s` of slow driving (specs/flow.md "Ručně").
  final VoidCallback? onToRoad;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return IgnorePointer(
      ignoring: false,
      child: SafeArea(
        child: ValueListenableBuilder<HudState>(
          valueListenable: game.hud,
          builder: (context, s, _) {
            final street = s.street.isEmpty ? l.unnamedRoad : s.street;
            final tag = s.layer > 0
                ? ' · ${l.bridgeTag}'
                : s.layer < 0
                ? ' · ${l.tunnelTag}'
                : '';
            final stuckOver = s.stuck10 > game.tuning.flow.stuckLimitPer10min;
            final speed = game.city.imperial
                ? l.speedMph((s.speedMps * 2.23694).round())
                : l.speedKmh((s.speedMps * 3.6).round());
            return Stack(
              children: [
                Positioned(
                  top: 8,
                  left: 12,
                  right: 12,
                  child: IgnorePointer(
                    child: Center(
                      child: _Pill(
                        child: Text(
                          [street + tag, ?s.district].join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(Tokens.colorUiText),
                            fontSize: Tokens.fontHud,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (s.nearBorder)
                  Positioned(
                    top: 56,
                    left: 24,
                    right: 24,
                    child: IgnorePointer(
                      child: Center(
                        child: _Pill(
                          color: const Color(Tokens.colorUiNotice),
                          child: Text(
                            l.borderNotice,
                            style: const TextStyle(color: Color(Tokens.colorUiText), fontSize: Tokens.fontNotice),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (s.carName.isNotEmpty)
                  Positioned(
                    left: 12,
                    bottom: 60,
                    child: IgnorePointer(
                      child: _Pill(
                        child: Text(
                          s.carName,
                          style: const TextStyle(
                            color: Color(Tokens.colorUiText),
                            fontSize: Tokens.fontHudSmall,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (s.carAction case final action?)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 96,
                    child: Center(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(Tokens.colorBrandAccent),
                          foregroundColor: const Color(Tokens.colorUiBackground),
                        ),
                        onPressed: () => onCarAction?.call(action),
                        child: Text(action == CarAction.board ? l.boardCar : l.garage),
                      ),
                    ),
                  ),
                if (s.flowButton && onToRoad != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 148,
                    child: Center(
                      child: FilledButton(
                        key: const ValueKey('flowToRoad'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(Tokens.colorUiPill),
                          foregroundColor: const Color(Tokens.colorUiText),
                        ),
                        onPressed: onToRoad,
                        child: Text(l.flowToRoad),
                      ),
                    ),
                  ),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: IgnorePointer(
                    child: _Pill(
                      child: Text(
                        speed,
                        style: const TextStyle(
                          color: Color(Tokens.colorUiText),
                          fontSize: Tokens.fontSpeed,
                          fontWeight: FontWeight.w800,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 52,
                  child: IgnorePointer(
                    child: Text(
                      '${s.fps.toStringAsFixed(0)} fps  ${s.frameMs.toStringAsFixed(1)} ms\n'
                      'bld ${s.buildings}  prep ${s.prepMs.toStringAsFixed(2)} ms\n'
                      'chunks ${s.chunks}  ${scheme.name.toUpperCase()}\n'
                      // Stuck events in the last 10 minutes of driving (specs/flow.md "Měření zaseknutí").
                      '${l.flowStuck10(s.stuck10)}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: s.fps >= 57 && !stuckOver
                            ? const Color(Tokens.colorUiFpsOk)
                            : const Color(Tokens.colorUiFpsBad),
                        fontSize: Tokens.fontHudSmall,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        shadows: const [Shadow(blurRadius: 2)],
                      ),
                    ),
                  ),
                ),
                if (s.hopFull case final full?)
                  Positioned(
                    right: 8,
                    bottom: 80,
                    child: _HopButton(
                      label: l.hopButton,
                      empty: l.hopEmpty,
                      charges: s.hopCharges,
                      full: full,
                      onTap: s.hopReady ? onHop : null,
                    ),
                  ),
                if (onPassport != null)
                  Positioned(
                    right: 8,
                    bottom: 24,
                    child: _RoundButton(icon: Icons.menu_book, tooltip: l.passport, onTap: onPassport!),
                  ),
                Positioned(
                  right: 8,
                  top: 4,
                  child: Row(
                    children: [
                      if (onPhone != null) ...[
                        _RoundButton(icon: Icons.smartphone, tooltip: l.phone, onTap: onPhone!),
                        const SizedBox(width: 6),
                      ],
                      _RoundButton(icon: Icons.brightness_4, tooltip: l.dayNight, onTap: onNight),
                      const SizedBox(width: 6),
                      _RoundButton(icon: Icons.tune, tooltip: l.debugPanel, onTap: onTuning),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child, this.color = const Color(Tokens.colorUiPill)});
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(Tokens.radiusPill)),
    child: child,
  );
}

/// "Hop" with the air tank as one pip per charge; greyed (null [onTap]) when a hop cannot start.
class _HopButton extends StatelessWidget {
  const _HopButton({
    required this.label,
    required this.empty,
    required this.charges,
    required this.full,
    required this.onTap,
  });
  final String label;
  final String empty;
  final int charges;
  final int full;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    final fg = Color(on ? Tokens.colorUiText : Tokens.colorUiTextFaint);
    return Tooltip(
      message: charges == 0 ? empty : '$label $charges/$full',
      child: Material(
        key: const ValueKey('hopButton'),
        color: Color(on ? Tokens.colorBrandAccent : Tokens.colorUiPill),
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
        child: InkWell(
          borderRadius: BorderRadius.circular(Tokens.radiusPill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(color: fg, fontSize: Tokens.fontHudSmall, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < full; i++)
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(i < charges ? Tokens.colorUiText : Tokens.colorUiTextFaint),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: const Color(Tokens.colorUiPill),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: const Color(Tokens.colorUiText), size: 20),
        ),
      ),
    ),
  );
}
