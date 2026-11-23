import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Board drawn around the table (u).
const _board = 160;

/// Vzdušný hokej (air hockey, specs/minigames/hokej.md): the mallet follows the finger; the
/// opponent is an automaton inside the tick; ticks at `tick_hz`.
class HokejGame implements Minigame {
  const HokejGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.hokej]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.hokej;
    return MinigameShell(
      id: MinigameId.hokej,
      env: env,
      rules: const [MessageKey.hokejRules1, MessageKey.hokejRules2, MessageKey.hokejRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _HokejBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _HokejBody extends StatefulWidget {
  const _HokejBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_HokejBody> createState() => _HokejBodyState();
}

WorldView _viewOf(Size size, HokejConfig c) => WorldView.fit(
  size,
  -_board.toDouble(),
  -_board.toDouble(),
  c.w + _board.toDouble(),
  c.h + _board.toDouble(),
  pad: 4,
);

class _HokejBodyState extends State<_HokejBody> with SingleTickerProviderStateMixin {
  final HokejRules _rules = HokejRules();
  late final TuningMinigamesHokej _tm = widget.env.tuning.minigames.hokej;
  late final HokejConfig _cfg = HokejConfig.fromTuning(_tm, widget.ctx.difficulty);
  late HokejState _s = _rules.start(_cfg);
  late final TickLoop _loop;
  bool _finished = false;
  Size _size = Size.zero;

  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  @override
  void initState() {
    super.initState();
    widget.hooks.onTimeout = () => _play(const HokejAction.timeout());
    _loop = TickLoop(
      this,
      hz: _tm.tickHz,
      paused: () => widget.shell.paused,
      running: () => !_finished,
      ticks: (n) => _play(HokejAction.tick(n)),
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
    if (mounted) widget.shell.status(t(MessageKey.hokejScore, {'player': _s.playerGoals, 'ai': _s.aiGoals}));
  }

  void _play(HokejAction a) {
    if (_finished || _s.over || !mounted) return;
    final before = _s;
    setState(() => _s = _rules.apply(_s, a));
    if (_s.playerGoals != before.playerGoals || _s.aiGoals != before.aiGoals) _status();
    final r = _rules.result(_s);
    if (r != null) {
      _finished = true;
      _status();
      widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
    }
  }

  void _follow(PointerEvent e) {
    if (widget.shell.paused || _finished) return;
    final p = _viewOf(_size, _cfg).toWorld(e.localPosition);
    _play(HokejAction.move(p.x.round(), p.y.round()));
  }

  @override
  Widget build(BuildContext context) {
    final goal = _s.pause > 0 && _s.tick > 0;
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceSm),
      child: Column(
        children: [
          Text(
            goal ? t(MessageKey.hokejGoal) : '',
            style: const TextStyle(color: Color(Tokens.colorUiText), fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Tokens.spaceXs),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                _size = c.biggest;
                return Listener(
                  key: const ValueKey('rink'),
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _follow,
                  onPointerMove: _follow,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _RinkPainter(cfg: _cfg, s: _s),
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

class _RinkPainter extends CustomPainter {
  _RinkPainter({required this.cfg, required this.s});

  final HokejConfig cfg;
  final HokejState s;

  @override
  void paint(Canvas canvas, Size size) {
    final v = _viewOf(size, cfg);
    final k = v.k;
    final mid = cfg.w ~/ 2;
    canvas.drawRect(
      Rect.fromPoints(v.p(-_board, cfg.h + _board), v.p(cfg.w + _board, -_board)),
      Paint()..color = const Color(Tokens.colorPoliceBody),
    );
    final table = Rect.fromPoints(v.p(0, cfg.h), v.p(cfg.w, 0));
    canvas.drawRect(table, Paint()..color = const Color(Tokens.colorWeatherIcon));
    final mouth = Paint()..color = const Color(Tokens.colorCarDetailLimoPillar);
    canvas.drawRect(Rect.fromPoints(v.p(mid - cfg.goalHalf, cfg.h + _board), v.p(mid + cfg.goalHalf, cfg.h)), mouth);
    canvas.drawRect(Rect.fromPoints(v.p(mid - cfg.goalHalf, 0), v.p(mid + cfg.goalHalf, -_board)), mouth);
    final red = Paint()
      ..color = const Color(Tokens.colorPoliceLightRed)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawLine(v.p(0, cfg.h / 2), v.p(cfg.w, cfg.h / 2), red);
    canvas.drawCircle(v.p(mid, cfg.h / 2), cfg.goalHalf * 0.8 * k, red);
    canvas.save();
    canvas.clipRect(table);
    final blue = Paint()
      ..color = const Color(Tokens.colorPoliceLightBlue)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final y in [0, cfg.h]) {
      canvas.drawCircle(v.p(mid, y), cfg.goalHalf * k, blue);
    }
    canvas.restore();
    final edge = Paint()
      ..color = const Color(Tokens.colorUiLabelShadow)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    void mallet(Mallet m, int color) {
      final c = v.p(m.x, m.y);
      canvas.drawCircle(c, cfg.malletR * k, Paint()..color = Color(color));
      canvas.drawCircle(c, cfg.malletR * k, edge);
      canvas.drawCircle(c, cfg.malletR * 0.45 * k, Paint()..color = const Color(Tokens.colorWorldDayMarking));
    }

    mallet(s.ai, Tokens.colorTrafficLightRed);
    mallet(s.me, Tokens.colorPoliceLightBlue);
    canvas.drawCircle(
      v.p(s.puck.x, s.puck.y),
      cfg.puckR * k,
      Paint()..color = const Color(Tokens.colorCarDetailTaxiChecker),
    );
  }

  @override
  bool shouldRepaint(_RinkPainter old) => old.s != s;
}
