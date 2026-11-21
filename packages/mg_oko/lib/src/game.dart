import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Rank and suit glyphs (symbols, not texts): rank = c mod 13, suit = c div 13 (♠ ♥ ♦ ♣).
const _ranks = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
const _suits = ['♠', '♥', '♦', '♣'];
const _flashMs = 900;

/// Oko bere (twenty-one): Hit or Stand, the banker draws to `dealer_stand`.
class OkoGame implements Minigame {
  const OkoGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.oko]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.oko;
    return MinigameShell(
      id: MinigameId.oko,
      env: env,
      rules: const [MessageKey.okoRules1, MessageKey.okoRules2, MessageKey.okoRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _OkoBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _OkoBody extends StatefulWidget {
  const _OkoBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_OkoBody> createState() => _OkoBodyState();
}

class _OkoBodyState extends State<_OkoBody> {
  final OkoRules _rules = OkoRules();
  late OkoState _s = _rules.start(OkoConfig.fromTuning(widget.env.tuning.minigames.oko), widget.ctx.seed);

  /// What the table shows: the live hands, or a finished round being revealed from `last`.
  late List<int> _player = _s.player, _dealer = _s.dealer;
  late bool _hole = _s.phase == 'play';
  bool _busy = false;
  String? _flash;
  Timer? _timer;

  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  bool get _canPlay => !_busy && _s.phase == 'play' && !_s.over;

  @override
  void initState() {
    super.initState();
    widget.hooks.onTimeout = _timeout;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _status();
      // A natural right at the first deal resolves inside start; show it like any other round.
      if (mounted && _s.last.outcome != '') _reveal();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _status() {
    if (mounted) widget.shell.status(_canPlay ? t(MessageKey.yourTurn) : '');
  }

  void _showLive() {
    _player = _s.player;
    _dealer = _s.dealer;
    _hole = _s.phase == 'play';
  }

  String _outcomeText(OkoLast l) => switch (l.outcome) {
    'push' => t(MessageKey.okoPush),
    'win' => isNatural(l.player) ? t(MessageKey.okoNatural) : t(MessageKey.roundWon),
    _ => handTotal(l.player) > 21 ? t(MessageKey.okoBust) : t(MessageKey.roundLost),
  };

  /// Waits while paused, then runs [f] after [ms].
  void _later(int ms, VoidCallback f) {
    void tick() {
      if (!mounted) return;
      if (widget.shell.paused) {
        _timer = Timer(const Duration(milliseconds: 200), tick);
        return;
      }
      f();
    }

    _timer = Timer(Duration(milliseconds: ms), tick);
  }

  /// Reveals the finished round from `last`: hole card, the banker's draws, then the outcome.
  void _reveal() {
    final l = _s.last;
    var k = l.dealer.length < 2 ? l.dealer.length : 2;
    final drawMs = (widget.env.tuning.minigames.oko.dealerDrawS * 1000).round();
    void step() {
      setState(() {
        _busy = true;
        _player = l.player;
        _dealer = l.dealer.sublist(0, k);
        _hole = false;
      });
      _status();
      if (k < l.dealer.length) {
        k++;
        _later(drawMs, step);
        return;
      }
      setState(() => _flash = _outcomeText(l));
      _later(_flashMs, () {
        final r = _rules.result(_s);
        if (r != null) {
          widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
          return;
        }
        setState(() {
          _flash = null;
          _busy = false;
          _showLive();
        });
        _status();
      });
    }

    step();
  }

  void _play(OkoAction a) {
    if (widget.shell.paused || !_canPlay) return;
    final before = _s;
    _s = _rules.apply(_s, a);
    if (_s.round != before.round || _s.over) {
      _reveal();
    } else {
      setState(_showLive);
    }
  }

  void _timeout() {
    if (_s.over) return;
    _timer?.cancel();
    setState(() {
      _s = _rules.apply(_s, const OkoAction.timeout());
      _busy = true;
    });
    _status();
    final r = _rules.result(_s)!;
    widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
  }

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: Color(Tokens.colorUiTextMuted));
    const label = TextStyle(color: Color(Tokens.colorUiText), fontSize: 18, fontWeight: FontWeight.w700);
    final shownDealer = _hole ? _dealer.take(1).toList() : _dealer;
    Widget hand(List<int> cards, {bool hole = false}) => ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 96),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: Tokens.spaceXs,
        runSpacing: Tokens.spaceXs,
        children: [for (var i = 0; i < cards.length; i++) _CardView(hole && i > 0 ? null : cards[i])],
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceMd),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${t(MessageKey.okoBanker)}  ${t(MessageKey.okoTotal, {'total': handTotal(shownDealer)})}',
            style: label,
          ),
          const SizedBox(height: Tokens.spaceSm),
          hand(_dealer, hole: _hole),
          const Spacer(),
          SizedBox(
            height: 32,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                color: Color(_flash != null ? Tokens.colorBrandAccent : Tokens.colorUiText),
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
              child: Text(_flash ?? ''),
            ),
          ),
          const Spacer(),
          hand(_player),
          const SizedBox(height: Tokens.spaceSm),
          Text('${t(MessageKey.okoYou)}  ${t(MessageKey.okoTotal, {'total': handTotal(_player)})}', style: label),
          const SizedBox(height: Tokens.spaceSm),
          Text(t(MessageKey.roundScore, {'player': _s.playerWins, 'ai': _s.dealerWins}), style: muted),
          const SizedBox(height: Tokens.spaceSm),
          Row(
            children: [
              for (final (a, k) in [(OkoAction.hit, MessageKey.okoHit), (OkoAction.stand, MessageKey.okoStand)])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Tokens.spaceXs),
                    child: FilledButton(onPressed: _canPlay ? () => _play(a) : null, child: Text(t(k))),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A card face (rank over suit) or, for null, the back.
class _CardView extends StatelessWidget {
  const _CardView(this.card);

  final int? card;

  @override
  Widget build(BuildContext context) {
    final c = card;
    final radius = BorderRadius.circular(Tokens.radiusButton);
    if (c == null) {
      return Container(
        width: 64,
        height: 92,
        decoration: BoxDecoration(
          color: const Color(Tokens.colorBrandAccent),
          borderRadius: radius,
          border: Border.all(color: const Color(Tokens.colorUiText), width: 4),
        ),
      );
    }
    final s = suitOf(c);
    final color = Color(s == 1 || s == 2 ? Tokens.colorUiControlBrake : Tokens.colorUiBackground);
    return Container(
      width: 64,
      height: 92,
      decoration: BoxDecoration(color: const Color(Tokens.colorUiText), borderRadius: radius),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _ranks[rankOf(c)],
            style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w700, height: 1.1),
          ),
          Text(
            _suits[s],
            style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.w700, height: 1.1),
          ),
        ],
      ),
    );
  }
}
