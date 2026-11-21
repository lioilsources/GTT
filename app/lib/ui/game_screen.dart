import 'package:drive_core/drive_core.dart';
import 'package:flame/game.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_gen/shared_gen.dart';

import '../game/metropole_game.dart';
import '../l10n/app_localizations.dart';
import '../main.dart' show appClock;
import '../phone/nav_hud.dart';
import '../phone/phone_controller.dart';
import '../phone/phone_sheet.dart';
import 'hud.dart';
import 'tuning_panel.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.city = CityId.nyc, this.car = CarId.m0Coupe});

  final CityId city;
  final CarId car;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final Future<MetropoleGame> _game = _load();
  ControlSchemeId _scheme = ControlSchemeId.a;
  PhoneController? _phone;

  @override
  void dispose() {
    _phone?.dispose();
    super.dispose();
  }

  Future<MetropoleGame> _load() async {
    final assets = await GameAssets.load(widget.city, widget.car);
    final game = MetropoleGame(assets);
    await game.preload();
    return game;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: const Color(Tokens.colorUiBackground),
      body: FutureBuilder<MetropoleGame>(
        future: _game,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l.loadFailed('${snap.error}'), style: const TextStyle(color: Color(Tokens.colorUiText))),
              ),
            );
          }
          final game = snap.data;
          if (game != null && game.firstFrameMs == 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (game.firstFrameMs == 0) game.firstFrameMs = appClock.elapsedMilliseconds;
            });
          }
          if (game == null) {
            return Center(
              child: Text(l.loading(widget.city.name), style: const TextStyle(color: Color(Tokens.colorUiTextMuted))),
            );
          }
          final phone = _phone ??= PhoneController(game);
          return Stack(
            fit: StackFit.expand,
            children: [
              Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) => game.pointerDown(e.pointer, e.localPosition),
                onPointerMove: (e) => game.pointerMove(e.pointer, e.localPosition),
                onPointerUp: (e) => game.pointerUp(e.pointer),
                onPointerCancel: (e) => game.pointerUp(e.pointer),
                child: GameWidget(game: game, autofocus: true),
              ),
              Hud(
                game: game,
                scheme: _scheme,
                onNight: () => setState(() => game.setNight(!game.night)),
                onPhone: phone.toggle,
                onTuning: () => showTuningPanel(
                  context,
                  game,
                  onScheme: (id) {
                    setState(() => _scheme = id);
                    game.setScheme(id);
                  },
                  onBench: game.startBench,
                ),
              ),
              NavHud(phone: phone),
              PhoneLayer(phone: phone),
              _BenchOverlay(game: game),
            ],
          );
        },
      ),
    );
  }
}

/// Progress pill while the benchmark runs, then the result with a copy button (specs/bench.md).
class _BenchOverlay extends StatelessWidget {
  const _BenchOverlay({required this.game});
  final MetropoleGame game;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([game.benchProgress, game.benchResult]),
      builder: (context, _) {
        final p = game.benchProgress.value;
        final r = game.benchResult.value;
        if (p == null && r == null) return const SizedBox.shrink();
        if (r == null) {
          return SafeArea(
            child: Align(
              alignment: const Alignment(0, -0.82),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(Tokens.colorUiNotice),
                  borderRadius: BorderRadius.circular(Tokens.radiusPill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    l.benchRunning((p! * 100).floor()),
                    style: const TextStyle(color: Color(Tokens.colorUiText), fontSize: Tokens.fontNotice),
                  ),
                ),
              ),
            ),
          );
        }
        final text = const JsonEncoder.withIndent('  ').convert(r.toJson());
        return Center(
          child: Container(
            width: 380,
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(Tokens.colorUiSheet),
              borderRadius: BorderRadius.circular(Tokens.radiusButton),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.benchDone, style: const TextStyle(color: Color(Tokens.colorUiText), fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      text,
                      style: const TextStyle(
                        color: Color(Tokens.colorUiTextMuted),
                        fontSize: Tokens.fontFaint,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: Text(l.copy),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.copied)));
                    }
                  },
                ),
                TextButton(onPressed: () => game.benchResult.value = null, child: Text(l.close)),
              ],
            ),
          ),
        );
      },
    );
  }
}
