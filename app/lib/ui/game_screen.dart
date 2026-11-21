import 'package:drive_core/drive_core.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:shared_gen/shared_gen.dart';

import '../game/metropole_game.dart';
import '../l10n/app_localizations.dart';
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
          if (game == null) {
            return Center(
              child: Text(l.loading(widget.city.name), style: const TextStyle(color: Color(Tokens.colorUiTextMuted))),
            );
          }
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
                onTuning: () => showTuningPanel(
                  context,
                  game,
                  onScheme: (id) {
                    setState(() => _scheme = id);
                    game.setScheme(id);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
