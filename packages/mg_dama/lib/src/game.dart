import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Dama: tap a piece, then its destination; a multi-jump is tapped square by square along
/// prefixes of legal paths. The opponent answers after `ai_think_s`.
class DamaGame implements Minigame {
  const DamaGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.dama]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.dama;
    return MinigameShell(
      id: MinigameId.dama,
      env: env,
      rules: const [MessageKey.damaRules1, MessageKey.damaRules2, MessageKey.damaRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _DamaBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _DamaBody extends StatefulWidget {
  const _DamaBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_DamaBody> createState() => _DamaBodyState();
}

class _DamaBodyState extends State<_DamaBody> {
  final DamaRules _rules = DamaRules();
  late final Prng _ai = aiPrng(widget.ctx.seed);
  late DamaState _s = _rules.start(DamaConfig.fromTuning(widget.env.tuning.minigames.dama), widget.ctx.seed);
  List<List<int>> _legal = const [];
  List<int> _sel = const [];
  bool _must = false;
  Timer? _aiTimer;

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
    super.dispose();
  }

  void _refresh() {
    _legal = _s.turn == 'player' ? [for (final a in _rules.legalActions(_s)) a.path] : const [];
    _must = _s.turn == 'player' && mustCapture(_s);
  }

  void _status() {
    if (!mounted) return;
    widget.shell.status(_s.over ? '' : (_s.turn == 'player' ? t(MessageKey.yourTurn) : t(MessageKey.opponentTurn)));
  }

  bool _startsWith(List<int> p, List<int> prefix) {
    if (p.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (p[i] != prefix[i]) return false;
    }
    return true;
  }

  void _tap(int i) {
    if (widget.shell.paused || _s.over || _s.turn != 'player') return;
    final step = [..._sel, i];
    final matches = _sel.isEmpty ? const <List<int>>[] : _legal.where((p) => _startsWith(p, step)).toList();
    if (matches.isNotEmpty) {
      final full = matches.where((p) => p.length == step.length).firstOrNull;
      if (full != null) {
        _sel = const [];
        _play(DamaAction('player', full));
        return;
      }
      setState(() => _sel = step);
    } else {
      setState(() => _sel = _legal.any((p) => p.first == i) ? [i] : const []);
    }
  }

  void _play(DamaAction a) {
    if (widget.shell.paused || _s.over) return;
    setState(() {
      _s = _rules.apply(_s, a);
      _refresh();
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
    final ms = (widget.env.tuning.minigames.dama.aiThinkS * 1000).round();
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
      _s = _rules.apply(_s, const DamaAction.timeout());
      _sel = const [];
      _refresh();
    });
    final r = _rules.result(_s)!;
    widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
  }

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: Color(Tokens.colorUiTextMuted));
    final next = <int>{
      if (_sel.isNotEmpty)
        for (final p in _legal)
          if (p.length > _sel.length && _startsWith(p, _sel)) p[_sel.length],
    };
    final starts = _must ? {for (final p in _legal) p.first} : const <int>{};
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceMd),
      child: Column(
        children: [
          Text(
            t(MessageKey.damaPieces, {'player': countPieces(_s.board, 'player'), 'ai': countPieces(_s.board, 'ai')}),
            style: muted,
          ),
          const SizedBox(height: Tokens.spaceSm),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: LayoutBuilder(
                  builder: (context, box) => GestureDetector(
                    key: const ValueKey('dama-board'),
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) {
                      final cell = box.maxWidth / 8;
                      final sq = squareAt((d.localPosition.dy / cell).floor(), (d.localPosition.dx / cell).floor());
                      if (sq >= 0) _tap(sq);
                    },
                    child: CustomPaint(painter: _BoardPainter(_s.board, _sel, next, starts), size: Size.infinite),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: Tokens.spaceSm),
          Text(
            !_s.over && _must ? t(MessageKey.damaMustCapture) : '',
            style: const TextStyle(color: Color(Tokens.colorUiNotice), fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// 8×8 board with the AI on top (same layout as the web client).
class _BoardPainter extends CustomPainter {
  _BoardPainter(this.board, this.sel, this.next, this.must);

  final String board;
  final List<int> sel;
  final Set<int> next, must;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 8;
    final light = Paint()..color = const Color(Tokens.colorWorldDayLand);
    final dark = Paint()..color = Color(Tokens.colorWorldDayFacades[6]);
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        canvas.drawRect(Rect.fromLTWH(c * cell, r * cell, cell, cell), (r + c).isOdd ? dark : light);
      }
    }
    final trail = Paint()..color = const Color(Tokens.colorUiControlHand);
    final accent = Paint()..color = const Color(Tokens.colorBrandAccent);
    for (var i = 0; i < 32; i++) {
      final center = Offset((colOf(i) + 0.5) * cell, (rowOf(i) + 0.5) * cell);
      if (sel.contains(i)) {
        canvas.drawRect(Rect.fromCenter(center: center, width: cell, height: cell), trail);
      }
      final ch = board[i];
      if (ch != '.') {
        final mine = ch == 'w' || ch == 'W';
        canvas.drawCircle(
          center,
          cell * 0.38,
          Paint()..color = Color(mine ? Tokens.colorWorldDayMarking : Tokens.colorWorldNightAsphalt),
        );
        final ring = sel.isNotEmpty && sel.first == i
            ? (Tokens.colorBrandAccent, 0.15)
            : must.contains(i)
            ? (Tokens.colorUiNotice, 0.13)
            : (mine ? Tokens.colorWorldDayBridgeEdge : Tokens.colorWorldNightMarking, 0.06);
        canvas.drawCircle(
          center,
          cell * 0.38,
          Paint()
            ..color = Color(ring.$1)
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * ring.$2,
        );
        if (ch == 'W' || ch == 'B') {
          canvas.drawCircle(
            center,
            cell * 0.18,
            Paint()
              ..color = const Color(Tokens.colorBrandAccent)
              ..style = PaintingStyle.stroke
              ..strokeWidth = cell * 0.08,
          );
        }
      }
      if (next.contains(i)) canvas.drawCircle(center, cell * 0.14, accent);
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) => true;
}
