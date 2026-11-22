import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_kulicky/mg_kulicky.dart' show BoardMap, DuelFrame, DuelTimer, drawDisc, drawGuide, duelMinSwipePx;
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Top-down court in board mm (y up): the rival's half is y ∈ [0, depth] at the top, the player's
/// y ∈ [−depth, 0] below, the net at y = 0. Rules coordinates are per half (y back from the net), so
/// a shot into the rival's half is drawn at (x, y) and one into the player's at (x, −y). Same as web.
class CourtLayout {
  factory CourtLayout.of(NohejbalConfig c) {
    final pad = [...c.scatter, ...c.aiScatter].reduce(math.max).toDouble();
    return CourtLayout._(c.halfWidth.toDouble(), c.depth.toDouble(), pad, c.halfWidth * 0.05, c.halfWidth * 0.09);
  }

  const CourtLayout._(this.halfW, this.depth, this.pad, this.ballR, this.manR);

  final double halfW, depth, ballR, manR;

  /// Space around the lines so out balls stay visible.
  final double pad;

  double get w => halfW + pad;
  double get d => depth + pad;

  /// Swipe in logical px (dx right, dy down) → integer aim point in the rival's half (y back from the net).
  static ({int x, int y}) aim(double dx, double dy, double mmPerPx) =>
      (x: (dx * mmPerPx).round(), y: (-dy * mmPerPx).round());
}

const _tween = Duration(milliseconds: 500);
const _show = Duration(milliseconds: 800);
const _aiDelay = Duration(milliseconds: 650);

/// Nohejbal (footnet): the first `sport` engine game.
class NohejbalGame implements Minigame {
  const NohejbalGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.nohejbal]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.nohejbal;
    return MinigameShell(
      id: MinigameId.nohejbal,
      env: env,
      rules: const [MessageKey.nohejbalRules1, MessageKey.nohejbalRules2, MessageKey.nohejbalRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _NohejbalBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _NohejbalBody extends StatefulWidget {
  const _NohejbalBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_NohejbalBody> createState() => _NohejbalBodyState();
}

class _NohejbalBodyState extends State<_NohejbalBody> with SingleTickerProviderStateMixin {
  final NohejbalRules _rules = NohejbalRules();
  final DuelTimer _timer = DuelTimer();
  late final Prng _ai = aiPrng(widget.ctx.seed);
  late final NohejbalConfig _cfg = NohejbalConfig.fromTuning(widget.env.tuning.minigames.nohejbal);
  late final CourtLayout _lay = CourtLayout.of(_cfg);
  late NohejbalState _s = _rules.start(_cfg, widget.ctx.seed);
  late final AnimationController _fly = AnimationController(vsync: this, duration: _tween);
  late final double _homeY = _cfg.homeY.toDouble();
  late Offset _me = Offset(0, -_homeY), _rival = Offset(0, _homeY), _ball = Offset(0, -_homeY);
  Offset? _mark;
  bool _busy = false;
  String _note = '';
  bool _flash = false;
  Offset? _dragStart;
  Offset _drag = Offset.zero;

  double get _mmPerPx => widget.env.tuning.minigames.nohejbal.flickMmPerPx;

  double get _aiReach {
    final r = _cfg.aiReach;
    final i = widget.ctx.difficulty - 1;
    return i >= 0 && i < r.length ? r[i].toDouble() : 0;
  }

  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  @override
  void initState() {
    super.initState();
    widget.hooks.onTimeout = _timeout;
    WidgetsBinding.instance.addPostFrameCallback((_) => _status());
  }

  @override
  void dispose() {
    _fly.dispose();
    _timer.cancel();
    super.dispose();
  }

  void _status() {
    if (mounted) widget.shell.status(t(MessageKey.nohejbalScore, {'player': _s.playerPts, 'ai': _s.aiPts}));
  }

  bool get _blocked => widget.shell.paused || _s.over || _busy || _s.turn != 'player';

  void _panStart(DragStartDetails d) {
    if (_blocked) return;
    setState(() {
      _dragStart = d.localPosition;
      _drag = Offset.zero;
    });
  }

  void _panUpdate(DragUpdateDetails d) {
    final start = _dragStart;
    if (start != null) setState(() => _drag = d.localPosition - start);
  }

  void _panEnd(DragEndDetails _) {
    if (_dragStart == null) return;
    final swipe = _drag;
    setState(() => _dragStart = null);
    if (_blocked || swipe.dy > -duelMinSwipePx) return;
    final aim = CourtLayout.aim(swipe.dx, swipe.dy, _mmPerPx);
    _play(NohejbalAction(aim.x, aim.y, widget.ctx.difficulty));
  }

  void _home() {
    _me = Offset(0, -_homeY);
    _rival = Offset(0, _homeY);
    _ball = _s.turn == 'player' ? _me : _rival;
  }

  /// Applies one shot and animates the ball (and the receiver, when it gets there).
  void _play(NohejbalAction a) {
    final before = _s;
    setState(() {
      _s = _rules.apply(_s, a);
      _busy = true;
      _mark = null;
      _note = '';
      _flash = false;
    });
    _status();
    final shot = _s.lastShot;
    final toRival = shot.by == 'player';
    final target = Offset(shot.x.toDouble(), (toRival ? shot.y : -shot.y).toDouble());
    final ball0 = _ball, runner0 = toRival ? _rival : _me;
    void tick() {
      final k = Curves.easeOut.transform(_fly.value);
      setState(() {
        _ball = Offset.lerp(ball0, target, k)!;
        if (shot.reached) {
          final r = Offset.lerp(runner0, target, k)!;
          toRival ? _rival = r : _me = r;
        }
      });
    }

    void status(AnimationStatus st) {
      if (st != AnimationStatus.completed) return;
      _fly
        ..removeListener(tick)
        ..removeStatusListener(status);
      if (mounted) _landed(before, shot, target);
    }

    _fly
      ..addListener(tick)
      ..addStatusListener(status)
      ..forward(from: 0);
  }

  void _landed(NohejbalState before, NohejbalShot shot, Offset target) {
    setState(() => _mark = target);
    if (shot.reached) {
      // Rally goes on: the receiver plays the ball back from where it caught it.
      if (_s.turn == 'ai') {
        _timer.later(_aiDelay, () => widget.shell.paused, _rivalShot);
      } else {
        setState(() => _busy = false);
      }
      return;
    }
    final won = _s.playerPts > before.playerPts;
    setState(() {
      _note = t(won ? MessageKey.roundWon : MessageKey.roundLost);
      _flash = won;
    });
    _timer.later(_show, () => widget.shell.paused, () {
      if (!mounted) return;
      final r = _rules.result(_s);
      if (r != null) {
        widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
        return;
      }
      setState(() {
        _flash = false;
        _mark = null;
        _home();
      });
      if (_s.turn == 'ai') {
        _timer.later(_aiDelay, () => widget.shell.paused, _rivalShot);
      } else {
        setState(() => _busy = false);
      }
    });
  }

  void _rivalShot() {
    if (!mounted || _s.over) return;
    _play(_rules.aiAction(_s, widget.ctx.difficulty, _ai));
  }

  void _timeout() {
    if (_s.over) return;
    _timer.cancel();
    _fly.stop();
    setState(() => _s = _rules.apply(_s, const NohejbalAction.timeout()));
    _status();
    final r = _rules.result(_s)!;
    widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
  }

  @override
  Widget build(BuildContext context) {
    final aim = _dragStart != null && _drag.dy < -duelMinSwipePx ? CourtLayout.aim(_drag.dx, _drag.dy, _mmPerPx) : null;
    return DuelFrame(
      info: _s.over ? '' : t(_s.turn == 'player' ? MessageKey.yourTurn : MessageKey.opponentTurn),
      note: _note,
      flash: _flash,
      board: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _panStart,
        onPanUpdate: _panUpdate,
        onPanEnd: _panEnd,
        child: CustomPaint(
          size: Size.infinite,
          painter: _CourtPainter(
            lay: _lay,
            homeY: _homeY,
            aiReach: _aiReach,
            playerReach: _cfg.playerReach.toDouble(),
            me: _me,
            rival: _rival,
            ball: _ball,
            mark: _mark,
            guide: aim == null ? null : Offset(aim.x.toDouble(), aim.y.toDouble()),
          ),
        ),
      ),
    );
  }
}

/// Court halves, net, both reach circles, landing mark, players and ball (same layout as the web client).
class _CourtPainter extends CustomPainter {
  _CourtPainter({
    required this.lay,
    required this.homeY,
    required this.aiReach,
    required this.playerReach,
    required this.me,
    required this.rival,
    required this.ball,
    required this.mark,
    required this.guide,
  });

  final CourtLayout lay;
  final double homeY, aiReach, playerReach;
  final Offset me, rival, ball;
  final Offset? mark, guide;

  @override
  void paint(Canvas canvas, Size size) {
    final m = BoardMap(size, -lay.w, lay.d, 2 * lay.w, 2 * lay.d);
    final k = m.k;
    Offset p(Offset o) => m.p(o.dx, o.dy);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromPoints(m.p(-lay.w, lay.d), m.p(lay.w, -lay.d)), Radius.circular(lay.ballR * k)),
      Paint()..color = const Color(Tokens.colorWorldDayLand),
    );
    final fill = Paint()..color = const Color(Tokens.colorWorldDayPark);
    final lines = Paint()
      ..color = const Color(Tokens.colorWorldDayMarking)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8 * k;
    for (final half in [
      Rect.fromPoints(m.p(-lay.halfW, lay.depth), m.p(lay.halfW, 0)),
      Rect.fromPoints(m.p(-lay.halfW, 0), m.p(lay.halfW, -lay.depth)),
    ]) {
      canvas
        ..drawRect(half, fill)
        ..drawRect(half, lines);
    }
    canvas.drawLine(
      m.p(-lay.w, 0),
      m.p(lay.w, 0),
      Paint()
        ..color = const Color(Tokens.colorUiText)
        ..strokeWidth = 12 * k,
    );
    final reach = Paint()
      ..color = const Color(Tokens.colorUiControlHint)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 * k;
    canvas
      ..drawCircle(m.p(0, homeY), aiReach * k, reach)
      ..drawCircle(m.p(0, -homeY), playerReach * k, reach);
    final g = guide;
    if (g != null) drawGuide(canvas, p(me), p(g), k);
    final mk = mark;
    if (mk != null) {
      canvas.drawCircle(p(mk), lay.ballR * 0.6 * k, Paint()..color = const Color(Tokens.colorUiControlBrake));
    }
    drawDisc(canvas, p(me), lay.manR * k, Tokens.colorWorldDayFacades[4], k);
    drawDisc(canvas, p(rival), lay.manR * k, Tokens.colorUiControlHand, k);
    canvas.drawCircle(p(ball), lay.ballR * k, Paint()..color = const Color(Tokens.colorBrandAccent));
    canvas.drawCircle(
      p(ball),
      lay.ballR * k,
      Paint()
        ..color = const Color(Tokens.colorUiLabelShadow)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 * k,
    );
  }

  @override
  bool shouldRepaint(_CourtPainter old) =>
      old.me != me || old.rival != rival || old.ball != ball || old.mark != mark || old.guide != guide;
}
