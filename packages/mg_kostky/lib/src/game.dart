import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mg_api/mg_api.dart';
import 'package:rules_core/rules_core.dart';
import 'package:shared_gen/shared_gen.dart';

import 'rules.dart';

/// Kostkový poker: tap dice to hold them, roll up to three times, then tap a free row of your
/// column (it previews what the roll would write). The opponent plays each step after `ai_think_s`.
class KostkyGame implements Minigame {
  const KostkyGame();

  @override
  MinigameMeta get meta => minigameCatalog[MinigameId.kostky]!;

  @override
  Widget build(MinigameContext ctx, MinigameEnv env, void Function(MinigameResult) onFinish) {
    final tm = env.tuning.minigames.kostky;
    return MinigameShell(
      id: MinigameId.kostky,
      env: env,
      rules: const [MessageKey.kostkyRules1, MessageKey.kostkyRules2, MessageKey.kostkyRules3],
      timeCapS: tm.timeCapS,
      onFinish: onFinish,
      body: (context, shell, hooks) => _KostkyBody(ctx: ctx, env: env, shell: shell, hooks: hooks),
    );
  }
}

class _KostkyBody extends StatefulWidget {
  const _KostkyBody({required this.ctx, required this.env, required this.shell, required this.hooks});

  final MinigameContext ctx;
  final MinigameEnv env;
  final ShellController shell;
  final GameHooks hooks;

  @override
  State<_KostkyBody> createState() => _KostkyBodyState();
}

class _KostkyBodyState extends State<_KostkyBody> {
  final KostkyRules _rules = KostkyRules();
  late final KostkyConfig _cfg = KostkyConfig.fromTuning(widget.env.tuning.minigames.kostky);
  late final Prng _ai = aiPrng(widget.ctx.seed);
  late KostkyState _s = _rules.start(_cfg, widget.ctx.seed);
  Timer? _aiTimer, _endTimer;
  Set<int> _held = {};

  /// Dice of the turn just written, shown until the next roll.
  List<int> _shown = const [];

  String t(MessageKey k, [Map<String, Object> a = const {}]) => widget.env.t(k, a);

  bool get _myMove => !_s.over && _s.turn == 'player';

  @override
  void initState() {
    super.initState();
    widget.hooks.onTimeout = _timeout;
    WidgetsBinding.instance.addPostFrameCallback((_) => _status());
  }

  @override
  void dispose() {
    _aiTimer?.cancel();
    _endTimer?.cancel();
    super.dispose();
  }

  void _status() {
    if (!mounted) return;
    widget.shell.status(_s.over ? '' : (_myMove ? t(MessageKey.yourTurn) : t(MessageKey.opponentTurn)));
  }

  void _toggle(int i) {
    if (widget.shell.paused || !_myMove || _s.rolls == 0 || _s.rolls >= 3) return;
    setState(() => _held.contains(i) ? _held.remove(i) : _held.add(i));
  }

  void _tapRoll() {
    if (widget.shell.paused || !_myMove || _s.rolls >= 3 || _held.length == 5) return;
    _play(KostkyAction.roll('player', _s.rolls == 0 ? const [] : (_held.toList()..sort())));
  }

  void _tapScore(int cat) {
    if (widget.shell.paused || !_myMove || _s.rolls == 0) return;
    _play(KostkyAction.score('player', cat));
  }

  void _play(KostkyAction a) {
    if (_s.over) return;
    final before = _s;
    setState(() {
      _s = _rules.apply(_s, a);
      if (a.op == 'score') {
        _shown = before.dice;
        _held = {};
      } else if (a.by == 'ai' && a.op == 'roll') {
        _held = a.keep.toSet();
      } else if (a.by == 'player' && a.op == 'roll' && before.rolls == 0) {
        _held = {};
      }
      if (_s.turn == 'player' && before.turn == 'ai') _held = {};
    });
    _status();
    final r = _rules.result(_s);
    if (r != null) {
      _endTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
      });
      return;
    }
    _scheduleAi();
  }

  void _scheduleAi() {
    if (_s.turn != 'ai' || _s.over) return;
    _aiTimer?.cancel();
    void tick() {
      if (!mounted) return;
      if (widget.shell.paused) {
        _aiTimer = Timer(const Duration(milliseconds: 200), tick);
        return;
      }
      _play(_rules.aiAction(_s, widget.ctx.difficulty, _ai));
    }

    _aiTimer = Timer(Duration(milliseconds: (widget.env.tuning.minigames.kostky.aiThinkS * 1000).round()), tick);
  }

  void _timeout() {
    if (_s.over) return;
    _aiTimer?.cancel();
    setState(() => _s = _rules.apply(_s, const KostkyAction.timeout()));
    final r = _rules.result(_s)!;
    widget.shell.finish(RulesOutcome(winner: r.winner, stars: r.stars, score: r.score));
  }

  String _bonus(List<int> table) =>
      upperSum(table) >= _cfg.bonusAt ? '${_cfg.bonus}' : '${upperSum(table)}/${_cfg.bonusAt}';

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(color: Color(Tokens.colorUiTextMuted));
    const text = TextStyle(color: Color(Tokens.colorUiText), fontSize: 15);
    final bold = text.copyWith(fontWeight: FontWeight.w700);
    final values = _s.dice.isNotEmpty ? _s.dice : _shown;
    final canHold = _myMove && _s.rolls > 0 && _s.rolls < 3;
    String cell(int v) => v < 0 ? '' : '$v';
    TableRow row(String label, String p, String a, {VoidCallback? onTap, bool preview = false, bool sum = false}) {
      final style = sum ? bold : text;
      return TableRow(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(label, style: style),
          ),
          InkWell(
            key: onTap == null ? null : ValueKey('cat-$label'),
            onTap: onTap,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: preview
                  ? BoxDecoration(
                      border: Border.all(color: const Color(Tokens.colorBrandAccent)),
                      borderRadius: BorderRadius.circular(Tokens.radiusButton),
                    )
                  : null,
              child: Text(p, style: preview ? style.copyWith(color: const Color(Tokens.colorBrandAccent)) : style),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(a, textAlign: TextAlign.center, style: style),
          ),
        ],
      );
    }

    final rows = <TableRow>[
      row('', t(MessageKey.srdceYou), widget.env.opponent?.name ?? '', sum: true),
      for (var i = 0; i < kostkyCats; i++) ...[
        if (_s.player[i] == -1 && _myMove && _s.rolls > 0)
          row(
            t(MessageKey.values.byName('kostkyCat$i')),
            '${catValue(i, _s.dice)}',
            cell(_s.ai[i]),
            onTap: () => _tapScore(i),
            preview: true,
          )
        else
          row(t(MessageKey.values.byName('kostkyCat$i')), cell(_s.player[i]), cell(_s.ai[i])),
        if (i == 5) row(t(MessageKey.kostkyBonus), _bonus(_s.player), _bonus(_s.ai), sum: true),
      ],
      row(t(MessageKey.kostkyTotal), '${tableTotal(_s.player, _cfg)}', '${tableTotal(_s.ai, _cfg)}', sum: true),
    ];
    return Padding(
      padding: const EdgeInsets.all(Tokens.spaceMd),
      child: Column(
        children: [
          Text(t(MessageKey.desetRound, {'round': math.min(_s.round, kostkyCats), 'max': kostkyCats}), style: muted),
          const SizedBox(height: Tokens.spaceSm),
          LayoutBuilder(
            builder: (context, c) {
              final side = math.min((c.maxWidth - 4 * Tokens.spaceSm) / 5, 72.0);
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 5; i++)
                    Padding(
                      padding: EdgeInsets.only(left: i == 0 ? 0 : Tokens.spaceSm),
                      child: GestureDetector(
                        key: ValueKey('die-$i'),
                        onTap: canHold ? () => _toggle(i) : null,
                        child: CustomPaint(
                          size: Size.square(side),
                          painter: DiePainter(
                            value: i < values.length ? values[i] : 0,
                            ring: _held.contains(i) ? DieRing.selected : DieRing.none,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: Tokens.spaceSm),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _myMove && _s.rolls < 3 && _held.length < 5 ? _tapRoll : null,
              child: Text(t(MessageKey.kostkyRoll, {'n': 3 - _s.rolls})),
            ),
          ),
          const SizedBox(height: Tokens.spaceSm),
          Expanded(
            child: SingleChildScrollView(
              child: Table(
                columnWidths: const {0: FlexColumnWidth(2.2), 1: FlexColumnWidth(), 2: FlexColumnWidth()},
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: rows,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
