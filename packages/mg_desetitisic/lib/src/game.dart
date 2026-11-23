import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Desetitisic (Ten thousand): tap dice to set them aside, then roll on or bank; the opponent plays
/// each step after `ai_think_s`.
class DesetitisicGame implements Minigame {
  const DesetitisicGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.desetitisic]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.desetitisic;
    return MinigameShell(
      id: MinigameId.desetitisic,
      env: env,
      rules: const [MessageKey.desetRules1, MessageKey.desetRules2, MessageKey.desetRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _DesetBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _DesetBody extends StatefulWidget {
  const _DesetBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_DesetBody> createState() => _DesetBodyState();
}

class _DesetBodyState extends State<_DesetBody> {
  final DesetitisicRules _rules = DesetitisicRules();
  late final Prng _ai = aiPrng(widget.ctx.seed);
  late DesetitisicState _s = _rules.start(
    DesetitisicConfig.fromTuning(widget.env.tuning.minigames.desetitisic),
    widget.ctx.seed,
  );
  Timer? _aiTimer;
  Timer? _flashTimer;
  String? _flash;
  Set<int> _selected = {};

  /// Dice shown when the state has none: a busted roll, or the roll the last keep came from.
  List<int> _shown = const [];
  Set<int> _kept = {};
  bool _busted = false;

  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  int get _thinkMs => (widget.env.tuning.minigames.desetitisic.aiThinkS * 1000).round();

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
    super.dispose();
  }

  void _status() {
    if (!mounted) return;
    widget.shell.status(_s.over ? '' : (_s.turn == 'player' ? t(MessageKey.yourTurn) : t(MessageKey.opponentTurn)));
  }

  List<int> get _selection => _selected.toList()..sort();

  int? get _selValue => scoreSelection([for (final i in _selection) _s.roll[i]]);

  void _toggle(int i) {
    if (widget.shell.paused || !_myMove || _s.phase != 'keep') return;
    setState(() => _selected.contains(i) ? _selected.remove(i) : _selected.add(i));
  }

  void _play(DesetitisicAction a) {
    if (widget.shell.paused || _s.over) return;
    final before = _s;
    setState(() {
      _s = _rules.apply(_s, a);
      _selected = {};
      if (a.op == 'keep') {
        _shown = before.roll;
        _kept = a.dice.toSet();
        _busted = false;
      } else if (a.op == 'roll' && _s.lastBust) {
        _shown = rollDice(before.rng, before.dice).values;
        _kept = {};
        _busted = true;
        _flash = t(MessageKey.desetBust);
        _flashTimer?.cancel();
        _flashTimer = Timer(
          Duration(milliseconds: math.max(900, _thinkMs)),
          () => mounted ? setState(() => _flash = null) : null,
        );
      } else if (a.op == 'bank') {
        _shown = const [];
        _kept = {};
        _busted = false;
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
    setState(() => _s = _rules.apply(_s, const DesetitisicAction.timeout()));
    final r = _rules.result(_s)!;
    widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
  }

  Widget _button(String label, bool enabled, DesetitisicAction Function() action) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceXs),
      child: FilledButton(onPressed: _myMove && enabled ? () => _play(action()) : null, child: Text(label)),
    ),
  );

  List<Widget> _buttons() {
    switch (_s.phase) {
      case 'keep':
        final v = _selValue;
        return [
          _button(
            t(MessageKey.desetKeep, {'points': v ?? 0}),
            v != null,
            () => DesetitisicAction.keep('player', _selection),
          ),
        ];
      case 'decide':
        return [
          _button(t(MessageKey.desetRoll), true, () => const DesetitisicAction.roll('player')),
          _button(
            t(MessageKey.desetBank, {'points': _s.turnScore}),
            true,
            () => const DesetitisicAction.bank('player'),
          ),
        ];
      default:
        return [_button(t(MessageKey.desetRoll), _s.phase == 'roll', () => const DesetitisicAction.roll('player'))];
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxRounds = widget.env.tuning.minigames.desetitisic.maxRounds;
    const muted = TextStyle(color: Color(Tokens.colorUiTextMuted));
    final keep = _s.phase == 'keep';
    final values = keep ? _s.roll : _shown;
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
                  final side = math.min(c.maxWidth / 3.6, c.maxHeight / 2.4).clamp(24.0, 96.0);
                  return Wrap(
                    alignment: WrapAlignment.center,
                    spacing: side * 0.2,
                    runSpacing: side * 0.2,
                    children: [
                      for (var i = 0; i < values.length; i++)
                        SizedBox(
                          width: side * 3.6 / 3 - side * 0.2,
                          child: Center(
                            child: GestureDetector(
                              key: ValueKey('die-$i'),
                              onTap: keep && _myMove ? () => _toggle(i) : null,
                              child: CustomPaint(
                                size: Size.square(side),
                                painter: DiePainter(
                                  value: values[i],
                                  ring: keep
                                      ? (_selected.contains(i) ? DieRing.selected : DieRing.none)
                                      : _busted
                                      ? DieRing.bust
                                      : (_kept.contains(i) ? DieRing.selected : DieRing.none),
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
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              color: Color(_flash != null ? Tokens.colorUiControlBrake : Tokens.colorUiText),
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
            child: Text(_flash ?? t(MessageKey.desetTurn, {'points': _s.turnScore})),
          ),
          const SizedBox(height: Tokens.spaceSm),
          Row(children: _buttons()),
        ],
      ),
    );
  }
}
