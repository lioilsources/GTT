import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Grass beside the gorod (u).
const _side = 100000;

/// Court view: the gorod band magnified on top, the run-up from the throw line squeezed below.
class _CourtView {
  factory _CourtView(Size s, GorodkiConfig c, int ly) {
    final from = (c.gorodY0 - 120000).toDouble(), to = (c.gorodY1 + 60000).toDouble();
    final k = math.min((s.width - 16) / (c.gorodW + 2 * _side), (s.height * 0.5) / (to - from));
    const top = 12.0;
    return _CourtView._(
      k,
      (s.width - c.gorodW * k) / 2,
      top,
      top + (to - from) * k,
      s.height - c.batR * k * 2.5,
      from,
      to,
      ly,
    );
  }

  _CourtView._(this.k, this.ox, this.top, this.seam, this.line, this.from, this.to, this.ly);

  final double k, ox, top, seam, line, from, to;
  final int ly;

  double x(num v) => ox + v * k;
  double y(num v) =>
      v >= from ? seam - (v - from) / (to - from) * (seam - top) : line - (v - ly) / (from - ly) * (line - seam);
  Offset p(num px, num py) => Offset(x(px), y(py));
}

typedef _Disc = ({int x, int y, bool on});
typedef _Shown = ({_Disc bat, List<_Disc> pieces});

/// Gorodki (specs/minigames/gorodki.md): slide along the throw line, then swing the bat up at the
/// figure in the square; five figures, a bat budget for the whole game.
class GorodkiGame implements Minigame {
  const GorodkiGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.gorodki]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.gorodki;
    return MinigameShell(
      id: MinigameId.gorodki,
      env: env,
      rules: const [MessageKey.gorodkiRules1, MessageKey.gorodkiRules2, MessageKey.gorodkiRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _GorodkiBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _GorodkiBody extends StatefulWidget {
  const _GorodkiBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_GorodkiBody> createState() => _GorodkiBodyState();
}

const _figKeys = [
  MessageKey.gorodkiFig1,
  MessageKey.gorodkiFig2,
  MessageKey.gorodkiFig3,
  MessageKey.gorodkiFig4,
  MessageKey.gorodkiFig5,
];

class _GorodkiBodyState extends State<_GorodkiBody> with TickerProviderStateMixin {
  final GorodkiRules _rules = GorodkiRules();
  late final TuningMinigamesGorodki _tm = widget.env.tuning.minigames.gorodki;
  late final GorodkiConfig _cfg = GorodkiConfig.fromTuning(_tm, widget.ctx.difficulty);
  late GorodkiState _s = _rules.start(_cfg, widget.ctx.seed);
  late final FramePlayback _playback = FramePlayback(this, () => widget.shell.paused);
  late final PausableTimer _timer = PausableTimer(() => widget.shell.paused);
  final Toast _toast = Toast();
  late int _x = _cfg.gorodW ~/ 2;
  late _Shown _shown = _rest();
  bool _busy = false;
  int _spin = 0;
  String _mode = '';
  int _slideFrom = 0;
  Offset? _dragStart;
  ({int aim, int power})? _aim;
  Size _size = Size.zero;

  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  _Shown _rest() => (
    bat: (x: _x, y: gorodkiThrowLine(_cfg, _s), on: true),
    pieces: [for (var k = 0; k < 5; k++) (x: _s.px[k], y: _s.py[k], on: _s.up[k])],
  );

  @override
  void initState() {
    super.initState();
    widget.hooks.onTimeout = _timeout;
    WidgetsBinding.instance.addPostFrameCallback((_) => _status());
  }

  @override
  void dispose() {
    _playback.cancel();
    _timer.cancel();
    _toast.dispose();
    super.dispose();
  }

  void _status() {
    if (mounted) widget.shell.status(t(MessageKey.gorodkiBats, {'n': _s.bats}));
  }

  bool get _canDrag => !widget.shell.paused && !_busy && !_s.over;

  _CourtView get _view => _CourtView(_size, _cfg, gorodkiThrowLine(_cfg, _s));

  void _panStart(DragStartDetails d) {
    if (!_canDrag) return;
    _dragStart = d.localPosition;
    _mode = '';
  }

  void _panUpdate(DragUpdateDetails d) {
    final start = _dragStart;
    if (start == null) return;
    final delta = d.localPosition - start;
    final v = _view;
    if (_mode == '') {
      if (delta.distance < 12) return;
      _mode = delta.dx.abs() > delta.dy.abs() ? 'slide' : 'throw';
      _slideFrom = _x;
    }
    setState(() {
      if (_mode == 'slide') {
        _x = (_slideFrom + delta.dx / v.k).round().clamp(0, _cfg.gorodW);
        _shown = _rest();
        _aim = null;
      } else {
        final p = delta.dy < -12 ? dragPower(0, delta.dy, _size.height * 0.55) : 0;
        _aim = p > 0 ? (aim: (_x + delta.dx / v.k * 2).round(), power: p) : null;
      }
    });
  }

  void _panEnd(DragEndDetails _) {
    final a = _aim, m = _mode;
    _dragStart = null;
    _mode = '';
    setState(() => _aim = null);
    if (m != 'throw' || a == null || !_canDrag) return;
    _hurl(GorodkiAction.hurl(_x, a.aim, a.power));
  }

  void _hurl(GorodkiAction a) {
    if (!_rules.legal(_s, a)) return;
    setState(() => _busy = true);
    final vel = _rules.velocity(_s, a);
    final frames = <_Shown>[];
    var n = 0;
    simulateThrow(
      _cfg,
      _s,
      a.x,
      (vx: vel.vx, vy: vel.vy),
      onStep: (bodies) {
        if (++n % _tm.stepsPerFrame != 0) return;
        final d = [for (final b in bodies) (x: b.x, y: b.y, on: b.on)];
        frames.add((bat: d.first, pieces: d.sublist(1)));
      },
    );
    _playback.play<_Shown>(
      frames,
      (f) => setState(() {
        _shown = f;
        _spin++;
      }),
      () {
        if (!mounted) return;
        final before = _s;
        setState(() => _s = _rules.apply(_s, a));
        _status();
        if (_s.cleared > before.cleared) _toast.show(t(MessageKey.gorodkiClear));
        final r = _rules.result(_s);
        if (r != null) {
          widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
          return;
        }
        _timer.later(const Duration(milliseconds: 500), () {
          if (mounted) {
            setState(() {
              _busy = false;
              _shown = _rest();
            });
          }
        });
      },
    );
  }

  void _timeout() {
    if (_s.over) return;
    _playback.cancel();
    _timer.cancel();
    setState(() => _s = _rules.apply(_s, const GorodkiAction.timeout()));
    final r = _rules.result(_s)!;
    widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
  }

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: Color(Tokens.colorUiTextMuted));
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceSm),
      child: Column(
        children: [
          Text(
            _s.over ? '' : t(MessageKey.gorodkiFig, {'n': _s.fig, 'total': 5, 'name': t(_figKeys[_s.fig - 1])}),
            style: const TextStyle(color: Color(Tokens.colorUiText)),
          ),
          Text(_s.polukon && !_s.over ? t(MessageKey.gorodkiPolukon) : '', style: muted),
          const SizedBox(height: Tokens.spaceXs),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                _size = c.biggest;
                return Stack(
                  children: [
                    GestureDetector(
                      key: const ValueKey('court'),
                      behavior: HitTestBehavior.opaque,
                      onPanStart: _panStart,
                      onPanUpdate: _panUpdate,
                      onPanEnd: _panEnd,
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _CourtPainter(
                          cfg: _cfg,
                          view: _view,
                          shown: _shown,
                          aim: _busy ? null : _aim,
                          x: _x,
                          spin: _spin,
                        ),
                      ),
                    ),
                    ToastView(toast: _toast),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: Tokens.spaceXs),
          PowerBar(power: _busy ? 0 : _aim?.power ?? 0),
        ],
      ),
    );
  }
}

class _CourtPainter extends CustomPainter {
  _CourtPainter({
    required this.cfg,
    required this.view,
    required this.shown,
    required this.aim,
    required this.x,
    required this.spin,
  });

  final GorodkiConfig cfg;
  final _CourtView view;
  final _Shown shown;
  final ({int aim, int power})? aim;
  final int x, spin;

  @override
  void paint(Canvas canvas, Size size) {
    final v = view;
    final k = v.k;
    canvas.drawRect(
      Rect.fromLTRB(v.x(-_side), v.top, v.x(cfg.gorodW + _side), size.height),
      Paint()..color = const Color(Tokens.colorWorldDayPark),
    );
    final gorod = Rect.fromLTRB(v.x(0), v.y(cfg.gorodY1), v.x(cfg.gorodW), v.y(cfg.gorodY0));
    canvas.drawRect(gorod, Paint()..color = Color(Tokens.colorWorldDayFacades[5]));
    final chalk = Paint()
      ..color = const Color(Tokens.colorWorldDayMarking)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(gorod, chalk);
    canvas.drawLine(Offset(v.x(-_side), v.line), Offset(v.x(cfg.gorodW + _side), v.line), chalk);
    final a = aim;
    if (a != null) {
      dashedLine(
        canvas,
        v.p(x, v.ly),
        v.p(a.aim, cfg.gorodY0),
        Paint()
          ..color = const Color(Tokens.colorUiControlWheel)
          ..strokeWidth = 2,
      );
    }
    final edge = Paint()
      ..color = const Color(Tokens.colorUiLabelShadow)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final p in shown.pieces) {
      if (!p.on) continue;
      final c = v.p(p.x, p.y);
      final r = math.max(3.0, cfg.pieceR * k * 1.1);
      canvas.drawCircle(c, r, Paint()..color = Color(Tokens.colorWorldDayFacades[0]));
      canvas.drawCircle(c, r, edge);
    }
    final b = shown.bat;
    if (b.on) {
      // The bat: a stick spinning about its middle; its sweep is the physics disc.
      final r = math.max(8.0, cfg.batR * k * (b.y >= v.from ? 1 : 0.7));
      final c = v.p(b.x, b.y);
      final d = Offset(math.cos(spin * 0.45), math.sin(spin * 0.45)) * r;
      canvas.drawLine(
        c - d,
        c + d,
        Paint()
          ..color = const Color(Tokens.colorBoothBody)
          ..strokeWidth = math.max(3.0, r * 0.22)
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_CourtPainter old) => true;
}
