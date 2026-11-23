import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

const _suitKeys = [MessageKey.prsiSuit0, MessageKey.prsiSuit1, MessageKey.prsiSuit2, MessageKey.prsiSuit3];

/// Prší: tap a playable card to lay it; a svršek asks for the suit, the button draws (or takes the
/// sevens) or stands on an ace. The opponent answers after `ai_think_s`.
class PrsiGame implements Minigame {
  const PrsiGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.prsi]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.prsi;
    return MinigameShell(
      id: MinigameId.prsi,
      env: env,
      rules: const [MessageKey.prsiRules1, MessageKey.prsiRules2, MessageKey.prsiRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _PrsiBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _PrsiBody extends StatefulWidget {
  const _PrsiBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_PrsiBody> createState() => _PrsiBodyState();
}

class _PrsiBodyState extends State<_PrsiBody> {
  final PrsiRules _rules = PrsiRules();
  late final Prng _ai = aiPrng(widget.ctx.seed);
  late PrsiState _s = _rules.start(PrsiConfig.fromTuning(widget.env.tuning.minigames.prsi), widget.ctx.seed);
  Timer? _aiTimer, _flashTimer, _endTimer;
  String? _flash;

  /// The svršek waiting for its suit, −1 when none.
  int _picking = -1;

  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  bool get _myMove => !_s.over && _s.turn == 'player';

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
    _flashTimer?.cancel();
    _endTimer?.cancel();
    super.dispose();
  }

  void _status() {
    if (!mounted) return;
    widget.shell.status(_s.over ? '' : (_myMove ? t(MessageKey.yourTurn) : t(MessageKey.opponentTurn)));
  }

  void _tapCard(int c) {
    if (widget.shell.paused || !_myMove) return;
    if (rankOf(c) == prsiQueen && !_s.ace && _s.sevens == 0) {
      setState(() => _picking = c);
      return;
    }
    _play(PrsiAction.play('player', c));
  }

  void _pick(int suit) {
    if (widget.shell.paused || !_myMove || _picking < 0) return;
    final c = _picking;
    _picking = -1;
    _play(PrsiAction.play('player', c, suit));
  }

  void _tapPass() {
    if (widget.shell.paused || !_myMove) return;
    _picking = -1;
    _play(_s.ace ? const PrsiAction.stand('player') : const PrsiAction.draw('player'));
  }

  void _play(PrsiAction a) {
    if (_s.over) return;
    final before = _s;
    setState(() {
      _s = _rules.apply(_s, a);
      if (_s.round != before.round || _s.over) {
        _flash = _s.last == 'player' ? t(MessageKey.roundWon) : t(MessageKey.roundLost);
        _flashTimer?.cancel();
        _flashTimer = Timer(const Duration(milliseconds: 1200), () => mounted ? setState(() => _flash = null) : null);
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

  void _scheduleAi() {
    if (!mounted || _s.turn != 'ai' || _s.over) return;
    _aiTimer?.cancel();
    void tick() {
      if (!mounted) return;
      if (widget.shell.paused) {
        _aiTimer = Timer(const Duration(milliseconds: 200), tick);
        return;
      }
      _play(_rules.aiAction(_s, widget.ctx.difficulty, _ai));
    }

    _aiTimer = Timer(Duration(milliseconds: (widget.env.tuning.minigames.prsi.aiThinkS * 1000).round()), tick);
  }

  void _timeout() {
    if (_s.over) return;
    _aiTimer?.cancel();
    setState(() => _s = _rules.apply(_s, const PrsiAction.timeout()));
    final r = _rules.result(_s)!;
    widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
  }

  String _rankText(int r) => r <= 3
      ? '${r + 7}'
      : t([MessageKey.prsiJack, MessageKey.prsiQueen, MessageKey.prsiKing, MessageKey.prsiAce][r - 4]);

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: Color(Tokens.colorUiTextMuted));
    final playable = {
      if (_myMove)
        for (final a in _rules.legalActions(_s))
          if (a.op == 'play') a.card,
    };
    final pass = _s.ace
        ? t(MessageKey.prsiStand)
        : _s.sevens > 0
        ? t(MessageKey.prsiDrawN, {'n': 2 * _s.sevens})
        : t(MessageKey.prsiDraw);
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceMd),
      child: Column(
        children: [
          Text(t(MessageKey.prsiRounds, {'player': _s.playerWins, 'ai': _s.aiWins}), style: muted),
          const SizedBox(height: Tokens.spaceSm),
          const _Card(null, width: 40),
          const SizedBox(height: Tokens.spaceXs),
          Text(t(MessageKey.prsiCards, {'n': _s.ai.length}), style: muted),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                children: [
                  const _Card(null, width: 48),
                  const SizedBox(height: Tokens.spaceXs),
                  Text('${_s.deck.length}', style: muted),
                ],
              ),
              const SizedBox(width: Tokens.spaceMd),
              _Card(_s.pile.last, width: 64, rankText: _rankText, hot: _s.sevens > 0 || _s.ace),
              const SizedBox(width: Tokens.spaceMd),
              Column(
                children: [
                  SuitIcon(_s.suit, size: 32),
                  const SizedBox(height: Tokens.spaceXs),
                  Text(t(_suitKeys[_s.suit]), style: muted),
                ],
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            height: 32,
            child: Text(
              _flash ?? (_picking >= 0 ? t(MessageKey.prsiPickSuit) : ''),
              style: const TextStyle(color: Color(Tokens.colorBrandAccent), fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: Tokens.spaceXs,
            runSpacing: Tokens.spaceXs,
            children: [
              for (final c in _s.player)
                GestureDetector(
                  key: ValueKey('card-$c'),
                  onTap: playable.contains(c) ? () => _tapCard(c) : null,
                  child: _Card(c, width: 52, rankText: _rankText, dim: _myMove && !playable.contains(c)),
                ),
            ],
          ),
          const SizedBox(height: Tokens.spaceSm),
          Row(
            children: _picking >= 0
                ? [
                    for (var su = 0; su < 4; su++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceXs),
                          child: FilledButton(
                            key: ValueKey('suit-$su'),
                            onPressed: () => _pick(su),
                            child: Semantics(label: t(_suitKeys[su]), child: SuitIcon(su, size: 24)),
                          ),
                        ),
                      ),
                  ]
                : [
                    Expanded(
                      child: FilledButton(onPressed: _myMove ? _tapPass : null, child: Text(pass)),
                    ),
                  ],
          ),
        ],
      ),
    );
  }
}

/// A card: rank text over the suit symbol, or (null) the back.
class _Card extends StatelessWidget {
  const _Card(this.card, {required this.width, this.rankText, this.dim = false, this.hot = false});

  final int? card;
  final double width;
  final String Function(int rank)? rankText;
  final bool dim, hot;

  @override
  Widget build(BuildContext context) {
    final c = card;
    final radius = BorderRadius.circular(Tokens.radiusButton);
    final h = width * 1.44;
    if (c == null) {
      return Container(
        width: width,
        height: h,
        decoration: BoxDecoration(
          color: const Color(Tokens.colorBrandAccent),
          borderRadius: radius,
          border: Border.all(color: const Color(Tokens.colorUiText), width: 3),
        ),
      );
    }
    return Opacity(
      opacity: dim ? 0.4 : 1,
      child: Container(
        width: width,
        height: h,
        decoration: BoxDecoration(
          color: const Color(Tokens.colorUiText),
          borderRadius: radius,
          border: hot ? Border.all(color: const Color(Tokens.colorUiNotice), width: 3) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              rankText!(rankOf(c)),
              style: TextStyle(
                color: const Color(Tokens.colorUiBackground),
                fontSize: width * 0.36,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
            SuitIcon(suitOf(c), size: width * 0.42),
          ],
        ),
      ),
    );
  }
}

/// Mariáš suit symbols (srdce, list, kule, žalud) as simple shapes, colours as the web client.
class SuitIcon extends StatelessWidget {
  const SuitIcon(this.suit, {super.key, required this.size});

  final int suit;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _SuitPainter(suit));
}

class _SuitPainter extends CustomPainter {
  _SuitPainter(this.suit);

  final int suit;

  static const _fill = [
    Tokens.colorUiControlBrake,
    Tokens.colorWorldDayPark,
    Tokens.colorUiNotice,
    Tokens.colorWorldNightAsphalt,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Shapes in a 0..10 box, as web/src/minigames/prsi/game.ts.
    final k = size.shortestSide / 10;
    canvas.scale(k);
    final fill = Paint()..color = Color(_fill[suit]);
    switch (suit) {
      case 0:
        canvas.drawPath(
          Path()
            ..moveTo(5, 9)
            ..lineTo(1.2, 4.8)
            ..arcToPoint(const Offset(5, 2.6), radius: const Radius.circular(2.1))
            ..arcToPoint(const Offset(8.8, 4.8), radius: const Radius.circular(2.1))
            ..close(),
          fill,
        );
      case 1:
        canvas.drawPath(
          Path()
            ..moveTo(5, 1)
            ..cubicTo(8.5, 3, 8.5, 7, 5, 9)
            ..cubicTo(1.5, 7, 1.5, 3, 5, 1)
            ..close(),
          fill,
        );
        canvas.drawLine(
          const Offset(5, 2),
          const Offset(5, 9.5),
          Paint()
            ..color = const Color(Tokens.colorUiText)
            ..strokeWidth = 0.6,
        );
      case 2:
        canvas.drawCircle(const Offset(5, 5), 3.6, fill);
      default:
        canvas.drawOval(Rect.fromCenter(center: const Offset(5, 6), width: 5.2, height: 6.4), fill);
        canvas.drawRRect(
          RRect.fromLTRBR(1.8, 1.6, 8.2, 4, const Radius.circular(1)),
          Paint()..color = const Color(Tokens.colorWorldDayBridgeEdge),
        );
    }
  }

  @override
  bool shouldRepaint(_SuitPainter old) => old.suit != suit;
}
