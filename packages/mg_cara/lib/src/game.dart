import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:mg_kulicky/mg_kulicky.dart'
    show BoardMap, DuelFrame, DuelTimer, drawDisc, drawGuide, duelMinSwipePx, roundNote;
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Pavement layout in mm (y up, the line at y = 0, the wall just behind it); same as the web client.
class PavementLayout {
  factory PavementLayout.of(CaraConfig c) {
    final spread = [...c.scatter, ...c.aiScatter, ...c.aiAim].reduce(math.max).toDouble();
    final halfW = spread * 2.5;
    final coinR = spread * 0.18;
    final wallY = spread * 1.2;
    final startY = -spread * 5.5;
    return PavementLayout._(
      halfW,
      wallY,
      wallY + spread * 0.6,
      startY,
      startY - coinR * 3,
      coinR,
      halfW / 3,
      -spread * 4,
    );
  }

  const PavementLayout._(
    this.halfW,
    this.wallY,
    this.top,
    this.startY,
    this.bottom,
    this.coinR,
    this.laneX,
    this.aimOriginY,
  );

  final double halfW, top, bottom, coinR;

  /// The wall's face.
  final double wallY;

  /// Where coins rest before a toss.
  final double startY;

  /// Coins are drawn left (player) and right (rival) of the middle.
  final double laneX;

  /// A straight-up swipe starts aiming here.
  final double aimOriginY;

  double get width => 2 * halfW;
  double get height => top - bottom;

  /// Swipe length in logical px (dy down) → integer aimed distance from the line in mm.
  int aim(double dy, double mmPerPx) => (aimOriginY - dy * mmPerPx).round();
}

const _tween = Duration(milliseconds: 450);
const _show = Duration(milliseconds: 800);
const _aiDelay = Duration(milliseconds: 700);

/// Čára (coin to the wall): toss closest to the line without burning it.
class CaraGame implements Minigame {
  const CaraGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.cara]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.cara;
    return MinigameShell(
      id: MinigameId.cara,
      env: env,
      rules: const [MessageKey.caraRules1, MessageKey.caraRules2, MessageKey.caraRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _CaraBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _CaraBody extends StatefulWidget {
  const _CaraBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_CaraBody> createState() => _CaraBodyState();
}

class _CaraBodyState extends State<_CaraBody> with SingleTickerProviderStateMixin {
  final CaraRules _rules = CaraRules();
  final DuelTimer _timer = DuelTimer();
  late final Prng _ai = aiPrng(widget.ctx.seed);
  late final CaraConfig _cfg = CaraConfig.fromTuning(widget.env.tuning.minigames.cara);
  late final PavementLayout _lay = PavementLayout.of(_cfg);
  late CaraState _s = _rules.start(_cfg, widget.ctx.seed);
  late final AnimationController _toss = AnimationController(vsync: this, duration: _tween);
  late double _mineY = _lay.startY, _rivalY = _lay.startY;
  bool _mineBurnt = false, _rivalBurnt = false;
  bool _busy = false;
  String _note = '';
  bool _flash = false;
  Offset? _dragStart;
  Offset _drag = Offset.zero;

  double get _mmPerPx => widget.env.tuning.minigames.cara.flickMmPerPx;

  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  @override
  void initState() {
    super.initState();
    widget.hooks.onTimeout = _timeout;
    WidgetsBinding.instance.addPostFrameCallback((_) => _status());
  }

  @override
  void dispose() {
    _toss.dispose();
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
    setState(() {
      _s = _rules.apply(_s, CaraAction(_lay.aim(swipe.dy, _mmPerPx), widget.ctx.difficulty));
      _busy = true;
      _note = '';
      _flash = false;
    });
    _status();
    _animate(true, () => _timer.later(_aiDelay, () => widget.shell.paused, _rivalToss));
  }

  /// Slides the player's ([mine]) or the rival's coin from the start line to where it settled.
  void _animate(bool mine, VoidCallback done) {
    final coin = mine ? _s.playerCoin : _s.aiCoin;
    void tick() {
      final y = _lay.startY + (coin.y - _lay.startY) * Curves.easeOut.transform(_toss.value);
      setState(() => mine ? _mineY = y : _rivalY = y);
    }

    void status(AnimationStatus st) {
      if (st != AnimationStatus.completed) return;
      _toss
        ..removeListener(tick)
        ..removeStatusListener(status);
      if (!mounted) return;
      setState(() => mine ? _mineBurnt = coin.burnt : _rivalBurnt = coin.burnt);
      done();
    }

    _toss
      ..addListener(tick)
      ..addStatusListener(status)
      ..forward(from: 0);
  }

  void _rivalToss() {
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
          _mineY = _rivalY = _lay.startY;
          _mineBurnt = _rivalBurnt = false;
          _busy = false;
          _flash = false;
        });
      });
    });
  }

  void _timeout() {
    if (_s.over) return;
    _timer.cancel();
    _toss.stop();
    setState(() => _s = _rules.apply(_s, const CaraAction.timeout()));
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
        painter: _PavementPainter(
          lay: _lay,
          mineY: _mineY,
          rivalY: _rivalY,
          mineBurnt: _mineBurnt,
          rivalBurnt: _rivalBurnt,
          guide: _dragStart != null && _drag.dy < -duelMinSwipePx ? _lay.aim(_drag.dy, _mmPerPx) : null,
        ),
      ),
    ),
  );
}

/// Pavement, wall, line, aim guide and both coins (same layout as the web client).
class _PavementPainter extends CustomPainter {
  _PavementPainter({
    required this.lay,
    required this.mineY,
    required this.rivalY,
    required this.mineBurnt,
    required this.rivalBurnt,
    required this.guide,
  });

  final PavementLayout lay;
  final double mineY, rivalY;
  final bool mineBurnt, rivalBurnt;
  final int? guide;

  @override
  void paint(Canvas canvas, Size size) {
    final m = BoardMap(size, -lay.halfW, lay.top, lay.width, lay.height);
    final k = m.k;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromPoints(m.p(-lay.halfW, lay.top), m.p(lay.halfW, lay.bottom)),
        Radius.circular(lay.coinR * k),
      ),
      Paint()..color = const Color(Tokens.colorWorldDayLand),
    );
    canvas.drawRect(
      Rect.fromPoints(m.p(-lay.halfW, lay.top), m.p(lay.halfW, lay.wallY)),
      Paint()..color = Color(Tokens.colorWorldDayFacades[6]),
    );
    canvas.drawLine(
      m.p(-lay.halfW, 0),
      m.p(lay.halfW, 0),
      Paint()
        ..color = const Color(Tokens.colorWorldDayMarking)
        ..strokeWidth = 6 * k,
    );
    final g = guide;
    if (g != null) drawGuide(canvas, m.p(-lay.laneX, lay.startY), m.p(-lay.laneX, g), k);
    drawDisc(canvas, m.p(-lay.laneX, mineY), lay.coinR * k, Tokens.colorWorldDayFacades[4], k, faded: mineBurnt);
    drawDisc(canvas, m.p(lay.laneX, rivalY), lay.coinR * k, Tokens.colorUiControlHand, k, faded: rivalBurnt);
  }

  @override
  bool shouldRepaint(_PavementPainter old) =>
      old.mineY != mineY ||
      old.rivalY != rivalY ||
      old.mineBurnt != mineBurnt ||
      old.rivalBurnt != rivalBurnt ||
      old.guide != guide;
}
