import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Rank and suit glyphs (symbols, not texts) as in Oko bere: rank = c mod 13, suit = c div 13.
const _ranks = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
const _suits = ['♠', '♥', '♦', '♣'];

/// Srdce (hearts): your hand at the bottom (illegal cards dimmed), three opponents around the
/// table; the last trick stays on the table until the next card is led. Opponents play after
/// `ai_think_s` each.
class SrdceGame implements Minigame {
  const SrdceGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.srdce]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.srdce;
    return MinigameShell(
      id: MinigameId.srdce,
      env: env,
      rules: const [MessageKey.srdceRules1, MessageKey.srdceRules2, MessageKey.srdceRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _SrdceBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _SrdceBody extends StatefulWidget {
  const _SrdceBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_SrdceBody> createState() => _SrdceBodyState();
}

class _SrdceBodyState extends State<_SrdceBody> {
  final SrdceRules _rules = SrdceRules();
  late final Prng _ai = aiPrng(widget.ctx.seed);
  late SrdceState _s = _rules.start(SrdceConfig.fromTuning(widget.env.tuning.minigames.srdce), widget.ctx.seed);
  Timer? _aiTimer, _endTimer;

  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  bool get _myMove => !_s.over && _s.turn == 0;

  @override
  void initState() {
    super.initState();
    widget.hooks.onTimeout = _timeout;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _status();
      _scheduleAi();
    });
  }

  @override
  void dispose() {
    _aiTimer?.cancel();
    _endTimer?.cancel();
    super.dispose();
  }

  void _status() {
    if (!mounted) return;
    widget.shell.status(_s.over ? '' : (_myMove ? t(MessageKey.yourTurn) : t(MessageKey.opponentTurn)));
  }

  void _tap(int c) {
    if (widget.shell.paused || !_myMove || !_rules.legalCards(_s).contains(c)) return;
    _play(SrdceAction('player', c));
  }

  void _play(SrdceAction a) {
    if (_s.over) return;
    setState(() => _s = _rules.apply(_s, a));
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

  void _scheduleAi() {
    if (!mounted || _s.turn == 0 || _s.over) return;
    _aiTimer?.cancel();
    void tick() {
      if (!mounted) return;
      if (widget.shell.paused) {
        _aiTimer = Timer(const Duration(milliseconds: 200), tick);
        return;
      }
      _play(_rules.aiAction(_s, widget.ctx.difficulty, _ai));
    }

    _aiTimer = Timer(Duration(milliseconds: (widget.env.tuning.minigames.srdce.aiThinkS * 1000).round()), tick);
  }

  void _timeout() {
    if (_s.over) return;
    _aiTimer?.cancel();
    setState(() => _s = _rules.apply(_s, const SrdceAction.timeout()));
    final r = _rules.result(_s)!;
    widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
  }

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: Color(Tokens.colorUiTextMuted));
    final names = [t(MessageKey.srdceYou), t(MessageKey.srdceWest), t(MessageKey.srdceNorth), t(MessageKey.srdceEast)];
    Widget seat(int i) => Text(
      '${names[i]}  ${t(MessageKey.srdcePoints, {'n': _s.scores[i] + (_s.over ? 0 : _s.taken[i])})}',
      key: ValueKey('seat-$i'),
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Color(!_s.over && _s.turn == i ? Tokens.colorBrandAccent : Tokens.colorUiText),
        fontWeight: FontWeight.w700,
      ),
    );
    final live = _s.trick.isNotEmpty;
    final cards = live ? _s.trick : _s.lastTrick.cards;
    final leader = live ? _s.leader : _s.lastTrick.leader;
    final legal = _myMove ? _rules.legalCards(_s).toSet() : const <int>{};
    // Seat → position on the table: you below, left, across, right.
    const spots = [Alignment(0, 0.9), Alignment(-0.9, 0), Alignment(0, -0.9), Alignment(0.9, 0)];
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceMd),
      child: Column(
        children: [
          Text(
            t(MessageKey.srdceDeal, {'n': _s.deal, 'total': widget.env.tuning.minigames.srdce.maxDeals}),
            style: muted,
          ),
          const SizedBox(height: Tokens.spaceSm),
          seat(2),
          Expanded(
            child: Row(
              children: [
                SizedBox(width: 72, child: seat(1)),
                Expanded(
                  child: Stack(
                    children: [
                      for (var k = 0; k < cards.length; k++)
                        Align(
                          alignment: spots[(leader + k) % 4],
                          child: _CardFace(cards[k], width: 52, ring: !live && (leader + k) % 4 == _s.lastTrick.winner),
                        ),
                    ],
                  ),
                ),
                SizedBox(width: 72, child: seat(3)),
              ],
            ),
          ),
          seat(0),
          const SizedBox(height: Tokens.spaceSm),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 2,
            runSpacing: Tokens.spaceXs,
            children: [
              for (final c in _s.hands[0])
                GestureDetector(
                  key: ValueKey('card-$c'),
                  onTap: legal.contains(c) ? () => _tap(c) : null,
                  child: _CardFace(c, width: 44, dim: _myMove && !legal.contains(c)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A card face (rank over suit), as in Oko bere.
class _CardFace extends StatelessWidget {
  const _CardFace(this.card, {required this.width, this.dim = false, this.ring = false});

  final int card;
  final double width;
  final bool dim, ring;

  @override
  Widget build(BuildContext context) {
    final s = suitOf(card);
    final color = Color(s == 1 || s == 2 ? Tokens.colorUiControlBrake : Tokens.colorUiBackground);
    return Opacity(
      opacity: dim ? 0.4 : 1,
      child: Container(
        width: width,
        height: width * 1.44,
        decoration: BoxDecoration(
          color: const Color(Tokens.colorUiText),
          borderRadius: BorderRadius.circular(Tokens.radiusButton),
          border: ring ? Border.all(color: const Color(Tokens.colorBrandAccent), width: 3) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _ranks[rankOf(card)],
              style: TextStyle(color: color, fontSize: width * 0.36, fontWeight: FontWeight.w700, height: 1.1),
            ),
            Text(
              _suits[s],
              style: TextStyle(color: color, fontSize: width * 0.4, fontWeight: FontWeight.w700, height: 1.1),
            ),
          ],
        ),
      ),
    );
  }
}
