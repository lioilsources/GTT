import 'package:drive_core/drive_core.dart';
import 'package:flutter/material.dart';

import '../game/metropole_game.dart';
import '../l10n/app_localizations.dart';

/// Street · district on top, speed bottom-left, FPS overlay, day/night and tuning buttons.
class Hud extends StatelessWidget {
  const Hud({super.key, required this.game, required this.scheme, required this.onNight, required this.onTuning});

  final MetropoleGame game;
  final ControlSchemeId scheme;
  final VoidCallback onNight;
  final VoidCallback onTuning;

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
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
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
                          color: const Color(0xDDFF7A00),
                          child: Text(l.borderNotice, style: const TextStyle(color: Colors.white, fontSize: 14)),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: IgnorePointer(
                    child: _Pill(
                      child: Text(speed,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              fontFeatures: [FontFeature.tabularFigures()])),
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
                      'chunks ${s.chunks}  ${scheme.name.toUpperCase()}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: s.fps >= 57 ? const Color(0xFF9CFF9C) : const Color(0xFFFF9C9C),
                        fontSize: 10,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        shadows: const [Shadow(blurRadius: 2)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 4,
                  child: Row(
                    children: [
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
  const _Pill({required this.child, this.color = const Color(0xAA15151B)});
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: child,
      );
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
          color: const Color(0xAA15151B),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(8), child: Icon(icon, color: Colors.white, size: 20)),
          ),
        ),
      );
}
