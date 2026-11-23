import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Row colours from the top (same as the web client).
final List<int> _rowColors = [
  Tokens.colorTrafficLightRed,
  Tokens.colorGaragePaints[5],
  Tokens.colorBrandAccent,
  Tokens.colorGaragePaints[3],
  Tokens.colorGaragePaints[2],
  Tokens.colorGaragePaints[6],
];

/// Cihly (breakout, specs/minigames/cihly.md): the paddle follows the finger; ticks at `tick_hz`.
class CihlyGame implements Minigame {
  const CihlyGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.cihly]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.cihly;
    return MinigameShell(
      id: MinigameId.cihly,
      env: env,
      rules: const [MessageKey.cihlyRules1, MessageKey.cihlyRules2, MessageKey.cihlyRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _CihlyBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _CihlyBody extends StatefulWidget {
  const _CihlyBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_CihlyBody> createState() => _CihlyBodyState();
}

class _CihlyBodyState extends State<_CihlyBody> with SingleTickerProviderStateMixin {
  final CihlyRules _rules = CihlyRules();
  late final TuningMinigamesCihly _tm = widget.env.tuning.minigames.cihly;
  late final CihlyConfig _cfg = CihlyConfig.fromTuning(_tm, widget.ctx.difficulty);
  late CihlyState _s = _rules.start(_cfg, widget.ctx.seed);
  late final TickLoop _loop;
  bool _finished = false;
  Size _size = Size.zero;

  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  WorldView get _view => WorldView.fit(_size, 0, 0, _cfg.w.toDouble(), _cfg.h.toDouble(), pad: 4);

  @override
  void initState() {
    super.initState();
    widget.hooks.onTimeout = () => _play(const CihlyAction.timeout());
    _loop = TickLoop(
      this,
      hz: _tm.tickHz,
      paused: () => widget.shell.paused,
      running: () => !_finished,
      ticks: (n) => _play(CihlyAction.tick(n)),
      frame: () {},
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

  void _play(CihlyAction a) {
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

  void _follow(PointerEvent e) {
    if (widget.shell.paused) return;
    _play(CihlyAction.move(_view.toWorld(e.localPosition).x.round()));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceSm),
      child: Column(
        children: [
          Text(
            t(MessageKey.cihlyLives, {'n': _s.lives}),
            style: const TextStyle(color: Color(Tokens.colorUiTextMuted)),
          ),
          const SizedBox(height: Tokens.spaceXs),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                _size = c.biggest;
                return Listener(
                  key: const ValueKey('field'),
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _follow,
                  onPointerMove: _follow,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _FieldPainter(cfg: _cfg, s: _s),
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

class _FieldPainter extends CustomPainter {
  _FieldPainter({required this.cfg, required this.s});

  final CihlyConfig cfg;
  final CihlyState s;

  @override
  void paint(Canvas canvas, Size size) {
    final v = WorldView.fit(size, 0, 0, cfg.w.toDouble(), cfg.h.toDouble(), pad: 4);
    final k = v.k;
    canvas.drawRect(
      Rect.fromPoints(v.p(0, cfg.h), v.p(cfg.w, 0)),
      Paint()..color = const Color(Tokens.colorWorldNightAsphalt),
    );
    for (var i = 0; i < s.bricks.length; i++) {
      if (!s.bricks[i]) continue;
      final b = cfg.brick(i);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromPoints(v.p(b.x0, b.y1), v.p(b.x1, b.y0)), const Radius.circular(2)),
        Paint()..color = Color(_rowColors[(i ~/ cfg.cols) % _rowColors.length]),
      );
    }
    final hw = cfg.halfWidth;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(v.p(s.paddle - hw, cfg.paddleY + cfg.paddleH), v.p(s.paddle + hw, cfg.paddleY - cfg.paddleH)),
        Radius.circular(cfg.paddleH * k),
      ),
      Paint()..color = const Color(Tokens.colorWorldDayMarking),
    );
    final bx = s.serve > 0 ? s.paddle : s.ball.x;
    canvas.drawCircle(
      v.p(bx, s.ball.y),
      math.max(3, cfg.ballR * k),
      Paint()..color = const Color(Tokens.colorBrandAccent),
    );
  }

  @override
  bool shouldRepaint(_FieldPainter old) => old.s != s;
}
