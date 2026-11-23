import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Posuvné puzzle: a tap on a tile in the gap's row or column slides the whole run; the UI sends
/// the single moves from the gap outwards (same as the web client).
class PosuvneGame implements Minigame {
  const PosuvneGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.posuvne]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.posuvne;
    return MinigameShell(
      id: MinigameId.posuvne,
      env: env,
      rules: const [MessageKey.posuvneRules1, MessageKey.posuvneRules2, MessageKey.posuvneRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _PosuvneBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _PosuvneBody extends StatefulWidget {
  const _PosuvneBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_PosuvneBody> createState() => _PosuvneBodyState();
}

class _PosuvneBodyState extends State<_PosuvneBody> {
  final PosuvneRules _rules = PosuvneRules();
  late PosuvneState _s = _rules.start(
    PosuvneConfig.fromTuning(widget.env.tuning.minigames.posuvne, widget.ctx.difficulty),
    widget.ctx.seed,
  );
  Timer? _finishTimer;

  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  @override
  void initState() {
    super.initState();
    widget.hooks.onTimeout = _timeout;
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.shell.status(''));
  }

  @override
  void dispose() {
    _finishTimer?.cancel();
    super.dispose();
  }

  void _tap(int p) {
    if (widget.shell.paused || _s.over) return;
    final run = slideTiles(_s, p);
    if (run.isEmpty) return;
    setState(() {
      for (final tile in run) {
        if (_s.over) break;
        _s = _rules.apply(_s, PosuvneAction(tile));
      }
    });
    final r = _rules.result(_s);
    if (r != null) {
      _finishTimer = Timer(const Duration(milliseconds: 700), () {
        if (mounted) widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
      });
    }
  }

  void _timeout() {
    if (_s.over) return;
    setState(() => _s = _rules.apply(_s, const PosuvneAction.timeout()));
    final r = _rules.result(_s)!;
    widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
  }

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: Color(Tokens.colorUiTextMuted));
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceMd),
      child: Column(
        children: [
          Text(t(MessageKey.posuvneMoves, {'moves': _s.moves, 'par': _s.par}), style: muted),
          const SizedBox(height: Tokens.spaceSm),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: LayoutBuilder(
                  builder: (context, box) {
                    final cell = box.maxWidth / 4;
                    return Stack(
                      children: [
                        for (var p = 0; p < 16; p++)
                          if (_s.tiles[p] != 0)
                            Positioned(
                              left: (p & 3) * cell,
                              top: (p >> 2) * cell,
                              width: cell,
                              height: cell,
                              child: GestureDetector(
                                key: ValueKey('posuvne-tile-$p'),
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _tap(p),
                                child: Padding(
                                  padding: EdgeInsets.all(cell * 0.04),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Color(_s.tiles[p] == p + 1 ? Tokens.colorBrandAccent : Tokens.colorUiPill),
                                      borderRadius: BorderRadius.circular(cell * 0.12),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${_s.tiles[p]}',
                                        style: TextStyle(
                                          color: Color(
                                            _s.tiles[p] == p + 1 ? Tokens.colorUiBackground : Tokens.colorUiText,
                                          ),
                                          fontSize: cell * 0.38,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
