import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Point positions on a 7×7 grid (specs/minigames/mlyn.md "Deska"), same as the web client.
const List<(int, int)> mlynGrid = [
  (0, 0), (3, 0), (6, 0), (1, 1), (3, 1), (5, 1), (2, 2), (3, 2), (4, 2), //
  (0, 3), (1, 3), (2, 3), (4, 3), (5, 3), (6, 3),
  (2, 4), (3, 4), (4, 4), (1, 5), (3, 5), (5, 5), (0, 6), (3, 6), (6, 6),
];

/// Centre of point [p] on a square board [side] px wide (grid cell = side / 7).
Offset mlynPoint(int p, double side) {
  final cell = side / 7;
  return Offset((mlynGrid[p].$1 + 0.5) * cell, (mlynGrid[p].$2 + 0.5) * cell);
}

/// Mlýn: placing by tapping a point, moving by tapping a stone and then its target; after a mill
/// the board recolours and the player taps the rival stone to take. The opponent answers after
/// `ai_think_s`.
class MlynGame implements Minigame {
  const MlynGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.mlyn]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.mlyn;
    return MinigameShell(
      id: MinigameId.mlyn,
      env: env,
      rules: const [MessageKey.mlynRules1, MessageKey.mlynRules2, MessageKey.mlynRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _MlynBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _MlynBody extends StatefulWidget {
  const _MlynBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_MlynBody> createState() => _MlynBodyState();
}

class _MlynBodyState extends State<_MlynBody> {
  final MlynRules _rules = MlynRules();
  late final Prng _ai = aiPrng(widget.ctx.seed);
  late MlynState _s = _rules.start(MlynConfig.fromTuning(widget.env.tuning.minigames.mlyn), widget.ctx.seed);
  List<MlynAction> _legal = const [];
  int _from = -1;

  /// Moves waiting for the removal choice (same from and to).
  List<MlynAction> _taking = const [];
  MlynAction? _lastAi;
  Timer? _aiTimer;
  bool _ended = false;

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
    _legal = _s.turn == 'player' && !_s.over ? _rules.legalActions(_s) : const [];
  }

  void _status() {
    if (!mounted) return;
    widget.shell.status(_s.over ? '' : (_s.turn == 'player' ? t(MessageKey.yourTurn) : t(MessageKey.opponentTurn)));
  }

  void _tap(int p) {
    if (widget.shell.paused || _s.over || _s.turn != 'player') return;
    if (_taking.isNotEmpty) {
      final m = _taking.where((x) => x.remove == p).firstOrNull;
      if (m != null) {
        _taking = const [];
        _from = -1;
        _play(m);
      }
      return;
    }
    final placing = _s.handPlayer > 0;
    if (!placing && _s.board[p] == 'w') {
      setState(() => _from = _legal.any((m) => m.from == p) ? p : -1);
      return;
    }
    final f = placing ? -1 : _from;
    if (!placing && f < 0) return;
    final ms = _legal.where((m) => m.from == f && m.to == p).toList();
    if (ms.isEmpty) return;
    if (ms.length == 1 && ms.first.remove == -1) {
      _from = -1;
      _play(ms.first);
      return;
    }
    // A mill: the player taps the rival stone to take (even when only one is allowed).
    setState(() => _taking = ms);
  }

  void _play(MlynAction a) {
    if (_s.over) return;
    setState(() {
      _s = _rules.apply(_s, a);
      if (a.by == 'ai') _lastAi = a;
      _refresh();
    });
    _status();
    final r = _rules.result(_s);
    if (r != null) {
      _ended = true;
      _aiTimer?.cancel();
      _aiTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
      });
      return;
    }
    _scheduleAi();
  }

  void _scheduleAi() {
    if (_ended || _s.turn != 'ai' || _s.over) return;
    _aiTimer?.cancel();
    final ms = (widget.env.tuning.minigames.mlyn.aiThinkS * 1000).round();
    void tick() {
      if (!mounted || _ended) return;
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
    _ended = true;
    _aiTimer?.cancel();
    setState(() {
      _s = _rules.apply(_s, const MlynAction.timeout());
      _taking = const [];
      _from = -1;
      _legal = const [];
    });
    final r = _rules.result(_s)!;
    widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
  }

  int _pointAt(Offset o, double side) {
    var best = -1;
    var bestD = double.infinity;
    for (var p = 0; p < 24; p++) {
      final d = (mlynPoint(p, side) - o).distance;
      if (d < bestD) {
        bestD = d;
        best = p;
      }
    }
    return bestD <= side / 14 ? best : -1;
  }

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: Color(Tokens.colorUiTextMuted));
    final placing = _s.handPlayer > 0;
    final targets = _taking.isNotEmpty || (!placing && _from < 0)
        ? const <int>{}
        : {
            for (final m in _legal)
              if (placing ? m.from == -1 : m.from == _from) m.to,
          };
    final movable = placing || _taking.isNotEmpty ? const <int>{} : {for (final m in _legal) m.from};
    final take = {for (final m in _taking) m.remove};
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceMd),
      child: Column(
        children: [
          Text(t(MessageKey.mlynHand, {'player': _s.handPlayer, 'ai': _s.handAi}), style: muted),
          const SizedBox(height: Tokens.spaceSm),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: LayoutBuilder(
                  builder: (context, box) => GestureDetector(
                    key: const ValueKey('mlyn-board'),
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) {
                      final p = _pointAt(d.localPosition, box.maxWidth);
                      if (p >= 0) _tap(p);
                    },
                    child: CustomPaint(
                      painter: _BoardPainter(_s.board, _from, targets, movable, take, _lastAi?.to ?? -1),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: Tokens.spaceSm),
          Text(
            !_s.over && _taking.isNotEmpty ? t(MessageKey.mlynTake) : '',
            style: const TextStyle(color: Color(Tokens.colorUiNotice), fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter(this.board, this.from, this.targets, this.movable, this.take, this.lastAi);

  final String board;
  final int from, lastAi;
  final Set<int> targets, movable, take;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.width;
    final cell = side / 7;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(Tokens.colorWorldDayLand));
    final line = Paint()
      ..color = Color(Tokens.colorWorldDayFacades[6])
      ..strokeWidth = cell * 0.08;
    for (final m in mills) {
      canvas.drawLine(mlynPoint(m[0], side), mlynPoint(m[2], side), line);
    }
    final accent = Paint()..color = const Color(Tokens.colorBrandAccent);
    for (var p = 0; p < 24; p++) {
      final c = mlynPoint(p, side);
      final ch = board[p];
      if (ch == '.') {
        final target = targets.contains(p);
        canvas.drawCircle(c, cell * (target ? 0.16 : 0.1), target ? accent : line);
        continue;
      }
      final mine = ch == 'w';
      canvas.drawCircle(
        c,
        cell * 0.33,
        Paint()..color = Color(mine ? Tokens.colorWorldDayMarking : Tokens.colorWorldNightAsphalt),
      );
      final ring = p == from
          ? (Tokens.colorBrandAccent, 0.12)
          : take.contains(p)
          ? (Tokens.colorUiNotice, 0.12)
          : movable.contains(p)
          ? (Tokens.colorUiControlHand, 0.08)
          : p == lastAi
          ? (Tokens.colorBrandAccent, 0.06)
          : (mine ? Tokens.colorWorldDayBridgeEdge : Tokens.colorWorldNightMarking, 0.05);
      canvas.drawCircle(
        c,
        cell * 0.33,
        Paint()
          ..color = Color(ring.$1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * ring.$2,
      );
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) => true;
}
