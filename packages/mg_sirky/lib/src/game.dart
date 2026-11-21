import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Sirky (duel): tap Take 1–3, the opponent answers after `ai_think_s`.
class SirkyGame implements Minigame {
  const SirkyGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.sirky]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.sirky;
    return MinigameShell(
      id: MinigameId.sirky,
      env: env,
      rules: const [MessageKey.sirkyRules1, MessageKey.sirkyRules2, MessageKey.sirkyRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _SirkyBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _SirkyBody extends StatefulWidget {
  const _SirkyBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_SirkyBody> createState() => _SirkyBodyState();
}

class _SirkyBodyState extends State<_SirkyBody> {
  final SirkyRules _rules = SirkyRules();
  late final Prng _ai = aiPrng(widget.ctx.seed);
  late SirkyState _s = _rules.start(SirkyConfig.fromTuning(widget.env.tuning.minigames.sirky), widget.ctx.seed);
  Timer? _aiTimer;
  String? _flash;
  Timer? _flashTimer;

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
    _flashTimer?.cancel();
    super.dispose();
  }

  void _status() {
    if (!mounted) return;
    widget.shell.status(_s.over ? '' : (_s.turn == 'player' ? t(MessageKey.yourTurn) : t(MessageKey.opponentTurn)));
  }

  void _play(SirkyAction a) {
    if (widget.shell.paused || _s.over) return;
    final before = _s;
    setState(() {
      _s = _rules.apply(_s, a);
      if (_s.round != before.round || _s.over) {
        _flash = _s.player > before.player ? t(MessageKey.roundWon) : t(MessageKey.roundLost);
        _flashTimer?.cancel();
        _flashTimer = Timer(const Duration(milliseconds: 900), () => mounted ? setState(() => _flash = null) : null);
      }
    });
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
    final ms = (widget.env.tuning.minigames.sirky.aiThinkS * 1000).round();
    void tick() {
      if (!mounted) return;
      if (widget.shell.paused) {
        _aiTimer = Timer(const Duration(milliseconds: 200), tick);
        return;
      }
      _play(_rules.aiAction(_s, widget.ctx.difficulty, _ai));
    }

    _aiTimer = Timer(Duration(milliseconds: ms), tick);
  }

  void _timeout() {
    if (_s.over) return;
    _aiTimer?.cancel();
    setState(() => _s = _rules.apply(_s, const SirkyAction.timeout()));
    final r = _rules.result(_s)!;
    widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
  }

  @override
  Widget build(BuildContext context) {
    final maxTake = widget.env.tuning.minigames.sirky.maxTake;
    const muted = TextStyle(color: Color(Tokens.colorUiTextMuted));
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceMd),
      child: Column(
        children: [
          Text(
            '${t(MessageKey.sirkyRound, {'round': _s.round})}  ·  ${t(MessageKey.roundScore, {'player': _s.player, 'ai': _s.ai})}',
            style: muted,
          ),
          Expanded(
            child: CustomPaint(painter: _PilePainter(_s.left), size: Size.infinite),
          ),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              color: Color(_flash != null ? Tokens.colorBrandAccent : Tokens.colorUiText),
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
            child: Text(_flash ?? t(MessageKey.sirkyLeft, {'count': _s.left})),
          ),
          const SizedBox(height: Tokens.spaceSm),
          Row(
            children: [
              for (var k = 1; k <= maxTake; k++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceXs),
                    child: FilledButton(
                      onPressed: _s.over || _s.turn != 'player' || k > _s.left
                          ? null
                          : () => _play(SirkyAction('player', k)),
                      child: Text(t(MessageKey.sirkyTake, {'count': k})),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Matches in rows of five, centred (same layout as the web client).
class _PilePainter extends CustomPainter {
  _PilePainter(this.left);

  final int left;
  static const perRow = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = (size.width < size.height ? size.width : size.height) / 100;
    final ox = (size.width - 100 * unit) / 2, oy = (size.height - 100 * unit) / 2;
    final rows = (left / perRow).ceil().clamp(1, 1000);
    final cellH = (96 / rows).clamp(0, 30).toDouble();
    final stick = Paint()
      ..color = Color(Tokens.colorWorldDayFacades[0])
      ..strokeWidth = 2.4 * unit
      ..strokeCap = StrokeCap.round;
    final head = Paint()..color = const Color(Tokens.colorUiControlBrake);
    for (var i = 0; i < left; i++) {
      final r = i ~/ perRow, c = i % perRow;
      final n = (left - r * perRow).clamp(0, perRow);
      final x = 50 + (c - (n - 1) / 2) * 16;
      final y = 50 + (r - (rows - 1) / 2) * cellH;
      final len = cellH * 0.78;
      canvas.drawLine(
        Offset(ox + x * unit, oy + (y - len / 2 + 3) * unit),
        Offset(ox + x * unit, oy + (y + len / 2) * unit),
        stick,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(ox + x * unit, oy + (y - len / 2 + 2.5) * unit),
          width: 4.8 * unit,
          height: 6.4 * unit,
        ),
        head,
      );
    }
  }

  @override
  bool shouldRepaint(_PilePainter old) => old.left != left;
}
