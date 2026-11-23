import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Lodě: the rival grid on top (a tap fires), the own smaller grid below, "Re-deal" before the
/// first shot. A sunk ship is outlined. The opponent fires after `ai_think_s` (again after a hit).
class LodeGame implements Minigame {
  const LodeGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.lode]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.lode;
    return MinigameShell(
      id: MinigameId.lode,
      env: env,
      rules: const [MessageKey.lodeRules1, MessageKey.lodeRules2, MessageKey.lodeRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _LodeBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _LodeBody extends StatefulWidget {
  const _LodeBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_LodeBody> createState() => _LodeBodyState();
}

class _LodeBodyState extends State<_LodeBody> {
  final LodeRules _rules = LodeRules();
  late final Prng _ai = aiPrng(widget.ctx.seed);
  late LodeState _s = _rules.start(LodeConfig.fromTuning(widget.env.tuning.minigames.lode), widget.ctx.seed);
  int _lastAi = -1;
  bool _sunkNote = false;
  Timer? _aiTimer, _toast, _endTimer;

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
    _toast?.cancel();
    _endTimer?.cancel();
    super.dispose();
  }

  void _status() {
    if (!mounted) return;
    widget.shell.status(_s.over ? '' : (_s.turn == 'player' ? t(MessageKey.yourTurn) : t(MessageKey.opponentTurn)));
  }

  int _sunkCount(LodeState s) => s.aShips.where((sh) => sunk(sh, s.aShots)).length;

  void _tap(int i) {
    if (widget.shell.paused || _s.over || _s.turn != 'player' || _s.aShots[i] != '.') return;
    _act(LodeAction.shot('player', i));
  }

  void _act(LodeAction a) {
    if (_s.over || widget.shell.paused) return;
    final before = a.by == 'player' ? _sunkCount(_s) : -1;
    setState(() {
      _s = _rules.apply(_s, a);
      if (a.by == 'ai' && a.op == 'shot') _lastAi = a.cell;
      if (before >= 0 && _sunkCount(_s) > before) {
        _sunkNote = true;
        _toast?.cancel();
        _toast = Timer(const Duration(milliseconds: 1200), () {
          if (mounted) setState(() => _sunkNote = false);
        });
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
    if (_s.turn != 'ai' || _s.over) return;
    _aiTimer?.cancel();
    final ms = (widget.env.tuning.minigames.lode.aiThinkS * 1000).round();
    void tick() {
      if (!mounted) return;
      if (widget.shell.paused) {
        _aiTimer = Timer(const Duration(milliseconds: 200), tick);
        return;
      }
      _act(_rules.aiAction(_s, widget.ctx.difficulty, _ai));
    }

    _aiTimer = Timer(Duration(milliseconds: ms), tick);
  }

  void _timeout() {
    if (_s.over) return;
    _aiTimer?.cancel();
    setState(() => _s = _rules.apply(_s, const LodeAction.timeout()));
    final r = _rules.result(_s)!;
    widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
  }

  Widget _grid(Key key, String shots, List<List<int>> ships, bool showShips, void Function(int)? onTap) => AspectRatio(
    aspectRatio: 1,
    child: LayoutBuilder(
      builder: (context, box) => GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTapUp: onTap == null
            ? null
            : (d) {
                final cell = box.maxWidth / 10;
                final x = (d.localPosition.dx / cell).floor(), y = (d.localPosition.dy / cell).floor();
                if (x >= 0 && x < 10 && y >= 0 && y < 10) onTap(y * 10 + x);
              },
        child: CustomPaint(
          painter: _SeaPainter(shots, ships, showShips, showShips ? _lastAi : -1),
          size: Size.infinite,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: Color(Tokens.colorUiTextMuted));
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceMd),
      child: Column(
        children: [
          Text(t(MessageKey.lodeShots, {'n': _s.shots}), style: muted),
          const SizedBox(height: Tokens.spaceSm),
          Expanded(
            flex: 3,
            child: Center(child: _grid(const ValueKey('lode-rival'), _s.aShots, _s.aShips, false, _tap)),
          ),
          SizedBox(
            height: 24,
            child: Text(
              _sunkNote ? t(MessageKey.lodeSunk) : '',
              style: const TextStyle(color: Color(Tokens.colorUiNotice), fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(flex: 2, child: Center(child: _grid(const ValueKey('lode-own'), _s.pShots, _s.pShips, true, null))),
          if (_s.shots == 0 && !_s.over)
            Padding(
              padding: const EdgeInsets.only(top: Tokens.spaceSm),
              child: FilledButton(
                onPressed: _rules.canShuffle(_s) ? () => _act(const LodeAction.shuffle()) : null,
                child: Text(t(MessageKey.lodeShuffle, {'n': _s.shuffles})),
              ),
            ),
        ],
      ),
    );
  }
}

/// 10×10 sea: water / ships, misses as dots, hits as crosses, sunk ships outlined.
class _SeaPainter extends CustomPainter {
  _SeaPainter(this.shots, this.ships, this.showShips, this.last);

  final String shots;
  final List<List<int>> ships;
  final bool showShips;
  final int last;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 10;
    final shipAt = {for (final sh in ships) ...sh};
    final water = Paint()..color = const Color(Tokens.colorWorldDayWater);
    final ship = Paint()..color = const Color(Tokens.colorWorldNightAsphalt);
    final grid = Paint()
      ..color = const Color(Tokens.colorWorldNightWater)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final miss = Paint()..color = const Color(Tokens.colorWorldDayMarking);
    final hit = Paint()
      ..color = const Color(Tokens.colorUiNotice)
      ..strokeWidth = cell * 0.12
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 100; i++) {
      final r = Rect.fromLTWH((i % 10) * cell, (i ~/ 10) * cell, cell, cell);
      canvas.drawRect(r, showShips && shipAt.contains(i) ? ship : water);
      canvas.drawRect(r, grid);
      final ch = shots[i];
      if (ch == 'o') {
        canvas.drawCircle(r.center, cell * 0.14, miss);
      } else if (ch == 'x') {
        final d = r.deflate(cell * 0.2);
        canvas.drawLine(d.topLeft, d.bottomRight, hit);
        canvas.drawLine(d.topRight, d.bottomLeft, hit);
      }
    }
    final outline = Paint()
      ..color = const Color(Tokens.colorBrandAccent)
      ..style = PaintingStyle.stroke
      ..strokeWidth = cell * 0.1;
    for (final sh in ships) {
      if (!sunk(sh, shots)) continue;
      var x0 = 9, y0 = 9, x1 = 0, y1 = 0;
      for (final c in sh) {
        final x = c % 10, y = c ~/ 10;
        if (x < x0) x0 = x;
        if (y < y0) y0 = y;
        if (x > x1) x1 = x;
        if (y > y1) y1 = y;
      }
      canvas.drawRect(
        Rect.fromLTRB(x0 * cell, y0 * cell, (x1 + 1) * cell, (y1 + 1) * cell).deflate(cell * 0.08),
        outline,
      );
    }
    if (last >= 0) {
      canvas.drawRect(
        Rect.fromLTWH((last % 10) * cell, (last ~/ 10) * cell, cell, cell),
        Paint()
          ..color = const Color(Tokens.colorUiControlHand)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.08,
      );
    }
  }

  @override
  bool shouldRepaint(_SeaPainter old) => true;
}
