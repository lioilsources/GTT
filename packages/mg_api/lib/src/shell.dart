import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_gen/shared_gen.dart';

import 'art.dart';
import 'contract.dart';

/// Lets a game body talk to the shell.
abstract class ShellController {
  /// True while the pause sheet is open; games must not advance then.
  bool get paused;

  /// Ends the game with the rules outcome; the shell shows the result screen.
  void finish(RulesOutcome outcome);

  /// Sets the status line in the top bar.
  void status(String text);
}

/// A game body: built once per game, told about the time cap through [onTimeout].
typedef GameBodyBuilder = Widget Function(BuildContext context, ShellController shell, GameHooks hooks);

/// Callbacks the body registers so the shell can drive it.
class GameHooks {
  /// Called when the time cap runs out; the body applies the `timeout` action.
  VoidCallback? onTimeout;
}

/// Common minigame chrome (specs/minigames/README.md "UI"): rule cards, pause sheet with
/// resume / give up, time cap, result screen with stars, play again and back.
class MinigameShell extends StatefulWidget {
  const MinigameShell({
    super.key,
    required this.id,
    required this.env,
    required this.rules,
    this.ruleArgs = const {},
    required this.timeCapS,
    required this.onFinish,
    required this.body,
  });

  final MinigameId id;
  final MinigameEnv env;

  /// Up to three rule cards (9.2).
  final List<MessageKey> rules;

  /// Placeholder values for the rule cards (e.g. a target from tuning).
  final Map<String, Object> ruleArgs;
  final int timeCapS;
  final void Function(MinigameResult) onFinish;
  final GameBodyBuilder body;

  @override
  State<MinigameShell> createState() => _MinigameShellState();
}

enum _Sheet { none, intro, pause, result }

class _MinigameShellState extends State<MinigameShell> with WidgetsBindingObserver implements ShellController {
  final Stopwatch _clock = Stopwatch();
  _Sheet _sheet = _Sheet.intro;
  int _card = 0;
  int _game = 0;
  String _status = '';
  RulesOutcome? _outcome;
  GameHooks _hooks = GameHooks();
  Timer? _cap;
  bool _done = false;

  MessageKey get _nameKey => MessageKey.values.firstWhere((k) => k.key == 'mg_${widget.id.id}');
  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.rules.isEmpty) _begin();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cap?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _pause(true);
  }

  @override
  bool get paused => _sheet == _Sheet.pause;

  @override
  void status(String text) {
    if (mounted && text != _status) setState(() => _status = text);
  }

  @override
  void finish(RulesOutcome outcome) {
    if (_done || !mounted) return;
    _done = true;
    _clock.stop();
    _cap?.cancel();
    setState(() {
      _outcome = outcome;
      _sheet = _Sheet.result;
    });
  }

  void _begin() {
    _done = false;
    _outcome = null;
    _status = '';
    _hooks = GameHooks();
    _game++;
    _sheet = _Sheet.none;
    _clock
      ..reset()
      ..start();
    final capMs =
        1000 *
        (widget.timeCapS < widget.env.tuning.minigames.timeCapS
            ? widget.timeCapS
            : widget.env.tuning.minigames.timeCapS);
    _cap?.cancel();
    _cap = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!_done && !paused && _clock.elapsedMilliseconds >= capMs) _hooks.onTimeout?.call();
    });
  }

  void _pause(bool p) {
    if (_done || _sheet == _Sheet.intro) return;
    if (p == paused) return;
    setState(() {
      _sheet = p ? _Sheet.pause : _Sheet.none;
      p ? _clock.stop() : _clock.start();
    });
  }

  void _giveUp() {
    if (_done) return;
    _done = true;
    _cap?.cancel();
    widget.onFinish(MinigameResult(stars: 0, score: 0, playedMs: _clock.elapsedMilliseconds, aborted: true));
  }

  @override
  Widget build(BuildContext context) {
    const text = TextStyle(color: Color(Tokens.colorUiText));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _sheet == _Sheet.pause ? _pause(false) : _pause(true);
      },
      child: Material(
        color: const Color(Tokens.colorUiBackground),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceMd, vertical: Tokens.spaceSm),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: t(MessageKey.pause),
                          icon: const Icon(Icons.pause, color: Color(Tokens.colorUiText)),
                          onPressed: () => _pause(true),
                        ),
                        Text(
                          t(_nameKey),
                          style: const TextStyle(color: Color(Tokens.colorBrandAccent), fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        Text(_status, style: const TextStyle(color: Color(Tokens.colorUiTextMuted))),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _sheet == _Sheet.intro && _game == 0
                        ? const SizedBox.shrink()
                        : KeyedSubtree(key: ValueKey(_game), child: widget.body(context, this, _hooks)),
                  ),
                ],
              ),
              if (_sheet != _Sheet.none)
                Positioned.fill(
                  child: ColoredBox(
                    color: const Color(Tokens.colorUiPill),
                    child: Center(child: _card2(text)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card2(TextStyle text) {
    Widget button(String label, VoidCallback onTap, {bool ghost = false}) => Padding(
      padding: const EdgeInsets.only(top: Tokens.spaceSm),
      child: SizedBox(
        width: double.infinity,
        child: ghost
            ? OutlinedButton(onPressed: onTap, child: Text(label))
            : FilledButton(onPressed: onTap, child: Text(label)),
      ),
    );
    final List<Widget> children;
    switch (_sheet) {
      case _Sheet.intro:
        final last = _card + 1 >= widget.rules.length;
        children = [
          Text(t(_nameKey), style: text.copyWith(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: Tokens.spaceMd),
          Text(
            t(widget.rules[_card], widget.ruleArgs),
            textAlign: TextAlign.center,
            style: text.copyWith(fontSize: 18),
          ),
          const SizedBox(height: Tokens.spaceMd),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.rules.length; i++)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(i == _card ? Tokens.colorBrandAccent : Tokens.colorUiTextFaint),
                  ),
                ),
            ],
          ),
          button(last ? t(MessageKey.play) : t(MessageKey.next), () => setState(() => last ? _begin() : _card++)),
        ];
      case _Sheet.pause:
        children = [
          Text(t(MessageKey.pause), style: text.copyWith(fontSize: 22, fontWeight: FontWeight.w700)),
          button(t(MessageKey.resume), () => _pause(false)),
          button(t(MessageKey.giveUp), _giveUp, ghost: true),
        ];
      case _Sheet.result:
        final o = _outcome!;
        final head = o.winner == 'player'
            ? t(MessageKey.youWin)
            : o.winner == 'draw'
            ? t(MessageKey.draw)
            : t(MessageKey.youLose);
        final ms = _clock.elapsedMilliseconds;
        children = [
          Text(head, style: text.copyWith(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: Tokens.spaceSm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Icon(
                  Icons.star_rounded,
                  size: 44,
                  color: Color(i < o.stars ? Tokens.colorBrandAccent : Tokens.colorUiTextFaint),
                ),
            ],
          ),
          Text(t(MessageKey.scoreValue, {'score': o.score}), style: text),
          if (widget.env.opponent case final opp?) OpponentLine(opponent: opp, winner: o.winner),
          button(t(MessageKey.playAgain), () => setState(_begin)),
          button(
            t(MessageKey.back),
            () => widget.onFinish(MinigameResult(stars: o.stars, score: o.score, playedMs: ms, aborted: false)),
            ghost: true,
          ),
        ];
      case _Sheet.none:
        children = const [];
    }
    return Container(
      width: 360,
      margin: const EdgeInsets.all(Tokens.spaceLg),
      padding: const EdgeInsets.all(Tokens.spaceLg),
      decoration: BoxDecoration(
        color: const Color(Tokens.colorUiSheet),
        borderRadius: BorderRadius.circular(Tokens.radiusButton),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// The opponent's short line on the result screen: portrait (`npc/<id>.png`, specs/art.md, else
/// initials on a token colour) and a speech bubble.
class OpponentLine extends StatelessWidget {
  const OpponentLine({super.key, required this.opponent, required this.winner});

  final MinigameOpponent opponent;
  final String winner;

  @override
  Widget build(BuildContext context) {
    final initial = opponent.name.isEmpty ? '?' : opponent.name[0].toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Tokens.spaceSm),
      child: Row(
        children: [
          NpcAvatar(id: opponent.id, initials: initial, index: opponent.portrait, size: 40),
          const SizedBox(width: Tokens.spaceSm),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceMd, vertical: Tokens.spaceSm),
              decoration: BoxDecoration(
                color: const Color(Tokens.colorNpcBubble),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${opponent.name} ',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: opponent.line(winner)),
                  ],
                ),
                style: const TextStyle(color: Color(Tokens.colorNpcBubbleText), fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
