import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Piškvorky: the first tap selects a square, a second tap on it places the mark (big fingers on
/// a 15×15 board). The last AI mark is ringed, the winning row marked. The opponent answers after
/// `ai_think_s`.
class PiskvorkyGame implements Minigame {
  const PiskvorkyGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.piskvorky]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.piskvorky;
    return MinigameShell(
      id: MinigameId.piskvorky,
      env: env,
      rules: const [MessageKey.piskvorkyRules1, MessageKey.piskvorkyRules2, MessageKey.piskvorkyRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _PiskvorkyBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _PiskvorkyBody extends StatefulWidget {
  const _PiskvorkyBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_PiskvorkyBody> createState() => _PiskvorkyBodyState();
}

class _PiskvorkyBodyState extends State<_PiskvorkyBody> {
  final PiskvorkyRules _rules = PiskvorkyRules();
  late final Prng _ai = aiPrng(widget.ctx.seed);
  late final PiskvorkyConfig _cfg = PiskvorkyConfig.fromTuning(widget.env.tuning.minigames.piskvorky);
  late PiskvorkyState _s = _rules.start(_cfg, widget.ctx.seed);
  int _sel = -1, _lastAi = -1, _lastCell = -1;
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
    super.dispose();
  }

  void _status() {
    if (!mounted) return;
    widget.shell.status(_s.over ? '' : (_s.turn == 'player' ? t(MessageKey.yourTurn) : t(MessageKey.opponentTurn)));
  }

  void _tap(int i) {
    if (widget.shell.paused || _s.over || _s.turn != 'player' || _s.board[i] != '.') return;
    if (_sel != i) {
      setState(() => _sel = i);
      return;
    }
    _sel = -1;
    _play(PiskvorkyAction('player', i));
  }

  void _play(PiskvorkyAction a) {
    if (_s.over) return;
    setState(() {
      _s = _rules.apply(_s, a);
      _lastCell = a.cell;
      if (a.by == 'ai') _lastAi = a.cell;
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
    final ms = (widget.env.tuning.minigames.piskvorky.aiThinkS * 1000).round();
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
    setState(() {
      _s = _rules.apply(_s, const PiskvorkyAction.timeout());
      _sel = -1;
    });
    _status();
    final r = _rules.result(_s)!;
    widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
  }

  @override
  Widget build(BuildContext context) {
    final n = _cfg.size;
    final win = _s.over && _lastCell >= 0 ? winningLine(_s.board, n, _lastCell).toSet() : const <int>{};
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceMd),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: LayoutBuilder(
                  builder: (context, box) => GestureDetector(
                    key: const ValueKey('piskvorky-board'),
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) {
                      final cell = box.maxWidth / n;
                      final r = (d.localPosition.dy / cell).floor(), c = (d.localPosition.dx / cell).floor();
                      if (r >= 0 && r < n && c >= 0 && c < n) _tap(r * n + c);
                    },
                    child: CustomPaint(
                      painter: _BoardPainter(_s.board, n, _sel, _lastAi, win),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: Tokens.spaceSm),
          Text(
            _sel >= 0 ? t(MessageKey.piskvorkyTapAgain) : '',
            style: const TextStyle(color: Color(Tokens.colorUiNotice), fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter(this.board, this.n, this.sel, this.lastAi, this.win);

  final String board;
  final int n, sel, lastAi;
  final Set<int> win;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / n;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(Tokens.colorWorldDayLand));
    final grid = Paint()
      ..color = Color(Tokens.colorWorldDayFacades[6])
      ..strokeWidth = 1;
    final selPaint = Paint()..color = const Color(Tokens.colorUiControlHand);
    final winPaint = Paint()..color = const Color(Tokens.colorBrandAccent);
    for (var i = 0; i < n * n; i++) {
      final rect = Rect.fromLTWH((i % n) * cell, (i ~/ n) * cell, cell, cell);
      if (win.contains(i)) {
        canvas.drawRect(rect, winPaint);
      } else if (i == sel) {
        canvas.drawRect(rect, selPaint);
      }
    }
    for (var k = 0; k <= n; k++) {
      canvas.drawLine(Offset(k * cell, 0), Offset(k * cell, size.height), grid);
      canvas.drawLine(Offset(0, k * cell), Offset(size.width, k * cell), grid);
    }
    final x = Paint()
      ..color = const Color(Tokens.colorWorldNightAsphalt)
      ..strokeWidth = cell * 0.12
      ..strokeCap = StrokeCap.round;
    final ghost = Paint()
      ..color = const Color(Tokens.colorUiTextMuted)
      ..strokeWidth = cell * 0.08
      ..strokeCap = StrokeCap.round;
    final o = Paint()
      ..color = const Color(Tokens.colorUiNotice)
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.12;
    final ring = Paint()
      ..color = const Color(Tokens.colorBrandAccent)
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.08;
    for (var i = 0; i < n * n; i++) {
      final c = Offset((i % n + 0.5) * cell, (i ~/ n + 0.5) * cell);
      final ch = board[i];
      void cross(Paint p, double k) {
        final d = cell * k;
        canvas.drawLine(c - Offset(d, d), c + Offset(d, d), p);
        canvas.drawLine(c - Offset(d, -d), c + Offset(d, -d), p);
      }

      if (ch == 'x') {
        cross(x, 0.25);
      } else if (ch == 'o') {
        canvas.drawCircle(c, cell * 0.28, o);
        if (i == lastAi) canvas.drawCircle(c, cell * 0.45, ring);
      } else if (i == sel) {
        cross(ghost, 0.2);
      }
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) => true;
}
