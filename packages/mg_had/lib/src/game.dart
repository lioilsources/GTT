import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// A swipe this long (px) along one axis turns the snake; the origin then moves on, so one drag
/// can turn several times (same as the web client).
const hadTurnPx = 22.0;

/// Swipe [d] (px, y down) → direction 0 up, 1 right, 2 down, 3 left; null while too short.
int? swipeDir(Offset d) {
  if (d.dx.abs() < hadTurnPx && d.dy.abs() < hadTurnPx) return null;
  return d.dx.abs() > d.dy.abs()
      ? (d.dx > 0 ? 1 : 3)
      : d.dy > 0
      ? 2
      : 0;
}

/// Had (snake, specs/minigames/had.md): swipe to turn, eat to grow; ticks at `tick_hz`.
class HadGame implements Minigame {
  const HadGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.had]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.had;
    return MinigameShell(
      id: MinigameId.had,
      env: env,
      rules: const [MessageKey.hadRules1, MessageKey.hadRules2, MessageKey.hadRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _HadBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _HadBody extends StatefulWidget {
  const _HadBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_HadBody> createState() => _HadBodyState();
}

class _HadBodyState extends State<_HadBody> with SingleTickerProviderStateMixin {
  final HadRules _rules = HadRules();
  late final TuningMinigamesHad _tm = widget.env.tuning.minigames.had;
  late final HadConfig _cfg = HadConfig.fromTuning(_tm, widget.ctx.difficulty);
  late HadState _s = _rules.start(_cfg, widget.ctx.seed);
  late final TickLoop _loop;
  bool _finished = false;
  int? _pointer;
  Offset _from = Offset.zero;

  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  @override
  void initState() {
    super.initState();
    widget.hooks.onTimeout = () => _play(const HadAction.timeout());
    _loop = TickLoop(
      this,
      hz: _tm.tickHz,
      paused: () => widget.shell.paused,
      running: () => !_finished,
      ticks: (n) => _play(HadAction.tick(n)),
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

  void _play(HadAction a) {
    if (_finished || _s.over || !mounted) return;
    final before = _s;
    final next = _rules.apply(_s, a);
    if (!identical(next, before)) setState(() => _s = next);
    if (next.score != before.score) _status();
    final r = _rules.result(_s);
    if (r != null) {
      _finished = true;
      _status();
      widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
    }
  }

  void _down(PointerDownEvent e) {
    _pointer ??= e.pointer;
    if (_pointer == e.pointer) _from = e.localPosition;
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer || widget.shell.paused) return;
    final dir = swipeDir(e.localPosition - _from);
    if (dir == null) return;
    _from = e.localPosition;
    _play(HadAction.turn(dir));
  }

  void _up(PointerEvent e) {
    if (e.pointer == _pointer) _pointer = null;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceSm),
      child: Column(
        children: [
          Text(
            t(MessageKey.hadLength, {'n': _s.body.length}),
            style: const TextStyle(color: Color(Tokens.colorUiTextMuted)),
          ),
          const SizedBox(height: Tokens.spaceXs),
          Expanded(
            child: Listener(
              key: const ValueKey('grid'),
              behavior: HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: _up,
              onPointerCancel: _up,
              child: CustomPaint(
                size: Size.infinite,
                painter: _GridPainter(cfg: _cfg, s: _s),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.cfg, required this.s});

  final HadConfig cfg;
  final HadState s;

  @override
  void paint(Canvas canvas, Size size) {
    final v = WorldView.fit(size, 0, 0, cfg.w.toDouble(), cfg.h.toDouble(), pad: 4);
    final c = v.k;
    canvas.drawRect(
      Rect.fromPoints(v.p(0, cfg.h), v.p(cfg.w, 0)),
      Paint()..color = const Color(Tokens.colorWorldNightPark),
    );
    final check = Paint()..color = const Color(Tokens.colorCarDetailCanopy);
    for (var y = 0; y < cfg.h; y++) {
      for (var x = y % 2; x < cfg.w; x += 2) {
        canvas.drawRect(Rect.fromLTWH(v.sx(x), v.sy(y + 1), c, c), check);
      }
    }
    canvas.drawCircle(
      v.p(s.food.$1 + 0.5, s.food.$2 + 0.5),
      c * 0.38,
      Paint()..color = const Color(Tokens.colorTrafficLightRed),
    );
    for (var i = 0; i < s.body.length; i++) {
      final (x, y) = s.body[i];
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(v.sx(x) + 1, v.sy(y + 1) + 1, c - 2, c - 2), Radius.circular(c * 0.3)),
        Paint()..color = Color(i == 0 ? Tokens.colorWorldDayMarking : Tokens.colorBrandAccent),
      );
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.s != s;
}
