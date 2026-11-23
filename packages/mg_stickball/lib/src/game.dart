import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:mg_api/mg_api.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Pause between the end of one pitch and the next wind-up (UI only, as web).
const _nextMs = 1100;

/// How long the `last` label shows.
const _labelMs = 900;

/// Longest real-time step the game clock takes per frame (app switches, hiccups).
const _maxFrameMs = 250;

/// Bands occupy this fraction of the field height above the batter (high, mid, low from the top).
const _bandsTop = 0.52, _bandsH = 0.33;

/// Lane of a tap at field y: 2 high (top band), 1 mid, 0 low; outside the bands the nearest one.
int stickballLaneAt(double y, double height) {
  final top = height * _bandsTop, band = height * _bandsH / 3;
  final i = ((y - top) / band).floor();
  return 2 - i.clamp(0, 2);
}

/// Stickball, specs/minigames/stickball.md: tap the band the pitch comes into, on time.
class StickballGame implements Minigame {
  const StickballGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.stickball]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) => MinigameShell(
    id: MinigameId.stickball,
    env: env,
    rules: const [MessageKey.stickballRules1, MessageKey.stickballRules2, MessageKey.stickballRules3],
    timeCapS: env.tuning.minigames.stickball.timeCapS,
    onFinish: onFinish,
    body: (context, shell, hooks) => _StickballBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
  );
}

class _StickballBody extends StatefulWidget {
  const _StickballBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_StickballBody> createState() => _StickballBodyState();
}

class _StickballBodyState extends State<_StickballBody> with SingleTickerProviderStateMixin {
  final StickballRules _rules = StickballRules();
  late final StickballConfig _cfg = StickballConfig.fromTuning(
    widget.env.tuning.minigames.stickball,
    widget.ctx.difficulty,
  );
  late StickballState _s = _rules.start(_cfg, widget.ctx.seed);
  late final Prng _ai = aiPrng(widget.ctx.seed);
  late final Ticker _ticker = createTicker(_frame);
  final Stopwatch _wall = Stopwatch()..start();

  /// Game clock (ms); stands while paused.
  double _clock = 0;
  Duration? _last;
  int _lastWallUs = 0;
  bool _finished = false;
  int _nextAt = _nextMs;
  int _pitchAt = 0;
  int _pitches = 0;
  ({int lane, double at})? _swing;
  String? _label;
  double _labelUntil = 0;

  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  @override
  void initState() {
    super.initState();
    widget.hooks.onTimeout = () => _play(const StickballAction.timeout());
    _ticker.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _status());
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _status() {
    if (mounted) widget.shell.status(t(MessageKey.stickballRuns, {'n': _s.runs}));
  }

  int get _arrival => _pitchAt + _s.pitch.flightMs;

  void _frame(Duration elapsed) {
    if (widget.shell.paused || _finished) {
      _last = null;
      return;
    }
    final last = _last;
    _last = elapsed;
    _lastWallUs = _wall.elapsedMicroseconds;
    if (last != null) _clock += math.min((elapsed - last).inMicroseconds / 1000, _maxFrameMs.toDouble());
    final ms = _clock.floor();
    if (_s.phase == 'pitch' && ms >= _nextAt) {
      _play(_rules.aiAction(_s, _cfg.level, _ai));
      _pitchAt = ms;
      _pitches++;
      _swing = null;
    } else if (_s.phase == 'bat' && ms > _arrival + _cfg.foulMs) {
      _play(const StickballAction.take());
    } else {
      setState(() {});
    }
  }

  void _play(StickballAction a) {
    if (_finished || _s.over) return;
    setState(() {
      _s = _rules.apply(_s, a);
      if (a.by == 'player') {
        if (_s.last.isNotEmpty) {
          _label = _lastText(_s.last);
          _labelUntil = _clock + _labelMs;
        }
        _nextAt = _clock.floor() + _nextMs;
      }
    });
    _status();
    final r = _rules.result(_s);
    if (r != null) {
      _finished = true;
      widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
    }
  }

  String _lastText(String last) => t(switch (last) {
    'ball' => MessageKey.stickballLastBall,
    'strike' => MessageKey.stickballLastStrike,
    'foul' => MessageKey.stickballLastFoul,
    'single' => MessageKey.stickballLastSingle,
    'double' => MessageKey.stickballLastDouble,
    'homer' => MessageKey.stickballLastHomer,
    'catch' => MessageKey.stickballLastCatch,
    'walk' => MessageKey.stickballLastWalk,
    _ => MessageKey.stickballLastStrikeout,
  });

  void _tap(Offset local, Size size) {
    if (widget.shell.paused || _finished || _s.phase != 'bat') return;
    // Game time of the tap: the clock of the last frame plus the real time since it.
    final at = _clock + (_last == null ? 0 : (_wall.elapsedMicroseconds - _lastWallUs) / 1000);
    if (at < _arrival - 2 * _cfg.foulMs) return;
    final lane = stickballLaneAt(local.dy, size.height);
    _swing = (lane: lane, at: at);
    _play(StickballAction.swing(lane, (at - _arrival).floor()));
  }

  @override
  Widget build(BuildContext context) {
    final label = _label != null && _clock < _labelUntil ? _label : null;
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceMd),
      child: Column(
        children: [
          Text(
            t(MessageKey.stickballCount, {'balls': _s.balls, 'strikes': _s.strikes, 'outs': _s.outs}),
            style: const TextStyle(color: Color(Tokens.colorUiTextMuted)),
          ),
          const SizedBox(height: Tokens.spaceSm),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final size = Size(box.maxWidth, box.maxHeight);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _tap(d.localPosition, size),
                  child: Stack(
                    children: [
                      CustomPaint(
                        key: const ValueKey('stickball-field'),
                        painter: _FieldPainter(_s, _clock, _pitchAt, _pitches, _swing),
                        size: size,
                      ),
                      if (label != null)
                        Align(
                          alignment: const Alignment(0, -0.45),
                          child: Text(
                            label,
                            style: const TextStyle(
                              color: Color(Tokens.colorStickballRunner),
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
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
  _FieldPainter(this.s, this.ms, this.pitchAt, this.pitches, this.swing);

  final StickballState s;
  final double ms;
  final int pitchAt, pitches;
  final ({int lane, double at})? swing;

  @override
  void paint(Canvas g, Size size) {
    final w = size.width, h = size.height;
    final m = math.min(w, h);
    g.drawRect(Offset.zero & size, Paint()..color = const Color(Tokens.colorStickballCurb));
    // Street in perspective: narrow at the pitcher, wide at the batter.
    g.drawPath(
      Path()
        ..moveTo(w * 0.38, 0)
        ..lineTo(w * 0.62, 0)
        ..lineTo(w * 1.05, h)
        ..lineTo(-w * 0.05, h)
        ..close(),
      Paint()..color = const Color(Tokens.colorStickballStreet),
    );
    final band = h * _bandsH / 3;
    const bands = [Tokens.colorStickballZoneHigh, Tokens.colorStickballZoneMid, Tokens.colorStickballZoneLow];
    for (var i = 0; i < 3; i++) {
      g.drawRect(
        Rect.fromLTWH(w * 0.08, h * _bandsTop + i * band, w * 0.84, band - 2),
        Paint()..color = Color(bands[i]),
      );
    }
    // Bases as manhole covers: first right, second up, third left of home.
    final bx = w * 0.5, by = h * 0.93, d = m * 0.06;
    final manhole = Paint()..color = const Color(Tokens.colorStickballManhole);
    final runner = Paint()..color = const Color(Tokens.colorStickballRunner);
    g.drawCircle(Offset(bx, by), d * 0.45, manhole);
    final basePts = [Offset(bx + d * 1.6, by - d * 0.7), Offset(bx, by - d * 1.4), Offset(bx - d * 1.6, by - d * 0.7)];
    for (var i = 0; i < 3; i++) {
      g.drawCircle(basePts[i], d * 0.5, (s.bases >> i) & 1 == 1 ? runner : manhole);
    }
    // Pitcher.
    final px = w * 0.5, py = h * 0.12;
    g.drawCircle(Offset(px, py), m * 0.035, runner);
    // Batter and stick.
    final sw = swing;
    final swinging = sw != null && ms - sw.at < 250;
    final lane = swinging ? sw.lane : 1;
    final ly = h * _bandsTop + (2 - lane + 0.5) * band;
    g.drawCircle(Offset(w * 0.3, h * 0.86), m * 0.045, runner);
    final k = swinging ? 1 : 0;
    g.drawLine(
      Offset(w * 0.3, h * 0.84),
      Offset(w * (0.3 + 0.32 * k + 0.05), ly - (1 - k) * band),
      Paint()
        ..color = const Color(Tokens.colorStickballCurb)
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
    // Ball in flight; a pitch outside the zone flies off to the side.
    if (s.phase == 'bat') {
      final f = ((ms - pitchAt) / s.pitch.flightMs).clamp(0.0, 1.25);
      final tx = s.pitch.zone ? w * 0.5 : w * (pitches.isOdd ? 0.92 : 0.08);
      final ty = h * _bandsTop + (2 - s.pitch.lane + 0.5) * band;
      g.drawCircle(
        Offset(px + (tx - px) * f, py + (ty - py) * f),
        m * (0.012 + 0.02 * math.min(1.0, f)),
        Paint()..color = const Color(Tokens.colorStickballBall),
      );
    }
  }

  @override
  bool shouldRepaint(_FieldPainter old) => true;
}
