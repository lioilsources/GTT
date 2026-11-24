import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Solid chess glyphs (no text) with the text-presentation selector, coloured per side.
const _glyph = {'k': '♚', 'q': '♛', 'r': '♜', 'b': '♝', 'n': '♞', 'p': '♟'};

/// Bulvárové šachy (Gardner 5×5): tap your piece to see its targets, tap a target to move; the
/// last move stays highlighted. The opponent answers after `ai_think_s`.
class SachyGame implements Minigame {
  const SachyGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.sachy]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.sachy;
    return MinigameShell(
      id: MinigameId.sachy,
      env: env,
      rules: const [MessageKey.sachyRules1, MessageKey.sachyRules2, MessageKey.sachyRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _SachyBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _SachyBody extends StatefulWidget {
  const _SachyBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_SachyBody> createState() => _SachyBodyState();
}

class _SachyBodyState extends State<_SachyBody> {
  final SachyRules _rules = SachyRules();
  late final Prng _ai = aiPrng(widget.ctx.seed);
  late SachyState _s = _rules.start(SachyConfig.fromTuning(widget.env.tuning.minigames.sachy), widget.ctx.seed);
  List<SachyAction> _moves = const [];
  int _sel = -1;
  List<int> _last = const [];
  bool _check = false;
  Timer? _aiTimer, _endTimer, _checkTimer;

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
    _endTimer?.cancel();
    _checkTimer?.cancel();
    super.dispose();
  }

  void _refresh() => _moves = _s.turn == 'player' && !_s.over ? _rules.legalActions(_s) : const [];

  void _status() {
    if (!mounted) return;
    widget.shell.status(_s.over ? '' : (_s.turn == 'player' ? t(MessageKey.yourTurn) : t(MessageKey.opponentTurn)));
  }

  void _tap(int i) {
    if (widget.shell.paused || _s.over || _s.turn != 'player') return;
    final m = _moves.where((m) => m.from == _sel && m.to == i);
    if (_sel >= 0 && m.isNotEmpty) {
      _play(m.first);
      return;
    }
    setState(() => _sel = _moves.any((m) => m.from == i) ? i : -1);
  }

  void _play(SachyAction a) {
    if (_s.over) return;
    setState(() {
      _s = _rules.apply(_s, a);
      _sel = -1;
      _last = [a.from, a.to];
      _check = !_s.over && _rules.check(_s);
      _refresh();
    });
    if (_check) {
      _checkTimer?.cancel();
      _checkTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _check = false);
      });
    }
    _status();
    final r = _rules.result(_s);
    if (r != null) {
      _endTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
      });
      return;
    }
    if (_s.turn == 'ai') _scheduleAi();
  }

  void _scheduleAi() {
    _aiTimer?.cancel();
    final ms = (widget.env.tuning.minigames.sachy.aiThinkS * 1000).round();
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
    setState(() {
      _s = _rules.apply(_s, const SachyAction.timeout());
      _refresh();
    });
    final r = _rules.result(_s)!;
    widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
  }

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: Color(Tokens.colorUiTextMuted));
    final targets = {
      for (final m in _moves)
        if (m.from == _sel) m.to,
    };
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceMd),
      child: Column(
        children: [
          Text(
            t(MessageKey.sachyMaterial, {
              'player': sachyMaterial(_s.board, 'player'),
              'ai': sachyMaterial(_s.board, 'ai'),
            }),
            style: muted,
          ),
          const SizedBox(height: Tokens.spaceSm),
          Text(
            _check ? t(MessageKey.sachyCheck) : '',
            style: const TextStyle(color: Color(Tokens.colorUiNotice), fontWeight: FontWeight.w700),
          ),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: LayoutBuilder(
                  builder: (context, box) => GestureDetector(
                    key: const ValueKey('sachy-board'),
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) {
                      final cell = box.maxWidth / 5;
                      final r = (d.localPosition.dy / cell).floor(), c = (d.localPosition.dx / cell).floor();
                      if (r >= 0 && r < 5 && c >= 0 && c < 5) _tap(r * 5 + c);
                    },
                    child: CustomPaint(painter: _BoardPainter(_s.board, targets, _last, _sel), size: Size.infinite),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 5×5 board with glyph pieces; selected square and the last move tinted, targets as dots.
class _BoardPainter extends CustomPainter {
  _BoardPainter(this.board, this.targets, this.last, this.sel);

  final String board;
  final Set<int> targets;
  final List<int> last;
  final int sel;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 5;
    for (var i = 0; i < 25; i++) {
      final r = i ~/ 5, c = i % 5;
      final rect = Rect.fromLTWH(c * cell, r * cell, cell, cell);
      canvas.drawRect(
        rect,
        Paint()..color = Color((r + c).isOdd ? Tokens.colorWorldDayFacades[5] : Tokens.colorWorldDayLand),
      );
      if (last.contains(i) || i == sel) {
        canvas.drawRect(rect, Paint()..color = const Color(Tokens.colorUiControlHand));
      }
      final ch = board[i];
      if (ch != '.') {
        final mine = ch == ch.toUpperCase();
        final tp = TextPainter(
          text: TextSpan(
            text: '${_glyph[ch.toLowerCase()]}︎',
            style: TextStyle(
              fontSize: cell * 0.72,
              color: Color(mine ? Tokens.colorWorldDayMarking : Tokens.colorWorldNightAsphalt),
              shadows: [
                Shadow(
                  color: Color(mine ? Tokens.colorWorldDayBridgeEdge : Tokens.colorWorldNightMarking),
                  blurRadius: 1.5,
                ),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
      }
      if (targets.contains(i)) {
        canvas.drawCircle(rect.center, cell * 0.14, Paint()..color = const Color(Tokens.colorBrandAccent));
      }
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) => true;
}
