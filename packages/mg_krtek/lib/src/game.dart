import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Ticks a mole takes to slide fully up or down (animation only, from `left`).
const _slideTicks = 6;

/// Hole centres and radius in a box of [size]: a grid three wide, rows as needed.
List<({Offset c, double r})> holeCells(Size size, int holes) {
  const cols = 3;
  final rows = (holes + cols - 1) ~/ cols;
  final side = math.min(size.width / cols, size.height / rows);
  final ox = (size.width - side * cols) / 2, oy = (size.height - side * rows) / 2;
  return [
    for (var i = 0; i < holes; i++)
      (c: Offset(ox + side * (i % cols + 0.5), oy + side * (i ~/ cols + 0.5)), r: side * 0.36),
  ];
}

/// Bouchni krtka (whack-a-mole, specs/minigames/krtek.md): tap the moles; ticks at `tick_hz`.
class KrtekGame implements Minigame {
  const KrtekGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.krtek]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.krtek;
    return MinigameShell(
      id: MinigameId.krtek,
      env: env,
      rules: const [MessageKey.krtekRules1, MessageKey.krtekRules2, MessageKey.krtekRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _KrtekBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _KrtekBody extends StatefulWidget {
  const _KrtekBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_KrtekBody> createState() => _KrtekBodyState();
}

class _KrtekBodyState extends State<_KrtekBody> with SingleTickerProviderStateMixin {
  final KrtekRules _rules = KrtekRules();
  late final TuningMinigamesKrtek _tm = widget.env.tuning.minigames.krtek;
  late final KrtekConfig _cfg = KrtekConfig.fromTuning(_tm, widget.ctx.difficulty);
  late KrtekState _s = _rules.start(_cfg, widget.ctx.seed);
  late final TickLoop _loop;
  final Stopwatch _clock = Stopwatch()..start();

  /// Recent taps (hole, ms on [_clock]) for the whack ring.
  final List<({int hole, int at})> _whacks = [];
  bool _finished = false;
  Size _size = Size.zero;

  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  @override
  void initState() {
    super.initState();
    widget.hooks.onTimeout = () => _play(const KrtekAction.timeout());
    _loop = TickLoop(
      this,
      hz: _tm.tickHz,
      paused: () => widget.shell.paused,
      running: () => !_finished,
      ticks: (n) => _play(KrtekAction.tick(n)),
      frame: () {
        if (_whacks.isNotEmpty && mounted) {
          setState(() => _whacks.removeWhere((w) => _clock.elapsedMilliseconds - w.at >= 250));
        }
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _status());
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  void _status() {
    if (mounted) widget.shell.status(t(MessageKey.scoreValue, {'score': _s.score}));
  }

  void _play(KrtekAction a) {
    if (_finished || _s.over || !mounted) return;
    final before = _s;
    setState(() => _s = _rules.apply(_s, a));
    if (_s.score != before.score) _status();
    final r = _rules.result(_s);
    if (r != null) {
      _finished = true;
      _status();
      widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
    }
  }

  void _tap(PointerDownEvent e) {
    if (widget.shell.paused || _finished) return;
    final cells = holeCells(_size, _cfg.holes);
    final i = cells.indexWhere((c) => (e.localPosition - c.c).distance <= c.r * 1.15);
    if (i < 0) return;
    _whacks.add((hole: i, at: _clock.elapsedMilliseconds));
    _play(KrtekAction.hit(i));
  }

  @override
  Widget build(BuildContext context) {
    final seconds = math.max(0, (_cfg.gameTicks - _s.tick + _tm.tickHz - 1) ~/ _tm.tickHz);
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceSm),
      child: Column(
        children: [
          Text(
            t(MessageKey.krtekTime, {'seconds': seconds}),
            style: const TextStyle(color: Color(Tokens.colorUiTextMuted)),
          ),
          const SizedBox(height: Tokens.spaceXs),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                _size = c.biggest;
                return Listener(
                  key: const ValueKey('holes'),
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _tap,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _HolesPainter(
                      s: _s,
                      up: _cfg.upTicks[_cfg.level - 1],
                      whacks: [for (final w in _whacks) (hole: w.hole, age: (_clock.elapsedMilliseconds - w.at) / 250)],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HolesPainter extends CustomPainter {
  _HolesPainter({required this.s, required this.up, required this.whacks});

  final KrtekState s;
  final int up;
  final List<({int hole, double age})> whacks;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(Tokens.colorWorldDayPark));
    final cells = holeCells(size, s.holes.length);
    for (var i = 0; i < cells.length; i++) {
      final (:c, :r) = cells[i];
      final hole = s.holes[i];
      final mouth = c.translate(0, r * 0.45);
      canvas.drawOval(
        Rect.fromCenter(center: mouth, width: 2 * r, height: r * 0.84),
        Paint()..color = const Color(Tokens.colorCarDetailBed),
      );
      if (hole.kind != '') {
        final shown = math.min(1.0, math.min(up - hole.left + 1, hole.left) / _slideTicks);
        final y = mouth.dy - r * 0.9 * shown;
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(c.dx - r, c.dy - r * 2, c.dx + r, c.dy + r * 0.45));
        if (hole.kind == 'bomb') {
          canvas.drawCircle(Offset(c.dx, y), r * 0.6, Paint()..color = const Color(Tokens.colorCarDetailTaxiChecker));
          canvas.drawLine(
            Offset(c.dx + r * 0.3, y - r * 0.5),
            Offset(c.dx + r * 0.5, y - r * 0.8),
            Paint()
              ..color = const Color(Tokens.colorTrafficLightAmber)
              ..strokeWidth = 3,
          );
        } else {
          final fur = hole.kind == 'gold' ? Tokens.colorBrandAccent : Tokens.colorGaragePaints[9];
          final eye = Paint()..color = const Color(Tokens.colorCarDetailTaxiChecker);
          canvas.drawCircle(Offset(c.dx, y), r * 0.62, Paint()..color = Color(fur));
          canvas.drawCircle(Offset(c.dx - r * 0.22, y - r * 0.15), r * 0.08, eye);
          canvas.drawCircle(Offset(c.dx + r * 0.22, y - r * 0.15), r * 0.08, eye);
          canvas.drawCircle(Offset(c.dx, y + r * 0.08), r * 0.12, Paint()..color = Color(Tokens.colorGaragePaints[7]));
        }
        canvas.restore();
      }
      canvas.drawArc(
        Rect.fromCenter(center: c.translate(0, r * 0.6), width: r * 2.1, height: r * 0.6),
        0,
        math.pi,
        true,
        Paint()..color = const Color(Tokens.colorWorldDayPark),
      );
    }
    for (final w in whacks) {
      if (w.hole >= cells.length || w.age >= 1) continue;
      final cell = cells[w.hole];
      canvas.drawCircle(
        cell.c,
        cell.r * (0.6 + w.age * 0.5),
        Paint()
          ..color = const Color(Tokens.colorWorldDayMarking).withValues(alpha: 1 - w.age)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
    }
  }

  @override
  bool shouldRepaint(_HolesPainter old) => old.s != s || old.whacks.isNotEmpty || whacks.isNotEmpty;
}
