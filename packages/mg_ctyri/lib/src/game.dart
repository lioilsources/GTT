import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Čtyři v řadě: a tap anywhere in a column drops a disc there; the disc falls with a short
/// animation. The opponent answers after `ai_think_s`.
class CtyriGame implements Minigame {
  const CtyriGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.ctyri]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.ctyri;
    return MinigameShell(
      id: MinigameId.ctyri,
      env: env,
      rules: const [MessageKey.ctyriRules1, MessageKey.ctyriRules2, MessageKey.ctyriRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _CtyriBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _CtyriBody extends StatefulWidget {
  const _CtyriBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_CtyriBody> createState() => _CtyriBodyState();
}

class _CtyriBodyState extends State<_CtyriBody> with SingleTickerProviderStateMixin {
  final CtyriRules _rules = CtyriRules();
  late final Prng _ai = aiPrng(widget.ctx.seed);
  late CtyriState _s = _rules.start(CtyriConfig.fromTuning(widget.env.tuning.minigames.ctyri), widget.ctx.seed);
  late final AnimationController _drop = AnimationController(vsync: this, duration: const Duration(milliseconds: 250))
    ..value = 1;
  int _last = -1;
  Timer? _aiTimer;

  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  @override
  void initState() {
    super.initState();
    widget.hooks.onTimeout = _timeout;
    WidgetsBinding.instance.addPostFrameCallback((_) => _status());
  }

  @override
  void dispose() {
    _aiTimer?.cancel();
    _drop.dispose();
    super.dispose();
  }

  void _status() {
    if (!mounted) return;
    widget.shell.status(_s.over ? '' : (_s.turn == 'player' ? t(MessageKey.yourTurn) : t(MessageKey.opponentTurn)));
  }

  void _tap(int col) {
    if (widget.shell.paused || _s.over || _s.turn != 'player' || _s.board[col] != '.') return;
    _play(CtyriAction('player', col));
  }

  void _play(CtyriAction a) {
    if (_s.over) return;
    setState(() {
      _last = _rules.landingCell(_s, a.col);
      _s = _rules.apply(_s, a);
    });
    _drop.forward(from: 0);
    _status();
    final r = _rules.result(_s);
    if (r != null) {
      Timer(const Duration(milliseconds: 900), () {
        if (mounted) widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
      });
      return;
    }
    _scheduleAi();
  }

  void _scheduleAi() {
    if (_s.turn != 'ai' || _s.over) return;
    _aiTimer?.cancel();
    final ms = (widget.env.tuning.minigames.ctyri.aiThinkS * 1000).round();
    void tick() {
      if (!mounted || _s.over) return;
      if (widget.shell.paused) {
        _aiTimer = Timer(const Duration(milliseconds: 200), tick);
        return;
      }
      // Exactly one draw from the AI stream per AI move.
      _play(_rules.aiAction(_s, widget.ctx.difficulty, _ai));
    }

    _aiTimer = Timer(Duration(milliseconds: ms), tick);
  }

  void _timeout() {
    if (_s.over) return;
    _aiTimer?.cancel();
    setState(() => _s = _rules.apply(_s, const CtyriAction.timeout()));
    _status();
    final r = _rules.result(_s)!;
    widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
  }

  @override
  Widget build(BuildContext context) {
    final win = _s.over && _last >= 0 ? winningLine(_s.board, _last).toSet() : const <int>{};
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceMd),
      child: Center(
        child: AspectRatio(
          aspectRatio: cols / rows,
          child: LayoutBuilder(
            builder: (context, box) => GestureDetector(
              key: const ValueKey('ctyri-board'),
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                final c = (d.localPosition.dx / (box.maxWidth / cols)).floor();
                if (c >= 0 && c < cols) _tap(c);
              },
              child: AnimatedBuilder(
                animation: _drop,
                builder: (context, _) => CustomPaint(
                  painter: _BoardPainter(_s.board, _last, win, _s.over ? 1 : _drop.value),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter(this.board, this.last, this.win, this.drop);

  final String board;
  final int last;
  final Set<int> win;

  /// 0..1 progress of the last disc falling into place.
  final double drop;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / cols;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(cell * 0.2)),
      Paint()..color = Color(Tokens.colorWorldDayFacades[6]),
    );
    final hole = Paint()..color = const Color(Tokens.colorWorldDayLand);
    final player = Paint()..color = const Color(Tokens.colorUiNotice);
    final ai = Paint()..color = const Color(Tokens.colorWorldNightAsphalt);
    final ring = Paint()
      ..color = const Color(Tokens.colorBrandAccent)
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.1;
    for (var i = 0; i < cols * rows; i++) {
      final r = i ~/ cols;
      final center = Offset((i % cols + 0.5) * cell, (r + 0.5) * cell);
      canvas.drawCircle(center, cell * 0.4, hole);
      final ch = board[i];
      if (ch == '.') continue;
      // The last disc falls from above the board.
      final at = i == last ? center - Offset(0, (1 - drop) * (r + 1) * cell) : center;
      canvas.drawCircle(at, cell * 0.4, ch == 'x' ? player : ai);
      if (win.contains(i)) canvas.drawCircle(at, cell * 0.4, ring);
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) => true;
}
