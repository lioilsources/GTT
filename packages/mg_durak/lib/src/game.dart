import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

const _ranks = ['6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
const _suits = ['♠', '♥', '♦', '♣'];

/// Durak (podkidnoy): NPCs with card counts on top, the table of attack/beat pairs with the stock
/// and the trump, your hand at the bottom (legal cards tappable), Take / Done buttons.
class DurakGame implements Minigame {
  const DurakGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.durak]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.durak;
    return MinigameShell(
      id: MinigameId.durak,
      env: env,
      rules: const [MessageKey.durakRules1, MessageKey.durakRules2, MessageKey.durakRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _DurakBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _DurakBody extends StatefulWidget {
  const _DurakBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_DurakBody> createState() => _DurakBodyState();
}

class _DurakBodyState extends State<_DurakBody> {
  final DurakRules _rules = DurakRules();
  late final Prng _ai = aiPrng(widget.ctx.seed);
  late DurakState _s = _rules.start(
    DurakConfig.fromTuning(widget.env.tuning.minigames.durak, widget.ctx.difficulty),
    widget.ctx.seed,
  );
  Timer? _aiTimer, _endTimer;

  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  bool get _mine => !_s.over && _rules.turn(_s) == 0;

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
    widget.shell.status(_s.over ? '' : (_mine ? t(MessageKey.yourTurn) : t(MessageKey.opponentTurn)));
  }

  void _tap(DurakAction a) {
    if (widget.shell.paused || !_mine) return;
    _play(a);
  }

  void _play(DurakAction a) {
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
    if (_s.over || _rules.turn(_s) == 0) return;
    _aiTimer?.cancel();
    final ms = (widget.env.tuning.minigames.durak.aiThinkS * 1000).round();
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
    setState(() => _s = _rules.apply(_s, const DurakAction.timeout()));
    final r = _rules.result(_s)!;
    widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
  }

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: Color(Tokens.colorUiTextMuted));
    final turn = _rules.turn(_s);
    final legal = _mine ? _rules.legalActions(_s) : const <DurakAction>[];
    final byCard = {
      for (final a in legal)
        if (a.hasCard) a.card: a,
    };
    final extra = legal.where((a) => a.op == 'take' || a.op == 'pass');
    final hand = _s.hands[0];
    final w = hand.length > 8 ? 36.0 : 48.0;
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceMd),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            spacing: Tokens.spaceSm,
            children: [
              for (var i = 1; i < _s.n; i++)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceSm, vertical: Tokens.spaceXs),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Color(!_s.over && turn == i ? Tokens.colorBrandAccent : 0x00000000),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(Tokens.radiusButton),
                  ),
                  child: Text(
                    '${t(MessageKey.durakOpp, {'n': i})} · ${_s.finished.contains(i) ? t(MessageKey.durakOut) : t(MessageKey.durakCards, {'n': _s.hands[i].length})}',
                    style: muted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: Tokens.spaceSm),
          Text(t(MessageKey.durakTrump, {'suit': _suits[_s.trump], 'n': _s.stock.length}), style: muted),
          Expanded(
            child: Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: Tokens.spaceSm,
                runSpacing: Tokens.spaceSm,
                children: [
                  if (_s.stock.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: Tokens.spaceMd),
                      child: RotatedBox(quarterTurns: 1, child: _CardFace(_s.trumpCard, width: 40)),
                    ),
                  for (final p in _s.table)
                    SizedBox(
                      width: 56,
                      height: 76,
                      child: Stack(
                        children: [
                          _CardFace(p.a, width: 40),
                          if (p.d >= 0) Positioned(left: 14, top: 16, child: _CardFace(p.d, width: 40)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          Text(
            !_mine
                ? ''
                : turn == _s.defender
                ? t(MessageKey.durakDefend)
                : _s.table.isNotEmpty
                ? t(MessageKey.durakThrow)
                : t(MessageKey.durakAttack),
            style: muted,
          ),
          const SizedBox(height: Tokens.spaceSm),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 2,
            runSpacing: Tokens.spaceXs,
            children: [
              for (final c in hand)
                GestureDetector(
                  key: ValueKey('card-$c'),
                  onTap: byCard[c] == null ? null : () => _tap(byCard[c]!),
                  child: _CardFace(c, width: w, dim: _mine && byCard[c] == null, ring: byCard[c] != null),
                ),
            ],
          ),
          const SizedBox(height: Tokens.spaceSm),
          SizedBox(
            height: 48,
            child: extra.isEmpty
                ? null
                : FilledButton(
                    onPressed: () => _tap(extra.first),
                    child: Text(t(extra.first.op == 'take' ? MessageKey.durakTake : MessageKey.durakPass)),
                  ),
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
    final s = durakSuit(card);
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
              _ranks[durakRank(card)],
              style: TextStyle(color: color, fontSize: width * 0.34, fontWeight: FontWeight.w700, height: 1.1),
            ),
            Text(
              _suits[s],
              style: TextStyle(color: color, fontSize: width * 0.38, fontWeight: FontWeight.w700, height: 1.1),
            ),
          ],
        ),
      ),
    );
  }
}
