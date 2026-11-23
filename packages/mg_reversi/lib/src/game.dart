import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Reversi: legal squares carry small dots, a tap plays. Without a legal move the UI passes on the
/// player's behalf after a short toast. The opponent answers after `ai_think_s`.
class ReversiGame implements Minigame {
  const ReversiGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.reversi]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.reversi;
    return MinigameShell(
      id: MinigameId.reversi,
      env: env,
      rules: const [MessageKey.reversiRules1, MessageKey.reversiRules2, MessageKey.reversiRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _ReversiBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _ReversiBody extends StatefulWidget {
  const _ReversiBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_ReversiBody> createState() => _ReversiBodyState();
}

class _ReversiBodyState extends State<_ReversiBody> {
  final ReversiRules _rules = ReversiRules();
  late final Prng _ai = aiPrng(widget.ctx.seed);
  late ReversiState _s = _rules.start(ReversiConfig.fromTuning(widget.env.tuning.minigames.reversi), widget.ctx.seed);
  Set<int> _legal = const {};
  int _last = -1;
  bool _passNote = false;
  Timer? _aiTimer, _passTimer, _endTimer;

  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  @override
  void initState() {
    super.initState();
    widget.hooks.onTimeout = _timeout;
    _refresh();
    WidgetsBinding.instance.addPostFrameCallback((_) => _status());
  }

  @override
  void dispose() {
    _aiTimer?.cancel();
    _passTimer?.cancel();
    _endTimer?.cancel();
    super.dispose();
  }

  void _refresh() {
    _legal = _s.turn == 'player' && !_s.over ? {for (final a in _rules.legalActions(_s)) a.cell} : const {};
  }

  void _status() {
    if (!mounted) return;
    widget.shell.status(_s.over ? '' : (_s.turn == 'player' ? t(MessageKey.yourTurn) : t(MessageKey.opponentTurn)));
  }

  void _tap(int i) {
    if (widget.shell.paused || _s.over || _s.turn != 'player' || i < 0 || !_legal.contains(i)) return;
    _play(ReversiAction('player', i));
  }

  void _play(ReversiAction a) {
    if (_s.over) return;
    setState(() {
      _s = _rules.apply(_s, a);
      if (a.cell >= 0) _last = a.cell;
      _refresh();
    });
    _status();
    final r = _rules.result(_s);
    if (r != null) {
      _endTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
      });
      return;
    }
    if (_s.turn == 'ai') {
      _scheduleAi();
    } else if (_legal.length == 1 && _legal.first == -1) {
      // The player has only the pass: show the toast, then pass on their behalf.
      setState(() => _passNote = true);
      _passTimer?.cancel();
      void tick() {
        if (!mounted) return;
        if (widget.shell.paused) {
          _passTimer = Timer(const Duration(milliseconds: 200), tick);
          return;
        }
        setState(() => _passNote = false);
        _play(const ReversiAction('player', -1));
      }

      _passTimer = Timer(const Duration(milliseconds: 1200), tick);
    }
  }

  void _scheduleAi() {
    if (_s.turn != 'ai' || _s.over) return;
    _aiTimer?.cancel();
    final ms = (widget.env.tuning.minigames.reversi.aiThinkS * 1000).round();
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
    _passTimer?.cancel();
    setState(() {
      _s = _rules.apply(_s, const ReversiAction.timeout());
      _refresh();
    });
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
          Text(
            t(MessageKey.reversiCount, {'player': discs(_s.board, 'player'), 'ai': discs(_s.board, 'ai')}),
            style: muted,
          ),
          const SizedBox(height: Tokens.spaceSm),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: LayoutBuilder(
                  builder: (context, box) => GestureDetector(
                    key: const ValueKey('reversi-board'),
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) {
                      final cell = box.maxWidth / 8;
                      final r = (d.localPosition.dy / cell).floor(), c = (d.localPosition.dx / cell).floor();
                      if (r >= 0 && r < 8 && c >= 0 && c < 8) _tap(r * 8 + c);
                    },
                    child: CustomPaint(painter: _BoardPainter(_s.board, _legal, _last), size: Size.infinite),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: Tokens.spaceSm),
          Text(
            _passNote && !_s.over ? t(MessageKey.reversiPass) : '',
            style: const TextStyle(color: Color(Tokens.colorUiNotice), fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// 8×8 felt with discs; legal squares as small dots, the last move ringed.
class _BoardPainter extends CustomPainter {
  _BoardPainter(this.board, this.legal, this.last);

  final String board;
  final Set<int> legal;
  final int last;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 8;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(Tokens.colorWorldDayPark));
    final line = Paint()
      ..color = const Color(Tokens.colorWorldNightPark)
      ..strokeWidth = 1;
    for (var k = 0; k <= 8; k++) {
      canvas.drawLine(Offset(k * cell, 0), Offset(k * cell, size.height), line);
      canvas.drawLine(Offset(0, k * cell), Offset(size.width, k * cell), line);
    }
    final dot = Paint()..color = const Color(Tokens.colorBrandAccent);
    for (var i = 0; i < 64; i++) {
      final center = Offset(((i & 7) + 0.5) * cell, ((i >> 3) + 0.5) * cell);
      final ch = board[i];
      if (ch != '.') {
        canvas.drawCircle(
          center,
          cell * 0.4,
          Paint()..color = Color(ch == 'x' ? Tokens.colorWorldNightAsphalt : Tokens.colorWorldDayMarking),
        );
        if (i == last) {
          canvas.drawCircle(
            center,
            cell * 0.4,
            Paint()
              ..color = const Color(Tokens.colorBrandAccent)
              ..style = PaintingStyle.stroke
              ..strokeWidth = cell * 0.08,
          );
        }
      } else if (legal.contains(i)) {
        canvas.drawCircle(center, cell * 0.12, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) => true;
}
