import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:mg_api/mg_api.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// How long a hit pop (+points) floats over the target.
const _popMs = 600;

/// Longest real-time step fed to the simulation per frame (app switches, hiccups).
const _maxFrameMs = 250;

/// Strelnice (shooting gallery): tap moving targets, three timed rounds. A [Ticker] sends
/// `tick n` actions at `tick_hz`; a tap sends `shoot` at the tapped point in field units.
class StrelniceGame implements Minigame {
  const StrelniceGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.strelnice]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.strelnice;
    return MinigameShell(
      id: MinigameId.strelnice,
      env: env,
      rules: const [MessageKey.strelniceRules1, MessageKey.strelniceRules2, MessageKey.strelniceRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _StrelniceBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _Pop {
  _Pop(this.x, this.y, this.points, this.atMs);
  final int x, y, points;
  final int atMs;
}

class _StrelniceBody extends StatefulWidget {
  const _StrelniceBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_StrelniceBody> createState() => _StrelniceBodyState();
}

class _StrelniceBodyState extends State<_StrelniceBody> with SingleTickerProviderStateMixin {
  final StrelniceRules _rules = StrelniceRules();
  late final StrelniceConfig _cfg = StrelniceConfig.fromTuning(widget.env.tuning.minigames.strelnice);
  late StrelniceState _s = _rules.start(_cfg, widget.ctx.seed);
  late final Ticker _ticker = createTicker(_frame);
  Duration? _last;
  double _accMs = 0;
  int _nowMs = 0;
  bool _finished = false;
  final List<_Pop> _pops = [];

  int get _tickHz => widget.env.tuning.minigames.strelnice.tickHz;
  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  @override
  void initState() {
    super.initState();
    widget.hooks.onTimeout = _timeout;
    _ticker.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _status());
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _status() {
    if (mounted) widget.shell.status(t(MessageKey.scoreValue, {'score': _s.score}));
  }

  void _frame(Duration elapsed) {
    _nowMs = elapsed.inMilliseconds;
    if (widget.shell.paused || _finished) {
      _last = null;
      return;
    }
    final last = _last;
    _last = elapsed;
    if (last != null) _accMs += math.min((elapsed - last).inMicroseconds / 1000, _maxFrameMs.toDouble());
    final n = (_accMs * _tickHz / 1000).floor();
    _pops.removeWhere((p) => _nowMs - p.atMs >= _popMs);
    if (n > 0) {
      _accMs -= n * 1000 / _tickHz;
      _play(StrelniceAction.tick(n));
    } else if (_pops.isNotEmpty) {
      setState(() {});
    }
  }

  void _play(StrelniceAction a) {
    if (_finished || _s.over) return;
    final before = _s;
    setState(() {
      _s = _rules.apply(_s, a);
      if (_s.hits > before.hits && _s.round == before.round) {
        var i = 0;
        while (!_s.targets[i].hit || before.targets[i].hit) {
          i++;
        }
        final tg = before.targets[i];
        final p = targetPos(tg, before.tick, _cfg);
        _pops.add(_Pop(p.x, p.y, _cfg.points(tg.kind), _nowMs));
      }
    });
    _status();
    final r = _rules.result(_s);
    if (r != null) {
      _finished = true;
      widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
    }
  }

  void _timeout() {
    if (_finished || _s.over) return;
    _play(const StrelniceAction.timeout());
  }

  void _tap(Offset local, Size size) {
    if (widget.shell.paused || _finished) return;
    final l = _FieldLayout(size, _cfg);
    final x = ((local.dx - l.ox) / l.k).round();
    final y = ((local.dy - l.oy) / l.k).round();
    if (x < 0 || x > _cfg.width || y < 0 || y > l.fieldH) return;
    _play(StrelniceAction.shoot(x, y));
  }

  @override
  Widget build(BuildContext context) {
    final seconds = math.max(0, ((_cfg.roundTicks - _s.tick) / _tickHz).ceil());
    final loaded = _s.reload == 0 ? _s.ammo : 0;
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceMd),
      child: Column(
        children: [
          Text(
            t(MessageKey.strelniceRound, {'round': _s.round, 'seconds': seconds}),
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
                  child: CustomPaint(
                    key: const ValueKey('strelnice-field'),
                    painter: _FieldPainter(_s, _cfg, List.of(_pops), _nowMs),
                    size: size,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: Tokens.spaceSm),
          SizedBox(
            height: 32,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _cfg.magazine; i++)
                  Container(
                    width: 10,
                    height: 24,
                    margin: const EdgeInsets.symmetric(horizontal: Tokens.spaceXs / 2),
                    decoration: BoxDecoration(
                      color: Color(i < loaded ? Tokens.colorBrandAccent : Tokens.colorUiTextFaint),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                if (_s.reload > 0) ...[
                  const SizedBox(width: Tokens.spaceMd),
                  Text(
                    t(MessageKey.strelniceReload),
                    style: const TextStyle(color: Color(Tokens.colorUiNotice), fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Square field (width × width units), top-aligned and centred horizontally (same as web).
class _FieldLayout {
  _FieldLayout(Size size, StrelniceConfig c) : fieldH = c.width.toDouble() {
    k = math.min(size.width / c.width, size.height / fieldH);
    ox = (size.width - c.width * k) / 2;
  }

  final double fieldH;
  late final double k, ox;
  final double oy = 0;
}

class _FieldPainter extends CustomPainter {
  _FieldPainter(this.s, this.c, this.pops, this.nowMs);

  final StrelniceState s;
  final StrelniceConfig c;
  final List<_Pop> pops;
  final int nowMs;

  static const _kindColors = [Tokens.colorWorldRoadblockA, Tokens.colorBrandAccent];

  Color _kind(int k) => Color(k < _kindColors.length ? _kindColors[k] : Tokens.colorWorldDayFacades[2]);

  @override
  void paint(Canvas canvas, Size size) {
    final l = _FieldLayout(size, c);
    canvas.save();
    canvas.translate(l.ox, l.oy);
    canvas.scale(l.k);
    final field = Rect.fromLTWH(0, 0, c.width.toDouble(), l.fieldH);
    canvas.clipRect(field);
    canvas.drawRect(field, Paint()..color = const Color(Tokens.colorWorldNightPlaza));
    final maxR = [0, 1, 2].map(c.radius).reduce(math.max);
    final rail = Paint()..color = const Color(Tokens.colorWorldDayRail);
    for (final y in c.lanes) {
      canvas.drawRect(Rect.fromLTWH(0, (y + maxR + 4).toDouble(), c.width.toDouble(), 6), rail);
    }
    final pole = Paint()
      ..color = const Color(Tokens.colorWorldDayRail)
      ..strokeWidth = 4;
    final white = Paint()..color = const Color(Tokens.colorWorldRoadblockB);
    for (final tg in s.targets) {
      if (!onField(tg, s.tick, c)) continue;
      final p = targetPos(tg, s.tick, c);
      final r = c.radius(tg.kind).toDouble();
      final o = Offset(p.x.toDouble(), p.y.toDouble());
      final col = Paint()..color = _kind(tg.kind);
      canvas.drawLine(o.translate(0, r), Offset(o.dx, (c.lanes[tg.lane] + maxR + 4).toDouble()), pole);
      canvas.drawCircle(o, r, col);
      canvas.drawCircle(o, r * 0.66, white);
      canvas.drawCircle(o, r * 0.33, col);
    }
    for (final p in pops) {
      final age = (nowMs - p.atMs) / _popMs;
      if (age < 0 || age >= 1) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: '+${p.points}',
          style: TextStyle(
            color: Color(Tokens.colorBrandAccent).withValues(alpha: 1 - age),
            fontSize: 48,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(p.x - tp.width / 2, p.y - 40 * age - tp.height / 2));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FieldPainter old) => true;
}
