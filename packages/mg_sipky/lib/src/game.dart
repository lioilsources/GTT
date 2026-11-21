import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:mg_api/mg_api.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Board drawing extent (0.1 mm): the double ring plus room for the numbers.
const _view = 2000.0;
const _labelR = 1850.0;

/// Sipky 301: drag to aim (the sight sways), release to throw; the opponent throws after `ai_think_s`.
class SipkyGame implements Minigame {
  const SipkyGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.sipky]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.sipky;
    return MinigameShell(
      id: MinigameId.sipky,
      env: env,
      rules: const [MessageKey.sipkyRules1, MessageKey.sipkyRules2, MessageKey.sipkyRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _SipkyBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _SipkyBody extends StatefulWidget {
  const _SipkyBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_SipkyBody> createState() => _SipkyBodyState();
}

class _SipkyBodyState extends State<_SipkyBody> with SingleTickerProviderStateMixin {
  final SipkyRules _rules = SipkyRules();
  late final Prng _ai = aiPrng(widget.ctx.seed);
  late SipkyState _s = _rules.start(SipkyConfig.fromTuning(widget.env.tuning.minigames.sipky), widget.ctx.seed);
  late final Ticker _ticker = createTicker(_tick);
  Timer? _aiTimer;
  Timer? _flashTimer;
  String? _flash;
  bool _bust = false;
  bool _thrown = false;

  /// Finger point and current sight, both in board units (y up); null while not aiming.
  Offset? _finger;
  Offset _sight = Offset.zero;
  Size _size = Size.zero;

  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  @override
  void initState() {
    super.initState();
    widget.hooks.onTimeout = _timeout;
    WidgetsBinding.instance.addPostFrameCallback((_) => _status());
  }

  @override
  void dispose() {
    _ticker.dispose();
    _aiTimer?.cancel();
    _flashTimer?.cancel();
    super.dispose();
  }

  void _status() {
    if (!mounted) return;
    widget.shell.status(_s.over ? '' : (_s.turn == 'player' ? t(MessageKey.yourTurn) : t(MessageKey.opponentTurn)));
  }

  bool get _canAim => !widget.shell.paused && !_s.over && _s.turn == 'player';

  void _play(SipkyAction a) {
    if (widget.shell.paused || _s.over) return;
    final before = _s;
    setState(() {
      _s = _rules.apply(_s, a);
      _thrown = true;
      _bust = before.score(before.turn) - _s.lastHit.points < 0;
      _flash = _bust ? t(MessageKey.sipkyBust) : t(MessageKey.sipkyHit, {'points': _s.lastHit.points});
      _flashTimer?.cancel();
      _flashTimer = Timer(const Duration(milliseconds: 900), () => mounted ? setState(() => _flash = null) : null);
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
    final ms = (widget.env.tuning.minigames.sipky.aiThinkS * 1000).round();
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
    _stopAim();
    setState(() => _s = _rules.apply(_s, const SipkyAction.timeout()));
    final r = _rules.result(_s)!;
    widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
  }

  double get _scale => math.min(_size.width, _size.height) / (2 * _view);

  /// Local widget point to board units (0.1 mm, y up).
  Offset _toBoard(Offset p) {
    final k = _scale;
    if (k <= 0) return Offset.zero;
    return Offset((p.dx - _size.width / 2) / k, -(p.dy - _size.height / 2) / k);
  }

  /// Lissajous-like sway around the finger (UI only, not part of the rules).
  void _tick(Duration elapsed) {
    final f = _finger;
    if (f == null) return;
    final tm = widget.env.tuning.minigames.sipky;
    final w = elapsed.inMicroseconds / 1e6 * 2 * math.pi * tm.wobbleHz;
    final amp = tm.playerWobble.toDouble();
    setState(() => _sight = f + Offset(amp * math.sin(w), amp * math.sin(1.7 * w + 0.6)));
  }

  void _stopAim() {
    _finger = null;
    if (_ticker.isActive) _ticker.stop();
  }

  void _onStart(DragStartDetails d) {
    if (!_canAim) return;
    setState(() {
      _finger = _toBoard(d.localPosition);
      _sight = _finger!;
    });
    if (!_ticker.isActive) _ticker.start();
  }

  void _onUpdate(DragUpdateDetails d) {
    if (_finger == null) return;
    _finger = _toBoard(d.localPosition);
  }

  void _onEnd(DragEndDetails d) {
    if (_finger == null) return;
    setState(_stopAim);
    if (_canAim) _play(SipkyAction.player(_sight.dx.round(), _sight.dy.round()));
  }

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: Color(Tokens.colorUiTextMuted));
    final noteColor = _flash == null
        ? Tokens.colorUiText
        : _bust
        ? Tokens.colorUiFpsBad
        : Tokens.colorBrandAccent;
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceMd),
      child: Column(
        children: [
          Text(t(MessageKey.sipkyRemaining, {'player': _s.player, 'ai': _s.ai}), style: muted),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                _size = box.biggest;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: _onStart,
                  onPanUpdate: _onUpdate,
                  onPanEnd: _onEnd,
                  onPanCancel: () => setState(_stopAim),
                  child: CustomPaint(
                    painter: _BoardPainter(hit: _thrown ? _s.lastHit : null, sight: _finger == null ? null : _sight),
                    size: Size.infinite,
                  ),
                );
              },
            ),
          ),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(color: Color(noteColor), fontSize: 20, fontWeight: FontWeight.w700),
            child: Text(_flash ?? t(MessageKey.sipkyDart, {'n': _s.dart + 1})),
          ),
        ],
      ),
    );
  }
}

/// The dartboard (same look as the web client); trigonometry is UI only, the rules use integer tables.
class _BoardPainter extends CustomPainter {
  _BoardPainter({this.hit, this.sight});

  final Hit? hit;
  final Offset? sight;

  @override
  void paint(Canvas canvas, Size size) {
    final k = math.min(size.width, size.height) / (2 * _view);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(k);
    Paint fill(int c) => Paint()..color = Color(c);
    canvas.drawCircle(Offset.zero, _view - 20, fill(Tokens.colorWorldNightTunnel));
    const deg = math.pi / 180;
    const rings = [
      (SipkyRing.outerBull, SipkyRing.tripleIn, false),
      (SipkyRing.tripleIn, SipkyRing.tripleOut, true),
      (SipkyRing.tripleOut, SipkyRing.doubleIn, false),
      (SipkyRing.doubleIn, SipkyRing.doubleOut, true),
    ];
    for (var s = 0; s < 20; s++) {
      // Canvas angles run clockwise from +x; board sector s is centred 18°·s clockwise from +y.
      final a0 = (18 * s - 9 - 90) * deg;
      for (final (r0, r1, ring) in rings) {
        final even = s.isEven;
        final c = ring
            ? (even ? Tokens.colorWorldDayFacades[1] : Tokens.colorWorldDayPark)
            : (even ? Tokens.colorWorldNightLand : Tokens.colorWorldDayFacades[0]);
        final path = Path()
          ..arcTo(Rect.fromCircle(center: Offset.zero, radius: r1.toDouble()), a0, 18 * deg, true)
          ..arcTo(Rect.fromCircle(center: Offset.zero, radius: r0.toDouble()), a0 + 18 * deg, -18 * deg, false)
          ..close();
        canvas.drawPath(path, fill(c));
      }
      final tp = TextPainter(
        text: TextSpan(
          text: '${sipkySectors[s]}',
          style: const TextStyle(color: Color(Tokens.colorUiText), fontSize: 150, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final a = 18 * s * deg;
      tp.paint(canvas, Offset(_labelR * math.sin(a) - tp.width / 2, -_labelR * math.cos(a) - tp.height / 2));
    }
    canvas.drawCircle(Offset.zero, SipkyRing.outerBull.toDouble(), fill(Tokens.colorWorldDayPark));
    canvas.drawCircle(Offset.zero, SipkyRing.bull.toDouble(), fill(Tokens.colorWorldDayFacades[1]));
    final h = hit;
    if (h != null) {
      final p = Offset(h.x.toDouble(), -h.y.toDouble());
      canvas.drawCircle(p, 28, fill(Tokens.colorBrandAccent));
      canvas.drawCircle(
        p,
        28,
        Paint()
          ..color = const Color(Tokens.colorUiLabelShadow)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8,
      );
    }
    final sp = sight;
    if (sp != null) {
      final c = Offset(sp.dx, -sp.dy);
      final pen = Paint()
        ..color = const Color(Tokens.colorBrandAccent)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14;
      canvas.drawCircle(c, 90, pen);
      canvas.drawLine(c - const Offset(150, 0), c + const Offset(150, 0), pen);
      canvas.drawLine(c - const Offset(0, 150), c + const Offset(0, 150), pen);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BoardPainter old) => old.sight != sight || !identical(old.hit, hit);
}
