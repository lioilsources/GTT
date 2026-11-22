import 'package:drive_core/drive_core.dart';
import 'package:flame/game.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:npc_dialogue/npc_dialogue.dart';
import 'package:shared_gen/shared_gen.dart';

import '../game/metropole_game.dart';
import '../l10n/app_localizations.dart';
import '../loop/loop_controller.dart';
import '../loop/loop_layer.dart';
import '../loop/save_store.dart';
import '../main.dart' show appClock;
import '../phone/nav_hud.dart';
import '../phone/phone_controller.dart';
import '../phone/phone_sheet.dart';
import '../taxi/taxi_controller.dart';
import '../taxi/taxi_hud.dart';
import 'garage_sheet.dart';
import 'hud.dart';
import 'passport.dart';
import 'police_hud.dart';
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
  // Loop glue and the save (specs/loop.md, specs/save.md): read before the first frame.
  LoopController? _loop;
  LoopController? _finesWired;
  TaxiController? _taxi;
  final SaveStore _store = FileSaveStore();
  Object? _saved;
  DialogueSession? _npc;

  @override
  void dispose() {
    _loop?.save();
    _loop?.dispose();
    _taxi?.dispose();
    TaxiGame.startInCity = null;
    _phone?.dispose();
    super.dispose();
  }

  Future<MetropoleGame> _load() async {
    final assets = await GameAssets.load(widget.city, widget.car);
    _saved = await _store.read(widget.city.id);
    _npc = await ensureDialogueSession(assets.tuning, city: widget.city.id).then<DialogueSession?>((s) => s, onError: (_) => null);
    final game = MetropoleGame(assets);
    await game.preload();
    return game;
  }

  /// Gallery: teleport to the taxi stand and start the shift there.
  void _startTaxi(MetropoleGame game, LoopController loop) {
    final s = game.city.spots.items.where((s) => s.minigame == MinigameId.taxi.id).firstOrNull;
    if (s == null) return;
    game.drive.spawn(s.parkX / 10, s.parkY / 10, s.parkHeading.toDouble());
    game.camera.snap(game.drive.car.x, game.drive.car.y, game.drive.car.heading, game.tuning);
    loop.start(s.id);
  }

  void _setSettings(MetropoleGame game, LoopSettings s) {
    _scheme = ControlSchemeId.values.firstWhere((c) => c.name == s.scheme, orElse: () => ControlSchemeId.a);
    game.setScheme(_scheme);
    game.setNight(s.night);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
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
          final loop = _loop ??= LoopController(
            game,
            phone,
            store: _store,
            npc: _npc,
            saved: _saved,
            settingsGet: () => (scheme: _scheme.name, night: game.night),
            settingsSet: (s) => _setSettings(game, s),
          );
          // Police fines take cash through the economy (specs/economy.md); wired once per controller.
          if (_finesWired != loop) {
            _finesWired = loop;
            game.police.onFined.add(loop.fine);
          }
          // Taxi: a world minigame the loop starts at the taxi stand (specs/minigames/taxi.md).
          final taxi = _taxi ??= TaxiController(game, phone);
          loop.worldGames[MinigameId.taxi] = taxi;
          TaxiGame.startInCity = () => _startTaxi(game, loop);
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
                onCarAction: (a) async {
                  if (a == CarAction.board) return game.boardCandidate();
                  game.carsPaused = true;
                  await showGarage(context, game.fleet);
                  game.carsPaused = false;
                },
                onTuning: () => showTuningPanel(
                  context,
                  game,
                  onScheme: (id) {
                    setState(() => _scheme = id);
                    game.setScheme(id);
                  },
                  onBench: game.startBench,
                  onResetSave: loop.resetSave,
                ),
                onPassport: () =>
                    PassportScreen.open(context, game.passport, game.city.manifest.name, AboutInfo.of(game.city)),
              ),
              PoliceHud(police: game.police),
              NavHud(phone: phone),
              TaxiHud(taxi: taxi),
              PhoneLayer(phone: phone),
              LoopLayer(loop: loop),
              PassportOverlay(events: game.passportEvent, seconds: game.tuning.passport.postcardS),
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
