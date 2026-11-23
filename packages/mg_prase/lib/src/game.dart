import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Prase (pig): roll as long as you dare, bank to keep the turn; a one loses it. The opponent
/// plays each step after `ai_think_s`.
class PraseGame implements Minigame {
  const PraseGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.prase]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.prase;
    return MinigameShell(
      id: MinigameId.prase,
      env: env,
      rules: const [MessageKey.praseRules1, MessageKey.praseRules2, MessageKey.praseRules3],
      ruleArgs: {'target': tm.target},
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _PraseBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _PraseBody extends StatefulWidget {
  const _PraseBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_PraseBody> createState() => _PraseBodyState();
}

class _PraseBodyState extends State<_PraseBody> {
  final PraseRules _rules = PraseRules();
  late final Prng _ai = aiPrng(widget.ctx.seed);
  late PraseState _s = _rules.start(PraseConfig.fromTuning(widget.env.tuning.minigames.prase), widget.ctx.seed);
  Timer? _aiTimer, _flashTimer, _endTimer;
  String? _flash;

  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  int get _thinkMs => (widget.env.tuning.minigames.prase.aiThinkS * 1000).round();

  bool get _myMove => !_s.over && _s.turn == 'player';

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
    _endTimer?.cancel();
    super.dispose();
  }

  void _status() {
    if (!mounted) return;
    widget.shell.status(_s.over ? '' : (_myMove ? t(MessageKey.yourTurn) : t(MessageKey.opponentTurn)));
  }

  void _play(PraseAction a) {
    if (_s.over) return;
    setState(() {
      _s = _rules.apply(_s, a);
      if (a.op == 'roll' && _s.bust) {
        _flash = t(MessageKey.praseBust);
        _flashTimer?.cancel();
        _flashTimer = Timer(
          Duration(milliseconds: math.max(900, _thinkMs)),
          () => mounted ? setState(() => _flash = null) : null,
        );
      }
    });
    _status();
    final r = _rules.result(_s);
    if (r != null) {
      _endTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
      });
      return;
    }
    _scheduleAi();
  }

  void _tap(String op) {
    if (widget.shell.paused || !_myMove) return;
    _play(PraseAction('player', op));
  }

  void _scheduleAi() {
    if (_s.turn != 'ai' || _s.over) return;
    _aiTimer?.cancel();
    void tick() {
      if (!mounted) return;
      if (widget.shell.paused) {
        _aiTimer = Timer(const Duration(milliseconds: 200), tick);
        return;
      }
      _play(_rules.aiAction(_s, widget.ctx.difficulty, _ai));
    }

    _aiTimer = Timer(Duration(milliseconds: _thinkMs), tick);
  }

  void _timeout() {
    if (_s.over) return;
    _aiTimer?.cancel();
    setState(() => _s = _rules.apply(_s, const PraseAction.timeout()));
    final r = _rules.result(_s)!;
    widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
  }

  Widget _button(String label, bool enabled, String op) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceXs),
      child: FilledButton(onPressed: _myMove && enabled ? () => _tap(op) : null, child: Text(label)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final maxRounds = widget.env.tuning.minigames.prase.maxRounds;
    const muted = TextStyle(color: Color(Tokens.colorUiTextMuted));
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceMd),
      child: Column(
        children: [
          Text(t(MessageKey.desetRound, {'round': math.min(_s.round, maxRounds), 'max': maxRounds}), style: muted),
          Text(t(MessageKey.desetScores, {'player': _s.player, 'ai': _s.ai}), style: muted),
          Expanded(
            child: Center(
              child: LayoutBuilder(
                builder: (context, c) {
                  final side = math.min(c.maxWidth, c.maxHeight) * 0.5;
                  return CustomPaint(
                    key: const ValueKey('die'),
                    size: Size.square(side.clamp(48.0, 180.0)),
                    painter: DiePainter(value: _s.die, ring: _s.bust ? DieRing.bust : DieRing.none),
                  );
                },
              ),
            ),
          ),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              color: Color(_flash != null ? Tokens.colorUiControlBrake : Tokens.colorUiText),
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
            child: Text(_flash ?? t(MessageKey.praseTurn, {'n': _s.turnScore})),
          ),
          const SizedBox(height: Tokens.spaceSm),
          Row(
            children: [
              _button(t(MessageKey.praseRoll), true, 'roll'),
              _button(t(MessageKey.praseHold), _s.turnScore > 0, 'hold'),
            ],
          ),
        ],
      ),
    );
  }
}
