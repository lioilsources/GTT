import 'package:drive_core/drive_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/metropole_game.dart';
import '../l10n/app_localizations.dart';

/// Live editor for tuning.yaml and the car parameters (M0 dogfooding).
/// Slider labels are the YAML keys on purpose: they are what gets pasted back into the repo.
void showTuningPanel(BuildContext context, MetropoleGame game, {required void Function(ControlSchemeId) onScheme}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xF01C1C22),
    barrierColor: Colors.transparent,
    builder: (_) => _TuningPanel(game: game, onScheme: onScheme),
  );
}

class _TuningPanel extends StatefulWidget {
  const _TuningPanel({required this.game, required this.onScheme});
  final MetropoleGame game;
  final void Function(ControlSchemeId) onScheme;

  @override
  State<_TuningPanel> createState() => _TuningPanelState();
}

class _TuningPanelState extends State<_TuningPanel> {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final g = widget.game;
    final t = g.tuning;
    final c = g.data.car;
    Widget slider(String key, double v, double min, double max, void Function(double) set, {int digits = 2}) {
      return Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(key, style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace')),
          ),
          Expanded(
            child: Slider(
              value: v.clamp(min, max),
              min: min,
              max: max,
              onChanged: (x) => setState(() {
                set(x);
                t.changed();
              }),
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(v.toStringAsFixed(digits),
                textAlign: TextAlign.right, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      );
    }

    Widget header(String s) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 4),
          child: Text(s, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.92,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          header(l.controlScheme),
          SegmentedButton<ControlSchemeId>(
            segments: [
              ButtonSegment(value: ControlSchemeId.a, label: Text(l.schemeA, style: const TextStyle(fontSize: 11))),
              ButtonSegment(value: ControlSchemeId.b, label: Text(l.schemeB, style: const TextStyle(fontSize: 11))),
              ButtonSegment(value: ControlSchemeId.c, label: Text(l.schemeC, style: const TextStyle(fontSize: 11))),
            ],
            selected: {g.scheme.id},
            onSelectionChanged: (s) => setState(() => widget.onScheme(s.first)),
          ),
          header(l.worldSection),
          slider('car_scale', t.carScale, 1, 4, (v) {
            t.carScale = v;
            g.drive.rescaleCar();
          }),
          slider('view_width_m.slow', t.viewWidthSlow, 25, 150, (v) => t.viewWidthSlow = v, digits: 0),
          slider('view_width_m.fast', t.viewWidthFast, 40, 250, (v) => t.viewWidthFast = v, digits: 0),
          slider('car_anchor.y', t.anchorY, 0.4, 0.9, (v) => t.anchorY = v),
          slider('extrusion.k', t.extrusionK, 0, 0.02, (v) => t.extrusionK = v, digits: 4),
          slider('extrusion.knee_m', t.extrusionKnee, 0, 200, (v) => t.extrusionKnee = v, digits: 0),
          slider('extrusion.exp', t.extrusionExp, 0.3, 1, (v) => t.extrusionExp = v),
          slider('extrusion.max_scale', t.extrusionMaxScale, 1, 4, (v) => t.extrusionMaxScale = v),
          slider('speed_mps.cruise', t.cruiseMps, 5, 60, (v) => t.cruiseMps = v, digits: 0),
          slider('speed_mps.top_default', t.topMps, 10, 80, (v) => t.topMps = v, digits: 0),
          header(l.carSection),
          slider('power', c.power, 2, 25, (v) => c.power = v, digits: 1),
          slider('brake', c.brake, 4, 40, (v) => c.brake = v, digits: 1),
          slider('grip_front', c.gripFront, 4, 60, (v) => c.gripFront = v, digits: 1),
          slider('grip_rear', c.gripRear, 4, 60, (v) => c.gripRear = v, digits: 1),
          slider('drift_bias', c.driftBias, 0.05, 1, (v) => c.driftBias = v),
          slider('steer_speed', c.steerSpeed, 1, 12, (v) => c.steerSpeed = v, digits: 1),
          slider('top_speed', c.topSpeed, 10, 90, (v) => c.topSpeed = v, digits: 0),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: Text(l.copyYaml),
                onPressed: () async {
                  final car = 'power: ${c.power}\nbrake: ${c.brake}\ngrip_front: ${c.gripFront}\n'
                      'grip_rear: ${c.gripRear}\ndrift_bias: ${c.driftBias}\nsteer_speed: ${c.steerSpeed}\n'
                      'top_speed: ${c.topSpeed}\n';
                  await Clipboard.setData(ClipboardData(text: '${t.panelYaml()}\n# ${c.id}\n$car'));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.copied)));
                  }
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.restart_alt, size: 16),
                label: Text(l.respawn),
                onPressed: g.respawn,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(l.aboutMaps, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }
}
