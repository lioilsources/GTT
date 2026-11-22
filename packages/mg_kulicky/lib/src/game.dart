import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

import 'duel_ui.dart';
import 'rules.dart';

/// Yard layout in mm (y up, hole at 0, 0); same as the web client.
class YardLayout {
  factory YardLayout.of(KulickyConfig c) {
    final spread = [c.holeR * 4, ...c.scatter, ...c.aiScatter].reduce(math.max).toDouble();
    final halfW = spread * 2.5;
    final marbleR = math.max(c.holeR * 0.45, 1.0);
    final startY = -halfW * 1.6;
    return YardLayout._(halfW, halfW, startY, startY - marbleR * 4, marbleR, -halfW);
  }

  const YardLayout._(this.halfW, this.top, this.startY, this.bottom, this.marbleR, this.aimOriginY);

  final double halfW, top, bottom, marbleR;

  /// Where marbles rest before a flick.
  final double startY;

  /// A straight-up swipe starts aiming here (the yard's lower edge).
  final double aimOriginY;

  /// Marbles rest this far left (player) and right (rival) of the middle.
  double get startX => marbleR * 3;

  double get width => 2 * halfW;
  double get height => top - bottom;

  /// Swipe in logical px (dx right, dy down) → integer aim point in mm.
  ({int x, int y}) aim(double dx, double dy, double mmPerPx) =>
      (x: (dx * mmPerPx).round(), y: (aimOriginY - dy * mmPerPx).round());
}

/// Which round line to show after the rival's shot settled a round.
MessageKey roundNote(int playerBefore, int aiBefore, int playerAfter, int aiAfter) {
  final dp = playerAfter - playerBefore, da = aiAfter - aiBefore;
  return dp > da
      ? MessageKey.roundWon
      : da > dp
      ? MessageKey.roundLost
      : MessageKey.draw;
}

const _tween = Duration(milliseconds: 450);
const _show = Duration(milliseconds: 800);
const _aiDelay = Duration(milliseconds: 700);

/// Kuličky (marbles): flick your marble to the hole, then the rival flicks.
class KulickyGame implements Minigame {
  const KulickyGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.kulicky]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.kulicky;
    return MinigameShell(
      id: MinigameId.kulicky,
      env: env,
      rules: const [MessageKey.kulickyRules1, MessageKey.kulickyRules2, MessageKey.kulickyRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _KulickyBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _KulickyBody extends StatefulWidget {
  const _KulickyBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_KulickyBody> createState() => _KulickyBodyState();
}

class _KulickyBodyState extends State<_KulickyBody> with SingleTickerProviderStateMixin {
  final KulickyRules _rules = KulickyRules();
  final DuelTimer _timer = DuelTimer();
  late final Prng _ai = aiPrng(widget.ctx.seed);
  late final KulickyConfig _cfg = KulickyConfig.fromTuning(widget.env.tuning.minigames.kulicky);
  late final YardLayout _lay = YardLayout.of(_cfg);
  late KulickyState _s = _rules.start(_cfg, widget.ctx.seed);
  late final AnimationController _roll = AnimationController(vsync: this, duration: _tween);
  late Offset _mine = Offset(-_lay.startX, _lay.startY);
  late Offset _rival = Offset(_lay.startX, _lay.startY);
  bool _busy = false;
  String _note = '';
  bool _flash = false;
  Offset? _dragStart;
  Offset _drag = Offset.zero;

  double get _mmPerPx => widget.env.tuning.minigames.kulicky.flickMmPerPx;

  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  @override
  void initState() {
    super.initState();
    widget.hooks.onTimeout = _timeout;
    WidgetsBinding.instance.addPostFrameCallback((_) => _status());
  }

  @override
  void dispose() {
    _roll.dispose();
    _timer.cancel();
    super.dispose();
  }

  void _status() {
    if (!mounted) return;
    final round = math.min(_s.round, _cfg.rounds);
    widget.shell.status(
      t(MessageKey.localScore, {'round': round, 'rounds': _cfg.rounds, 'player': _s.playerPts, 'ai': _s.aiPts}),
    );
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
    final aim = _lay.aim(swipe.dx, swipe.dy, _mmPerPx);
    setState(() {
      _s = _rules.apply(_s, KulickyAction(aim.x, aim.y, widget.ctx.difficulty));
      _busy = true;
      _note = '';
      _flash = false;
    });
    _status();
    _animate(true, () => _timer.later(_aiDelay, () => widget.shell.paused, _rivalShot));
  }

  /// Rolls the player's ([mine]) or the rival's marble from its rest spot to its last shot.
  void _animate(bool mine, VoidCallback done) {
    final from = mine ? _mine : _rival;
    final shot = mine ? _s.playerShot : _s.aiShot;
    final to = Offset(shot.x.toDouble(), shot.y.toDouble());
    void tick() {
      final p = Offset.lerp(from, to, Curves.easeOut.transform(_roll.value))!;
      setState(() => mine ? _mine = p : _rival = p);
    }

    void status(AnimationStatus st) {
      if (st != AnimationStatus.completed) return;
      _roll
        ..removeListener(tick)
        ..removeStatusListener(status);
      if (mounted) done();
    }

    _roll
      ..addListener(tick)
      ..addStatusListener(status)
      ..forward(from: 0);
  }

  void _rivalShot() {
    if (!mounted || _s.over) return;
    final before = _s;
    setState(() => _s = _rules.apply(_s, _rules.aiAction(_s, widget.ctx.difficulty, _ai)));
    _animate(false, () {
      setState(() {
        _note = t(roundNote(before.playerPts, before.aiPts, _s.playerPts, _s.aiPts));
        _flash = _s.playerPts > before.playerPts;
      });
      _status();
      _timer.later(_show, () => widget.shell.paused, () {
        if (!mounted) return;
        final r = _rules.result(_s);
        if (r != null) {
          widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
          return;
        }
        setState(() {
          _mine = Offset(-_lay.startX, _lay.startY);
          _rival = Offset(_lay.startX, _lay.startY);
          _busy = false;
          _flash = false;
        });
      });
    });
  }

  void _timeout() {
    if (_s.over) return;
    _timer.cancel();
    _roll.stop();
    setState(() => _s = _rules.apply(_s, const KulickyAction.timeout()));
    _status();
    final r = _rules.result(_s)!;
    widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
  }

  @override
  Widget build(BuildContext context) => DuelFrame(
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
        painter: _YardPainter(
          cfg: _cfg,
          lay: _lay,
          mine: _mine,
          rival: _rival,
          guide: _dragStart != null && _drag.dy < -duelMinSwipePx ? _lay.aim(_drag.dx, _drag.dy, _mmPerPx) : null,
        ),
      ),
    ),
  );
}

/// Yard, throw line, hole, aim guide and both marbles (same layout as the web client).
class _YardPainter extends CustomPainter {
  _YardPainter({required this.cfg, required this.lay, required this.mine, required this.rival, required this.guide});

  final KulickyConfig cfg;
  final YardLayout lay;
  final Offset mine, rival;
  final ({int x, int y})? guide;

  @override
  void paint(Canvas canvas, Size size) {
    final m = BoardMap(size, -lay.halfW, lay.top, lay.width, lay.height);
    final k = m.k;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(m.p(-lay.halfW, lay.top), m.p(lay.halfW, lay.bottom)),
        Radius.circular(lay.marbleR * k),
      ),
      Paint()..color = const Color(Tokens.colorWorldDayLand),
    );
    canvas.drawLine(
      m.p(-lay.halfW, lay.aimOriginY),
      m.p(lay.halfW, lay.aimOriginY),
      Paint()
        ..color = const Color(Tokens.colorWorldDayMarking)
        ..strokeWidth = 6 * k,
    );
    final hole = m.p(0, 0);
    canvas.drawCircle(hole, cfg.holeR * k, Paint()..color = const Color(Tokens.colorWorldDayBridgeEdge));
    canvas.drawCircle(
      hole,
      cfg.holeR * k,
      Paint()
        ..color = const Color(Tokens.colorBrandAccent)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 * k,
    );
    final g = guide;
    if (g != null) drawGuide(canvas, m.p(-lay.startX, lay.startY), m.p(g.x, g.y), k);
    drawDisc(canvas, m.p(mine.dx, mine.dy), lay.marbleR * k, Tokens.colorWorldDayFacades[4], k);
    drawDisc(canvas, m.p(rival.dx, rival.dy), lay.marbleR * k, Tokens.colorUiControlHand, k);
  }

  @override
  bool shouldRepaint(_YardPainter old) => old.mine != mine || old.rival != rival || old.guide != guide;
}
